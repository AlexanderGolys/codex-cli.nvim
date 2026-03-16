local fs = require("clodex.util.fs")

--- Generates and persists prompt-instruction payloads used by the Codex execution pipeline.
--- This object bridges queue items to terminal jobs and project-local workspace mutations.
---@class Clodex.Workspace.Execution
---@field config Clodex.Config.Values
local Execution = {}
Execution.__index = Execution

local SKILL_TEMPLATE = [[---
name: %s
description: Handle clodex.nvim queued prompt executions by updating the local workspace queue file when the work is complete.
---

Treat obvious typos in the user-written title and prompt text as mistakes to silently normalize before you interpret the task.
Keep the original intent, but do not preserve clearly accidental misspellings, duplicated words, or broken punctuation in your understanding of the request.

# Queue Completion

Use this skill when a prompt includes `$%s`.

When the prompt provides a project workspace path and queued item id before the skill call:

1. Finish the requested work first.
2. Update the exact workspace JSON file provided by the prompt only after the work is complete.
3. Find the queue item with the provided id in `queues.queued`.
4. Move that same item into `queues.history` without changing its `id`.
5. Set `history_summary`, `history_commit` when available, `history_completed_at`, and refresh `updated_at`.
6. If the item is already in `queues.history`, update it in place instead of duplicating it.
7. If more prompts are waiting in the project's workspace file under `queues.queued`, continue with the next queued prompt immediately after finishing the current one.
8. Repeat until `queues.queued` is empty. Do not start prompts that are only in `queues.planned`.
]]

--- Builds the markdown guidance block that is appended to prompts requiring workspace updates.
--- It includes the file path and queued item id so downstream agents can complete work in-place.
--- This block is injected for both direct prompts and skill-directed prompts.
local function completion_instruction_lines(workspace_path, item_id)
    return {
        ("Project workspace path: `%s`"):format(workspace_path),
        ("Current queued item id: `%s`"):format(item_id),
    }
end

