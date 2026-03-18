local Backend = require("clodex.backend")
local History = require("clodex.history")
local fs = require("clodex.util.fs")
local git = require("clodex.util.git")
local notify = require("clodex.util.notify")

---@class Clodex.ExecutionRunner
---@field app Clodex.App
---@field config Clodex.Config.Values
---@field active table<string, vim.SystemObj>
local Runner = {}
Runner.__index = Runner

---@param project Clodex.Project
---@param item Clodex.QueueItem
---@return string
local function run_key(project, item)
    return ("%s::%s"):format(project.root, item.id)
end

---@param execution Clodex.Workspace.Execution
---@param project Clodex.Project
---@param item Clodex.QueueItem
---@return string
local function run_dir(execution, project, item)
    return fs.join(execution:project_execution_dir(project), "runs", item.id)
end

---@param text string?
---@return string
local function trim_block(text)
    text = tostring(text or ""):gsub("\r\n", "\n"):gsub("\r", "\n")
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    return text
end

---@param path string
---@return table?
local function read_json_file(path)
    local decoded = fs.read_json(path, nil)
    return type(decoded) == "table" and decoded or nil
end

---@return table
local function output_schema()
    return {
        type = "object",
        additionalProperties = false,
        properties = {
            summary = {
                type = "string",
                description = "One short sentence summarizing the outcome or blocker.",
            },
            response = {
                type = "string",
                description = "Natural-language response for the user. Markdown is allowed.",
            },
        },
        required = { "summary", "response" },
    }
end

---@param message table?
---@return string?
local function response_summary(message)
    if type(message) ~= "table" then
        return nil
    end
    local summary = vim.trim(message.summary or "")
    return summary ~= "" and summary or nil
end

---@param project Clodex.Project
---@param item Clodex.QueueItem
---@param schema_path string
---@param output_path string
---@return string[]
local function build_command(project, item, schema_path, output_path)
    local cmd = {}
    cmd[#cmd + 1] = "exec"
    cmd[#cmd + 1] = "--cd"
    cmd[#cmd + 1] = project.root
    cmd[#cmd + 1] = "--skip-git-repo-check"
    cmd[#cmd + 1] = "--full-auto"
    cmd[#cmd + 1] = "--ephemeral"
    cmd[#cmd + 1] = "--output-schema"
    cmd[#cmd + 1] = schema_path
    cmd[#cmd + 1] = "--output-last-message"
    cmd[#cmd + 1] = output_path
    if item.image_path and fs.is_file(item.image_path) then
        cmd[#cmd + 1] = "--image"
        cmd[#cmd + 1] = item.image_path
    end
    cmd[#cmd + 1] = "-"
    return cmd
end

---@param app Clodex.App
---@param config Clodex.Config.Values
---@return Clodex.ExecutionRunner
function Runner.new(app, config)
    return setmetatable({
        app = app,
        config = config,
        active = {},
    }, Runner)
end

---@param config Clodex.Config.Values
function Runner:update_config(config)
    self.config = config
end

--- Returns the next queued item after the given item_id, or nil if none.
---@param project Clodex.Project
---@param current_item_id string
---@return Clodex.QueueItem?
function Runner:get_next_queued_item(project, current_item_id)
    local queues = self.app.queue:queues(project)
    if not queues or not queues.queued or #queues.queued == 0 then
        return nil
    end
    for i, item in ipairs(queues.queued) do
        if item.id == current_item_id and queues.queued[i + 1] then
            return queues.queued[i + 1]
        end
    end
    return nil
end

---@param project Clodex.Project
---@param item Clodex.QueueItem
---@param summary string?
function Runner:complete_item(project, item, summary)
    local queue_name = self.app.queue:find_item(project, item.id)
    if queue_name ~= "implemented" then
        return
    end

    local fallback_summary = vim.trim(summary or "")
    if fallback_summary == "" then
        return
    end

    self.app.queue:update_implemented_item(project, item.id, {
        summary = fallback_summary,
        commit = git.head_commit(project.root, true),
        completed_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    })
    self.app.queue_actions:remember_workspace_revision(project)
    History.append_prompt_resolved(project.name, item.title, fallback_summary)
end

---@param project Clodex.Project
---@param item Clodex.QueueItem
---@param result vim.SystemCompleted
---@param run_dir string
---@param output_path string
function Runner:handle_completion(project, item, result, run_dir, output_path)
    local message = read_json_file(output_path)
    fs.remove(run_dir)

    if result.code == 0 then
        local summary = response_summary(message)
        self:complete_item(project, item, summary)
        local still_in_implemented = self.app.queue:find_item(project, item.id) == "implemented"
        if still_in_implemented then
            notify.warn(
                ("Direct Codex run finished for %s but did not update the implemented item automatically: %s\n\n%s"):format(
                    project.name,
                    item.title,
                    self.app.queue_cycle:next_item_guidance(project)
                )
            )
        else
            notify.notify(
                ("Direct Codex run finished for %s: %s\n\n%s"):format(
                    project.name,
                    item.title,
                    self.app.queue_cycle:next_item_guidance(project)
                )
            )
        end
    else
        notify.error(
            ("Direct Codex run failed for %s: %s (exit %d)"):format(project.name, item.title, result.code)
        )
    end

    self.app.project_details_store:touch_activity(project)
    self.app:refresh_changed_project_buffers()
    self.app:refresh_views()
end

---@param project Clodex.Project
---@param item Clodex.QueueItem
---@return boolean
function Runner:start(project, item)
    if not Backend.supports_direct_exec(self.config.backend) then
        notify.warn(
            ("%s direct exec mode is not supported yet; use the interactive session flow instead."):format(
                Backend.display_name(self.config.backend)
            )
        )
        return false
    end

    local key = run_key(project, item)
    if self.active[key] then
        notify.warn(("Direct Codex run is already active for %s: %s"):format(project.name, item.title))
        return false
    end

    local dir = run_dir(self.app.execution, project, item)
    local schema_path = fs.join(dir, "response.schema.json")
    local output_path = fs.join(dir, "last-message.json")
    local next_item = self:get_next_queued_item(project, item.id)
    local prompt = self.app.execution:dispatch_prompt(project, item, next_item)
    if prompt == "" then
        notify.warn(("Cannot run empty prompt for %s"):format(project.name))
        return false
    end
    local cmd = Backend.cli_cmd(self.config)
    vim.list_extend(cmd, build_command(project, item, schema_path, output_path))

    fs.write_json(schema_path, output_schema())

    local ok, system = pcall(vim.system, cmd, {
        cwd = project.root,
        text = true,
        stdin = prompt,
    }, vim.schedule_wrap(function(result)
        self.active[key] = nil
        self:handle_completion(project, item, result, dir, output_path)
    end))

    if not ok or not system then
        notify.error(("Could not start direct Codex run for %s: %s"):format(project.name, item.title))
        return false
    end

    self.active[key] = system
    self.app.project_details_store:touch_activity(project)
    return true
end

return Runner
