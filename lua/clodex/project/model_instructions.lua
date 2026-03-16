local fs = require("clodex.util.fs")

---@class Clodex.ProjectModelInstructions
---@field config Clodex.Config.Values
local ModelInstructions = {}
ModelInstructions.__index = ModelInstructions

local function trim(value)
    return vim.trim(value or "")
end

---@param path string
---@return boolean
local function is_absolute_path(path)
    path = trim(path)
    return path ~= "" and (vim.startswith(path, "/") or path:match("^%a:[/\\]") ~= nil)
end

---@param project_root string
---@return string
local function project_id(project_root)
    return vim.fn.sha256(fs.normalize(project_root)):sub(1, 16)
end

---@param root_dir string
---@param project_root string
---@return string
local function project_storage_dir(root_dir, project_root)
    local normalized = fs.normalize(root_dir)
    if is_absolute_path(normalized) then
        return normalized
    end
    return fs.join(project_root, normalized)
end

---@param config Clodex.Config.Values
---@param project_root string
---@return string
local function workspace_path(config, project_root)
    local storage_dir = project_storage_dir(config.storage.workspaces_dir, project_root)
    return fs.join(storage_dir, project_id(project_root) .. ".json")
end

---@param config Clodex.Config.Values
---@param project_root string
---@return string?
local function instructions_path(config, project_root)
    local relative = trim(config.manual_history.model_instructions_file)
    if relative == "" then
        return nil
    end
    if is_absolute_path(relative) then
        return fs.normalize(relative)
    end
    return fs.join(project_root, relative)
end

---@param path string
---@return string
local function toml_string(path)
    return vim.json.encode(fs.normalize(path))
end

---@param project Clodex.Project
---@param config Clodex.Config.Values
---@return string
local function instructions_content(project, config)
    local path = workspace_path(config, project.root)
    return table.concat({
        "# Project History Records",
        "",
        "Use these instructions only for direct project work done from normal Codex CLI conversation in this repository.",
        "Do not use this file for queued prompt execution; queued prompts already manage their own workspace updates.",
        "",
        ("Project workspace path: `%s`"):format(path),
        "",
        "When you complete a user-requested implementation, bug fix, or other code change in this project outside the queue workflow:",
        "",
        "1. Update the workspace JSON file above after the work is complete.",
        "2. Add a new item to the front of `queues.history` unless the newest matching history item already represents the same completed task, in which case update it in place.",
        "3. Do not modify unrelated `queues.planned` or `queues.queued` items.",
        "4. Normalize obvious typos in the user request before you turn it into a title, prompt, or summary.",
        "5. Keep the original intent, but do not preserve clearly accidental misspellings, duplicated words, or broken punctuation.",
        "6. Use a concise `title` that describes the completed task.",
        "7. Set `kind` to `error` for bug fixes or regressions, otherwise use the closest existing queue category such as `todo`, `refactor`, `adjustment`, or `idea`.",
        "8. Set `details` when extra context from the user request matters later; otherwise leave it unset.",
        "9. Set `prompt` to a clean plain-text version of the request that could have been queued manually.",
        "10. Set `history_summary` to a short summary of what changed or what blocker remains.",
        "11. Set `history_commit` when a commit exists, otherwise leave it unset.",
        "12. Set `history_completed_at` and `updated_at` to a UTC timestamp like `2026-03-13T16:40:17Z`.",
        "13. If you create a new history item, also set `created_at` and include a non-empty `id`; a generated unique string is fine.",
        "14. Preserve existing items instead of rewriting the whole file unnecessarily.",
        "",
        "Only create or update a history record when the conversation actually resulted in project work worth remembering. Do not create history items for pure discussion, exploration, or no-op answers.",
    }, "\n")
end

---@param config Clodex.Config.Values
---@return Clodex.ProjectModelInstructions
function ModelInstructions.new(config)
    return setmetatable({
        config = config,
    }, ModelInstructions)
end

---@param config Clodex.Config.Values
function ModelInstructions:update_config(config)
    self.config = config
end

---@param project Clodex.Project
---@return boolean
function ModelInstructions:is_enabled(project)
    return project ~= nil and instructions_path(self.config, project.root) ~= nil
end

---@param project Clodex.Project
---@return string?
function ModelInstructions:path(project)
    return project and instructions_path(self.config, project.root) or nil
end

---@param project Clodex.Project
---@return string[]
function ModelInstructions:codex_args(project)
    local path = self:path(project)
    if not path then
        return {}
    end

    fs.write_file(path, instructions_content(project, self.config))
    return {
        "-c",
        "model_instructions_file=" .. toml_string(path),
    }
end

return ModelInstructions
