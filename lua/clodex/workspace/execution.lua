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
    local prompt_kind = Prompt.categories.get(item.kind).id
    local commit_policy = Prompt.categories.commit_policy(item.kind)
    local lines = {
        ("Current queue item id: `%s`"):format(item.id),
        ("Current prompt kind: `%s`"):format(prompt_kind),
        ("Commit policy for this prompt: `%s`"):format(commit_policy),
    }
    if prompt_kind == "freeform" then
        lines[#lines + 1] = "Completion destination for this prompt: `agent_decides`"
    end
    if item.completion_target == "history" then
        lines[#lines + 1] = "Completion destination for this prompt: `history`"
    end
    return lines
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

---@param item Clodex.QueueItem
---@return string
function Execution:queue_item_instructions(item)
    local lines = completion_instruction_lines(item, self.config)
    if self:uses_prompt_skill() then
        lines[#lines + 1] = ("$%s"):format(skill_name(self.config))
    else
        table.insert(lines, 1, "$prompt")
    end
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

---@param _project Clodex.Project
---@param item Clodex.QueueItem
---@return string
function Execution:dispatch_prompt(_project, item)
    if not item.prompt or vim.trim(item.prompt) == "" then
        return ""
    end

    if self:uses_prompt_skill() then
        self:sync_prompt_skill()
    end

    local prompt_lines = prompt_prefix_lines(item)
    prompt_lines[#prompt_lines + 1] = item.prompt
    local execution_instructions = trim(item.execution_instructions)
    if execution_instructions == "" then
        execution_instructions = self:queue_item_instructions(item)
    end

    local lines = vim.deepcopy(prompt_lines)
    lines[#lines + 1] = ""
    vim.list_extend(lines, vim.split(execution_instructions, "\n", { plain = true }))
    return table.concat(lines, "\n")
end

return Execution
