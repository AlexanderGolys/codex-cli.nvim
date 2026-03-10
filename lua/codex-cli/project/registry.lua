local fs = require("codex-cli.util.fs")
local Project = require("codex-cli.project.project")

--- Defines the CodexCli.ProjectRegistry type for this module.
--- This annotation documents structured state so modules can pass data with consistent expectations.
---@class CodexCli.ProjectRegistry
---@field path string
---@field projects CodexCli.Project[]
---@field by_root table<string, CodexCli.Project>
local Registry = {}
Registry.__index = Registry

--- Creates a new project registry instance from this module.
--- It is used by callers to bootstrap module state before running higher-level plugin actions.
---@param opts { path: string }
---@return CodexCli.ProjectRegistry
function Registry.new(opts)
  local self = setmetatable({}, Registry)
  self.path = fs.normalize(opts.path)
  self.projects = {}
  self.by_root = {}
  self:load()
  return self
end

--- Persists or restores project registry data for this workflow.
--- It is used by session restoration and command surfaces so behavior remains repeatable.
function Registry:load()
  self.projects = {}
  self.by_root = {}

  local data = fs.read_json(self.path, { projects = {} })
  for _, record in ipairs(data.projects or {}) do
    local project = Project.new(record)
    self.by_root[project.root] = project
    self.projects[#self.projects + 1] = project
  end

  table.sort(self.projects, function(left, right)
    return left.name:lower() < right.name:lower()
  end)
end

--- Persists or restores project registry data for this workflow.
--- It is used by session restoration and command surfaces so behavior remains repeatable.
function Registry:save()
  local records = {} ---@type CodexCli.Project.Record[]
  for _, project in ipairs(self.projects) do
    records[#records + 1] = project:to_record()
  end
  fs.write_json(self.path, { projects = records })
end

--- Implements the list path for project registry.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@return CodexCli.Project[]
function Registry:list()
  return vim.deepcopy(self.projects)
end

--- Implements the get path for project registry.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param root string
---@return CodexCli.Project?
function Registry:get(root)
  return self.by_root[fs.normalize(root)]
end

--- Implements the has_root path for project registry.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param root string
---@return boolean
function Registry:has_root(root)
  return self:get(root) ~= nil
end

--- Implements the suggest_name path for project registry.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param root string
---@return string
function Registry:suggest_name(root)
  return fs.basename(root)
end

--- Adds a new project registry entry and keeps related state aligned.
--- This function feeds the same workflow used by interactive and scripted callers.
---@param spec CodexCli.Project|CodexCli.Project.Record
---@return CodexCli.Project
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
---@return CodexCli.Project?
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

--- Implements the find_for_path path for project registry.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param path string
---@return CodexCli.Project?
function Registry:find_for_path(path)
  path = fs.normalize(path)
  local best ---@type CodexCli.Project?

  for _, project in ipairs(self.projects) do
    if fs.is_relative_to(path, project.root) and (not best or #project.root > #best.root) then
      best = project
    end
  end

  return best
end

--- Implements the find_by_name_or_root path for project registry.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param value string
---@return CodexCli.Project?
function Registry:find_by_name_or_root(value)
  local normalized = fs.normalize(value)
  if self.by_root[normalized] then
    return self.by_root[normalized]
  end

  for _, project in ipairs(self.projects) do
    if project.name == value then
      return project
    end
  end
end

return Registry
