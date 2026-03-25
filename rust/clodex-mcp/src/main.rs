use chrono::Utc;
use serde::{Deserialize, Serialize};
use serde_json::{json, Map, Value};
use std::env;
use std::fs;
use std::io::{self, BufRead, BufReader, Write};
use std::path::{Path, PathBuf};
use std::process;
use std::time::{SystemTime, UNIX_EPOCH};

const JSONRPC_VERSION: &str = "2.0";
const MCP_PROTOCOL_VERSION: &str = "2024-11-05";
const SERVER_NAME: &str = "clodex-mcp";
const ACTIVE_FILE_NAME: &str = "active.json";
const EVENTS_FILE_NAME: &str = "events.jsonl";
const QUEUE_NAMES: [&str; 4] = ["planned", "queued", "implemented", "history"];
const PROMPT_KINDS: [&str; 10] = [
    "todo",
    "bug",
    "freeform",
    "adjustment",
    "refactor",
    "idea",
    "ask",
    "explain",
    "library",
    "notworking",
];

#[derive(Debug)]
struct AppError {
    message: String,
}

impl AppError {
    fn new(message: impl Into<String>) -> Self {
        Self {
            message: message.into(),
        }
    }
}

impl std::fmt::Display for AppError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.message)
    }
}

impl std::error::Error for AppError {}

impl From<io::Error> for AppError {
    fn from(value: io::Error) -> Self {
        Self::new(value.to_string())
    }
}

impl From<serde_json::Error> for AppError {
    fn from(value: serde_json::Error) -> Self {
        Self::new(value.to_string())
    }
}

type AppResult<T> = Result<T, AppError>;

#[derive(Clone, Debug, Deserialize)]
struct JsonRpcRequest {
    #[serde(default)]
    id: Option<Value>,
    method: String,
    #[serde(default)]
    params: Option<Value>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
struct JsonRpcResponse {
    jsonrpc: &'static str,
    #[serde(skip_serializing_if = "Option::is_none")]
    id: Option<Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    result: Option<Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    error: Option<JsonRpcError>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
struct JsonRpcError {
    code: i64,
    message: String,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
struct QueueItem {
    id: String,
    #[serde(default)]
    kind: String,
    title: String,
    #[serde(default)]
    details: Option<String>,
    prompt: String,
    #[serde(default)]
    execution_instructions: Option<String>,
    #[serde(default)]
    completion_target: Option<String>,
    #[serde(default)]
    image_path: Option<String>,
    created_at: String,
    updated_at: String,
    #[serde(default)]
    history_summary: Option<String>,
    #[serde(default)]
    history_commits: Vec<String>,
    #[serde(default)]
    history_completed_at: Option<String>,
    #[serde(flatten)]
    extra: Map<String, Value>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
struct ActiveItem {
    item_id: String,
    claimed_at: String,
    source_queue: String,
}

#[derive(Clone, Debug, Deserialize)]
struct ProjectRootArgs {
    project_root: String,
}

#[derive(Clone, Debug, Deserialize)]
struct CompleteArgs {
    project_root: String,
    #[serde(default)]
    summary: Option<String>,
    #[serde(default)]
    commit: Option<String>,
    #[serde(default)]
    commits: Option<Vec<String>>,
    #[serde(default)]
    completion_target: Option<String>,
}

#[derive(Clone, Debug, Deserialize)]
struct FailArgs {
    project_root: String,
    #[serde(default)]
    note: Option<String>,
}

#[derive(Clone, Debug, Deserialize)]
struct CloseTaskArgs {
    project_root: String,
    success: bool,
    #[serde(default)]
    comment: Option<String>,
    #[serde(default)]
    commit_id: Option<String>,
}

#[derive(Clone, Debug, Deserialize)]
struct CreatePromptArgs {
    project_root: String,
    title: String,
    #[serde(default)]
    details: Option<String>,
    #[serde(default)]
    kind: Option<String>,
    #[serde(default)]
    queue: Option<String>,
    #[serde(default)]
    image_path: Option<String>,
    #[serde(default)]
    completion_target: Option<String>,
}

struct Server {
    stdout: io::Stdout,
}

enum TaskClaim {
    Task {
        active: ActiveItem,
        item: QueueItem,
        active_exists: bool,
    },
    Done,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum TransportMode {
    ContentLength,
    NewlineDelimited,
}

impl Server {
    fn new() -> Self {
        Self {
            stdout: io::stdout(),
        }
    }

    fn run(&mut self) -> AppResult<()> {
        let stdin = io::stdin();
        let mut reader = BufReader::new(stdin.lock());
        while let Some((message, transport)) = read_message(&mut reader)? {
            let request: JsonRpcRequest = serde_json::from_slice(&message)?;
            if let Some(response) = self.handle_request(request) {
                self.write_response(&response, transport)?;
            }
        }
        Ok(())
    }

    fn handle_request(&mut self, request: JsonRpcRequest) -> Option<JsonRpcResponse> {
        let id = request.id.clone();
        let response = match self.dispatch(request) {
            Ok(Some(result)) => JsonRpcResponse {
                jsonrpc: JSONRPC_VERSION,
                id,
                result: Some(result),
                error: None,
            },
            Ok(None) => return None,
            Err(err) => JsonRpcResponse {
                jsonrpc: JSONRPC_VERSION,
                id,
                result: None,
                error: Some(JsonRpcError {
                    code: -32000,
                    message: err.message,
                }),
            },
        };
        Some(response)
    }

