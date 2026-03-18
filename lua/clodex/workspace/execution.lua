local Prompt = require("clodex.prompt")
local fs = require("clodex.util.fs")

--- Generates and persists prompt-instruction payloads used by the Codex execution pipeline.
--- This object bridges queue items to terminal jobs and workspace mutations.
---@class Clodex.Workspace.Execution
---@field config Clodex.Config.Values
local Execution = {}
Execution.__index = Execution

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
---@return string
local function skills_dir(config)
    local dir = vim.trim(config.prompt_execution.skills_dir or "")
    if dir == "" then
        return ""
    end
    return fs.normalize(vim.fn.expand(dir))
end

---@param config Clodex.Config.Values
---@return string
local function skill_name(config)
    local name = trim(config.prompt_execution.skill_name)
    return name ~= "" and name or "prompt-nvim-clodex"
end

---@param config Clodex.Config.Values
---@return string
local function repo_skill_content()
    local file = io.open(REPO_SKILL_TEMPLATE_PATH, "rb")
    if not file then
        error(("Could not open prompt skill template: %s"):format(REPO_SKILL_TEMPLATE_PATH))
    end

    local content = file:read("*a")
    file:close()
    if not content or content == "" then
        error(("Prompt skill template is empty: %s"):format(REPO_SKILL_TEMPLATE_PATH))
    end
    return content
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

--- Generates a guidance block for the queue workflow cycle.
--- This is embedded in prompts so agents always know what to do next,
--- even when handling prompts directly without the Neovim UI.
---@param project Clodex.Project
---@param next_item? Clodex.QueueItem
---@return string
function Execution:cycle_guidance(project, next_item)
    local lines = {
        "",
        "--- Queue Cycle Guidance ---",
        "",
        ("Workspace directory: %s/.clodex/"):format(project.root),
    }

    if next_item then
        local requires_commit = Prompt.categories.requires_commit(next_item.kind)
        lines[#lines + 1] = ("Next queued item: `%s`"):format(next_item.title)
        lines[#lines + 1] = ("Kind: `%s`"):format(next_item.kind)
        lines[#lines + 1] = ("Id: `%s`"):format(next_item.id)
        if requires_commit then
            lines[#lines + 1] = "Note: This kind requires a commit."
        end
        lines[#lines + 1] = ""
        lines[#lines + 1] = "After completing the current item, use advance_to_history() to move it to history."
    else
        lines[#lines + 1] = "No more queued items."
    end

    lines[#lines + 1] = ""
    lines[#lines + 1] = "Available queue automation tools:"
    lines[#lines + 1] = "- advance_item(project, item_id): Move item to next queue (planned->queued->implemented)"
    lines[#lines + 1] = "- advance_to_history(project, item_id, summary?, commits?): Complete item, move to history"
    lines[#lines + 1] = "- rewind_item(project, item_id, opts?): Move item back to previous queue"
    lines[#lines + 1] = "- next_item_guidance(project): Get guidance for continuing to next queued item"

    return table.concat(lines, "\n")
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
    local dir = skills_dir(self.config)
    return dir ~= "" and trim(self.config.prompt_execution.skill_name) ~= ""
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

    local file = self:skill_file()
    fs.write_file(file, repo_skill_content())
    return true
end

---@param project Clodex.Project
---@return string
function Execution:project_execution_dir(project)
    return fs.join(project.root, ".clodex", "prompt-executions")
end

---@param project Clodex.Project
---@param item Clodex.QueueItem
---@param next_item? Clodex.QueueItem
---@return string
function Execution:dispatch_prompt(project, item, next_item)
    if not item.prompt or vim.trim(item.prompt) == "" then
        return ""
    end

    if self:uses_prompt_skill() then
        self:sync_prompt_skill()
    end

    local instruction_lines = completion_instruction_lines(item, self.config)

    local prompt_lines = prompt_prefix_lines(item)
    prompt_lines[#prompt_lines + 1] = item.prompt

    if self:uses_prompt_skill() then
        local lines = vim.deepcopy(prompt_lines)
        lines[#lines + 1] = ""
        vim.list_extend(lines, instruction_lines)
        lines[#lines + 1] = ("$%s"):format(skill_name(self.config))
        if next_item then
            vim.list_extend(lines, vim.split(self:cycle_guidance(project, next_item), "\n"))
        end
        return table.concat(lines, "\n")
    end

    local lines = vim.deepcopy(prompt_lines)
    lines[#lines + 1] = ""
    lines[#lines + 1] = "$prompt"
    vim.list_extend(lines, instruction_lines)
    if next_item then
        vim.list_extend(lines, vim.split(self:cycle_guidance(project, next_item), "\n"))
    end
    return table.concat(lines, "\n")
end

return Execution
