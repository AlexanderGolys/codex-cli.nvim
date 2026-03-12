local fs = require("clodex.util.fs")

--- Defines the Clodex.Project.Record type for this module.
--- This annotation documents structured state so modules can pass data with consistent expectations.
---@class Clodex.Project.Record
---@field name string
---@field root string

--- Defines the Clodex.Project type for this module.
--- This annotation documents structured state so modules can pass data with consistent expectations.
---@class Clodex.Project
---@field name string
---@field root string
local Project = {}
Project.__index = Project

---@param record Clodex.Project.Record
---@return Clodex.Project
function Project.new(record)
  assert(type(record.name) == "string" and record.name ~= "", "project name is required")
  assert(type(record.root) == "string" and record.root ~= "", "project root is required")

  local self = setmetatable({}, Project)
  self.name = vim.trim(record.name)
  self.root = fs.normalize(record.root)
  return self
end

---@return Clodex.Project.Record
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
