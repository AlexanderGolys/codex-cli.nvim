local Session = require("clodex.terminal.session")
local TerminalUi = require("clodex.terminal.ui")

--- Defines the Clodex.TerminalTarget.Project type for this module.
--- This annotation documents structured state so modules can pass data with consistent expectations.
---@class Clodex.TerminalTarget.Project
---@field kind 'project'
---@field project Clodex.Project

--- Defines the Clodex.TerminalTarget.Free type for this module.
--- This annotation documents structured state so modules can pass data with consistent expectations.
---@class Clodex.TerminalTarget.Free
---@field kind 'free'
---@field cwd string

--- Defines the Clodex.TerminalTarget type for this module.
--- This annotation documents structured state so modules can pass data with consistent expectations.
---@alias Clodex.TerminalTarget Clodex.TerminalTarget.Project|Clodex.TerminalTarget.Free

--- Defines the Clodex.TerminalManager type for this module.
--- This annotation documents structured state so modules can pass data with consistent expectations.
---@class Clodex.TerminalManager
---@field config Clodex.Config.Values
---@field project_sessions table<string, Clodex.TerminalSession>
---@field free_session? Clodex.TerminalSession
local Manager = {}
Manager.__index = Manager

---@param tabpage number
---@param fn fun()
local function call_in_tabpage(tabpage, fn)
  local target = tabpage
  if not vim.api.nvim_tabpage_is_valid(target) then
    target = vim.api.nvim_get_current_tabpage()
  end

  local tabpage_call = vim.api.nvim_tabpage_call
  if type(tabpage_call) == "function" then
    tabpage_call(target, fn)
    return
  end

  local current = vim.api.nvim_get_current_tabpage()
  if current == target then
    fn()
    return
  end

  vim.api.nvim_set_current_tabpage(target)
  local ok, err = pcall(fn)
  if vim.api.nvim_tabpage_is_valid(current) then
    vim.api.nvim_set_current_tabpage(current)
  end
  if not ok then
    error(err)
  end
end

---@param config Clodex.Config.Values
---@return Clodex.TerminalManager
function Manager.new(config)
  local self = setmetatable({}, Manager)
  self.config = config
  self.project_sessions = {}
  return self
end

---@param config Clodex.Config.Values
function Manager:update_config(config)
  self.config = config
end

---@param target Clodex.TerminalTarget
---@return Clodex.TerminalSession.Spec
function Manager:session_spec(target)
  if target.kind == "project" then
    return {
      key = target.project.root,
      kind = "project",
      cwd = target.project.root,
      title = string.format("Clodex: %s", target.project.name),
      cmd = vim.deepcopy(self.config.codex_cmd),
      project_root = target.project.root,
      header_enabled = false,
    }
  end

  return {
    key = "free::" .. target.cwd,
    kind = "free",
    cwd = target.cwd,
    title = string.format("Clodex: %s", target.cwd),
    cmd = vim.deepcopy(self.config.codex_cmd),
    header_enabled = true,
  }
end

---@param project Clodex.Project
---@return Clodex.TerminalSession?
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

---@param project Clodex.Project
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
---@return Clodex.TerminalSession?
function Manager:project_session(root)
  return self.project_sessions[root]
end

--- Checks a project session running condition for terminal manager.
--- This gate keeps callers safe before continuing higher-level state transitions.
---@param root string
---@return boolean
function Manager:is_project_session_running(root)
  local session = self:project_session(root)
  return session ~= nil and session:is_running() or false
end

---@param project Clodex.Project
---@return Clodex.TerminalSession?
function Manager:ensure_project_session(project)
  local session = self:get_session({
    kind = "project",
    project = project,
  })
  return session
end

---@param buf number
---@return Clodex.TerminalSession?
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

---@param target Clodex.TerminalTarget
---@return Clodex.TerminalSession?, string?
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

---@param session Clodex.TerminalSession
---@return snacks.win
function Manager:open_window(session)
  local Snacks = require("snacks")
  local opts = Snacks.win.resolve("terminal", self.config.terminal.win, {
    buf = session.buf,
    enter = true,
    show = true,
    fixbuf = true,
    bo = {
      filetype = "clodex_terminal",
    },
    wo = {
      statusline = "%!v:lua.require('clodex.terminal.ui').statusline()",
      winbar = "%!v:lua.require('clodex.terminal.ui').winbar()",
    },
    on_win = function()
      TerminalUi.statusline()
      TerminalUi.winbar()
      if self.config.terminal.start_insert then
        vim.cmd.startinsert()
      end
    end,
  })

  return Snacks.win(opts)
end

---@param state Clodex.TabState
---@param session Clodex.TerminalSession
function Manager:show_in_tab(state, session)
  if state:has_visible_window() then
    state:hide_window()
  end

  local window
  call_in_tabpage(state.tabpage, function()
    window = self:open_window(session)
  end)
  window:on("WinClosed", function()
    if state.window == window then
      state:clear_window()
    end
  end, { win = true })
  state:set_window(window, session.key)
end

---@param state Clodex.TabState
function Manager:hide_in_tab(state)
  state:hide_window()
end

---@param key string
---@return Clodex.TerminalSession?
function Manager:session_by_key(key)
  if self.free_session and self.free_session.key == key then
    return self.free_session
  end

  return self.project_sessions[key]
end

---@param session_key string
---@param states Clodex.TabState[]
function Manager:detach_session(session_key, states)
  for _, state in ipairs(states) do
    if state.session_key == session_key then
      state:hide_window()
    end
  end
end

---@return Clodex.TerminalSession.Snapshot[]
function Manager:snapshot()
  local ret = {} ---@type Clodex.TerminalSession.Snapshot[]

  local roots = vim.tbl_keys(self.project_sessions)
  table.sort(roots)
  for _, root in ipairs(roots) do
    ret[#ret + 1] = self.project_sessions[root]:snapshot()
  end

  return ret
end

---@return Clodex.TerminalSession.Spec[]
function Manager:persistence_specs()
  local specs = {} ---@type Clodex.TerminalSession.Spec[]

  local roots = vim.tbl_keys(self.project_sessions)
  table.sort(roots)
  for _, root in ipairs(roots) do
    local session = self.project_sessions[root]
    if session and session:is_running() then
      specs[#specs + 1] = {
        key = session.key,
        kind = session.kind,
        cwd = session.cwd,
        title = session.title,
        cmd = vim.deepcopy(session.cmd),
        project_root = session.project_root,
        header_enabled = session.header_enabled,
      }
    end
  end

  if self.free_session and self.free_session:is_running() then
    specs[#specs + 1] = {
      key = self.free_session.key,
      kind = self.free_session.kind,
      cwd = self.free_session.cwd,
      title = self.free_session.title,
      cmd = vim.deepcopy(self.free_session.cmd),
      project_root = self.free_session.project_root,
      header_enabled = self.free_session.header_enabled,
    }
  end

  return specs
end

---@param specs Clodex.TerminalSession.Spec[]
function Manager:restore_specs(specs)
  specs = specs or {}

  for _, root in ipairs(vim.tbl_keys(self.project_sessions)) do
    self:destroy_project_session(root)
  end
  if self.free_session then
    self.free_session:destroy()
    self.free_session = nil
  end

  for _, spec in ipairs(specs) do
    local session = Session.new(spec)
    if session:ensure_started() then
      if spec.kind == "project" and spec.project_root then
        self.project_sessions[spec.project_root] = session
      elseif spec.kind == "free" then
        self.free_session = session
      end
    end
  end
end

return Manager
