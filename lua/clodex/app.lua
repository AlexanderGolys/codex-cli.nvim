local Backend = require("clodex.backend")
local Config = require("clodex.config")
local Commands = require("clodex.commands")
local ExecutionRunner = require("clodex.execution.runner")
local History = require("clodex.history")
local ProjectActions = require("clodex.app.project_actions")
local PromptActions = require("clodex.app.prompt_actions")
local QueueActions = require("clodex.app.queue_actions")
local QueueCycle = require("clodex.app.queue_cycle")
local ProjectDetails = require("clodex.project.details")
local ProjectBookmarks = require("clodex.project.bookmarks")
local ProjectCheatsheet = require("clodex.project.cheatsheet")
local ProjectNotes = require("clodex.project.notes")
local Registry = require("clodex.project.registry")
local TabManager = require("clodex.tab.manager")
local TerminalManager = require("clodex.terminal.manager")
local StatePreview = require("clodex.ui.state_preview")
local QueueWorkspace = require("clodex.ui.queue_workspace")
local SessionPersistence = require("clodex.session.persistence")
local Execution = require("clodex.workspace.execution")
local Queue = require("clodex.workspace.queue")
local TerminalUi = require("clodex.terminal.ui")
local TerminalLualine = require("clodex.terminal.lualine")
local fs = require("clodex.util.fs")
local notify = require("clodex.util.notify")

--- Defines the Clodex.App type for this module.
--- This annotation documents structured state so modules can pass data with consistent expectations.
---@class Clodex.App
---@field config Clodex.Config
---@field registry Clodex.ProjectRegistry
---@field project_details_store Clodex.ProjectDetails
---@field tabs Clodex.TabManager
---@field terminals Clodex.TerminalManager
---@field state_preview Clodex.StatePreview
---@field project_bookmarks Clodex.ProjectBookmarks
---@field project_notes Clodex.ProjectNotes
---@field project_cheatsheet Clodex.ProjectCheatsheet
---@field queue Clodex.Workspace.Queue
---@field execution Clodex.Workspace.Execution
---@field exec_runner Clodex.ExecutionRunner
---@field queue_workspace Clodex.QueueWorkspace
---@field project_actions Clodex.AppProjectActions
---@field prompt_actions Clodex.AppPromptActions
---@field queue_actions Clodex.AppQueueActions
---@field queue_cycle Clodex.QueueCycle
---@field session_persistence Clodex.SessionPersistence
---@field group? integer
---@field execution_timer? uv.uv_timer_t
---@field current_tab fun(self: Clodex.App): Clodex.TabState
---@field resolve_target fun(self: Clodex.App, state: Clodex.TabState): Clodex.TerminalTarget

--- Defines the Clodex.App.StateSnapshot type for this module.
--- This annotation documents structured state so modules can pass data with consistent expectations.
---@class Clodex.App.StateSnapshot
---@field current_path string
---@field active_project? Clodex.Project
---@field detected_project? Clodex.Project
---@field resolved_target Clodex.TerminalTarget
---@field current_tab Clodex.TabState.Snapshot
---@field tabs Clodex.TabState.Snapshot[]
---@field sessions Clodex.TerminalSession.Snapshot[]
---@field projects Clodex.Project[]
---@field project_states Clodex.App.ProjectState[]

--- Defines the Clodex.App.ProjectState type for this module.
--- This annotation documents structured state so modules can pass data with consistent expectations.
---@class Clodex.App.ProjectState
---@field project Clodex.Project
---@field session_active boolean
---@field window_open_in_active_tab boolean
---@field usage_events string
---@field working string
---@field model string
---@field context string
---@field bookmark_count integer
---@field notes_count integer
---@field cheatsheet_count integer
---@field cheatsheet_items string[]
local App = {}
App.__index = App

---@alias Clodex.AppForwardGroup "project_actions"|"prompt_actions"|"queue_actions"
---@class Clodex.AppForwardSpec
---@field field Clodex.AppForwardGroup
---@field method string

