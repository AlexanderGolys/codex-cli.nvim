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

---@return string
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
---@param project_root string?
---@return string?
local function skills_dir(config, project_root)
    local dir = trim(config.prompt_execution.skills_dir)
    if dir == "" then
        return nil
    end

    local expanded = fs.normalize(vim.fn.expand(dir))
    if is_absolute_path(expanded) then
        return expanded
    end

    if config.backend == "opencode" then
        if not project_root or project_root == "" then
            return nil
        end
        return fs.join(project_root, expanded)
    end

    return expanded
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

---@param project Clodex.Project?
---@return string
function Execution:skill_dir(project)
    local project_root = project and project.root or nil
    return assert(skills_dir(self.config, project_root))
end

---@param project Clodex.Project?
---@return string
function Execution:skill_file(project)
    return fs.join(self:skill_dir(project), skill_name(self.config), "SKILL.md")
end

---@return boolean
---@param project Clodex.Project?
function Execution:sync_prompt_skill(project)
    if not self:uses_prompt_skill() then
        return false
    end

    local file = self:skill_file(project)
    fs.write_file(file, repo_skill_content())
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
    if self:uses_prompt_skill() then
        self:sync_prompt_skill(project)
    end

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