    fn dispatch(&mut self, request: JsonRpcRequest) -> AppResult<Option<Value>> {
        match request.method.as_str() {
            "initialize" => Ok(Some(json!({
                "protocolVersion": MCP_PROTOCOL_VERSION,
                "capabilities": {
                    "tools": {
                        "listChanged": false,
                    },
                },
                "serverInfo": {
                    "name": SERVER_NAME,
                    "version": env!("CARGO_PKG_VERSION"),
                },
            }))),
            "notifications/initialized" => Ok(None),
            "ping" => Ok(Some(json!({}))),
            "tools/list" => Ok(Some(json!({
                "tools": tool_definitions(),
            }))),
            "tools/call" => self.handle_tool_call(request.params),
            _ => Err(AppError::new(format!("Unknown method: {}", request.method))),
        }
    }

    fn handle_tool_call(&mut self, params: Option<Value>) -> AppResult<Option<Value>> {
        let params = params.ok_or_else(|| AppError::new("Missing tools/call params"))?;
        let name = required_string(&params, "name")?;
        let arguments = params
            .get("arguments")
            .cloned()
            .unwrap_or_else(|| json!({}));
        let result = match name.as_str() {
            "get_task" => tool_result(get_task(parse_args(arguments)?)?),
            "close_task" => tool_result(close_task(parse_args(arguments)?)?),
            "create_prompt" => tool_result(create_prompt(parse_args(arguments)?)?),
            "queue_status" => tool_result(queue_status(parse_args(arguments)?)?),
            "queue_claim_next" => tool_result(queue_claim_next(parse_args(arguments)?)?),
            "queue_complete_current" => {
                tool_result(queue_complete_current(parse_args(arguments)?)?)
            }
            "queue_fail_current" => tool_result(queue_fail_current(parse_args(arguments)?)?),
            _ => tool_error(format!("Unknown tool: {name}")),
        };
        Ok(Some(result))
    }

    fn write_response(
        &mut self,
        response: &JsonRpcResponse,
        transport: TransportMode,
    ) -> AppResult<()> {
        let payload = encode_response_payload(response, transport)?;
        self.stdout.write_all(&payload)?;
        self.stdout.flush()?;
        Ok(())
    }
}

fn main() {
    if let Err(err) = run_main() {
        eprintln!("{err}");
        process::exit(1);
    }
}

fn run_main() -> AppResult<()> {
    let args: Vec<String> = env::args().skip(1).collect();
    if args.iter().any(|arg| arg == "--version") {
        println!("{}", env!("CARGO_PKG_VERSION"));
        return Ok(());
    }

    let mut server = Server::new();
    server.run()
}

fn encode_response_payload(
    response: &JsonRpcResponse,
    transport: TransportMode,
) -> AppResult<Vec<u8>> {
    let payload = serde_json::to_vec(response)?;
    if transport == TransportMode::NewlineDelimited {
        let mut framed = payload;
        framed.push(b'\n');
        return Ok(framed);
    }

    let mut framed = format!("Content-Length: {}\r\n\r\n", payload.len()).into_bytes();
    framed.extend(payload);
    Ok(framed)
}

fn read_message<R: BufRead>(reader: &mut R) -> AppResult<Option<(Vec<u8>, TransportMode)>> {
    let mut content_length = None;

    loop {
        let mut line = String::new();
        let bytes = reader.read_line(&mut line)?;
        if bytes == 0 {
            return Ok(None);
        }

        if line == "\r\n" || line == "\n" {
            break;
        }

        let trimmed = line.trim();
        if content_length.is_none() && looks_like_json_payload(trimmed) {
            return Ok(Some((
                trimmed.as_bytes().to_vec(),
                TransportMode::NewlineDelimited,
            )));
        }

        if let Some((name, value)) = line.split_once(':') {
            if name.eq_ignore_ascii_case("content-length") {
                let parsed = value
                    .trim()
                    .parse::<usize>()
                    .map_err(|_| AppError::new("Invalid Content-Length header"))?;
                content_length = Some(parsed);
            }
        }
    }

    let length = content_length.ok_or_else(|| AppError::new("Missing Content-Length header"))?;
    let mut payload = vec![0_u8; length];
    reader.read_exact(&mut payload)?;
    Ok(Some((payload, TransportMode::ContentLength)))
}

fn looks_like_json_payload(value: &str) -> bool {
    value.starts_with('{') || value.starts_with('[')
}

fn required_string(value: &Value, key: &str) -> AppResult<String> {
    value
        .get(key)
        .and_then(Value::as_str)
        .map(ToOwned::to_owned)
        .ok_or_else(|| AppError::new(format!("Missing string field: {key}")))
}

fn parse_args<T: for<'de> Deserialize<'de>>(value: Value) -> AppResult<T> {
    serde_json::from_value(value).map_err(AppError::from)
}

fn tool_result(result: Value) -> Value {
    json!({
        "content": [
            {
                "type": "text",
                "text": serde_json::to_string_pretty(&result).unwrap_or_else(|_| "{}".to_string()),
            }
        ],
        "structuredContent": result,
        "isError": false,
    })
}

fn tool_error(message: String) -> Value {
    json!({
        "content": [
            {
                "type": "text",
                "text": message,
            }
        ],
        "isError": true,
    })
}

fn tool_definitions() -> Vec<Value> {
    vec![
        json!({
            "name": "get_task",
            "description": "Claim or resume the active Clodex queued task and return the next work item.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "project_root": { "type": "string" }
                },
                "required": ["project_root"],
                "additionalProperties": false,
            },
        }),
        json!({
            "name": "close_task",
            "description": "Close the active Clodex task and automatically return the next one when available.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "project_root": { "type": "string" },
                    "success": { "type": "boolean" },
                    "comment": { "type": "string" },
                    "commit_id": { "type": "string" }
                },
                "required": ["project_root", "success", "comment"],
                "additionalProperties": false,
            },
        }),
        json!({
            "name": "create_prompt",
            "description": "Create a new Clodex prompt item, defaulting to the planned queue for post-discussion follow-up work.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "project_root": { "type": "string" },
                    "title": { "type": "string" },
                    "details": { "type": "string" },
                    "kind": { "type": "string" },
                    "queue": { "type": "string", "enum": ["planned", "queued", "implemented", "history"] },
                    "image_path": { "type": "string" },
                    "completion_target": { "type": "string", "enum": ["history"] }
                },
                "required": ["project_root", "title"],
                "additionalProperties": false,
            },
        }),
        json!({
            "name": "queue_status",
            "description": "Inspect queue counts and active work for one Clodex project.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "project_root": { "type": "string" }
                },
                "required": ["project_root"],
                "additionalProperties": false,
            },
        }),
        json!({
            "name": "queue_claim_next",
            "description": "Claim the next queued item, move it into implemented, and mark it active.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "project_root": { "type": "string" }
                },
                "required": ["project_root"],
                "additionalProperties": false,
            },
        }),
        json!({
            "name": "queue_complete_current",
            "description": "Record completion metadata for the active item and optionally move it to history.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "project_root": { "type": "string" },
                    "summary": { "type": "string" },
                    "commit": { "type": "string" },
                    "commits": {
                        "type": "array",
                        "items": { "type": "string" }
                    },
                    "completion_target": {
                        "type": "string",
                        "enum": ["implemented", "history"]
                    }
                },
                "required": ["project_root"],
                "additionalProperties": false,
            },
        }),
        json!({
            "name": "queue_fail_current",
            "description": "Return the active item to queued and optionally append a failure note.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "project_root": { "type": "string" },
                    "note": { "type": "string" }
                },
                "required": ["project_root"],
                "additionalProperties": false,
            },
        }),
    ]
}

