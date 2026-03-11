local fs = require("codex-cli.util.fs")

--- Defines the CodexCli.SessionPersistence type for this module.
--- This annotation documents structured state so modules can pass data with consistent expectations.
---@class CodexCli.SessionPersistence
---@field storage_dir string
---@field legacy_sidecar_suffix string
local Persistence = {}
Persistence.__index = Persistence

local STATE_VERSION = 1
local STATE_DIRNAME = "session-state"
local LEGACY_SIDECAR_SUFFIX = ".codex-cli.json"

--- Checks whether a candidate session file is a real path instead of a virtual buffer name.
--- Scratch names like `codex-cli:/...` and `term:/...` should never reach persistence.
---@param path string
---@return boolean
local function is_virtual_session_path(path)
  if vim.startswith(path, "codex-cli:") or vim.startswith(path, "term:") then
    return true
  end

  if path:match("^%a:[/\\]") then
    return false
  end

  return path:match("^[%w_.-]+:") ~= nil
end

local function normalize_session_file(session_file)
  session_file = vim.trim(session_file or "")
  if session_file == "" or is_virtual_session_path(session_file) then
    return
  end
  return fs.normalize(session_file)
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

--- Defines the CodexCli.SessionPersistence.State type for this module.
--- This annotation documents structured state so modules can pass data with consistent expectations.
---@class CodexCli.SessionPersistence.State
---@field version integer
---@field tabs CodexCli.TabState.Snapshot[]
---@field terminal_sessions CodexCli.TerminalSession.Spec[]

---@return CodexCli.SessionPersistence
function Persistence.new()
  local self = setmetatable({}, Persistence)
  self.storage_dir = fs.join(vim.fn.stdpath("data"), "codex-cli", STATE_DIRNAME)
  self.legacy_sidecar_suffix = LEGACY_SIDECAR_SUFFIX
  return self
end

---@param app CodexCli.App
---@return CodexCli.SessionPersistence.State
function Persistence:build_state(app)
  local tabs = {} ---@type CodexCli.TabState.Snapshot[]
  for _, snapshot in ipairs(app.tabs:snapshot()) do
    tabs[#tabs + 1] = snapshot
  end

  return {
    version = STATE_VERSION,
    tabs = tabs,
    terminal_sessions = app.terminals:persistence_specs(),
  }
end

---@param app CodexCli.App
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

---@param app CodexCli.App
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

  app.tabs:restore(state.tabs or {})
  app.terminals:restore_specs(state.terminal_sessions or {})
  app:restore_session_windows(state.tabs or {})
  app:refresh_state_preview()
end

return Persistence
