local Prompt = require("clodex.prompt")
local fs = require("clodex.util.fs")
local util = require("clodex.util")

--- Queue names represent the supported lanes for prompt entries: planned, queued, implemented, and history.
---@alias Clodex.QueueName "planned"|"queued"|"implemented"|"history"

--- Canonical representation of one queued prompt item.
---@class Clodex.QueueItem
---@field id string
---@field kind Clodex.PromptCategory
---@field title string
---@field details? string
---@field prompt string
---@field execution_instructions? string
---@field completion_target? Clodex.QueueName
---@field image_path? string
---@field created_at string
---@field updated_at string
---@field history_summary? string
---@field history_commits string[]
---@field history_commit? string
---@field history_completed_at? string

--- Human-friendly queue summary assembled for UI and project-level diagnostics.
---@class Clodex.ProjectQueueSummary
---@field project Clodex.Project
---@field session_running boolean
---@field session_working boolean
---@field last_updated_at string
---@field counts table<Clodex.QueueName, integer>
---@field queues table<Clodex.QueueName, Clodex.QueueItem[]>

---@class Clodex.Workspace.Queue
---@field root_dir string
local Queue = {}
Queue.__index = Queue

---@return string
local function iso_utc_now()
    local timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
    return type(timestamp) == "string" and timestamp or ""
end

local ORDER = { "planned", "queued", "implemented", "history" }

---@param root_dir? string
---@return Clodex.Workspace.Queue
function Queue.new(root_dir)
    return setmetatable({ root_dir = root_dir or ".clodex" }, Queue)
end
local NEXT_QUEUE = {
    planned = "queued",
    queued = "implemented",
    implemented = "history",
}
local KNOWN_QUEUES = {
    planned = true,
    queued = true,
    implemented = true,
    history = true,
}

