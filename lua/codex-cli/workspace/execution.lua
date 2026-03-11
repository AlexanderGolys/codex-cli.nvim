local fs = require("codex-cli.util.fs")
local git = require("codex-cli.util.git")

--- Parsed receipt payload emitted by completed queue prompts.
--- This metadata is read back to update queue history and track completion details.
---@class CodexCli.Workspace.ExecutionReceipt
---@field summary string
---@field commit? string
---@field completed_at? string

--- Generates and persists prompt-instruction payloads used by the Codex execution pipeline.
--- This object bridges queue items to terminal jobs and completion receipts.
---@class CodexCli.Workspace.Execution
---@field config CodexCli.Config.Values
local Execution = {}
Execution.__index = Execution

local RECEIPT_VERSION = 1
local SKILL_TEMPLATE = [[---
name: %s
description: Handle codex-cli.nvim queued prompt executions that end by writing a JSON receipt file exactly as requested.
---

# Prompt Receipt

Use this skill when a prompt includes `$%s`.

When the prompt provides an execution receipt path and a required JSON shape before the skill call:

1. Finish the requested work first.
2. Write the receipt only after the work is complete.
3. Write valid JSON to the exact path provided by the prompt.
4. Match the requested shape exactly.
5. Do not change unrelated files while creating the receipt.
6. If more prompts are waiting in the project's `Queued` lane, continue with the next queued prompt immediately after finishing the current one.
7. Repeat until the project's `Queued` lane is empty. Do not start prompts that are only in `Planned`.
]]

--- Builds the markdown guidance block that is appended to prompts requiring receipts.
--- It includes the file path and expected JSON shape so downstream agents can write completion data consistently.
--- This block is injected for both direct prompts and skill-directed prompts.
local function completion_instruction_lines(receipt_path, receipt_json)
  return {
    ("Execution receipt path: `%s`"):format(receipt_path),
    "Write the execution receipt only after the work is complete.",
    "Use this exact shape:",
    "```json",
    receipt_json,
    "```",
    "If more prompts are waiting in the project's `Queued` lane, continue with the next queued prompt immediately after finishing the current one.",
    "Repeat until the project's `Queued` lane is empty. Do not start prompts that are only in `Planned`.",
  }
end