--- Adds optional image-context lines at the top of a generated prompt body.
--- It keeps item-level context uniform for the execution engine and user-visible behavior.
--- Image details are included only when a valid file path is present.
---@param item Clodex.QueueItem
---@return string[]
local function prompt_prefix_lines(item)
    local lines = {} ---@type string[]
    if item.image_path and fs.is_file(item.image_path) then
        lines[#lines + 1] = ("Primary visual reference: `%s`"):format(item.image_path)
        lines[#lines + 1] = "Use that local image file as part of the implementation context."
        lines[#lines + 1] = ""
    end
    lines[#lines + 1] = ""
    return lines
end

local function trim(value)
    return vim.trim(value or "")
end

local function is_absolute_path(path)
    path = fs.normalize(path)
    return vim.startswith(path, "/") or path:match("^%a:[/\\]") ~= nil
end

--- Computes a stable directory name for one project's local execution data.
---@param project_root string
---@return string
local function project_id(project_root)
    return vim.fn.sha256(fs.normalize(project_root)):sub(1, 16)
end

--- Resolves the canonical project-local execution root.
--- The old `receipts_dir` option is still honored as the base artifacts directory for compatibility.
---@param config Clodex.Config.Values
---@param project_root string
---@return string
local function execution_dir(config, project_root)
    local dir = trim(config.prompt_execution.receipts_dir)
    if dir ~= "" then
        local expanded = fs.normalize(vim.fn.expand(dir))
        if is_absolute_path(expanded) then
            return expanded
        end
        return fs.join(project_root, expanded)
    end
    return fs.join(project_root, ".clodex", "prompt-executions")
end

---@param root_dir string
---@param project_root string
---@return string
local function workspace_storage_dir(root_dir, project_root)
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
    local storage_dir = workspace_storage_dir(config.storage.workspaces_dir, project_root)
    return fs.join(storage_dir, project_id(project_root) .. ".json")
end

--- Resolves the configured project-local directory where generated skill files are stored.
--- Returns nil when skill mode is disabled.
--- This controls whether `$prompt` or `$<skill>` execution mode is active.
---@param config Clodex.Config.Values
---@param project_root string
---@return string?
local function skills_dir(config, project_root)
    local dir = trim(config.prompt_execution.skills_dir)
    if dir == "" then
        return nil
    end
    return fs.join(project_root, dir)
end

local function skill_name(config)
    local name = trim(config.prompt_execution.skill_name)
    return name ~= "" and name or "prompt-nvim-clodex"
end

--- Renders the full SKILL.md template for the currently configured skill name.
--- It keeps the generated skill content stable and traceable in testable text form.
---@param config Clodex.Config.Values
---@return string
local function generated_skill_content(config)
    local name = skill_name(config)
    return SKILL_TEMPLATE:format(name, name)
end

--- Resolves the final on-disk project-local skill directory.
---@param config Clodex.Config.Values
---@param project_root string
---@return string?
local function installed_skill_dir(config, project_root)
    local dir = skills_dir(config, project_root)
    if not dir then
        return nil
    end

    local name = skill_name(config)
    return fs.join(dir, name)
end

--- The created object is used by app runtime to dispatch prompt text and write project-local helpers.
---@param config Clodex.Config.Values
---@return Clodex.Workspace.Execution
function Execution.new(config)
    local self = setmetatable({}, Execution)
    self.config = config
    return self
end

--- Replaces the cached config so in-flight execution behavior stays aligned with updated user options.
---@param config Clodex.Config.Values
function Execution:update_config(config)
    self.config = config
end

--- Reports whether execution should use a generated skill (`$<name>`) instead of raw `$prompt`.
--- This branch influences how queue items are formatted before being sent to the terminal.
---@return boolean
function Execution:uses_prompt_skill()
    return trim(self.config.prompt_execution.skill_name) ~= "" and trim(self.config.prompt_execution.skills_dir) ~= ""
end

--- Returns the effective project-local skill directory and asserts it exists when skill mode is enabled.
---@param project Clodex.Project
---@return string
function Execution:skill_dir(project)
    return assert(installed_skill_dir(self.config, project.root))
end

--- Returns the path to the generated project-local SKILL.md file.
---@param project Clodex.Project
---@return string
function Execution:skill_file(project)
    return fs.join(self:skill_dir(project), "SKILL.md")
end

--- Returns the project-scoped directory used for local execution artifacts.
---@param project Clodex.Project
---@return string
function Execution:project_execution_dir(project)
    return fs.join(execution_dir(self.config, project.root), project_id(project.root))
end

--- Updates the generated project-local skill file for one project.
--- This keeps queued execution self-contained inside the project workspace.
---@param project Clodex.Project
function Execution:ensure_prompt_skill(project)
    if not self:uses_prompt_skill() then
        return
    end

    local content = generated_skill_content(self.config)
    fs.write_file(self:skill_file(project), content)
end

---@param project Clodex.Project
---@param item Clodex.QueueItem
---@return string
function Execution:dispatch_prompt(project, item)
    self:ensure_prompt_skill(project)
    local instruction_lines = completion_instruction_lines(workspace_path(self.config, project.root), item.id)

    local prompt_lines = prompt_prefix_lines(item)
    prompt_lines[#prompt_lines + 1] = item.prompt

    if self:uses_prompt_skill() then
        local lines = vim.deepcopy(prompt_lines)
        lines[#lines + 1] = ""
    vim.list_extend(lines, instruction_lines)
        lines[#lines + 1] = ("$%s"):format(skill_name(self.config))
        return table.concat(lines, "\n")
    end

    local lines = vim.deepcopy(prompt_lines)
    lines[#lines + 1] = ""
    lines[#lines + 1] = "$prompt"
    vim.list_extend(lines, instruction_lines)
    return table.concat(lines, "\n")
end

return Execution
