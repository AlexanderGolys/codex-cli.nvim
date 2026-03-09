local notify = require("codex-cli.util.notify")

---@class CodexCli.TerminalSession.Spec
---@field key string
---@field kind 'project'|'free'
---@field cwd string
---@field title string
---@field cmd string[]
---@field project_root? string
---@field header_enabled? boolean

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

local function termopen(cmd, opts)
  local fn = vim.fn.termopen or vim.fn.jobstart
  if fn == vim.fn.jobstart then
    opts.term = true
  end
  return fn(cmd, vim.tbl_isempty(opts) and vim.empty_dict() or opts)
end

---@param spec CodexCli.TerminalSession.Spec
---@return CodexCli.TerminalSession
function Session.new(spec)
  spec = vim.deepcopy(spec)
  if spec.header_enabled == nil then
    spec.header_enabled = spec.kind == "free"
  end
  return setmetatable(spec, Session)
end

function Session:header_text()
  if self.kind == "free" then
    return ("[Codex CLI] %s"):format(self.cwd)
  end
  return ("[Codex CLI] %s"):format(self.title)
end

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

function Session:toggle_header()
  self.header_enabled = not self.header_enabled
  self:sync_header()
  return self.header_enabled
end

---@return boolean
function Session:buf_valid()
  return self.buf ~= nil and vim.api.nvim_buf_is_valid(self.buf)
end

---@return boolean
function Session:is_running()
  if not self.job_id then
    return false
  end
  return vim.fn.jobwait({ self.job_id }, 0)[1] == -1
end

function Session:update_buffer_state()
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
  self:sync_header()
end

function Session:ensure_started()
  if self:buf_valid() and self:is_running() then
    self:update_buffer_state()
    return true
  end

  if self:buf_valid() then
    pcall(vim.api.nvim_buf_delete, self.buf, { force = true })
  end

  self.buf = vim.api.nvim_create_buf(false, true)
  self:update_buffer_state()

  local ok, job_id = pcall(vim.api.nvim_buf_call, self.buf, function()
    return termopen(self.cmd, {
      cwd = self.cwd,
      on_exit = function(_, code)
        self.job_id = nil
        if code ~= 0 then
          notify.warn(("Codex session exited with code %d at %s"):format(code, self.cwd))
        end
      end,
    })
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
  return true
end

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