--- Adds optional image-context lines at the top of a generated prompt body.
--- It keeps item-level context uniform for the execution engine and user-visible behavior.
--- Image details are included only when a valid file path is present.
---@param item CodexCli.QueueItem
---@return string[]
local function prompt_prefix_lines(item)
  local lines = {} ---@type string[]
  if item.image_path and fs.is_file(item.image_path) then
    lines[#lines + 1] = ("Primary visual reference: `%s`"):format(item.image_path)
    lines[#lines + 1] = "Use that local image file as part of the implementation context."
    lines[#lines + 1] = ""
  end
  return lines
end

local function trim(value)
  return vim.trim(value or "")
end

--- Computes a stable directory name for one project's queued prompt receipts.
---@param project_root string
---@return string
local function project_id(project_root)
  return vim.fn.sha256(fs.normalize(project_root)):sub(1, 16)
end

--- Resolves the shared receipt root stored under plugin data.
---@param config CodexCli.Config.Values
---@return string
local function receipts_dir(config)
  local dir = trim(config.prompt_execution.receipts_dir)
  if dir ~= "" then
    return fs.normalize(vim.fn.expand(dir))
  end
  return fs.join(vim.fn.stdpath("data"), "codex-cli", "prompt-executions")
end

--- Resolves the legacy per-project receipt directory when configured.
---@param config CodexCli.Config.Values
---@param project_root string
---@return string?
local function legacy_receipts_dir(config, project_root)
  local dir = trim(config.prompt_execution.relative_dir)
  if dir == "" then
    return nil
  end
  return fs.join(project_root, dir)
end

--- Resolves the configured directory where generated skill files are stored.
--- Returns nil when skill mode is not configured.
--- This controls whether `$prompt` or `$<skill>` execution mode is active.
local function skills_dir(config)
  local dir = trim(config.prompt_execution.skills_dir)
  if dir == "" then
    return nil
  end
  return fs.normalize(vim.fn.expand(dir))
end

local function skill_name(config)
  local name = trim(config.prompt_execution.skill_name)
  return name ~= "" and name or "prompt-nvim-codex-cli"
end

--- Renders the full SKILL.md template for the currently configured skill name.
--- It keeps the generated skill content stable and traceable in testable text form.
---@param config CodexCli.Config.Values
---@return string
local function generated_skill_content(config)
  local name = skill_name(config)
  return SKILL_TEMPLATE:format(name, name)
end

--- Resolves the final on-disk skill directory, supporting nested configured roots.
--- If configured directory points elsewhere, this appends the canonical skill folder name.
---@param config CodexCli.Config.Values
---@return string?
local function installed_skill_dir(config)
  local dir = skills_dir(config)
  if not dir then
    return nil
  end

  local name = skill_name(config)
  if fs.basename(dir) == name then
    return dir
  end
  return fs.join(dir, name)
end

--- Reads a file fully from disk.
--- Returns nil if the file is missing or unreadable, allowing cleanup logic to skip safely.
---@param path string
---@return string?
local function read_file(path)
  local file = io.open(path, "rb")
  if not file then
    return nil
  end

  local content = file:read("*a")
  file:close()
  return content
end

--- The created object is used by app runtime to dispatch prompt text and read receipts.
---@param config CodexCli.Config.Values
---@return CodexCli.Workspace.Execution
function Execution.new(config)
  local self = setmetatable({}, Execution)
  self.config = config
  return self
end

--- Replaces the cached config so in-flight execution behavior stays aligned with updated user options.
---@param config CodexCli.Config.Values
function Execution:update_config(config)
  self.config = config
end

--- Reports whether execution should use a generated skill (`$<name>`) instead of raw `$prompt`.
--- This branch influences how queue items are formatted before being sent to the terminal.
---@return boolean
function Execution:uses_prompt_skill()
  return skills_dir(self.config) ~= nil
end

--- Returns the effective skill directory and asserts it exists when skill mode is enabled.
--- Code paths that require writing or reading skill artifacts should use this before IO.
---@return string
function Execution:skill_dir()
  return assert(installed_skill_dir(self.config))
end

--- Returns the path to the generated SKILL.md file.
--- Callers use this when persisting or verifying prompt execution setup.
---@return string
function Execution:skill_file()
  return fs.join(self:skill_dir(), "SKILL.md")
end

---@return string?
function Execution:legacy_skill_file()
  local dir = skills_dir(self.config)
  if not dir then
    return nil
  end

  local path = fs.join(dir, "SKILL.md")
  if path == self:skill_file() then
    return nil
  end
  return path
end

--- Returns the project-scoped directory used for queued prompt receipts.
---@param project CodexCli.Project
---@return string
function Execution:project_receipts_dir(project)
  return fs.join(receipts_dir(self.config), project_id(project.root))
end

--- Returns the current canonical receipt path for one queued prompt item.
---@param project CodexCli.Project
---@param item CodexCli.QueueItem
---@return string
function Execution:current_receipt_path(project, item)
  return fs.join(self:project_receipts_dir(project), item.id .. ".json")
end

--- Returns the legacy project-local receipt path when that migration path exists.
---@param project CodexCli.Project
---@param item CodexCli.QueueItem
---@return string?
function Execution:legacy_receipt_path(project, item)
  local dir = legacy_receipts_dir(self.config, project.root)
  if not dir then
    return nil
  end
  return fs.join(dir, item.id .. ".json")
end

--- Updates the generated skill file and removes legacy duplicates if they match the new content.
--- This keeps tool-call contract consistency while avoiding stale instructions.
function Execution:ensure_prompt_skill()
  if not self:uses_prompt_skill() then
    return
  end

  local content = generated_skill_content(self.config)
  fs.write_file(self:skill_file(), content)

  local legacy = self:legacy_skill_file()
  if legacy and fs.is_file(legacy) and read_file(legacy) == content then
    fs.remove(legacy)
  end
end

---@param project CodexCli.Project
---@param item CodexCli.QueueItem
---@return string
function Execution:receipt_path(project, item)
  return self:current_receipt_path(project, item)
end

---@param project CodexCli.Project
---@param item CodexCli.QueueItem
function Execution:clear_receipt(project, item)
  fs.remove(self:current_receipt_path(project, item))
  local legacy = self:legacy_receipt_path(project, item)
  if legacy then
    fs.remove(legacy)
  end
end

---@param project CodexCli.Project
---@param item CodexCli.QueueItem
---@return string
function Execution:dispatch_prompt(project, item)
  local receipt_path = self:current_receipt_path(project, item)
  fs.ensure_dir(fs.dirname(receipt_path))
  local receipt = {
    version = RECEIPT_VERSION,
    summary = "Short summary of the implemented change",
    commit = git.head_commit(project.root, true) or "HEAD",
    completed_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
  }
  local receipt_json = vim.json.encode(receipt)
  local instruction_lines = completion_instruction_lines(receipt_path, receipt_json)

  local prompt_lines = prompt_prefix_lines(item)
  prompt_lines[#prompt_lines + 1] = item.prompt

  if self:uses_prompt_skill() then
    local skill = skill_name(self.config)
    local lines = vim.deepcopy(prompt_lines)
    lines[#lines + 1] = ""
    vim.list_extend(lines, instruction_lines)
    lines[#lines + 1] = ("$%s"):format(skill)
    return table.concat(lines, "\n")
  end

  local lines = vim.deepcopy(prompt_lines)
  lines[#lines + 1] = ""
  lines[#lines + 1] = "$prompt"
  vim.list_extend(lines, instruction_lines)
  return table.concat(lines, "\n")
end

---@param project CodexCli.Project
---@param item CodexCli.QueueItem
---@return CodexCli.Workspace.ExecutionReceipt?
function Execution:read_receipt(project, item)
  local data = fs.read_json(self:current_receipt_path(project, item), nil)
  if type(data) ~= "table" then
    local legacy = self:legacy_receipt_path(project, item)
    if legacy then
      data = fs.read_json(legacy, nil)
    end
  end
  if type(data) ~= "table" then
    return
  end

  local summary = vim.trim(data.summary or "")
  if summary == "" then
    return
  end

  local commit = vim.trim(data.commit or "")
  local completed_at = vim.trim(data.completed_at or "")
  return {
    summary = summary,
    commit = commit ~= "" and commit or git.head_commit(project.root, true),
    completed_at = completed_at ~= "" and completed_at or os.date("!%Y-%m-%dT%H:%M:%SZ"),
  }
end

return Execution
