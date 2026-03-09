local fs = require("codex-cli.util.fs")
local git = require("codex-cli.util.git")

---@class CodexCli.Workspace.ExecutionReceipt
---@field summary string
---@field commit? string
---@field completed_at? string

---@class CodexCli.Workspace.Execution
---@field config CodexCli.Config.Values
local Execution = {}
Execution.__index = Execution

local RECEIPT_VERSION = 1

---@param config CodexCli.Config.Values
---@return CodexCli.Workspace.Execution
function Execution.new(config)
  local self = setmetatable({}, Execution)
  self.config = config
  return self
end

---@param config CodexCli.Config.Values
function Execution:update_config(config)
  self.config = config
end

---@param project CodexCli.Project
---@param item CodexCli.QueueItem
---@return string
function Execution:receipt_path(project, item)
  return fs.join(project.root, self.config.prompt_execution.relative_dir, item.id .. ".json")
end

---@param project CodexCli.Project
---@param item CodexCli.QueueItem
function Execution:clear_receipt(project, item)
  fs.remove(self:receipt_path(project, item))
end

---@param project CodexCli.Project
---@param item CodexCli.QueueItem
---@return string
function Execution:dispatch_prompt(project, item)
  local receipt_path = self:receipt_path(project, item)
  fs.ensure_dir(fs.dirname(receipt_path))
  local receipt = {
    version = RECEIPT_VERSION,
    summary = "Short summary of the implemented change",
    commit = git.head_commit(project.root, true) or "HEAD",
    completed_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
  }

  return table.concat({
    item.prompt,
    "",
    "$prompt",
    ("When this prompt is fully implemented, write a JSON execution receipt to `%s`."):format(receipt_path),
    "Do not write the receipt early. Write it only after the work is complete.",
    "Use this exact shape:",
    "```json",
    vim.json.encode(receipt),
    "```",
  }, "\n")
end

---@param project CodexCli.Project
---@param item CodexCli.QueueItem
---@return CodexCli.Workspace.ExecutionReceipt?
function Execution:read_receipt(project, item)
  local path = self:receipt_path(project, item)
  local data = fs.read_json(path, nil)
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
