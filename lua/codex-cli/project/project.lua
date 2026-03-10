local fs = require("codex-cli.util.fs")

--- Defines the CodexCli.Project.Record type for this module.
--- This annotation documents structured state so modules can pass data with consistent expectations.
---@class CodexCli.Project.Record
---@field name string
---@field root string

--- Defines the CodexCli.Project type for this module.
--- This annotation documents structured state so modules can pass data with consistent expectations.
---@class CodexCli.Project
---@field name string
---@field root string
local Project = {}
Project.__index = Project

--- Creates a new project project instance from this module.
--- It is used by callers to bootstrap module state before running higher-level plugin actions.
---@param record CodexCli.Project.Record
---@return CodexCli.Project
function Project.new(record)
  assert(type(record.name) == "string" and record.name ~= "", "project name is required")
  assert(type(record.root) == "string" and record.root ~= "", "project root is required")

  local self = setmetatable({}, Project)
  self.name = vim.trim(record.name)
  self.root = fs.normalize(record.root)
  return self
end

--- Implements the to_record path for project project.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@return CodexCli.Project.Record
function Project:to_record()
  return {
    name = self.name,
    root = self.root,
  }
end

--- Implements the display_name path for project project.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@return string
function Project:display_name()
  return self.name
end

return Project