fn queue_status(args: ProjectRootArgs) -> AppResult<Value> {
    let project_root = normalize_project_root(&args.project_root)?;
    let status = queue_status_value(&project_root)?;
    Ok(json!({
        "project_root": project_root,
        "status": status,
    }))
}

fn get_task(args: ProjectRootArgs) -> AppResult<Value> {
    let project_root = normalize_project_root(&args.project_root)?;
    claim_or_resume_task(&project_root)
}

fn queue_claim_next(args: ProjectRootArgs) -> AppResult<Value> {
    let project_root = normalize_project_root(&args.project_root)?;
    let claimed = claim_or_resume_item(&project_root)?;
    Ok(match claimed {
        TaskClaim::Task {
            active,
            item,
            active_exists,
        } => {
            let status = if active_exists {
                "already_active"
            } else {
                "claimed"
            };
            json!({
                "project_root": project_root,
                "status": status,
                "active": active,
                "item": item,
            })
        }
        TaskClaim::Done => json!({
            "project_root": project_root,
            "status": "empty",
        }),
    })
}

fn queue_complete_current(args: CompleteArgs) -> AppResult<Value> {
    let project_root = normalize_project_root(&args.project_root)?;
    let active =
        load_active_state(&project_root)?.ok_or_else(|| AppError::new("No active queue item"))?;
    let mut implemented = load_queue(&project_root, "implemented")?;
    let index = implemented
        .iter()
        .position(|item| item.id == active.item_id)
        .ok_or_else(|| AppError::new("Active item not found in implemented queue"))?;

    let mut item = implemented[index].clone();
    item.updated_at = timestamp();
    item.history_summary = normalize_optional_string(args.summary);
    item.history_completed_at = Some(timestamp());
    item.history_commits = extend_commits(item.history_commits.clone(), args.commit, args.commits);

    let target =
        normalize_completion_target(args.completion_target, item.completion_target.clone());
    let final_queue = if target == "history" {
        implemented.remove(index);
        save_queue(&project_root, "implemented", &implemented)?;
        let mut history = load_queue(&project_root, "history")?;
        history.insert(0, item.clone());
        save_queue(&project_root, "history", &history)?;
        "history"
    } else {
        implemented[index] = item.clone();
        save_queue(&project_root, "implemented", &implemented)?;
        "implemented"
    };

    clear_active_state(&project_root)?;
    append_event(
        &project_root,
        "complete_current",
        json!({
            "item_id": item.id,
            "final_queue": final_queue,
        }),
    )?;

    Ok(json!({
        "project_root": project_root,
        "status": "completed",
        "final_queue": final_queue,
        "item": item,
    }))
}

fn close_task(args: CloseTaskArgs) -> AppResult<Value> {
    let project_root = normalize_project_root(&args.project_root)?;
    close_active_task(
        &project_root,
        args.success,
        normalize_optional_string(args.comment),
        normalize_optional_string(args.commit_id),
    )
}

