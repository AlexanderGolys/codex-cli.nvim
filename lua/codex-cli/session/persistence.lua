local fs = require("codex-cli.util.fs")

---@class CodexCli.SessionPersistence
---@field sidecar_suffix string
local Persistence = {}
Persistence.__index = Persistence

local STATE_VERSION = 1

---@class CodexCli.SessionPersistence.State
---@field version integer
---@field tabs { active_project_root?: string, prompted_project?: boolean }[]
---@field terminal_sessions CodexCli.TerminalSession.Spec[]

---@return CodexCli.SessionPersistence
function Persistence.new()
  local self = setmetatable({}, Persistence)
  self.sidecar_suffix = ".codex-cli.json"
  return self
end

---@param session_file string
---@return string?
function Persistence:sidecar_path(session_file)
  session_file = vim.trim(session_file or "")
  if session_file == "" then
    return
  end
  return session_file .. self.sidecar_suffix
end

---@param app CodexCli.App
---@return CodexCli.SessionPersistence.State
function Persistence:build_state(app)
  local tabs = {} ---@type { active_project_root?: string, prompted_project?: boolean }[]
  for _, snapshot in ipairs(app.tabs:snapshot()) do
    tabs[#tabs + 1] = {
      active_project_root = snapshot.active_project_root,
      prompted_project = snapshot.prompted_project == true,
    }
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
  local sidecar_path = self:sidecar_path(session_file)
  if not sidecar_path then
    return
  end
  fs.write_json(sidecar_path, self:build_state(app))
end

---@param app CodexCli.App
---@param session_file string
function Persistence:restore(app, session_file)
  local sidecar_path = self:sidecar_path(session_file)
  if not sidecar_path or not fs.is_file(sidecar_path) then
    return
  end

  local state = fs.read_json(sidecar_path, nil)
  if type(state) ~= "table" then
    return
  end

  app.tabs:restore(state.tabs or {})
  app.terminals:restore_specs(state.terminal_sessions or {})
  app:refresh_state_preview()
end

return Persistence