local singleton ---@type Clodex.App?
local FORWARDED_METHODS = {
    open_project_readme_file = { field = "project_actions", method = "open_project_readme_file" },
    open_project_todo_file = { field = "project_actions", method = "open_project_todo_file" },
    open_project_dictionary_file = { field = "project_actions", method = "open_project_dictionary_file" },
    open_project_cheatsheet_file = { field = "project_actions", method = "open_project_cheatsheet_file" },
    toggle_project_cheatsheet_preview = { field = "project_actions", method = "toggle_project_cheatsheet_preview" },
    add_project_cheatsheet_item = { field = "project_actions", method = "add_project_cheatsheet_item" },
    open_project_notes_picker = { field = "project_actions", method = "open_project_notes_picker" },
    create_project_note = { field = "project_actions", method = "create_project_note" },
    add_project_bookmark = { field = "project_actions", method = "add_project_bookmark" },
    open_project_bookmarks_picker = { field = "project_actions", method = "open_project_bookmarks_picker" },
    implement_next_queued_item = { field = "queue_actions", method = "implement_next_queued_item" },
    implement_all_queued_items = { field = "queue_actions", method = "implement_all_queued_items" },
    add_bug_todo = { field = "prompt_actions", method = "add_bug_todo" },
    activate_project = { field = "project_actions", method = "activate_project" },
    set_current_project = { field = "project_actions", method = "set_current_project" },
    clear_active_project = { field = "project_actions", method = "clear_active_project" },
    toggle = { field = "project_actions", method = "toggle" },
    rename_project = { field = "project_actions", method = "rename_project" },
    add_project = { field = "project_actions", method = "add_project" },
    remove_project = { field = "project_actions", method = "remove_project" },
    maybe_offer_project = { field = "project_actions", method = "maybe_offer_project" },
    toggle_terminal_header = { field = "project_actions", method = "toggle_terminal_header" },
} ---@type table<string, Clodex.AppForwardSpec>

---@param field Clodex.AppForwardGroup
---@param method string
---@return fun(self: Clodex.App, ...): any
local function forward(field, method)
    return function(self, ...)
        return self[field][method](self[field], ...)
    end
end

---@param buf integer
---@return boolean
local function should_check_buffer(buf)
    if not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_buf_is_loaded(buf) then
        return false
    end
    if vim.bo[buf].buftype ~= "" or vim.bo[buf].modified then
        return false
    end

    local path = vim.api.nvim_buf_get_name(buf)
    if path == "" or fs.is_virtual_path(path) then
        return false
    end
    return fs.is_file(path)
end

---@param path string
---@param projects Clodex.Project[]
---@return boolean
local function path_in_registered_project(path, projects)
    for _, project in ipairs(projects) do
        if fs.is_relative_to(path, project.root) then
            return true
        end
    end
    return false
end

---@param buf integer
---@return boolean
local function snapshot_context_buffer(buf)
    if not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_buf_is_loaded(buf) then
        return false
    end
    if vim.bo[buf].buftype ~= "" then
        return false
    end
    local filetype = vim.bo[buf].filetype
    return filetype ~= "clodex_state" and filetype ~= "clodex_queue_workspace"
end

---@param config Clodex.Config.Values
---@param buf integer
local function reconnect_terminal_on_enter(config, buf)
    if not config.terminal.start_insert then
        return
    end
    if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].filetype ~= "clodex_terminal" then
        return
    end

    local win = vim.api.nvim_get_current_win()
    vim.schedule(function()
        if not vim.api.nvim_win_is_valid(win) or vim.api.nvim_win_get_buf(win) ~= buf then
            return
        end
        if vim.api.nvim_get_mode().mode:sub(1, 1) == "t" then
            return
        end
        vim.cmd.startinsert()
    end)
end

---@return integer?
local function snapshot_context_buf()
    local tabpage = vim.api.nvim_get_current_tabpage()
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
        if vim.api.nvim_win_is_valid(win) then
            local config = vim.api.nvim_win_get_config(win)
            if (config.relative or "") == "" then
                local buf = vim.api.nvim_win_get_buf(win)
                if snapshot_context_buffer(buf) then
                    return buf
                end
            end
        end
    end

    local current = vim.api.nvim_get_current_buf()
    if snapshot_context_buffer(current) then
        return current
    end
end

---@param registry Clodex.ProjectRegistry
---@param root? string
---@return Clodex.Project?
local function active_project_for_root(registry, root)
    if type(root) ~= "string" or root == "" then
        return nil
    end

    local project = registry:get(root)
    if not project or not fs.is_dir(project.root) then
        return nil
    end

    return project
end

---@return Clodex.App
--- Returns the singleton application object, creating it lazily on first access.
--- This guarantees shared state across modules and prevents duplicate terminal managers.
function App.instance()
    singleton = singleton or App.new()
    return singleton