fn create_prompt(args: CreatePromptArgs) -> AppResult<Value> {
    let project_root = normalize_project_root(&args.project_root)?;
    let title = normalize_required_string(args.title, "title")?;
    let details = normalize_optional_string(args.details);
    let kind = normalize_kind(args.kind);
    let queue_name = normalize_queue_name(args.queue);
    let timestamp = timestamp();
    let item = QueueItem {
        id: uuid::Uuid::new_v4().to_string(),
        kind,
        title: title.clone(),
        details: details.clone(),
        prompt: match &details {
            Some(details) => format!("{title}\n\n{details}"),
            None => title.clone(),
        },
        execution_instructions: None,
        completion_target: normalize_completion_target_arg(args.completion_target),
        image_path: normalize_optional_string(args.image_path),
        created_at: timestamp.clone(),
        updated_at: timestamp,
        history_summary: None,
        history_commits: Vec::new(),
        history_completed_at: None,
        extra: Map::new(),
    };

    let mut items = load_queue(&project_root, &queue_name)?;
    if queue_name == "queued" {
        items.push(item.clone());
    } else {
        items.insert(0, item.clone());
    }
    save_queue(&project_root, &queue_name, &items)?;
    append_event(
        &project_root,
        "create_prompt",
        json!({
            "item_id": item.id,
            "queue": queue_name,
            "kind": item.kind,
        }),
    )?;

    Ok(json!({
        "project_root": project_root,
        "status": "created",
        "queue": queue_name,
        "item": item,
    }))
}

fn queue_fail_current(args: FailArgs) -> AppResult<Value> {
    let project_root = normalize_project_root(&args.project_root)?;
    let active =
        load_active_state(&project_root)?.ok_or_else(|| AppError::new("No active queue item"))?;
    let mut implemented = load_queue(&project_root, "implemented")?;
    let index = implemented
        .iter()
        .position(|item| item.id == active.item_id)
        .ok_or_else(|| AppError::new("Active item not found in implemented queue"))?;

    let mut item = implemented.remove(index);
    save_queue(&project_root, "implemented", &implemented)?;
    item.updated_at = timestamp();
    if let Some(note) = normalize_optional_string(args.note) {
        append_failure_note(&mut item, &note);
    }

    let mut queued = load_queue(&project_root, "queued")?;
    queued.insert(0, item.clone());
    save_queue(&project_root, "queued", &queued)?;

    clear_active_state(&project_root)?;
    append_event(
        &project_root,
        "fail_current",
        json!({
            "item_id": item.id,
            "returned_queue": "queued",
        }),
    )?;

    Ok(json!({
        "project_root": project_root,
        "status": "failed",
        "returned_queue": "queued",
        "item": item,
    }))
}

fn normalize_project_root(project_root: &str) -> AppResult<String> {
    let path = PathBuf::from(project_root);
    if !path.is_dir() {
        return Err(AppError::new(format!(
            "Project root does not exist: {project_root}"
        )));
    }
    let canonical = fs::canonicalize(path)?;
    Ok(canonical.to_string_lossy().into_owned())
}

fn normalize_optional_string(value: Option<String>) -> Option<String> {
    value.and_then(|entry| {
        let trimmed = entry.trim().to_string();
        if trimmed.is_empty() {
            None
        } else {
            Some(trimmed)
        }
    })
}

fn normalize_required_string(value: String, field: &str) -> AppResult<String> {
    let trimmed = value.trim().to_string();
    if trimmed.is_empty() {
        return Err(AppError::new(format!("Missing {field}")));
    }
    Ok(trimmed)
}

fn normalize_kind(value: Option<String>) -> String {
    let normalized = normalize_optional_string(value).unwrap_or_else(|| "todo".to_string());
    if PROMPT_KINDS.contains(&normalized.as_str()) {
        normalized
    } else {
        "todo".to_string()
    }
}

fn normalize_queue_name(value: Option<String>) -> String {
    let normalized = normalize_optional_string(value).unwrap_or_else(|| "planned".to_string());
    if QUEUE_NAMES.contains(&normalized.as_str()) {
        normalized
    } else {
        "planned".to_string()
    }
}

fn normalize_completion_target_arg(value: Option<String>) -> Option<String> {
    match normalize_optional_string(value).as_deref() {
        Some("history") => Some("history".to_string()),
        _ => None,
    }
}

fn normalize_completion_target(cli_target: Option<String>, item_target: Option<String>) -> String {
    let value = cli_target
        .or(item_target)
        .unwrap_or_else(|| "implemented".to_string());
    if value == "history" {
        "history".to_string()
    } else {
        "implemented".to_string()
    }
}

fn combine_commits(commit: Option<String>, commits: Option<Vec<String>>) -> Vec<String> {
    let mut values = Vec::new();
    if let Some(single) = normalize_optional_string(commit) {
        values.push(single);
    }
    if let Some(many) = commits {
        for entry in many {
            if let Some(trimmed) = normalize_optional_string(Some(entry)) {
                if !values.contains(&trimmed) {
                    values.push(trimmed);
                }
            }
        }
    }
    values
}

fn append_failure_note(item: &mut QueueItem, note: &str) {
    let section = format!("## Failure Note\n\n{note}");
    item.details = Some(match item.details.take() {
        Some(existing) if !existing.trim().is_empty() => {
            format!("{}\n\n{}", existing.trim(), section)
        }
        _ => section,
    });
    item.prompt = match &item.details {
        Some(details) => format!("{}\n\n{}", item.title, details),
        None => item.title.clone(),
    };
}

