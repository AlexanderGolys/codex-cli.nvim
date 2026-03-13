local fs = require("clodex.util.fs")
local Project = require("clodex.project.project")

--- Defines the Clodex.ProjectRegistry type for this module.
--- This annotation documents structured state so modules can pass data with consistent expectations.
---@class Clodex.ProjectRegistry
---@field path string
---@field projects Clodex.Project[]
---@field by_root table<string, Clodex.Project>
local Registry = {}
Registry.__index = Registry

---@param data any
---@return Clodex.Project[]
local function parse_projects(data)
  local projects = {} ---@type Clodex.Project[]
  if type(data) ~= "table" then
    return projects
  end

  for _, record in ipairs(data.projects or {}) do
    local ok, project = pcall(Project.new, record)
    if ok and project then
      projects[#projects + 1] = project
    end
  end

  table.sort(projects, function(left, right)
    return left.name:lower() < right.name:lower()
  end)
  return projects
end

---@param opts { path: string }
---@return Clodex.ProjectRegistry
function Registry.new(opts)
  local self = setmetatable({}, Registry)
  self.path = fs.normalize(opts.path)
  self.projects = {}
  self.by_root = {}
  self:load()
  return self
end

function Registry:load()
  self.projects = {}
  self.by_root = {}

  self.projects = parse_projects(fs.read_json(self.path, { projects = {} }))
  for _, project in ipairs(self.projects) do
    self.by_root[project.root] = project
  end
end

function Registry:save()
  local records = {} ---@type Clodex.Project.Record[]
  for _, project in ipairs(self.projects) do
    records[#records + 1] = project:to_record()
  end
  fs.write_json(self.path, { projects = records })
end

---@return Clodex.Project[]
function Registry:list()
  return vim.deepcopy(self.projects)
end

---@param root string
---@return Clodex.Project?
function Registry:get(root)
  return self.by_root[fs.normalize(root)]
end

---@param name string
---@return Clodex.Project?
function Registry:find_by_name(name)
  for _, project in ipairs(self.projects) do
    if project.name == name then
      return project
    end
  end
end

---@param root string
---@return boolean
function Registry:has_root(root)
  return self:get(root) ~= nil
end

---@param root string
---@return string
function Registry:suggest_name(root)
  return fs.basename(root)
end

--- Adds a new project registry entry and keeps related state aligned.
--- This function feeds the same workflow used by interactive and scripted callers.
---@param spec Clodex.Project|Clodex.Project.Record
---@return Clodex.Project
function Registry:add(spec)
  local project = getmetatable(spec) == Project and spec or Project.new(spec)
  local existing = self.by_root[project.root]

  if existing then
    existing.name = project.name
    self:save()
    table.sort(self.projects, function(left, right)
      return left.name:lower() < right.name:lower()
    end)
    return existing
  end

  self.by_root[project.root] = project
  self.projects[#self.projects + 1] = project
  table.sort(self.projects, function(left, right)
    return left.name:lower() < right.name:lower()
  end)
  self:save()
  return project
end

--- Removes a project registry item and normalizes dependent state.
--- This cleanup keeps persistence and session state consistent with user actions.
---@param root string
---@return Clodex.Project?
function Registry:remove(root)
  root = fs.normalize(root)
  local project = self.by_root[root]
  if not project then
    return
  end

  self.by_root[root] = nil
  for index, item in ipairs(self.projects) do
    if item.root == root then
      table.remove(self.projects, index)
      break
    end
  end
  self:save()
  return project
end

---@param path string
---@return Clodex.Project?
function Registry:find_for_path(path)
  path = fs.normalize(path)
  local best ---@type Clodex.Project?

  for _, project in ipairs(self.projects) do
    if fs.is_relative_to(path, project.root) and (not best or #project.root > #best.root) then
      best = project
    end
  end

  return best
end

---@param value string
---@return Clodex.Project?
function Registry:find_by_name_or_root(value)
  local normalized = fs.normalize(value)
  if self.by_root[normalized] then
    return self.by_root[normalized]
  end

  return self:find_by_name(value)
end

return Registry
