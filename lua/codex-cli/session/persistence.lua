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

--- Defines the CodexCli.SessionPersistence.State type for this module.
--- This annotation documents structured state so modules can pass data with consistent expectations.
---@class CodexCli.SessionPersistence.State
---@field version integer
---@field tabs CodexCli.TabState.Snapshot[]
---@field terminal_sessions CodexCli.TerminalSession.Spec[]

--- Creates a new session persistence instance from this module.
--- It is used by callers to bootstrap module state before running higher-level plugin actions.
---@return CodexCli.SessionPersistence
function Persistence.new()
  local self = setmetatable({}, Persistence)
  self.storage_dir = fs.join(vim.fn.stdpath("data"), "codex-cli", STATE_DIRNAME)
  self.legacy_sidecar_suffix = LEGACY_SIDECAR_SUFFIX
  return self
end

--- Implements the normalize_session_file path for session persistence.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param session_file string
---@return string?
function Persistence:normalize_session_file(session_file)
  session_file = vim.trim(session_file or "")
  if session_file == "" then
    return
  end
  return fs.normalize(session_file)
end

--- Implements the storage_path path for session persistence.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param session_file string
---@return string?
function Persistence:storage_path(session_file)
  session_file = self:normalize_session_file(session_file)
  if not session_file then
    return
  end

  local basename = fs.basename(session_file):gsub("[^%w%-_%.]", "_")
  local digest = vim.fn.sha256(session_file):sub(1, 16)
  return fs.join(self.storage_dir, ("%s-%s.json"):format(basename, digest))
end

--- Implements the legacy_sidecar_path path for session persistence.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param session_file string
---@return string?
function Persistence:legacy_sidecar_path(session_file)
  session_file = self:normalize_session_file(session_file)
  if not session_file then
    return
  end
  return session_file .. self.legacy_sidecar_suffix
end

--- Implements the build_state path for session persistence.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
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

--- Persists or restores session persistence data for this workflow.
--- It is used by session restoration and command surfaces so behavior remains repeatable.
---@param app CodexCli.App
---@param session_file string
function Persistence:save(app, session_file)
  local storage_path = self:storage_path(session_file)
  if not storage_path then
    return
  end
  fs.write_json(storage_path, self:build_state(app))

  local legacy_sidecar = self:legacy_sidecar_path(session_file)
  if legacy_sidecar and fs.is_file(legacy_sidecar) then
    fs.remove(legacy_sidecar)
  end
end

--- Persists or restores session persistence data for this workflow.
--- It is used by session restoration and command surfaces so behavior remains repeatable.
---@param app CodexCli.App
---@param session_file string
function Persistence:restore(app, session_file)
  local state_path = self:storage_path(session_file)
  if not state_path or not fs.is_file(state_path) then
    state_path = self:legacy_sidecar_path(session_file)
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