fn close_contract() -> Value {
    json!({
        "tool": "close_task",
        "version": 1,
        "workflow": "commit",
        "required_fields": {
            "success": "boolean",
            "comment": "string",
            "commit_id": "string"
        },
        "success_behavior": {
            "move_to": "implemented"
        },
        "failure_behavior": {
            "move_to": "queued",
            "append_failure_note": true
        }
    })
}

fn task_context(item: &QueueItem) -> Value {
    json!({
        "prior_commits": item.history_commits,
        "latest_comment": item.history_summary,
    })
}

fn work_prompt(item: &QueueItem) -> String {
    let prompt = item.prompt.trim();
    if !prompt.is_empty() {
        return prompt.to_string();
    }

    match &item.details {
        Some(details) if !details.trim().is_empty() => {
            format!("{}\n\n{}", item.title.trim(), details.trim())
        }
        _ => item.title.trim().to_string(),
    }
}

fn task_payload(item: &QueueItem) -> Value {
    json!({
        "id": item.id,
        "kind": item.kind,
        "title": item.title,
        "details": item.details,
        "work_prompt": work_prompt(item),
        "image_path": item.image_path,
    })
}

fn task_response(project_root: &str, item: &QueueItem, active_exists: bool) -> Value {
    let mut response = json!({
        "status": "task",
        "project_root": project_root,
        "task": task_payload(item),
        "close_contract": close_contract(),
        "context": task_context(item),
    });
    if active_exists {
        response["active"] = json!(true);
    }
    response
}

fn done_response(project_root: &str, closed_task: Option<Value>) -> Value {
    let mut response = json!({
        "status": "done",
        "project_root": project_root,
        "message": "No queued tasks remain.",
    });
    if let Some(closed_task) = closed_task {
        response["closed_task"] = closed_task;
    }
    response
}

fn extend_commits(
    existing: Vec<String>,
    commit: Option<String>,
    commits: Option<Vec<String>>,
) -> Vec<String> {
    let mut values = existing;
    for entry in combine_commits(commit, commits) {
        if !values.contains(&entry) {
            values.push(entry);
        }
    }
    values
}

fn claim_or_resume_item(project_root: &str) -> AppResult<TaskClaim> {
    if let Some(current) = load_active_state(project_root)? {
        if let Some(item) = find_item(project_root, "implemented", &current.item_id)? {
            return Ok(TaskClaim::Task {
                active: current,
                item,
                active_exists: true,
            });
        }
        clear_active_state(project_root)?;
    }

    let mut queued = load_queue(project_root, "queued")?;
    if queued.is_empty() {
        return Ok(TaskClaim::Done);
    }

    let mut item = queued.remove(0);
    item.updated_at = timestamp();
    save_queue(project_root, "queued", &queued)?;

    let mut implemented = load_queue(project_root, "implemented")?;
    implemented.insert(0, item.clone());
    save_queue(project_root, "implemented", &implemented)?;

    let active = ActiveItem {
        item_id: item.id.clone(),
        claimed_at: timestamp(),
        source_queue: "queued".to_string(),
    };
    save_active_state(project_root, &active)?;
    append_event(
        project_root,
        "claim_next",
        json!({
            "item_id": item.id,
            "queue": "implemented",
        }),
    )?;

    Ok(TaskClaim::Task {
        active,
        item,
        active_exists: false,
    })
}

fn claim_or_resume_task(project_root: &str) -> AppResult<Value> {
    Ok(match claim_or_resume_item(project_root)? {
        TaskClaim::Task {
            item,
            active_exists,
            ..
        } => task_response(project_root, &item, active_exists),
        TaskClaim::Done => done_response(project_root, None),
    })
}

fn closed_task_payload(item: &QueueItem, final_queue: &str, failure_note_appended: bool) -> Value {
    let mut response = json!({
        "id": item.id,
        "final_queue": final_queue,
        "history_summary": item.history_summary,
        "history_commits": item.history_commits,
    });
    if failure_note_appended {
        response["failure_note_appended"] = json!(true);
    }
    response
}

fn close_active_task(
    project_root: &str,
    success: bool,
    comment: Option<String>,
    commit_id: Option<String>,
) -> AppResult<Value> {
    let active =
        load_active_state(project_root)?.ok_or_else(|| AppError::new("No active queue item"))?;
    let mut implemented = load_queue(project_root, "implemented")?;
    let index = implemented
        .iter()
        .position(|item| item.id == active.item_id)
        .ok_or_else(|| AppError::new("Active item not found in implemented queue"))?;

    let mut item = implemented.remove(index);
    item.updated_at = timestamp();

    let closed_task = if success {
        let summary = comment.ok_or_else(|| AppError::new("Missing close_task comment"))?;
        let commit = commit_id.ok_or_else(|| AppError::new("Missing close_task commit_id"))?;
        item.history_summary = Some(summary);
        item.history_completed_at = Some(timestamp());
        item.history_commits = extend_commits(item.history_commits.clone(), Some(commit), None);

        let final_queue = normalize_completion_target(None, item.completion_target.clone());
        if final_queue == "history" {
            save_queue(project_root, "implemented", &implemented)?;
            let mut history = load_queue(project_root, "history")?;
            history.insert(0, item.clone());
            save_queue(project_root, "history", &history)?;
        } else {
            implemented.insert(index, item.clone());
            save_queue(project_root, "implemented", &implemented)?;
        }
        clear_active_state(project_root)?;
        append_event(
            project_root,
            "close_task",
            json!({
                "item_id": item.id,
                "final_queue": final_queue,
                "success": true,
            }),
        )?;
        closed_task_payload(&item, &final_queue, false)
    } else {
        if let Some(note) = comment {
            append_failure_note(&mut item, &note);
        }
        save_queue(project_root, "implemented", &implemented)?;
        let mut queued = load_queue(project_root, "queued")?;
        queued.insert(0, item.clone());
        save_queue(project_root, "queued", &queued)?;
        clear_active_state(project_root)?;
        append_event(
            project_root,
            "close_task",
            json!({
                "item_id": item.id,
                "final_queue": "queued",
                "success": false,
            }),
        )?;
        closed_task_payload(&item, "queued", true)
    };

    match claim_or_resume_item(project_root)? {
        TaskClaim::Task {
            item,
            active_exists,
            ..
        } => {
            let mut response = task_response(project_root, &item, active_exists);
            response["closed_task"] = closed_task;
            Ok(response)
        }
        TaskClaim::Done => Ok(done_response(project_root, Some(closed_task))),
    }
}

