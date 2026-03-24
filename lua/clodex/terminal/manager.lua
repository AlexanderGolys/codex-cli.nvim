local Backend = require("clodex.backend")
local fs = require("clodex.util.fs")
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

---@param session Clodex.TerminalSession
---@param spec Clodex.TerminalSession.Spec
---@return boolean
local function session_requires_restart(session, spec)
    if not session then
        return false
    end

    return session:is_running()
        and (
            not vim.deep_equal(session.cmd, spec.cmd)
            or not vim.deep_equal(session.env or {}, spec.env or {})
            or session.terminal_provider ~= spec.terminal_provider
        )
end

---@param tabpage number
---@return integer?
local function resolved_tabpage(tabpage)
    if vim.api.nvim_tabpage_is_valid(tabpage) then
        return tabpage
    end

    local current = vim.api.nvim_get_current_tabpage()
    if vim.api.nvim_tabpage_is_valid(current) then
        return current
    end
end

---@param tabpage number
---@param fn fun()
local function call_in_tabpage(tabpage, fn)
    local target = resolved_tabpage(tabpage)
    if not target then
        return
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

local function session_running_for_project(session, project_root)
    if not session or not session:is_running() then
        return false
    end

    local normalized_root = fs.normalize(project_root)
    return session.kind == "project"
        and session.project_root ~= nil
        and fs.normalize(session.project_root) == normalized_root
end

---@param config Clodex.Config.Values
---@return "snacks"|"term"
local function session_terminal_provider(config)
    local backend = Backend.normalize(config.backend)
    if backend == "opencode" then
        return "term"
    end
    return config.terminal.provider
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