end

---@return Clodex.App
--- Constructs a fully wired application instance with default subcomponents.
--- The instance created here is the runtime container for registry, terminals, and UI surfaces.
function App.new()
    local self = setmetatable({}, App)
    self.config = Config.new()
    self.tabs = TabManager.new()
    self.session_persistence = SessionPersistence.new()
    self.project_actions = ProjectActions.new(self)
    self.prompt_actions = PromptActions.new(self)
    self.queue_actions = QueueActions.new(self)
    self.queue_cycle = QueueCycle.new(self)
    self:setup({})
    return self
end

---@param opts? Clodex.Config.Values|{}
--- Applies/refreshes configuration and rebuilds dependent managers when options change.
--- This is invoked on startup and every setup call from the public API layer.
function App:setup(opts)
    local values = self.config:setup(opts)
    Config.apply_highlights(values)
    TerminalLualine.ensure_terminal_disabled(values.terminal.prefer_native_statusline)
    self.registry = Registry.new({ path = values.storage.projects_file })
    self.project_details_store = self.project_details_store or ProjectDetails.new(values)
    self.project_bookmarks = self.project_bookmarks or ProjectBookmarks.new()
    self.project_notes = self.project_notes or ProjectNotes.new()
    self.project_cheatsheet = self.project_cheatsheet or ProjectCheatsheet.new()
    self.terminals = self.terminals or TerminalManager.new(values)
    self.state_preview = self.state_preview or StatePreview.new(values)
    self.queue = self.queue or Queue.new(values.storage.workspaces_dir)
    self.execution = self.execution or Execution.new(values)
    self.exec_runner = self.exec_runner or ExecutionRunner.new(self, values)
    self.queue_workspace = self.queue_workspace or QueueWorkspace.new(self, values)
    self.session_persistence:update_storage_dir(values.storage.session_state_dir)
    History.configure(values.storage.history_file)
    self.terminals:update_config(values)
    self.state_preview:update_config(values)
    self.project_details_store:update_config(values)
    self.execution:update_config(values)
    if self.execution:uses_prompt_skill() then
        local ok, err = pcall(function()
            self.execution:sync_prompt_skill()
        end)
        if not ok then
            notify.warn(("Could not sync global prompt skill: %s"):format(err))
        end
    end
    self.exec_runner:update_config(values)
    self.queue_workspace:update_config(values)
    Commands.register()
    Commands.register_keymaps(values)
    self:setup_autocmds()
    self:setup_execution_timer()
    self:refresh_state_preview()
end

