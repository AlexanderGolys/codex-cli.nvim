local fs = require("codex-cli.util.fs")

--- On-disk queue data container for a workspace root.
---@class CodexCli.Workspace.Store
---@field root_dir string
local Store = {}
Store.__index = Store

local DEFAULT_DATA = {
  version = 1,
  queues = {
    planned = {},
    queued = {},
    history = {},
  },
}

---@param root_dir string
---@return CodexCli.Workspace.Store
--- Creates a workspace store rooted at a shared directory.
---@param root_dir string
---@return CodexCli.Workspace.Store
function Store.new(root_dir)
  local self = setmetatable({}, Store)
  self.root_dir = fs.normalize(root_dir)
  return self
end

---@param project_root string
---@return string
--- Computes a stable identifier for queue/workspace files.
---@param project_root string
---@return string
function Store:project_id(project_root)
  return vim.fn.sha256(fs.normalize(project_root)):sub(1, 16)
end

---@param project_root string
---@return string
--- Computes the queue persistence path for a project root.
---@param project_root string
---@return string
function Store:path(project_root)
  return fs.join(self.root_dir, self:project_id(project_root) .. ".json")
end

---@param project_root string
---@return table
--- Loads queue state from disk with safe defaults for missing fields.
---@param project_root string
---@return table
function Store:load(project_root)
  local data = fs.read_json(self:path(project_root), vim.deepcopy(DEFAULT_DATA))
  data.version = data.version or DEFAULT_DATA.version
  data.queues = data.queues or {}
  data.queues.planned = data.queues.planned or {}
  data.queues.queued = data.queues.queued or {}
  data.queues.history = data.queues.history or {}
  return data
end

---@param project_root string
---@param data table
--- Persists queue state to disk for one project.
---@param project_root string
---@param data table
function Store:save(project_root, data)
  fs.write_json(self:path(project_root), data)
end

---@param project_root string
--- Removes queue state for a project from disk.
---@param project_root string
function Store:delete(project_root)
  fs.remove(self:path(project_root))
end

return Store
