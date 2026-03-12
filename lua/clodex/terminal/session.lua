local notify = require("clodex.util.notify")

--- Defines the Clodex.TerminalSession.Spec type for this module.
--- This annotation documents structured state so modules can pass data with consistent expectations.
---@class Clodex.TerminalSession.Spec
---@field key string
---@field kind 'project'|'free'
---@field cwd string
---@field title string
---@field cmd string[]
---@field project_root? string
---@field header_enabled? boolean

--- Defines the Clodex.TerminalSession type for this module.
--- This annotation documents structured state so modules can pass data with consistent expectations.
---@class Clodex.TerminalSession
---@field key string
---@field kind 'project'|'free'
---@field cwd string
---@field title string
---@field cmd string[]
---@field project_root? string
---@field header_enabled boolean
---@field buf? number
---@field job_id? integer
---@field suppress_exit_warning boolean

--- Defines the Clodex.TerminalSession.Snapshot type for this module.
--- This annotation documents structured state so modules can pass data with consistent expectations.
---@class Clodex.TerminalSession.Snapshot
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


local Snacks = {
    terminal = require("snacks.terminal"),
}

---@param cmd string[]
---@param opts { cwd?: string }
---@param buf number
---@return snacks.win
local function start_with_snacks(cmd, opts, buf)
    local terminal = Snacks.terminal.open(cmd, {
        cwd = opts.cwd,
        interactive = true,
        win = {
            buf = buf,
            bo = {
                filetype = "clodex_terminal"
            }
        }
    })
    if terminal and terminal.hide then
        terminal:hide()
    end
    return terminal
end

---@param buf integer
---@return integer?
local function terminal_job_id(buf)
    local ok, job_id = pcall(vim.api.nvim_buf_get_var, buf, "terminal_job_id")
    if ok and type(job_id) == "number" and job_id > 0 then
        return job_id
    end
end

---@param self Clodex.TerminalSession
local function attach_termclose_handler(self)
    vim.api.nvim_create_autocmd("TermClose", {
        buffer = self.buf,
        callback = function()
            self.job_id = nil
            local suppress_warning = self.suppress_exit_warning
            self.suppress_exit_warning = false
            local code = type(vim.v.event) == "table" and vim.v.event.status or 0
            if code ~= 0 and not suppress_warning then
                notify.warn(("Codex session exited with code %d at %s"):format(code, self.cwd))
            end
        end
    })
end

---@param buf integer
---@param fn fun()
local function with_editable_buffer(buf, fn)
    local was_modifiable = vim.bo[buf].modifiable
    vim.bo[buf].modifiable = true

    local ok, err = pcall(fn)

    if not was_modifiable and vim.api.nvim_buf_is_valid(buf) then
        vim.bo[buf].modifiable = false
    end

    if not ok then
        error(err)
    end
end

---@param spec Clodex.TerminalSession.Spec
---@return Clodex.TerminalSession
function Session.new(spec)
    spec = vim.deepcopy(spec)
    if spec.header_enabled == nil then
        spec.header_enabled = spec.kind == "free"
    end
    spec.suppress_exit_warning = false
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
            with_editable_buffer(self.buf, function()
                vim.api.nvim_buf_set_lines(self.buf, 0, 1, false, { header })
            end)
        end
        return
    end

    local existing = vim.api.nvim_buf_get_lines(self.buf, 0, 1, false)[1]
    if existing and existing:find("^%[Codex CLI%]") then
        with_editable_buffer(self.buf, function()
            vim.api.nvim_buf_set_lines(self.buf, 0, 1, false, {})
        end)
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

---@param opts? { sync_header?: boolean }
function Session:update_buffer_state(opts)
    opts = opts or {}
    if not self:buf_valid() then
        return
    end

    vim.bo[self.buf].bufhidden = "hide"
    vim.bo[self.buf].swapfile = false
    vim.bo[self.buf].filetype = "clodex_terminal"
    vim.b[self.buf].clodex = {
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

    local ok, terminal = pcall(start_with_snacks, self.cmd, {
        cwd = self.cwd,
    }, self.buf)
    local job_id = ok and self.buf and terminal_job_id(self.buf) or nil
    if not ok or not terminal or type(job_id) ~= "number" or job_id <= 0 then
        self.job_id = nil
        if self:buf_valid() then
            pcall(vim.api.nvim_buf_delete, self.buf, { force = true })
        end
        self.buf = nil
        notify.error(("Failed to start Codex session in %s"):format(self.cwd))
        return false
    end

    self.job_id = job_id
    attach_termclose_handler(self)
    self:update_buffer_state({ sync_header = false })
    self:sync_header()
    return true
end

--- Stops any running process and deletes terminal buffer state.
--- It is called during project shutdown and when switching away from removed sessions.
function Session:destroy()
    if self:is_running() then
        self.suppress_exit_warning = true
        pcall(vim.fn.jobstop, self.job_id)
    end
    self.job_id = nil

    if self:buf_valid() then
        pcall(vim.api.nvim_buf_delete, self.buf, { force = true })
    end
    self.buf = nil
end

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

---@param spec Clodex.TerminalSession.Spec
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
    if spec.suppress_exit_warning ~= nil then
        self.suppress_exit_warning = spec.suppress_exit_warning
    end
    self:update_buffer_state()
end

---@return Clodex.TerminalSession.Snapshot
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
