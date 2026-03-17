local Prompt = require("clodex.prompt")
local fs = require("clodex.util.fs")

--- Generates and persists prompt-instruction payloads used by the Codex execution pipeline.
--- This object bridges queue items to terminal jobs and workspace mutations.
---@class Clodex.Workspace.Execution
---@field config Clodex.Config.Values
local Execution = {}
Execution.__index = Execution

local SKILL_TEMPLATE = [[---
name: prompt-nvim-clodex
description: Handle clodex.nvim queued prompt executions by updating the local workspace queue file when the work is complete.
---

Treat obvious typos in the user-written title and prompt text as mistakes to silently normalize before you interpret the task.
Keep the original intent, but do not preserve clearly accidental misspellings, duplicated words, or broken punctuation in your understanding of the request.

# Queue Completion

Use this skill when a prompt includes `$__CLODEX_SKILL_NAME__`.

When the prompt provides a queue item id and prompt kind before the skill call:

1. Finish the requested work first.
2. If the prompt kind is `ask`, do not create a commit for this queue item.
3. For any other prompt kind, create a focused git commit before you update the queue item when the project root is git-backed. If the project root is not a git repository, skip the commit step and leave `history_commit` unset.
4. Resolve the project-local workspace JSON file from the current repository root as `.clodex/workspaces/<sha256(project_root):sub(1, 16)>.json`, then update that file only after the work is complete.
5. Find the queue item with the provided id in `queues.queued`, `queues.implemented`, or `queues.history`.
6. If it is still in `queues.queued`, move that same item into `queues.implemented` without changing its `id`.
7. If it is already in `queues.implemented`, update it in place.
8. If it is already in `queues.history`, update it in place instead of duplicating it.
9. Set `history_summary`, `history_commit` when a commit exists, `history_completed_at`, and refresh `updated_at`.
10. If more prompts are waiting in the project's workspace file under `queues.queued`, continue with the next queued prompt immediately after finishing the current one.
11. Repeat until `queues.queued` is empty. Do not start prompts that are only in `queues.planned` or `queues.implemented`.
]]

local SOURCE_PATH = fs.normalize(debug.getinfo(1, "S").source:sub(2))
local REPO_ROOT = fs.dirname(fs.dirname(fs.dirname(fs.dirname(SOURCE_PATH))))
local REPO_SKILL_TEMPLATE_PATH = fs.join(REPO_ROOT, ".codex", "skills", "prompt-nvim-clodex", "SKILL.md")

local function trim(value)
    return vim.trim(value or "")
end

local function is_absolute_path(path)
    path = fs.normalize(path)
    return vim.startswith(path, "/") or path:match("^%a:[/\\]") ~= nil
end

---@return string
local function codex_home()
    local configured = trim(vim.env.CODEX_HOME)
    if configured ~= "" then
        return fs.normalize(vim.fn.expand(configured))
    end

    return fs.join(vim.fn.expand("~"), ".codex")
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

---@param config Clodex.Config.Values
---@return string?
local function skills_dir(config)
    local dir = trim(config.prompt_execution.skills_dir)
    if dir == "" then
        return nil
    end

    local expanded = fs.normalize(vim.fn.expand(dir))
    if is_absolute_path(expanded) then
        return expanded
    end
    return fs.join(codex_home(), expanded)
end

---@param config Clodex.Config.Values
---@return string
local function skill_name(config)
    local name = trim(config.prompt_execution.skill_name)
    return name ~= "" and name or "prompt-nvim-clodex"
end

---@param config Clodex.Config.Values
---@return string
local function generated_skill_content(config)
    local template = SKILL_TEMPLATE
    if fs.is_file(REPO_SKILL_TEMPLATE_PATH) then
        local file = io.open(REPO_SKILL_TEMPLATE_PATH, "rb")
        if file then
            local content = file:read("*a")
            file:close()
            if content and content ~= "" then
                template = content
            end
        end
    end

    return template:gsub("__CLODEX_SKILL_NAME__", skill_name(config))
end

---@param item Clodex.QueueItem
---@param _config Clodex.Config.Values
---@return string[]
local function completion_instruction_lines(item, _config)
    local commit_policy = Prompt.categories.requires_commit(item.kind) and "required" or "skip"
    return {
        ("Current queue item id: `%s`"):format(item.id),
        ("Current prompt kind: `%s`"):format(Prompt.categories.get(item.kind).id),
        ("Commit policy for this prompt: `%s`"):format(commit_policy),
    }
end

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

---@param config Clodex.Config.Values
---@return Clodex.Workspace.Execution
function Execution.new(config)
    local self = setmetatable({}, Execution)
    self.config = config
    return self
end

---@param config Clodex.Config.Values
function Execution:update_config(config)
    self.config = config
end

---@return boolean
function Execution:uses_prompt_skill()
    return trim(self.config.prompt_execution.skill_name) ~= "" and trim(self.config.prompt_execution.skills_dir) ~= ""
end

---@return string
function Execution:skill_dir()
    return assert(skills_dir(self.config))
end

---@return string
function Execution:skill_file()
    return fs.join(self:skill_dir(), skill_name(self.config), "SKILL.md")
end

---@return boolean
function Execution:sync_prompt_skill()
    if not self:uses_prompt_skill() then
        return false
    end

    fs.write_file(self:skill_file(), generated_skill_content(self.config))
    return true
end

---@param project Clodex.Project
---@return string
function Execution:project_execution_dir(project)
    return fs.join(execution_dir(self.config, project.root), project_id(project.root))
end

---@param project Clodex.Project
---@param item Clodex.QueueItem
---@return string
function Execution:dispatch_prompt(project, item)
    local instruction_lines = completion_instruction_lines(item, self.config)

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
