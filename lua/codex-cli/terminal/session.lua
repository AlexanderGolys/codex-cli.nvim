local notify = require("codex-cli.util.notify")

--- Defines the CodexCli.TerminalSession.Spec type for this module.
--- This annotation documents structured state so modules can pass data with consistent expectations.
---@class CodexCli.TerminalSession.Spec
---@field key string
---@field kind 'project'|'free'
---@field cwd string
---@field title string
---@field cmd string[]
---@field project_root? string
---@field header_enabled? boolean

--- Defines the CodexCli.TerminalSession type for this module.
--- This annotation documents structured state so modules can pass data with consistent expectations.
---@class CodexCli.TerminalSession
---@field key string
---@field kind 'project'|'free'
---@field cwd string
---@field title string
---@field cmd string[]
---@field project_root? string
---@field header_enabled boolean
---@field buf? number
---@field job_id? integer

--- Defines the CodexCli.TerminalSession.Snapshot type for this module.
--- This annotation documents structured state so modules can pass data with consistent expectations.
---@class CodexCli.TerminalSession.Snapshot
---@field key string
---@field kind 'project'|'free'
---@field cwd string
---@field title string
---@field project_root? string
---@field buf? integer
---@field buffer_valid boolean
---@field job_id? integer
---@field running boolean
local Session = {}
Session.__index = Session

--- Implements the termopen path for terminal session.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
local function termopen(cmd, opts)
  local fn = vim.fn.termopen or vim.fn.jobstart
  if fn == vim.fn.jobstart then
    opts.term = true
  end
  return fn(cmd, vim.tbl_isempty(opts) and vim.empty_dict() or opts)
end

--- Implements the start_with_snacks path for terminal session.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param cmd string[]
---@param opts vim.fn.jobstart.Opts
---@param buf number
---@return boolean, integer?
local function start_with_snacks(cmd, opts, buf)
  local started_job ---@type integer?
  local ok, err = pcall(function()
    local Snacks = require("snacks")
    Snacks.terminal.open(cmd, {
      cwd = opts.cwd,
      interactive = false,
      auto_close = false,
      start_insert = false,
      auto_insert = false,
      win = {
        buf = buf,
        show = false,
        enter = false,
        fixbuf = true,
        bo = {
          filetype = "codex_cli_terminal",
        },
      },
--- Implements the override path for terminal session.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
      override = function(terminal_cmd, terminal_opts)
        local terminal = Snacks.win(terminal_opts.win)
        vim.b[buf].snacks_terminal = {
          cmd = terminal_cmd,
          cwd = terminal_opts.cwd,
        }
        started_job = vim.api.nvim_buf_call(buf, function()
          return termopen(terminal_cmd, opts)
        end)
        return terminal
      end,
    })

    if type(started_job) ~= "number" or started_job <= 0 then
      error("invalid terminal job")
    end
  end)

  if not ok then
    notify.warn(("Falling back to raw terminal startup: %s"):format(tostring(err)))
    return false
  end

  return true, started_job
end

--- Creates a new terminal session instance from this module.
--- It is used by callers to bootstrap module state before running higher-level plugin actions.
---@param spec CodexCli.TerminalSession.Spec
---@return CodexCli.TerminalSession
function Session.new(spec)
  spec = vim.deepcopy(spec)
  if spec.header_enabled == nil then
    spec.header_enabled = spec.kind == "free"
  end
  return setmetatable(spec, Session)
end

--- Returns the title line shown in the terminal header when enabled.
--- The header is reused by free and project sessions to identify context at a glance.
--- It is included in terminal UI rendering and refreshed whenever session state changes.
function Session:header_text()
  if self.kind == "free" then
    return ("[Codex CLI] %s"):format(self.cwd)
  end
  return ("[Codex CLI] %s"):format(self.title)
end

--- Ensures the header line in the terminal buffer reflects current session settings.
--- This normalizes what users see when entering buffers and when settings change.
--- It also removes stale headers when header mode is disabled.
function Session:sync_header()
  if not self:buf_valid() then
    return
  end

  if self.header_enabled then
    local header = self:header_text()
    local existing = vim.api.nvim_buf_get_lines(self.buf, 0, 1, false)[1]
    if existing ~= header then
      vim.api.nvim_buf_set_lines(self.buf, 0, 1, false, { header })
    end
    return
  end

  local existing = vim.api.nvim_buf_get_lines(self.buf, 0, 1, false)[1]
  if existing and existing:find("^%[Codex CLI%]") then
    vim.api.nvim_buf_set_lines(self.buf, 0, 1, false, {})
  end
end