--- Registers the plugin-wide autocommand group for project and terminal state refreshes.
--- These hooks keep preview panes, tab state, and project prompts in sync automatically.
function App:setup_autocmds()
    if self.group then
        return
    end

    self.group = vim.api.nvim_create_augroup("clodex", { clear = true })
    vim.api.nvim_create_autocmd("TabClosed", {
        group = self.group,
        --- Rebuilds tab state after closing any tab and refreshes preview windows.
        --- This keeps stale per-tab session information from leaking.
        callback = function()
            self.tabs:cleanup()
            self:refresh_views()
        end,
    })

    vim.api.nvim_create_autocmd("TabNewEntered", {
        group = self.group,
        --- Prompts new tabs for an active project choice instead of inheriting the old tab silently.
        --- This keeps tab-local project focus intentional right when the tab opens.
        callback = function()
            self:prompt_new_tab_active_project()
        end,
    })

    vim.api.nvim_create_autocmd({ "BufEnter", "DirChanged", "FocusGained", "TabEnter" }, {
        group = self.group,
        --- Refreshes preview state and prompts project detection for the current buffer.
        --- Helps users who navigate tabs or directories get immediate context updates.
        callback = function(args)
            local buf = args.buf or vim.api.nvim_get_current_buf()
            self:refresh_changed_project_buffer(buf)
            self:refresh_bookmarks_for_buffer(buf)
            self:refresh_views()
            self:maybe_prompt_active_project(buf)
            reconnect_terminal_on_enter(self.config:get(), buf)
        end,
    })

    vim.api.nvim_create_autocmd("User", {
        group = self.group,
        pattern = "ClodexCommandsUpdated",
        callback = function()
            self:refresh_state_preview()
        end,
    })

    vim.api.nvim_create_autocmd("FileType", {
        group = self.group,
        pattern = "clodex_terminal",
        --- Applies Clodex terminal chrome when the terminal buffer filetype is established.
        --- When lualine is present, prefer the native mirrored CLI line unless config opts out.
        callback = function(args)
            TerminalLualine.ensure_terminal_disabled(self.config:get().terminal.prefer_native_statusline)
            local win = vim.fn.bufwinid(args.buf)
            if type(win) == "number" and win > 0 then
                TerminalUi.refresh_chrome(win)
            end
            vim.schedule(function()
                self:refresh_views()
            end)
        end,
    })

    vim.api.nvim_create_autocmd("TermClose", {
        group = self.group,
        callback = function(args)
            local buf = args.buf
            if not buf or not vim.api.nvim_buf_is_valid(buf) then
                return
            end
            if vim.bo[buf].filetype ~= "clodex_terminal" then
                return
            end
            vim.schedule(function()
                self:refresh_views()
            end)
        end,
    })

    vim.api.nvim_create_autocmd({ "BufEnter", "ModeChanged", "TermLeave", "TermEnter", "WinScrolled" }, {
        group = self.group,
        callback = function()
            local win = vim.api.nvim_get_current_win()
            if not win or not vim.api.nvim_win_is_valid(win) then
                return
            end
            local buf = vim.api.nvim_win_get_buf(win)
            if not buf or not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].filetype ~= "clodex_terminal" then
                return
            end

            vim.schedule(function()
                if not vim.api.nvim_win_is_valid(win) then
                    return
                end
                if not vim.api.nvim_buf_is_valid(buf) or vim.api.nvim_win_get_buf(win) ~= buf then
                    return
                end
                TerminalUi.refresh_chrome(win)
            end)
        end,
    })

    vim.api.nvim_create_autocmd({ "BufWritePost", "BufLeave" }, {
        group = self.group,
        callback = function(args)
            self:sync_bookmarks_for_buffer(args.buf)
            self:refresh_bookmarks_for_buffer(args.buf)
            self:refresh_views()
        end,
    })

    vim.api.nvim_create_autocmd("SessionWritePost", {
        group = self.group,
        --- Persists live app state whenever Vim writes its session file.
        --- This ensures reopening that session restores queue and terminal associations.
        callback = function(args)
            self:save_session_state(args.file)
        end,
    })

    vim.api.nvim_create_autocmd("SessionLoadPost", {
        group = self.group,
        --- Restores app state after session load completes.
        --- The work is deferred to keep Neovim session restoration ordering safe.
        callback = function(args)
            vim.schedule(function()
                self:restore_session_state(args.file)
            end)
        end,
    })

    vim.api.nvim_create_autocmd("ColorScheme", {
        group = self.group,
        --- Reapplies highlights and redraws queue state when colorscheme changes.
        --- This keeps generated popup styling aligned with the active theme.
        callback = function()
            Config.apply_highlights(self.config:get())
            self:refresh_all_bookmarks()
            self:refresh_views()
        end,
    })
end

--- Reloads unmodified file buffers whose on-disk contents changed under registered projects.
--- This keeps Neovim synchronized after Codex edits files externally in project sessions.
---@param buf integer
function App:refresh_changed_project_buffer(buf)
    if not should_check_buffer(buf) then
        return
    end

    local path = fs.normalize(vim.api.nvim_buf_get_name(buf))
    if not self.registry:find_for_path(path) then
        return
    end

    pcall(vim.api.nvim_buf_call, buf, function()
        vim.cmd("silent! checktime")
    end)
    self:refresh_bookmarks_for_buffer(buf)
end

function App:refresh_changed_project_buffers()
    local projects = self.registry:list()
    if #projects == 0 then
        return
    end

    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if should_check_buffer(buf) then
            local path = fs.normalize(vim.api.nvim_buf_get_name(buf))
            if path_in_registered_project(path, projects) then
                self:refresh_changed_project_buffer(buf)
            end
        end
    end
end

---@param buf integer
function App:refresh_bookmarks_for_buffer(buf)
    if not buf or not vim.api.nvim_buf_is_valid(buf) then
        return
    end

    local path = vim.api.nvim_buf_get_name(buf)
    if path == "" or fs.is_virtual_path(path) then
        return
    end

    local project = self.registry:find_for_path(path)
    if not project then
        return
    end
    self.project_bookmarks:decorate_buffer(project, buf)
end

function App:refresh_all_bookmarks()
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        self:refresh_bookmarks_for_buffer(buf)
    end
end

