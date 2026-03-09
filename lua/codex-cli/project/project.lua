local fs = require("codex-cli.util.fs")

---@class CodexCli.Project.Record
---@field name string
---@field root string

---@class CodexCli.Project
---@field name string
---@field root string
local Project = {}
Project.__index = Project

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

---@return CodexCli.Project.Record
function Project:to_record()
  return {
    name = self.name,
    root = self.root,
  }
end

---@return string
function Project:display_name()
  return self.name
end

return Project