fn queue_status_value(project_root: &str) -> AppResult<Value> {
    let mut counts = Map::new();
    for queue_name in QUEUE_NAMES {
        counts.insert(
            queue_name.to_string(),
            json!(load_queue(project_root, queue_name)?.len()),
        );
    }

    let active = load_active_state(project_root)?;
    let current_item = match &active {
        Some(state) => find_item(project_root, "implemented", &state.item_id)?,
        None => None,
    };
    let next_item = load_queue(project_root, "queued")?.into_iter().next();

    Ok(json!({
        "counts": counts,
        "active": active,
        "current_item": current_item,
        "next_item": next_item,
    }))
}

fn workspace_dir(project_root: &str) -> PathBuf {
    Path::new(project_root).join(".clodex")
}

fn queue_file_path(project_root: &str, queue_name: &str) -> PathBuf {
    workspace_dir(project_root).join(format!("{queue_name}.json"))
}

fn runtime_dir(project_root: &str) -> PathBuf {
    workspace_dir(project_root).join("mcp")
}

fn active_file_path(project_root: &str) -> PathBuf {
    runtime_dir(project_root).join(ACTIVE_FILE_NAME)
}

fn events_file_path(project_root: &str) -> PathBuf {
    runtime_dir(project_root).join(EVENTS_FILE_NAME)
}

fn load_queue(project_root: &str, queue_name: &str) -> AppResult<Vec<QueueItem>> {
    let path = queue_file_path(project_root, queue_name);
    if !path.is_file() {
        return Ok(Vec::new());
    }
    let content = fs::read_to_string(path)?;
    if content.trim().is_empty() {
        return Ok(Vec::new());
    }
    let items = serde_json::from_str(&content)?;
    Ok(items)
}

fn save_queue(project_root: &str, queue_name: &str, items: &[QueueItem]) -> AppResult<()> {
    let path = queue_file_path(project_root, queue_name);
    write_json_file(&path, items)
}

fn load_active_state(project_root: &str) -> AppResult<Option<ActiveItem>> {
    let path = active_file_path(project_root);
    if !path.is_file() {
        return Ok(None);
    }
    let content = fs::read_to_string(path)?;
    if content.trim().is_empty() {
        return Ok(None);
    }
    let state = serde_json::from_str(&content)?;
    Ok(Some(state))
}

fn save_active_state(project_root: &str, state: &ActiveItem) -> AppResult<()> {
    let path = active_file_path(project_root);
    write_json_file(&path, state)
}

fn clear_active_state(project_root: &str) -> AppResult<()> {
    let path = active_file_path(project_root);
    if path.is_file() {
        fs::remove_file(path)?;
    }
    Ok(())
}

fn find_item(project_root: &str, queue_name: &str, item_id: &str) -> AppResult<Option<QueueItem>> {
    let items = load_queue(project_root, queue_name)?;
    Ok(items.into_iter().find(|item| item.id == item_id))
}

fn append_event(project_root: &str, event: &str, payload: Value) -> AppResult<()> {
    let path = events_file_path(project_root);
    ensure_parent_dir(&path)?;
    let mut file = fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(path)?;
    let entry = json!({
        "timestamp": timestamp(),
        "event": event,
        "payload": payload,
    });
    serde_json::to_writer(&mut file, &entry)?;
    file.write_all(b"\n")?;
    Ok(())
}

fn write_json_file<T: Serialize + ?Sized>(path: &Path, value: &T) -> AppResult<()> {
    ensure_parent_dir(path)?;
    let content = serde_json::to_vec(value)?;
    let suffix = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|_| AppError::new("System clock before unix epoch"))?
        .as_nanos();
    let file_name = path
        .file_name()
        .and_then(|name| name.to_str())
        .ok_or_else(|| AppError::new("Invalid output file name"))?;
    let tmp = path.with_file_name(format!(".{file_name}.{suffix}.tmp"));
    fs::write(&tmp, content)?;
    fs::rename(tmp, path)?;
    Ok(())
}

fn ensure_parent_dir(path: &Path) -> AppResult<()> {
    let parent = path
        .parent()
        .ok_or_else(|| AppError::new("Path has no parent directory"))?;
    fs::create_dir_all(parent)?;
    Ok(())
}