---@param buf integer
function App:sync_bookmarks_for_buffer(buf)
    if not buf or not vim.api.nvim_buf_is_valid(buf) then
        return
    end
    self.project_bookmarks:sync_buffer(self.registry, buf)
end

--- Starts or restarts the periodic prompt-execution sync timer.
--- When syncing is enabled, the timer keeps queue state current as background jobs update workspace files.
function App:setup_execution_timer()
    local poll_ms = self.config:get().prompt_execution.poll_ms
    if poll_ms <= 0 then
        if self.execution_timer then
            self.execution_timer:stop()
        end
        return
    end

    if self.execution_timer then
        self.execution_timer:stop()
        self.execution_timer:start(
            poll_ms,
            poll_ms,
            vim.schedule_wrap(function()
                self.queue_actions:poll_workspace_updates()
            end)
        )
        return
    end

    self.execution_timer = vim.uv.new_timer()
    self.execution_timer:start(
        poll_ms,
        poll_ms,
        --- Poller callback executed on each timer tick.
        --- Delegates to workspace sync so externally completed queued items appear promptly.
        vim.schedule_wrap(function()
            self.queue_actions:poll_workspace_updates()
        end)
    )
end

---@param session_file string
function App:save_session_state(session_file)
    if not self.config:get().session.persist_current_project then
        return
    end
    self.session_persistence:save(self, session_file ~= "" and session_file or vim.v.this_session)
end

---@param session_file string
function App:restore_session_state(session_file)
    if not self.config:get().session.persist_current_project then
        return
    end
    self.session_persistence:restore(self, session_file ~= "" and session_file or vim.v.this_session)
end

---@param snapshots Clodex.TabState.Snapshot[]
function App:restore_session_windows(snapshots)
    snapshots = snapshots or {}

    local tabpages = vim.api.nvim_list_tabpages()
    table.sort(tabpages, function(left, right)
        return left < right
    end)

    for index, tabpage in ipairs(tabpages) do
        local snapshot = snapshots[index]
        if snapshot and snapshot.has_visible_window and snapshot.session_key then
            local state = self.tabs:get(tabpage)
            local session = self.terminals:session_by_key(snapshot.session_key)
            if session then
                self.terminals:show_in_tab(state, session)
            end
        end
    end
end

---@param project Clodex.Project
---@param state Clodex.TabState
--- Forwards project activation prompts into project action handlers.
--- This is used by picker and auto-detection code before creating or reusing a session.
function App:prompt_set_active_project(project, state)
    self.project_actions:prompt_set_active_project(project, state)
end

---@param buffer? number
function App:maybe_prompt_active_project(buffer)
    self.project_actions:maybe_prompt_active_project(buffer)
end

function App:prompt_new_tab_active_project()
    self.project_actions:prompt_new_tab_active_project(self:current_tab())
end

---@return Clodex.TabState
function App:current_tab()
    return self.tabs:get()
end

---@param state Clodex.TabState
---@return Clodex.TerminalTarget
--- Resolves active target by first honoring pinned tab root and then current path.
--- This is the core decision point for free-mode versus project-mode terminal routing.
function App:resolve_target(state)
    return self:resolve_target_from_path(state, fs.current_path(), true)
end

---@param state Clodex.TabState
---@param path string
---@param mutate boolean
---@return Clodex.TerminalTarget
function App:resolve_target_from_path(state, path, mutate)
    local active_root = state.active_project_root
    if active_root then
        local active_project = active_project_for_root(self.registry, active_root)
        if active_project then
            return {
                kind = "project",
                project = active_project,
            }
        end
        if mutate then
            state:clear_active_project()
        end
    end

    local project = self.registry:find_for_path(path)
    if project then
        if mutate and state.active_project_root ~= project.root then
            state:set_active_project(project.root)
        end
        return {
            kind = "project",
            project = project,
        }
    end

    return {
        kind = "free",
        cwd = fs.cwd_for_path(path),
    }
end