---@return Clodex.TerminalSession[]
function Manager:sessions()
    local sessions = {} ---@type Clodex.TerminalSession[]

    if self.free_session then
        sessions[#sessions + 1] = self.free_session
    end

    local roots = vim.tbl_keys(self.project_sessions)
    table.sort(roots)
    for _, root in ipairs(roots) do
        sessions[#sessions + 1] = self.project_sessions[root]
    end

    return sessions
end

---@param target Clodex.TerminalTarget
---@return Clodex.TerminalSession.Spec
function Manager:session_spec(target)
    local terminal_provider = session_terminal_provider(self.config)
    if target.kind == "project" then
        local cmd = Backend.cli_cmd(self.config)
        return {
            key = target.project.root,
            kind = "project",
            cwd = target.project.root,
            title = string.format("Clodex: %s", target.project.name),
            cmd = cmd,
            env = Backend.cli_env(self.config, target),
            terminal_provider = terminal_provider,
            project_root = target.project.root,
            header_enabled = false,
        }
    end

    return {
        key = "free::" .. target.cwd,
        kind = "free",
        cwd = target.cwd,
        title = string.format("Clodex: %s", target.cwd),
        cmd = Backend.cli_cmd(self.config),
        env = Backend.cli_env(self.config, target),
        terminal_provider = terminal_provider,
        header_enabled = true,
    }
end

---@param root string
function Manager:destroy_project_session(root)
    if type(root) ~= "string" then
        return
    end
    root = fs.normalize(root)
    local session = self.project_sessions[root]
    if not session then
        return
    end
    session:destroy()
    self.project_sessions[root] = nil
end

---@param project Clodex.Project
function Manager:update_project_identity(project)
    local session = self.project_sessions[fs.normalize(project.root)]
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
    if type(root) ~= "string" or root == "" then
        return nil
    end
    root = fs.normalize(root)
    return self.project_sessions[root]
end

--- Checks a project session running condition for terminal manager.
--- This gate keeps callers safe before continuing higher-level state transitions.
---@param root string
---@return boolean
function Manager:is_project_session_running(root)
    if type(root) ~= "string" or root == "" then
        return false
    end

    local normalized_root = fs.normalize(root)
    local session = self:project_session(normalized_root)
    return session ~= nil and session_running_for_project(session, normalized_root)
end

---@param root string
---@return boolean
function Manager:is_project_session_working(root)
    if type(root) ~= "string" or root == "" then
        return false
    end

    local normalized_root = fs.normalize(root)
    local session = self:project_session(normalized_root)
    return session ~= nil and session_running_for_project(session, normalized_root) and session:is_working()
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
    local spec = self:session_spec(target)
    if target.kind == "project" then
        local project_root = fs.normalize(target.project.root)
        local session = self.project_sessions[project_root]
        if session_requires_restart(session, spec) then
            session:destroy()
            session = nil
        end
        if session then
            session:update_identity(spec)
        else
            session = Session.new(spec)
        end
        self.project_sessions[project_root] = session
        if not self.project_sessions[project_root]:ensure_started() then
            return nil
        end
        return self.project_sessions[project_root]
    end

    local replaced_key ---@type string?
    if self.free_session and self.free_session.cwd ~= target.cwd then
        replaced_key = self.free_session.key
        self.free_session:destroy()
        self.free_session = nil
    end

    if session_requires_restart(self.free_session, spec) then
        self.free_session:destroy()
        self.free_session = nil
    end

    if self.free_session then
        self.free_session:update_identity(spec)
    else
        self.free_session = Session.new(spec)
    end
    if not self.free_session:ensure_started() then
        return nil, replaced_key
    end
    return self.free_session, replaced_key
end

---@param session Clodex.TerminalSession
---@param parent_win? integer
---@param overrides? snacks.win.Config|{}
---@return snacks.win
function Manager:open_window(session, parent_win, overrides)
    local Snacks = require("snacks")
    local is_opencode = Backend.normalize(self.config.backend) == "opencode"
    local wo
    if not is_opencode then
        wo = {
            statusline = "%!v:lua.require('clodex.terminal.ui').statusline()",
            winbar = "%!v:lua.require('clodex.terminal.ui').winbar()",
        }
    end
    local terminal_fixbuf = true
    if self.config and type(self.config.terminal) == "table" and type(self.config.terminal.win) == "table" then
        local configured = self.config.terminal.win.fixbuf
        if type(configured) == "boolean" then
            terminal_fixbuf = configured
        end
    end
    if is_opencode then
        terminal_fixbuf = false
    end
    local opts = Snacks.win.resolve("terminal", self.config.terminal.win, {
        buf = session.buf,
        enter = true,
        show = true,
        fixbuf = terminal_fixbuf,
        bo = {
            filetype = "clodex_terminal",
        },
        wo = wo,
        on_win = function()
            if not is_opencode then
                TerminalUi.statusline()
                TerminalUi.winbar()
            end
            if self.config.terminal.start_insert then
                vim.cmd.startinsert()
            end
        end,
    })
    if overrides then
        opts = vim.tbl_deep_extend("force", opts, vim.deepcopy(overrides))
    end
    if type(parent_win) == "number" and vim.api.nvim_win_is_valid(parent_win) then
        opts.win = parent_win
    end
    opts.title = opts.title or session.title

    return Snacks.win(opts)
end

---@param session Clodex.TerminalSession
---@param tabpage integer
---@return snacks.win?
function Manager:open_blocked_input_window(session, tabpage)
    local blocked_input = self.config.terminal.blocked_input
    if blocked_input == false or blocked_input.enabled == false then
        return nil
    end

    local waiting_state = session:waiting_state()
    if not waiting_state then
        return nil
    end

    local title_suffix = waiting_state == "permission" and "Waiting for permission" or "Waiting for input"
    local window
    call_in_tabpage(tabpage, function()
        window = self:open_window(
            session,
            nil,
            vim.tbl_deep_extend("force", {
                title = ("%s - %s"):format(session.title, title_suffix),
            }, vim.deepcopy(blocked_input.win or {}))
        )
    end)
    return window
end

---@param win integer
---@param tabpage number
---@return boolean
local function is_tab_local_normal_window(win, tabpage)
    if not vim.api.nvim_win_is_valid(win) or vim.api.nvim_win_get_tabpage(win) ~= tabpage then
        return false
    end

    local config = vim.api.nvim_win_get_config(win)
    return (config.relative or "") == ""
end

---@param tabpage number
---@param preferred? integer
---@return integer?
local function split_parent_window(tabpage, preferred)
    tabpage = resolved_tabpage(tabpage)
    if not tabpage then
        return nil
    end

    if type(preferred) == "number" and is_tab_local_normal_window(preferred, tabpage) then
        return preferred
    end

    local fallback ---@type integer?
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
        if is_tab_local_normal_window(win, tabpage) then
            fallback = fallback or win
            if vim.bo[vim.api.nvim_win_get_buf(win)].filetype ~= "clodex_terminal" then
                return win
            end
        end
    end

    return fallback
end

---@param state Clodex.TabState
---@param session Clodex.TerminalSession
function Manager:show_in_tab(state, session)
    local tabpage = resolved_tabpage(state.tabpage)
    if not tabpage then
        return
    end
    state.tabpage = tabpage

    local parent_win = state:has_visible_window() and state.window.win or nil
    if state:has_visible_window() then
        local previous = state.session_key and self:session_by_key(state.session_key) or nil
        if previous then
            previous:archive_history_chunk()
        end
        state:hide_window()
    end

    parent_win = split_parent_window(tabpage, parent_win)
    local window
    call_in_tabpage(tabpage, function()
        window = self:open_window(session, parent_win)
    end)
    window:on("WinClosed", function()
        if state.window == window then
            session:archive_history_chunk()
            state:clear_window()
        end
    end, { win = true })
    state:set_window(window, session.key)
end

---@param state Clodex.TabState
function Manager:hide_in_tab(state)
    local session = state.session_key and self:session_by_key(state.session_key) or nil
    if session then
        session:archive_history_chunk()
    end
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
    local session = self:session_by_key(session_key)
    if session then
        session:archive_history_chunk()
    end
    for _, state in ipairs(states) do
        if state.session_key == session_key then
            state:hide_window()
        end
    end
end

---@return Clodex.TerminalSession.Snapshot[]
function Manager:snapshot()
    local ret = {} ---@type Clodex.TerminalSession.Snapshot[]

    if self.free_session then
        ret[#ret + 1] = self.free_session:snapshot()
    end

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
                env = session.env and vim.deepcopy(session.env) or nil,
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
            env = self.free_session.env and vim.deepcopy(self.free_session.env) or nil,
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
        if fs.is_dir(spec.cwd) then
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
end

return Manager
