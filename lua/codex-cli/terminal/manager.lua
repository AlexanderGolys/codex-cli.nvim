local Session = require("codex-cli.terminal.session")

---@class CodexCli.TerminalTarget.Project
---@field kind 'project'
---@field project CodexCli.Project

---@class CodexCli.TerminalTarget.Free
---@field kind 'free'
---@field cwd string

---@alias CodexCli.TerminalTarget CodexCli.TerminalTarget.Project|CodexCli.TerminalTarget.Free

---@class CodexCli.TerminalManager
---@field config CodexCli.Config.Values
---@field project_sessions table<string, CodexCli.TerminalSession>
---@field free_session? CodexCli.TerminalSession
local Manager = {}
Manager.__index = Manager

---@param config CodexCli.Config.Values
---@return CodexCli.TerminalManager
function Manager.new(config)
  local self = setmetatable({}, Manager)
  self.config = config
  self.project_sessions = {}
  return self
end

---@param config CodexCli.Config.Values
function Manager:update_config(config)
  self.config = config
end

---@param target CodexCli.TerminalTarget
---@return CodexCli.TerminalSession.Spec
function Manager:session_spec(target)
  if target.kind == "project" then
    return {
      key = target.project.root,
      kind = "project",
      cwd = target.project.root,
      title = string.format("Codex: %s", target.project.name),
      cmd = vim.deepcopy(self.config.codex_cmd),
      project_root = target.project.root,
      header_enabled = false,
    }
  end

  return {
    key = "free::" .. target.cwd,
    kind = "free",
    cwd = target.cwd,
    title = string.format("Codex: %s", target.cwd),
    cmd = vim.deepcopy(self.config.codex_cmd),
    header_enabled = true,
  }
end

---@param project CodexCli.Project
---@return CodexCli.TerminalSession?
function Manager:promote_free_session(project)
  if not self.free_session or self.free_session.cwd ~= project.root then
    return self.project_sessions[project.root]
  end

  local spec = self:session_spec({ kind = "project", project = project })
  self.free_session:update_identity(spec)
  self.project_sessions[project.root] = self.free_session
  self.free_session = nil
  return self.project_sessions[project.root]
end

---@param root string
function Manager:destroy_project_session(root)
  local session = self.project_sessions[root]
  if not session then
    return
  end
  session:destroy()
  self.project_sessions[root] = nil
end

---@param project CodexCli.Project
function Manager:update_project_identity(project)
  local session = self.project_sessions[project.root]
  if not session then
    return
  end

  local spec = self:session_spec({
    kind = "project",
    project = project,
  })
  session:update_identity(spec)
end

---@param root string
---@return CodexCli.TerminalSession?
function Manager:project_session(root)
  return self.project_sessions[root]
end

---@param root string
---@return boolean
function Manager:is_project_session_running(root)
  local session = self:project_session(root)
  return session ~= nil and session:is_running() or false
end

---@param project CodexCli.Project
---@return CodexCli.TerminalSession?
function Manager:ensure_project_session(project)
  local session = self:get_session({
    kind = "project",
    project = project,
  })
  return session
end

---@param buf number
---@return CodexCli.TerminalSession?
function Manager:session_by_buf(buf)
  if self.free_session and self.free_session.buf == buf then
    return self.free_session
  end

  for _, session in pairs(self.project_sessions) do
    if session.buf == buf then
      return session
    end
  end
end

---@param buf number
---@return boolean|nil
function Manager:toggle_header_for_buf(buf)
  local session = self:session_by_buf(buf)
  if not session then
    return
  end
  return session:toggle_header()
end

---@param target CodexCli.TerminalTarget
---@return CodexCli.TerminalSession?, string?
function Manager:get_session(target)
  if target.kind == "project" then
    local promoted = self:promote_free_session(target.project)
    if promoted then
      if not promoted:ensure_started() then
        return nil
      end
      return promoted
    end

    self.project_sessions[target.project.root] = self.project_sessions[target.project.root]
      or Session.new(self:session_spec(target))
    if not self.project_sessions[target.project.root]:ensure_started() then
      return nil
    end
    return self.project_sessions[target.project.root]
  end

  local replaced_key ---@type string?
  if self.free_session and self.free_session.cwd ~= target.cwd then
    replaced_key = self.free_session.key
    self.free_session:destroy()
    self.free_session = nil
  end

  self.free_session = self.free_session or Session.new(self:session_spec(target))
  if not self.free_session:ensure_started() then
    return nil, replaced_key
  end
  return self.free_session, replaced_key
end

---@param session CodexCli.TerminalSession
---@return snacks.win
function Manager:open_window(session)
  local Snacks = require("snacks")
  local opts = Snacks.win.resolve("terminal", self.config.terminal.win, {
    buf = session.buf,
    enter = true,
    show = true,
    fixbuf = true,
    bo = {
      filetype = "codex_cli_terminal",
    },
    title = session.title,
    on_win = function()
      if self.config.terminal.start_insert then
        vim.cmd.startinsert()
      end
    end,
  })

  return Snacks.win(opts)
end

---@param state CodexCli.TabState
---@param session CodexCli.TerminalSession
function Manager:show_in_tab(state, session)
  if state:has_visible_window() then
    state:hide_window()
  end

  local window = self:open_window(session)
  window:on("WinClosed", function()
    if state.window == window then
      state:clear_window()
    end
  end, { win = true })
  state:set_window(window, session.key)
end

---@param state CodexCli.TabState
function Manager:hide_in_tab(state)
  state:hide_window()
end

---@param session_key string
---@param states CodexCli.TabState[]
function Manager:detach_session(session_key, states)
  for _, state in ipairs(states) do
    if state.session_key == session_key then
      state:hide_window()
    end
  end
end

---@return CodexCli.TerminalSession.Snapshot[]
function Manager:snapshot()
  local ret = {} ---@type CodexCli.TerminalSession.Snapshot[]

  local roots = vim.tbl_keys(self.project_sessions)
  table.sort(roots)
  for _, root in ipairs(roots) do
    ret[#ret + 1] = self.project_sessions[root]:snapshot()
  end

  return ret
end

return Manager