---@param items Clodex.QueueItem[]
---@param queue_name Clodex.QueueName
---@param item Clodex.QueueItem
local function insert_queue_item(items, queue_name, item)
    if queue_name == "queued" then
        items[#items + 1] = item
        return
    end
    table.insert(items, 1, item)
end

--- Returns the path to a queue file for a project.
---@param project_root string
---@param queue_name string
---@return string
local function queue_file_path(project_root, queue_name)
    return fs.join(project_root, ".clodex", queue_name .. ".json")
end

--- Returns the old (legacy) workspace file path.
---@param project_root string
---@return string
local function legacy_workspace_path(project_root)
    local id = vim.fn.sha256(fs.normalize(project_root)):sub(1, 16)
    return fs.join(project_root, ".clodex", "workspaces", id .. ".json")
end

---@param item any
---@return boolean
local function has_item_id(item)
    return type(item) == "table" and type(item.id) == "string" and vim.trim(item.id) ~= ""
end

---@param item Clodex.QueueItem
local function sanitize_history_metadata(item)
    if type(item.history_summary) ~= "string" or vim.trim(item.history_summary) == "" then
        item.history_summary = nil
    else
        item.history_summary = vim.trim(item.history_summary)
    end

    if item.history_commits == nil and type(item.history_commit) == "string" and vim.trim(item.history_commit) ~= "" then
        item.history_commits = { item.history_commit }
    end
    item.history_commit = nil

    if type(item.history_commits) ~= "table" then
        item.history_commits = {}
        return
    end

    local commits = {} ---@type string[]
    for _, commit in ipairs(item.history_commits) do
        if type(commit) == "string" then
            commit = vim.trim(commit)
            if commit ~= "" then
                commits[#commits + 1] = commit
            end
        end
    end
    item.history_commits = commits
end

---@param item any
---@return Clodex.QueueItem
local function normalize_item(item)
    item = vim.deepcopy(item)
    if not has_item_id(item) then
        item.id = util.uuid_v4()
    end
    item.kind = Prompt.categories.is_valid(item.kind) and item.kind or "todo"
    sanitize_history_metadata(item)
    if type(item.execution_instructions) ~= "string" or vim.trim(item.execution_instructions) == "" then
        item.execution_instructions = nil
    end
    if type(item.image_path) ~= "string" or vim.trim(item.image_path) == "" then
        item.image_path = nil
    end
    if item.completion_target ~= "history" then
        item.completion_target = nil
    end
    return item
end

--- Loads a single queue file, returns empty array if missing.
---@param project_root string
---@param queue_name string
---@return Clodex.QueueItem[]
local function load_queue_file(project_root, queue_name)
    local path = queue_file_path(project_root, queue_name)
    local data = fs.read_json(path, nil)
    if type(data) ~= "table" then
        return {}
    end
    if type(data[1]) == "table" then
        local items = {}
        for _, item in ipairs(data) do
            items[#items + 1] = normalize_item(item)
        end
        return items
    end
    return {}
end

--- Saves a queue file.
---@param project_root string
---@param queue_name string
---@param items Clodex.QueueItem[]
local function save_queue_file(project_root, queue_name, items)
    local path = queue_file_path(project_root, queue_name)
    fs.write_json(path, items)
end

--- Migrates from old workspace format to new separate files.
---@param project_root string
local function migrate_from_legacy(project_root)
    local legacy_path = legacy_workspace_path(project_root)
    if not fs.is_file(legacy_path) then
        return
    end

    local data = fs.read_json(legacy_path, nil)
    if type(data) ~= "table" or type(data.queues) ~= "table" then
        return
    end

    for _, queue_name in ipairs(ORDER) do
        local items = data.queues[queue_name]
        if type(items) == "table" and #items > 0 then
            local normalized = {}
            for _, item in ipairs(items) do
                normalized[#normalized + 1] = normalize_item(item)
            end
            save_queue_file(project_root, queue_name, normalized)
        end
    end

    fs.remove(legacy_path)
end

--- Returns a summary of all queues for a project.
---@param project Clodex.Project
---@param session_running? boolean
---@param session_working? boolean
---@return Clodex.ProjectQueueSummary
function Queue:summary(project, session_running, session_working)
    local queues = self:queues(project)
    local latest = ""
    for _, queue_name in ipairs(ORDER) do
        for _, item in ipairs(queues[queue_name]) do
            if type(item.updated_at) == "string" and item.updated_at > latest then
                latest = item.updated_at
            end
        end
    end

    return {
        project = project,
        session_running = session_running == true,
        session_working = session_working == true,
        last_updated_at = latest,
        counts = {
            planned = #queues.planned,
            queued = #queues.queued,
            implemented = #queues.implemented,
            history = #queues.history,
        },
        queues = queues,
    }
end

---@param project Clodex.Project
---@return table<Clodex.QueueName, Clodex.QueueItem[]>
function Queue:queues(project)
    migrate_from_legacy(project.root)

    return {
        planned = load_queue_file(project.root, "planned"),
        queued = load_queue_file(project.root, "queued"),
        implemented = load_queue_file(project.root, "implemented"),
        history = load_queue_file(project.root, "history"),
    }
end

---@param project Clodex.Project
---@param queue_name Clodex.QueueName
---@return Clodex.QueueItem[]
function Queue:queue(project, queue_name)
    if not KNOWN_QUEUES[queue_name] then
        return {}
    end
    migrate_from_legacy(project.root)
    return load_queue_file(project.root, queue_name)
end

---@param project Clodex.Project
---@return string
function Queue:workspace_path(project)
    return fs.join(project.root, ".clodex")
end

---@param project Clodex.Project
---@return string?
function Queue:workspace_revision(project)
    local latest ---@type integer?
    for _, queue_name in ipairs(ORDER) do
        local path = queue_file_path(project.root, queue_name)
        local stat = fs.stat(path)
        if stat and stat.mtime and stat.mtime.sec then
            if not latest or stat.mtime.sec > latest then
                latest = stat.mtime.sec
            end
        end
    end
    return latest and tostring(latest) or nil
end

---@param project Clodex.Project
---@param item_id string
---@param expected_queue? Clodex.QueueName
---@return Clodex.QueueName?, integer?, Clodex.QueueItem?
function Queue:find_item(project, item_id, expected_queue)
    local queues_to_search = expected_queue and { expected_queue } or ORDER
    for _, queue_name in ipairs(queues_to_search) do
        local items = self:queue(project, queue_name)
        for index, item in ipairs(items) do
            if item.id == item_id then
                return queue_name, index, item
            end
        end
    end
end

---@param project Clodex.Project
---@param spec { title: string, details?: string, queue?: Clodex.QueueName, kind?: Clodex.PromptCategory, image_path?: string, execution_instructions?: string, completion_target?: Clodex.QueueName }
---@return Clodex.QueueItem
function Queue:add_todo(project, spec)
    local queue_name = KNOWN_QUEUES[spec.queue] and spec.queue or "planned"
    local timestamp = iso_utc_now()
    local title = vim.trim(spec.title)
    local details = spec.details and vim.trim(spec.details) or nil

    local item = normalize_item({
        kind = Prompt.categories.is_valid(spec.kind) and spec.kind or "todo",
        title = title,
        details = details,
        prompt = title .. (details and ("\n\n" .. details) or ""),
        execution_instructions = spec.execution_instructions,
        completion_target = spec.completion_target,
        image_path = spec.image_path and vim.trim(spec.image_path) or nil,
        created_at = timestamp,
        updated_at = timestamp,
    })

    local items = self:queue(project, queue_name)
    insert_queue_item(items, queue_name, item)
    save_queue_file(project.root, queue_name, items)
    return item
end

---@param project Clodex.Project
---@param item_id string
---@param expected_queue? Clodex.QueueName
---@return Clodex.QueueItem?, Clodex.QueueName?
function Queue:take_item(project, item_id, expected_queue)
    local queues_to_search = expected_queue and { expected_queue } or ORDER
    for _, queue_name in ipairs(queues_to_search) do
        local items = self:queue(project, queue_name)
        for index, item in ipairs(items) do
            if item.id == item_id then
                table.remove(items, index)
                save_queue_file(project.root, queue_name, items)
                return item, queue_name
            end
        end
    end
end

---@param project Clodex.Project
---@param queue_name Clodex.QueueName
---@param item Clodex.QueueItem
---@param opts? {
---  copy?: boolean,
---  clear_history?: boolean,
---  execution_instructions?: string|false,
---}
---@return Clodex.QueueItem?
function Queue:put_item(project, queue_name, item, opts)
    if not KNOWN_QUEUES[queue_name] then
        return
    end

    opts = opts or {}
    local items = self:queue(project, queue_name)
    local timestamp = iso_utc_now()
    local moved = vim.deepcopy(item)

    if opts.copy then
        moved.id = util.uuid_v4()
        moved.created_at = timestamp
    end
    moved.updated_at = timestamp

    if opts.clear_history then
        moved.history_summary = nil
        moved.history_commits = {}
        moved.history_completed_at = nil
    end
    if opts.execution_instructions ~= nil then
        moved.execution_instructions = opts.execution_instructions ~= false and opts.execution_instructions or nil
    end
    sanitize_history_metadata(moved)

    insert_queue_item(items, queue_name, moved)
    save_queue_file(project.root, queue_name, items)
    return moved
end

---@param project Clodex.Project
---@param item_id string
---@param attrs {
---  title?: string,
---  details?: string|false,
---  history_summary?: string|false,
---  history_commits?: string[]|false,
---  history_completed_at?: string|false,
---  kind?: Clodex.PromptCategory,
---  execution_instructions?: string|false,
---  completion_target?: Clodex.QueueName|false,
---}
---@return Clodex.QueueItem?
function Queue:update_item(project, item_id, attrs)
    for _, queue_name in ipairs(ORDER) do
        local items = self:queue(project, queue_name)
        for _, item in ipairs(items) do
            if item.id == item_id then
                if attrs.title ~= nil then
                    item.title = vim.trim(attrs.title)
                end
                if attrs.details ~= nil then
                    item.details = attrs.details ~= false and vim.trim(attrs.details) or nil
                end
                if attrs.kind ~= nil and Prompt.categories.is_valid(attrs.kind) then
                    item.kind = attrs.kind
                end
                if attrs.title ~= nil or attrs.details ~= nil then
                    item.prompt = item.title .. (item.details and ("\n\n" .. item.details) or "")
                end
                if attrs.history_summary ~= nil then
                    item.history_summary = attrs.history_summary ~= false and attrs.history_summary or nil
                end
                if attrs.history_commits ~= nil then
                    if attrs.history_commits == false then
                        item.history_commits = {}
                    elseif attrs.history_commits then
                        if item.kind == "notworking" and item.history_commits then
                            for _, commit in ipairs(attrs.history_commits) do
                                if not vim.list_contains(item.history_commits, commit) then
                                    item.history_commits[#item.history_commits + 1] = commit
                                end
                            end
                        else
                            item.history_commits = attrs.history_commits
                        end
                    end
                end
                if attrs.history_completed_at ~= nil then
                    item.history_completed_at = attrs.history_completed_at ~= false and attrs.history_completed_at or nil
                end
                if attrs.execution_instructions ~= nil then
                    item.execution_instructions = attrs.execution_instructions ~= false and attrs.execution_instructions or nil
                end
                if attrs.completion_target ~= nil then
                    item.completion_target = attrs.completion_target ~= false and attrs.completion_target or nil
                end
                sanitize_history_metadata(item)
                item.updated_at = iso_utc_now()
                save_queue_file(project.root, queue_name, items)
                return vim.deepcopy(item)
            end
        end
    end
end

---@param project Clodex.Project
---@param item_id string
---@return boolean
function Queue:delete_item(project, item_id)
    for _, queue_name in ipairs(ORDER) do
        local items = self:queue(project, queue_name)
        for index, item in ipairs(items) do
            if item.id == item_id then
                table.remove(items, index)
                save_queue_file(project.root, queue_name, items)
                return true
            end
        end
    end
    return false
end

---@param project Clodex.Project
---@param item_id string
---@return Clodex.QueueName?
function Queue:advance(project, item_id)
    local queue_name, _, item = self:find_item(project, item_id)
    local next_queue = queue_name and NEXT_QUEUE[queue_name] or nil
    if not next_queue or not item then
        return
    end

    self:take_item(project, item_id, queue_name)
    self:put_item(project, next_queue, item, {})
    return next_queue
end

---@param project Clodex.Project
---@param item_id string
---@param result { summary?: string|false, commit?: string|false, completed_at?: string|false }
---@return Clodex.QueueItem?
function Queue:update_implemented_item(project, item_id, result)
    local commits = nil ---@type string[]|false|nil
    if result.commit ~= nil then
        commits = result.commit ~= false and { result.commit } or false
    end
    return self:update_item(project, item_id, {
        history_summary = result.summary,
        history_commits = commits,
        history_completed_at = result.completed_at,
    })
end

return Queue
