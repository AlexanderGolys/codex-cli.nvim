local Config = require("clodex.config")
local Commands = require("clodex.commands")
local ProjectActions = require("clodex.app.project_actions")
local PromptActions = require("clodex.app.prompt_actions")
local QueueActions = require("clodex.app.queue_actions")
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
local fs = require("clodex.util.fs")

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
---@field queue_workspace Clodex.QueueWorkspace
---@field project_actions Clodex.AppProjectActions
---@field prompt_actions Clodex.AppPromptActions
---@field queue_actions Clodex.AppQueueActions
---@field session_persistence Clodex.SessionPersistence
---@field group? integer
---@field execution_timer? uv.uv_timer_t

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

local singleton ---@type Clodex.App?

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
    self:setup({})
    return self
end

---@param opts? Clodex.Config.Values|{}
--- Applies/refreshes configuration and rebuilds dependent managers when options change.
--- This is invoked on startup and every setup call from the public API layer.
function App:setup(opts)
    local values = self.config:setup(opts)
    Config.apply_highlights(values)
    self.registry = Registry.new({ path = values.storage.projects_file })
    self.project_details_store = self.project_details_store or ProjectDetails.new(values)
    self.project_bookmarks = self.project_bookmarks or ProjectBookmarks.new()
    self.project_notes = self.project_notes or ProjectNotes.new()
    self.project_cheatsheet = self.project_cheatsheet or ProjectCheatsheet.new()
    self.terminals = self.terminals or TerminalManager.new(values)
    self.state_preview = self.state_preview or StatePreview.new(values)
    self.queue = self.queue or Queue.new(values.storage.workspaces_dir)
    self.execution = self.execution or Execution.new(values)
    self.queue_workspace = self.queue_workspace or QueueWorkspace.new(self, values)
    self.session_persistence:update_storage_dir(values.storage.session_state_dir)
    self.terminals:update_config(values)
    self.state_preview:update_config(values)
    self.project_details_store:update_config(values)
    self.execution:update_config(values)
    self.execution:ensure_prompt_skill()
    self.queue_workspace:update_config(values)
    Commands.register()
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
            self:refresh_state_preview()
        end,
    })

    vim.api.nvim_create_autocmd("TabNewEntered", {
        group = self.group,
        --- Marks freshly opened tabs as already handled for project prompts.
        --- New tabs are commonly used to switch context, so avoid auto-offering the file's project there.
        callback = function()
            self:current_tab():mark_prompted_project()
            self:refresh_state_preview()
        end,
    })

    vim.api.nvim_create_autocmd({ "BufEnter", "DirChanged", "FocusGained", "TabEnter" }, {
        group = self.group,
        --- Refreshes preview state and prompts project detection for the current buffer.
        --- Helps users who navigate tabs or directories get immediate context updates.
        callback = function()
            self:refresh_changed_project_buffers()
            self:refresh_bookmarks_for_buffer(vim.api.nvim_get_current_buf())
            self:refresh_state_preview()
            self:maybe_prompt_active_project(vim.api.nvim_get_current_buf())
        end,
    })

    vim.api.nvim_create_autocmd({ "BufWritePost", "BufLeave" }, {
        group = self.group,
        callback = function(args)
            self:sync_bookmarks_for_buffer(args.buf)
            self:refresh_bookmarks_for_buffer(args.buf)
            self:refresh_state_preview()
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
            self.queue_workspace:refresh()
            self:refresh_state_preview()
        end,
    })
end

--- Reloads unmodified file buffers whose on-disk contents changed under registered projects.
--- This keeps Neovim synchronized after Codex edits files externally in project sessions.
function App:refresh_changed_project_buffers()
    local projects = self.registry:list()
    if #projects == 0 then
        return
    end

    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if should_check_buffer(buf) then
            local path = fs.normalize(vim.api.nvim_buf_get_name(buf))
            if path_in_registered_project(path, projects) then
                pcall(vim.api.nvim_buf_call, buf, function()
                    vim.cmd("silent! checktime")
                end)
                self:refresh_bookmarks_for_buffer(buf)
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

--- Starts or restarts the periodic prompt-execution polling timer.
--- When polling is enabled, the timer keeps queue state current as background jobs complete.
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
                self.queue_actions:poll_prompt_execution_receipts()
            end)
        )
        return
    end

    self.execution_timer = vim.uv.new_timer()
    self.execution_timer:start(
        poll_ms,
        poll_ms,
        --- Poller callback executed on each timer tick.
        --- Delegates to receipt processing so completed jobs can advance queue state promptly.
        vim.schedule_wrap(function()
            self.queue_actions:poll_prompt_execution_receipts()
        end)
    )
end

---@param session_file string
function App:save_session_state(session_file)
    self.session_persistence:save(self, session_file ~= "" and session_file or vim.v.this_session)
end

---@param session_file string
function App:restore_session_state(session_file)
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
        local active_project = self.registry:get(active_root)
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
    local path = fs.current_path()
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
        active_project = state.active_project_root and self.registry:get(state.active_project_root) or nil,
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
    if self.queue_workspace then
        self.queue_workspace:refresh()
    end
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
    table.sort(projects, function(left, right)
        local left_running = self:is_project_session_running(left)
        local right_running = self:is_project_session_running(right)
        if left_running ~= right_running then
            return left_running
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

App.open_project_todo_file = forward("project_actions", "open_project_todo_file")
App.open_project_dictionary_file = forward("project_actions", "open_project_dictionary_file")
App.open_project_cheatsheet_file = forward("project_actions", "open_project_cheatsheet_file")
App.toggle_project_cheatsheet_preview = forward("project_actions", "toggle_project_cheatsheet_preview")
App.add_project_cheatsheet_item = forward("project_actions", "add_project_cheatsheet_item")
App.open_project_notes_picker = forward("project_actions", "open_project_notes_picker")
App.create_project_note = forward("project_actions", "create_project_note")
App.add_project_bookmark = forward("project_actions", "add_project_bookmark")
App.open_project_bookmarks_picker = forward("project_actions", "open_project_bookmarks_picker")
App.implement_next_queued_item = forward("queue_actions", "implement_next_queued_item")
App.implement_all_queued_items = forward("queue_actions", "implement_all_queued_items")
App.add_error_todo = forward("prompt_actions", "add_error_todo")
App.open_queue_workspace = function(self)
    if self.queue_workspace:is_open() then
        self.queue_workspace:close()
        return
    end
    self.queue_workspace:open()
end
App.activate_project = forward("project_actions", "activate_project")
App.set_current_project = forward("project_actions", "set_current_project")
App.clear_active_project = forward("project_actions", "clear_active_project")
App.toggle = forward("project_actions", "toggle")
App.rename_project = forward("project_actions", "rename_project")
App.add_project = forward("project_actions", "add_project")
App.remove_project = forward("project_actions", "remove_project")
App.maybe_offer_project = forward("project_actions", "maybe_offer_project")
App.toggle_terminal_header = forward("project_actions", "toggle_terminal_header")

return App
