local notify = require("codex-cli.util.notify")

---@class CodexCli.TerminalSession.Spec
---@field key string
---@field kind 'project'|'free'
---@field cwd string
---@field title string
---@field cmd string[]
---@field project_root? string

---@class CodexCli.TerminalSession
---@field key string
---@field kind 'project'|'free'
---@field cwd string
---@field title string
---@field cmd string[]
---@field project_root? string
---@field buf? number
---@field job_id? integer
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
  return setmetatable(vim.deepcopy(spec), Session)
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
  self:update_buffer_state()
end

return Session
