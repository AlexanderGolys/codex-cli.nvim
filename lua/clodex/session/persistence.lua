local fs = require("clodex.util.fs")

--- Defines the Clodex.SessionPersistence type for this module.
--- This annotation documents structured state so modules can pass data with consistent expectations.
---@class Clodex.SessionPersistence
---@field storage_dir string
---@field legacy_sidecar_suffix string
local Persistence = {}
Persistence.__index = Persistence

local STATE_VERSION = 1
local STATE_DIRNAME = "session-state"
local LEGACY_SIDECAR_SUFFIX = ".clodex.json"

--- Checks whether a candidate session file is a real path instead of a virtual buffer name.
--- Scratch names like `clodex:/...` and `term:/...` should never reach persistence.
---@param path string
---@return boolean
local function is_virtual_session_path(path)
  return fs.is_virtual_path(path)
end

local function normalize_session_file(session_file)
  session_file = vim.trim(session_file or "")
  if session_file == "" or is_virtual_session_path(session_file) then
    return
  end
  return fs.normalize(session_file)
end

---@param tabpage integer
---@return string?
local function tab_visible_path(tabpage)
  if not vim.api.nvim_tabpage_is_valid(tabpage) then
    return nil
  end

  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
    if vim.api.nvim_win_is_valid(win) then
      local config = vim.api.nvim_win_get_config(win)
      if (config.relative or "") == "" then
        local buf = vim.api.nvim_win_get_buf(win)
        if vim.api.nvim_buf_is_valid(buf) then
          local path = vim.api.nvim_buf_get_name(buf)
          if path ~= "" and not fs.is_virtual_path(path) then
            return fs.normalize(path)
          end
        end
      end
    end
  end
end

local function storage_path(self, session_file)
  session_file = normalize_session_file(session_file)
  if not session_file then
    return
  end

  local basename = fs.basename(session_file):gsub("[^%w%-_%.]", "_")
  local digest = vim.fn.sha256(session_file):sub(1, 16)
  return fs.join(self.storage_dir, ("%s-%s.json"):format(basename, digest))
end

local function legacy_sidecar_path(self, session_file)
  session_file = normalize_session_file(session_file)
  return session_file and (session_file .. self.legacy_sidecar_suffix) or nil
end

--- Defines the Clodex.SessionPersistence.State type for this module.
--- This annotation documents structured state so modules can pass data with consistent expectations.
---@class Clodex.SessionPersistence.State
---@field version integer
---@field tabs Clodex.TabState.Snapshot[]

---@param storage_dir? string
---@return Clodex.SessionPersistence
function Persistence.new(storage_dir)
  local self = setmetatable({}, Persistence)
  self.storage_dir = fs.normalize(storage_dir or fs.join(fs.cwd(), ".clodex", STATE_DIRNAME))
  self.legacy_sidecar_suffix = LEGACY_SIDECAR_SUFFIX
  return self
end

---@param storage_dir string
function Persistence:update_storage_dir(storage_dir)
  self.storage_dir = fs.normalize(storage_dir)
end

---@param app Clodex.App
---@return Clodex.SessionPersistence.State
function Persistence:build_state(app)
  local tabs = {} ---@type Clodex.TabState.Snapshot[]
  local tabpages = vim.api.nvim_list_tabpages()
  table.sort(tabpages, function(left, right)
    return left < right
  end)

  for _, tabpage in ipairs(tabpages) do
    local state = app.tabs:get(tabpage)
    local snapshot = state:snapshot()
    if not snapshot.active_project_root then
      local path = tab_visible_path(tabpage)
      local project = path and app.registry:find_for_path(path) or nil
      if project then
        snapshot.active_project_root = project.root
      end
    end
    snapshot.has_visible_window = false
    snapshot.session_key = nil
    snapshot.window_id = nil
    tabs[#tabs + 1] = snapshot
  end

  return {
    version = STATE_VERSION,
    tabs = tabs,
  }
end

---@param app Clodex.App
---@param session_file string
function Persistence:save(app, session_file)
  local path = storage_path(self, session_file)
  if not path then
    return
  end
  fs.write_json(path, self:build_state(app))

  local legacy_sidecar = legacy_sidecar_path(self, session_file)
  if legacy_sidecar and fs.is_file(legacy_sidecar) then
    fs.remove(legacy_sidecar)
  end
end

---@param app Clodex.App
---@param session_file string
function Persistence:restore(app, session_file)
  local state_path = storage_path(self, session_file)
  if not state_path or not fs.is_file(state_path) then
    state_path = legacy_sidecar_path(self, session_file)
  end
  if not state_path or not fs.is_file(state_path) then
    return
  end

  local state = fs.read_json(state_path, nil)
  if type(state) ~= "table" then
    return
  end

  app.registry:load()
  app.tabs:restore(state.tabs or {})
  app:refresh_views()
end

return Persistence