---@return Clodex.App.StateSnapshot
--- Captures a complete app state snapshot used by persistence and state previews.
--- The snapshot combines registry, tabs, sessions, and detection state for diagnostics.
function App:state_snapshot()
    local context_buf = snapshot_context_buf()
    local path = fs.current_path(context_buf)
    local state = self:current_tab()
    local current_tab = state:snapshot()
    local sessions = self.terminals:snapshot()
    local session_by_key = {} ---@type table<string, Clodex.TerminalSession.Snapshot>
    for _, session in ipairs(sessions) do
        session_by_key[session.key] = session
    end

    local projects = self.registry:list()
    local project_states = {} ---@type Clodex.App.ProjectState[]
    for _, project in ipairs(projects) do
        local session = session_by_key[project.root]
        project_states[#project_states + 1] = {
            project = project,
            session_active = session ~= nil and session.buffer_valid or false,
            window_open_in_active_tab = current_tab.has_visible_window and current_tab.session_key == project.root,
            usage_events = "not tracked yet",
            working = session and (session.running and "session alive" or "session stopped") or "offline",
            model = "not tracked yet",
            context = "not tracked yet",
            bookmark_count = self.project_bookmarks:count(project),
            notes_count = self.project_notes:count(project),
            cheatsheet_count = self.project_cheatsheet:count(project),
            cheatsheet_items = self.project_cheatsheet:items(project),
        }
    end

    return {
        current_path = path,
        active_project = active_project_for_root(self.registry, state.active_project_root),
        detected_project = self.registry:find_for_path(path),
        resolved_target = self:resolve_target_from_path(state, path, false),
        current_tab = current_tab,
        tabs = self.tabs:snapshot(),
        sessions = sessions,
        projects = projects,
        project_states = project_states,
    }
end

function App:refresh_state_preview()
    self.state_preview:refresh(self)
end

function App:refresh_queue_workspace()
    if self.queue_workspace and self.queue_workspace:is_open() then
        self.queue_workspace:refresh()
    end
end

function App:refresh_views()
    self:refresh_state_preview()
    self:refresh_queue_workspace()
end

App.toggle_state_preview = function(self)
    self.state_preview:toggle(self)
end

--- Checks a project session running condition for app.
--- This gate keeps callers safe before continuing higher-level state transitions.
---@param project Clodex.Project
---@return boolean
function App:is_project_session_running(project)
    return self.terminals:is_project_session_running(project.root)
end

---@return Clodex.Project[]
function App:projects_for_queue_workspace()
    local projects = self.registry:list()
    local active_root = self:current_tab().active_project_root
    local summaries = {} ---@type table<string, Clodex.ProjectQueueSummary>
    local project_updates = {} ---@type table<string, integer>
    for _, project in ipairs(projects) do
        summaries[project.root] = self:queue_summary(project)
        local details = self.project_details_store:get_cached(project)
        project_updates[project.root] = details and (
            details.last_file_modified_at
            or details.last_codex_activity_at
        ) or 0
    end

    table.sort(projects, function(left, right)
        local left_active = active_root ~= nil and left.root == active_root
        local right_active = active_root ~= nil and right.root == active_root
        if left_active ~= right_active then
            return left_active
        end
        local left_summary = summaries[left.root]
        local right_summary = summaries[right.root]
        local left_running = left_summary and left_summary.session_running or false
        local right_running = right_summary and right_summary.session_running or false
        if left_running ~= right_running then
            return left_running
        end
        local left_updated_at = project_updates[left.root] or 0
        local right_updated_at = project_updates[right.root] or 0
        if left_updated_at ~= right_updated_at then
            return left_updated_at > right_updated_at
        end
        return left.name:lower() < right.name:lower()
    end)
    return projects
end

---@param project Clodex.Project
---@return Clodex.ProjectQueueSummary
function App:queue_summary(project)
    return self.queue:summary(project, self:is_project_session_running(project))
end

function App:add_todo(opts)
    self.prompt_actions:pick_project(self.prompt_actions:resolve_project(opts), function(project)
        self.prompt_actions:prompt_for_todo(project)
    end)
end

function App:add_prompt(opts)
    self.prompt_actions:pick_target(opts or {}, function(project, category)
        self.prompt_actions:prompt_for_category_kind(project, category)
    end)
end

function App:add_prompt_for_project(opts)
    opts = vim.tbl_extend("force", { project_required = true }, opts or {})
    self.prompt_actions:pick_target(opts, function(project, category)
        self.prompt_actions:prompt_for_category_kind(project, category)
    end)
end

for name, spec in pairs(FORWARDED_METHODS) do
    App[name] = forward(spec.field, spec.method)
end

App.open_queue_workspace = function(self)
    if self.queue_workspace:is_open() then
        self.queue_workspace:close()
        return
    end
    self.queue_workspace:open()
end
App.open_history = function()
    History.open()
end

return App