fn timestamp() -> String {
    Utc::now().format("%Y-%m-%dT%H:%M:%SZ").to_string()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Cursor;
    use tempfile::tempdir;

    fn sample_item(id: &str, title: &str) -> QueueItem {
        QueueItem {
            id: id.to_string(),
            kind: "todo".to_string(),
            title: title.to_string(),
            details: Some("details".to_string()),
            prompt: format!("{title}\n\ndetails"),
            execution_instructions: None,
            completion_target: None,
            image_path: None,
            created_at: timestamp(),
            updated_at: timestamp(),
            history_summary: None,
            history_commits: Vec::new(),
            history_completed_at: None,
            extra: Map::new(),
        }
    }

    fn project_root() -> (tempfile::TempDir, String) {
        let dir = tempdir().expect("tempdir");
        let root = dir.path().join("project");
        fs::create_dir_all(root.join(".clodex")).expect("workspace dir");
        (dir, root.to_string_lossy().into_owned())
    }

    #[test]
    fn reads_content_length_framed_messages() {
        let payload = br#"{"jsonrpc":"2.0","id":1,"method":"ping"}"#;
        let input = format!("Content-Length: {}\r\n\r\n", payload.len()).into_bytes();
        let mut bytes = input;
        bytes.extend_from_slice(payload);
        let mut reader = Cursor::new(bytes);

        let (message, transport) = read_message(&mut reader)
            .expect("read framed message")
            .expect("message");

        assert_eq!(transport, TransportMode::ContentLength);
        assert_eq!(message, payload);
    }

    #[test]
    fn reads_newline_delimited_messages() {
        let payload = b"{\"jsonrpc\":\"2.0\",\"id\":0,\"method\":\"initialize\"}\n";
        let mut reader = Cursor::new(payload);

        let (message, transport) = read_message(&mut reader)
            .expect("read line-delimited message")
            .expect("message");

        assert_eq!(transport, TransportMode::NewlineDelimited);
        assert_eq!(message, &payload[..payload.len() - 1]);
    }

    #[test]
    fn encodes_newline_delimited_responses_without_content_length_headers() {
        let response = JsonRpcResponse {
            jsonrpc: JSONRPC_VERSION,
            id: Some(json!(1)),
            result: Some(json!({ "ok": true })),
            error: None,
        };

        let encoded = encode_response_payload(&response, TransportMode::NewlineDelimited)
            .expect("encode line-delimited response");

        assert!(encoded.ends_with(b"\n"));
        assert!(!String::from_utf8_lossy(&encoded).contains("Content-Length:"));
        let decoded: Value =
            serde_json::from_slice(&encoded[..encoded.len() - 1]).expect("decode response");
        assert_eq!(decoded["id"], json!(1));
        assert_eq!(decoded["result"], json!({ "ok": true }));
    }

    #[test]
    fn claim_and_complete_to_history() {
        let (_dir, root) = project_root();
        save_queue(&root, "queued", &[sample_item("item-1", "first")]).expect("save queued");

        let claimed = queue_claim_next(ProjectRootArgs {
            project_root: root.clone(),
        })
        .expect("claim next");
        assert_eq!(claimed["status"], "claimed");
        assert_eq!(load_queue(&root, "queued").expect("queued len").len(), 0);
        assert_eq!(
            load_queue(&root, "implemented")
                .expect("implemented len")
                .len(),
            1
        );

        let completed = queue_complete_current(CompleteArgs {
            project_root: root.clone(),
            summary: Some("done".to_string()),
            commit: Some("abc123".to_string()),
            commits: None,
            completion_target: Some("history".to_string()),
        })
        .expect("complete current");

        assert_eq!(completed["final_queue"], "history");
        assert_eq!(
            load_queue(&root, "implemented")
                .expect("implemented len")
                .len(),
            0
        );
        let history = load_queue(&root, "history").expect("history len");
        assert_eq!(history.len(), 1);
        assert_eq!(history[0].history_summary.as_deref(), Some("done"));
        assert_eq!(history[0].history_commits, vec!["abc123".to_string()]);
        assert!(load_active_state(&root).expect("active state").is_none());
    }

    #[test]
    fn get_task_claims_then_returns_done_after_close() {
        let (_dir, root) = project_root();
        save_queue(&root, "queued", &[sample_item("item-1", "first")]).expect("save queued");

        let task = get_task(ProjectRootArgs {
            project_root: root.clone(),
        })
        .expect("get task");

        assert_eq!(task["status"], "task");
        assert_eq!(task["task"]["id"], "item-1");
        assert_eq!(task["context"]["prior_commits"], json!([]));

        let closed = close_task(CloseTaskArgs {
            project_root: root.clone(),
            success: true,
            comment: Some("done".to_string()),
            commit_id: Some("abc123".to_string()),
        })
        .expect("close task");

        assert_eq!(closed["status"], "done");
        assert_eq!(closed["closed_task"]["history_summary"], "done");
        assert_eq!(closed["closed_task"]["history_commits"], json!(["abc123"]));
    }

    #[test]
    fn get_task_resumes_existing_active_item() {
        let (_dir, root) = project_root();
        save_queue(&root, "queued", &[sample_item("item-1", "first")]).expect("save queued");

        let first = get_task(ProjectRootArgs {
            project_root: root.clone(),
        })
        .expect("first task");
        let resumed = get_task(ProjectRootArgs {
            project_root: root.clone(),
        })
        .expect("resumed task");

        assert_eq!(first["task"]["id"], resumed["task"]["id"]);
        assert_eq!(resumed["active"], true);
    }

    #[test]
    fn close_task_returns_next_queued_item() {
        let (_dir, root) = project_root();
        save_queue(
            &root,
            "queued",
            &[
                sample_item("item-1", "first"),
                sample_item("item-2", "second"),
            ],
        )
        .expect("save queued");

        get_task(ProjectRootArgs {
            project_root: root.clone(),
        })
        .expect("get first task");
        let response = close_task(CloseTaskArgs {
            project_root: root.clone(),
            success: true,
            comment: Some("finished first".to_string()),
            commit_id: Some("abc123".to_string()),
        })
        .expect("close first task");

        assert_eq!(response["status"], "task");
        assert_eq!(response["closed_task"]["id"], "item-1");
        assert_eq!(response["task"]["id"], "item-2");
    }

    #[test]
    fn create_prompt_adds_a_new_planned_item_by_default() {
        let (_dir, root) = project_root();

        let response = create_prompt(CreatePromptArgs {
            project_root: root.clone(),
            title: "Follow up after planning".to_string(),
            details: Some("Turn the agreed approach into an implementation prompt.".to_string()),
            kind: Some("idea".to_string()),
            queue: None,
            image_path: None,
            completion_target: None,
        })
        .expect("create prompt");

        assert_eq!(response["status"], "created");
        assert_eq!(response["queue"], "planned");
        assert_eq!(response["item"]["kind"], "idea");

        let planned = load_queue(&root, "planned").expect("planned queue");
        assert_eq!(planned.len(), 1);
        assert_eq!(planned[0].title, "Follow up after planning");
        assert_eq!(
            planned[0].prompt,
            "Follow up after planning\n\nTurn the agreed approach into an implementation prompt."
        );
    }

    #[test]
    fn create_prompt_appends_to_the_end_of_the_queued_lane() {
        let (_dir, root) = project_root();
        save_queue(&root, "queued", &[sample_item("item-1", "first")]).expect("save queued");

        let response = create_prompt(CreatePromptArgs {
            project_root: root.clone(),
            title: "second".to_string(),
            details: None,
            kind: Some("todo".to_string()),
            queue: Some("queued".to_string()),
            image_path: None,
            completion_target: None,
        })
        .expect("create queued prompt");

        assert_eq!(response["queue"], "queued");
        let queued = load_queue(&root, "queued").expect("queued queue");
        assert_eq!(queued.len(), 2);
        assert_eq!(queued[0].id, "item-1");
        assert_eq!(queued[1].title, "second");
    }

    #[test]
    fn close_task_failure_requeues_item_with_note() {
        let (_dir, root) = project_root();
        save_queue(&root, "queued", &[sample_item("item-1", "first")]).expect("save queued");

        get_task(ProjectRootArgs {
            project_root: root.clone(),
        })
        .expect("get task");
        let failed = close_task(CloseTaskArgs {
            project_root: root.clone(),
            success: false,
            comment: Some("tests failed".to_string()),
            commit_id: None,
        })
        .expect("close failed task");

        assert_eq!(failed["status"], "task");
        assert_eq!(failed["closed_task"]["final_queue"], "queued");
        assert_eq!(failed["task"]["id"], "item-1");
        assert!(failed["task"]["details"]
            .as_str()
            .expect("details")
            .contains("## Failure Note"));
    }

    #[test]
    fn close_task_appends_commit_history_for_notworking_items() {
        let (_dir, root) = project_root();
        let mut item = sample_item("item-1", "fix regression");
        item.kind = "notworking".to_string();
        item.history_summary = Some("previous fix".to_string());
        item.history_commits = vec!["old123".to_string()];
        save_queue(&root, "queued", &[item]).expect("save queued");

        let task = get_task(ProjectRootArgs {
            project_root: root.clone(),
        })
        .expect("get task");
        assert_eq!(task["context"]["prior_commits"], json!(["old123"]));
        assert_eq!(task["context"]["latest_comment"], "previous fix");

        let closed = close_task(CloseTaskArgs {
            project_root: root.clone(),
            success: true,
            comment: Some("new fix".to_string()),
            commit_id: Some("new456".to_string()),
        })
        .expect("close task");

        assert_eq!(closed["closed_task"]["history_summary"], "new fix");
        assert_eq!(
            closed["closed_task"]["history_commits"],
            json!(["old123", "new456"])
        );
    }

    #[test]
    fn fail_returns_active_item_to_queue() {
        let (_dir, root) = project_root();
        save_queue(&root, "queued", &[sample_item("item-1", "first")]).expect("save queued");
        queue_claim_next(ProjectRootArgs {
            project_root: root.clone(),
        })
        .expect("claim next");

        let failed = queue_fail_current(FailArgs {
            project_root: root.clone(),
            note: Some("tests failed".to_string()),
        })
        .expect("fail current");

        assert_eq!(failed["returned_queue"], "queued");
        assert_eq!(
            load_queue(&root, "implemented")
                .expect("implemented len")
                .len(),
            0
        );
        let queued = load_queue(&root, "queued").expect("queued len");
        assert_eq!(queued.len(), 1);
        assert!(queued[0]
            .details
            .as_deref()
            .expect("details")
            .contains("## Failure Note"));
        assert!(load_active_state(&root).expect("active state").is_none());
    }
}