--- Toggles whether the header row is shown in the terminal buffer.
--- The new setting is applied immediately and persisted for the session lifecycle.
--- Callers use this for user-facing header visibility toggles.
function Session:toggle_header()
  self.header_enabled = not self.header_enabled
  self:sync_header()
  return self.header_enabled
end

--- Implements the buf_valid path for terminal session.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@return boolean
function Session:buf_valid()
  return self.buf ~= nil and vim.api.nvim_buf_is_valid(self.buf)
end

--- Checks a running condition for terminal session.
--- This gate keeps callers safe before continuing higher-level state transitions.
---@return boolean
function Session:is_running()
  if not self.job_id then
    return false
  end
  return vim.fn.jobwait({ self.job_id }, 0)[1] == -1
end

--- Implements the update_buffer_state path for terminal session.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param opts? { sync_header?: boolean }
function Session:update_buffer_state(opts)
  opts = opts or {}
  if not self:buf_valid() then
    return
  end

  vim.bo[self.buf].bufhidden = "hide"
  vim.bo[self.buf].swapfile = false
  vim.bo[self.buf].filetype = "codex_cli_terminal"
  vim.b[self.buf].codex_cli = {
    key = self.key,
    kind = self.kind,
    cwd = self.cwd,
    project_root = self.project_root,
  }
  if opts.sync_header ~= false then
    self:sync_header()
  end
end

--- Starts the terminal if needed and initializes buffer state.
--- This is the main readiness gate used before any prompt is sent to a session.
---@return boolean
function Session:ensure_started()
  if self:buf_valid() and self:is_running() then
    self:update_buffer_state()
    return true
  end

  if self:buf_valid() then
    pcall(vim.api.nvim_buf_delete, self.buf, { force = true })
  end

  self.buf = vim.api.nvim_create_buf(false, true)
  self:update_buffer_state({ sync_header = false })

  local ok, job_id = pcall(vim.api.nvim_buf_call, self.buf, function()
    local start_opts = {
      cwd = self.cwd,
--- Implements the on_exit path for terminal session.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
      on_exit = function(_, code)
        self.job_id = nil
        if code ~= 0 then
          notify.warn(("Codex session exited with code %d at %s"):format(code, self.cwd))
        end
      end,
    }

    local started, snacks_job = start_with_snacks(self.cmd, start_opts, self.buf)
    if started then
      return snacks_job
    end

    return termopen(self.cmd, start_opts)
  end)

  if not ok or type(job_id) ~= "number" or job_id <= 0 then
    self.job_id = nil
    if self:buf_valid() then
      pcall(vim.api.nvim_buf_delete, self.buf, { force = true })
    end
    self.buf = nil
    notify.error(("Failed to start Codex session in %s"):format(self.cwd))
    return false
  end

  self.job_id = job_id
  self:sync_header()
  return true
end

--- Stops any running process and deletes terminal buffer state.
--- It is called during project shutdown and when switching away from removed sessions.
function Session:destroy()
  if self:is_running() then
    pcall(vim.fn.jobstop, self.job_id)
  end
  self.job_id = nil

  if self:buf_valid() then
    pcall(vim.api.nvim_buf_delete, self.buf, { force = true })
  end
  self.buf = nil
end

--- Implements the send path for terminal session.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param text string
---@return boolean
function Session:send(text)
  text = vim.trim(text or "")
  if text == "" then
    return false
  end
  if not self:ensure_started() or not self.job_id then
    return false
  end

  local ok = pcall(vim.fn.chansend, self.job_id, text .. "\n")
  if not ok then
    notify.error(("Failed to send prompt to Codex session at %s"):format(self.cwd))
    return false
  end
  return true
end

--- Implements the update_identity path for terminal session.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param spec CodexCli.TerminalSession.Spec
function Session:update_identity(spec)
  self.key = spec.key
  self.kind = spec.kind
  self.cwd = spec.cwd
  self.title = spec.title
  self.cmd = vim.deepcopy(spec.cmd)
  self.project_root = spec.project_root
  if spec.header_enabled ~= nil then
    self.header_enabled = spec.header_enabled
  end
  self:update_buffer_state()
end

--- Implements the snapshot path for terminal session.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@return CodexCli.TerminalSession.Snapshot
function Session:snapshot()
  local buffer_valid = self:buf_valid()
  return {
    key = self.key,
    kind = self.kind,
    cwd = self.cwd,
    title = self.title,
    project_root = self.project_root,
    buf = self.buf,
    buffer_valid = buffer_valid,
    job_id = self.job_id,
    running = self:is_running(),
  }
end

return Session
