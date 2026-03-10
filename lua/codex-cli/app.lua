local Config = require("codex-cli.config")
local Commands = require("codex-cli.commands")
local ProjectActions = require("codex-cli.app.project_actions")
local PromptActions = require("codex-cli.app.prompt_actions")
local QueueActions = require("codex-cli.app.queue_actions")
local Detector = require("codex-cli.project.detector")
local ProjectDetails = require("codex-cli.project.details")
local Picker = require("codex-cli.project.picker")
local Registry = require("codex-cli.project.registry")
local TabManager = require("codex-cli.tab.manager")
local TerminalManager = require("codex-cli.terminal.manager")
local PromptPicker = require("codex-cli.ui.prompt_picker")
local StatePreview = require("codex-cli.ui.state_preview")
local QueueWorkspace = require("codex-cli.ui.queue_workspace")
local SessionPersistence = require("codex-cli.session.persistence")
local Execution = require("codex-cli.workspace.execution")
local Queue = require("codex-cli.workspace.queue")

--- Defines the CodexCli.App type for this module.
--- This annotation documents structured state so modules can pass data with consistent expectations.
---@class CodexCli.App
---@field config CodexCli.Config
---@field registry CodexCli.ProjectRegistry
---@field detector CodexCli.ProjectDetector
---@field project_details_store CodexCli.ProjectDetails
---@field picker CodexCli.ProjectPicker
---@field prompt_picker CodexCli.PromptPicker
---@field tabs CodexCli.TabManager
---@field terminals CodexCli.TerminalManager
---@field state_preview CodexCli.StatePreview
---@field queue CodexCli.Workspace.Queue
---@field execution CodexCli.Workspace.Execution
---@field queue_workspace CodexCli.QueueWorkspace
---@field project_actions CodexCli.AppProjectActions
---@field prompt_actions CodexCli.AppPromptActions
---@field queue_actions CodexCli.AppQueueActions
---@field session_persistence CodexCli.SessionPersistence
---@field group? integer
---@field execution_timer? uv.uv_timer_t

--- Defines the CodexCli.App.StateSnapshot type for this module.
--- This annotation documents structured state so modules can pass data with consistent expectations.
---@class CodexCli.App.StateSnapshot
---@field current_path string
---@field active_project? CodexCli.Project
---@field detected_project? CodexCli.Project
---@field resolved_target CodexCli.TerminalTarget
---@field current_tab CodexCli.TabState.Snapshot
---@field tabs CodexCli.TabState.Snapshot[]
---@field sessions CodexCli.TerminalSession.Snapshot[]
---@field projects CodexCli.Project[]
---@field project_states CodexCli.App.ProjectState[]

--- Defines the CodexCli.App.ProjectState type for this module.
--- This annotation documents structured state so modules can pass data with consistent expectations.
---@class CodexCli.App.ProjectState
---@field project CodexCli.Project
---@field session_active boolean
---@field window_open_in_active_tab boolean
---@field usage_events string
---@field working string
---@field model string
---@field context string
local App = {}
App.__index = App

local singleton ---@type CodexCli.App?

---@return CodexCli.App
--- Returns the singleton application object, creating it lazily on first access.
--- This guarantees shared state across modules and prevents duplicate terminal managers.
function App.instance()
  singleton = singleton or App.new()
  return singleton
end

---@return CodexCli.App
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

---@param opts? CodexCli.Config.Values|{}
--- Applies/refreshes configuration and rebuilds dependent managers when options change.
--- This is invoked on startup and every setup call from the public API layer.
function App:setup(opts)
  local values = self.config:setup(opts)
  Config.apply_highlights(values)
  self.registry = Registry.new({ path = values.storage.projects_file })
  self.detector = Detector.new(self.registry)
  self.project_details_store = self.project_details_store or ProjectDetails.new(values)
  self.picker = Picker.new(self.registry)
  self.prompt_picker = self.prompt_picker or PromptPicker.new(self)
  self.terminals = self.terminals or TerminalManager.new(values)
  self.state_preview = self.state_preview or StatePreview.new(values)
  self.queue = self.queue or Queue.new(values.storage.workspaces_dir)
  self.execution = self.execution or Execution.new(values)
  self.queue_workspace = self.queue_workspace or QueueWorkspace.new(self, values)
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

  self.group = vim.api.nvim_create_augroup("codex_cli", { clear = true })
  vim.api.nvim_create_autocmd("TabClosed", {
    group = self.group,
    --- Rebuilds tab state after closing any tab and refreshes preview windows.
    --- This keeps stale per-tab session information from leaking.
    callback = function()
      self.tabs:cleanup()
      self:refresh_state_preview()
    end,
  })

  vim.api.nvim_create_autocmd({ "BufEnter", "DirChanged", "TabEnter" }, {
    group = self.group,
    --- Refreshes preview state and prompts project detection for the current buffer.
    --- Helps users who navigate tabs or directories get immediate context updates.
    callback = function()
      self:refresh_state_preview()
      self:maybe_prompt_active_project(vim.api.nvim_get_current_buf())
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
      self.queue_workspace:refresh()
      self:refresh_state_preview()
    end,
  })
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
        self:poll_prompt_execution_receipts()
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
      self:poll_prompt_execution_receipts()
    end)
  )
end

--- Implements the save_session_state path for app.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param session_file string
function App:save_session_state(session_file)
  self.session_persistence:save(self, session_file ~= "" and session_file or vim.v.this_session)
end

--- Implements the restore_session_state path for app.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param session_file string
function App:restore_session_state(session_file)
  self.session_persistence:restore(self, session_file ~= "" and session_file or vim.v.this_session)
end

--- Implements the restore_session_windows path for app.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param snapshots CodexCli.TabState.Snapshot[]
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

---@param project CodexCli.Project
---@param state CodexCli.TabState
--- Forwards project activation prompts into project action handlers.
--- This is used by picker and auto-detection code before creating or reusing a session.
function App:prompt_set_active_project(project, state)
  self.project_actions:prompt_set_active_project(project, state)
end

--- Implements the maybe_prompt_active_project path for app.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param buffer? number
function App:maybe_prompt_active_project(buffer)
  self.project_actions:maybe_prompt_active_project(buffer)
end

--- Implements the current_tab path for app.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@return CodexCli.TabState
function App:current_tab()
  return self.tabs:get()
end

---@param state CodexCli.TabState
---@return CodexCli.TerminalTarget
--- Resolves active target by first honoring pinned tab root and then current path.
--- This is the core decision point for free-mode versus project-mode terminal routing.
function App:resolve_target(state)
  return self:resolve_target_from_path(state, self.detector:current_path(), true)
end

--- Implements the resolve_target_from_path path for app.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param state CodexCli.TabState
---@param path string
---@param mutate boolean
---@return CodexCli.TerminalTarget
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

  local project = self.detector:project_for_path(path)
  if project then
    return {
      kind = "project",
      project = project,
    }
  end

  return {
    kind = "free",
    cwd = self.detector:cwd_for_path(path),
  }
end

---@return CodexCli.App.StateSnapshot
--- Captures a complete app state snapshot used by persistence and state previews.
--- The snapshot combines registry, tabs, sessions, and detection state for diagnostics.
function App:state_snapshot()
  local path = self.detector:current_path()
  local state = self:current_tab()
  local current_tab = state:snapshot()
  local sessions = self.terminals:snapshot()
  local session_by_key = {} ---@type table<string, CodexCli.TerminalSession.Snapshot>
  for _, session in ipairs(sessions) do
    session_by_key[session.key] = session
  end

  local projects = self.registry:list()
  local project_states = {} ---@type CodexCli.App.ProjectState[]
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
    }
  end

  return {
    current_path = path,
    active_project = state.active_project_root and self.registry:get(state.active_project_root) or nil,
    detected_project = self.detector:project_for_path(path),
    resolved_target = self:resolve_target_from_path(state, path, false),
    current_tab = current_tab,
    tabs = self.tabs:snapshot(),
    sessions = sessions,
    projects = projects,
    project_states = project_states,
  }
end

--- Refreshes all top-level preview surfaces from the latest app state snapshot.
--- This keeps command, project, and queue UI views aligned after every state change.
function App:refresh_state_preview()
  self.state_preview:refresh(self)
  if self.queue_workspace then
    self.queue_workspace:refresh()
  end
end

--- Toggles the state preview floating layout on and off.
--- It is a thin wrapper around the state-preview component for UI-level command wiring.
function App:toggle_state_preview()
  self.state_preview:toggle(self)
end

--- Checks a project session running condition for app.
--- This gate keeps callers safe before continuing higher-level state transitions.
---@param project CodexCli.Project
---@return boolean
function App:is_project_session_running(project)
  return self.terminals:is_project_session_running(project.root)
end

--- Implements the projects_for_queue_workspace path for app.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@return CodexCli.Project[]
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

--- Implements the queue_summary path for app.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param project CodexCli.Project
---@return CodexCli.ProjectQueueSummary
function App:queue_summary(project)
  return self.queue:summary(project, self:is_project_session_running(project))
end

--- Implements the project_details path for app.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param project CodexCli.Project
---@return CodexCli.ProjectDetails.Snapshot
function App:project_details(project)
  return self.project_details_store:get(project)
end

--- Implements the touch_project_activity path for app.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param project CodexCli.Project
function App:touch_project_activity(project)
  self.project_details_store:touch_codex_activity(project)
end

--- Implements the activate_project_session path for app.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param project CodexCli.Project
---@return CodexCli.TerminalSession?
function App:activate_project_session(project)
  return self.project_actions:activate_project_session(project)
end

--- Implements the deactivate_project_session path for app.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param project CodexCli.Project
function App:deactivate_project_session(project)
  self.project_actions:deactivate_project_session(project)
end

--- Implements the open_project_workspace_target path for app.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param project CodexCli.Project
function App:open_project_workspace_target(project)
  self.project_actions:open_project_workspace_target(project)
end

--- Opens the current project's todo file in the active window.
--- This delegates project resolution and file creation to project actions.
---@param project? CodexCli.Project
function App:open_project_todo_file(project)
  self.project_actions:open_project_todo_file(project)
end

--- Implements the resolve_todo_project path for app.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param opts? { project?: CodexCli.Project, project_value?: string }
---@return CodexCli.Project?
function App:resolve_todo_project(opts)
  return self.prompt_actions:resolve_project(opts)
end

--- Implements the pick_or_run_todo_project path for app.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param target_project CodexCli.Project?
---@param callback fun(project: CodexCli.Project)
function App:pick_or_run_todo_project(target_project, callback)
  self.prompt_actions:pick_project(target_project, callback)
end

--- Implements the prompt_asset_dir path for app.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param category CodexCli.PromptCategory
---@return string
function App:prompt_asset_dir(category)
  return self.prompt_actions:asset_dir(category)
end

--- Implements the prompt_asset_path path for app.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param category CodexCli.PromptCategory
---@param ext string
---@return string
function App:prompt_asset_path(category, ext)
  return self.prompt_actions:asset_path(category, ext)
end

--- Implements the prompt_category path for app.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param category CodexCli.PromptCategory
---@return CodexCli.PromptCategoryDef
function App:prompt_category(category)
  return self.prompt_actions:category(category)
end

--- Implements the pick_prompt_target path for app.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param opts? { project?: CodexCli.Project, project_value?: string, project_required?: boolean, category?: CodexCli.PromptCategory }
---@param callback fun(project: CodexCli.Project, category: CodexCli.PromptCategory)
function App:pick_prompt_target(opts, callback)
  self.prompt_actions:pick_target(opts, callback)
end

--- Implements the prompt_for_todo path for app.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param target_project CodexCli.Project
function App:prompt_for_todo(target_project)
  self.prompt_actions:prompt_for_todo(target_project)
end

--- Implements the prompt_for_category path for app.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param project CodexCli.Project
---@param category CodexCli.PromptCategory
function App:prompt_for_category(project, category)
  self.prompt_actions:prompt_for_category(project, category)
end

--- Implements the prompt_for_visual path for app.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param project CodexCli.Project
function App:prompt_for_visual(project)
  self.prompt_actions:prompt_for_visual(project)
end

--- Implements the prompt_for_library path for app.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param project CodexCli.Project
function App:prompt_for_library(project)
  self.prompt_actions:prompt_for_library(project)
end

--- Implements the prompt_for_prompt_category path for app.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param project CodexCli.Project
---@param category CodexCli.PromptCategory
function App:prompt_for_prompt_category(project, category)
  self.prompt_actions:prompt_for_category_kind(project, category)
end

--- Implements the normalize_prompt_spec path for app.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param project CodexCli.Project
---@param spec { title: string, details?: string }
---@return { title: string, details?: string, broken: boolean }
function App:normalize_prompt_spec(project, spec)
  return self.prompt_actions:normalize_spec(project, spec)
end

--- Implements the dispatch_queue_item path for app.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param project CodexCli.Project
---@param item CodexCli.QueueItem
---@return boolean
function App:dispatch_queue_item(project, item)
  return self.queue_actions:dispatch_item(project, item)
end

--- Delegates completion-receipt polling into queue actions.
--- This bridge is shared by the timer callback and any manual poll calls.
function App:poll_prompt_execution_receipts()
  self.queue_actions:poll_prompt_execution_receipts()
end

--- Adds a new app entry and keeps related state aligned.
--- This function feeds the same workflow used by interactive and scripted callers.
---@param project CodexCli.Project
---@param spec { title: string, details?: string, kind?: CodexCli.PromptCategory, image_path?: string }
function App:add_project_todo(project, spec)
  self.queue_actions:add_project_todo(project, spec)
end

--- Implements the edit_queue_item path for app.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param project CodexCli.Project
---@param item_id string
---@param spec { title: string, details?: string }
function App:edit_queue_item(project, item_id, spec)
  self.queue_actions:edit_queue_item(project, item_id, spec)
end

--- Implements the implement_queue_item path for app.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param project CodexCli.Project
---@param item_id string
function App:implement_queue_item(project, item_id)
  self.queue_actions:implement_queue_item(project, item_id)
end

--- Implements the implement_queued_items path for app.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param project CodexCli.Project
function App:implement_queued_items(project)
  self.queue_actions:implement_queued_items(project)
end

--- Implements the implement_next_queued_item path for app.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param opts? { project?: CodexCli.Project, project_value?: string }
function App:implement_next_queued_item(opts)
  self.queue_actions:implement_next_queued_item(opts)
end

--- Implements the implement_all_queued_items path for app.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param opts? { project?: CodexCli.Project, project_value?: string }
function App:implement_all_queued_items(opts)
  self.queue_actions:implement_all_queued_items(opts)
end

--- Implements the advance_queue_item path for app.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param project CodexCli.Project
---@param item_id string
function App:advance_queue_item(project, item_id)
  self.queue_actions:advance_queue_item(project, item_id)
end

--- Implements the rewind_queue_item path for app.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param project CodexCli.Project
---@param item_id string
---@param opts? { copy?: boolean }
function App:rewind_queue_item(project, item_id, opts)
  self.queue_actions:rewind_queue_item(project, item_id, opts)
end

--- Implements the move_queue_item_to_project path for app.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param project CodexCli.Project
---@param item_id string
---@param target_project CodexCli.Project
---@param opts? { target_queue?: CodexCli.QueueName, copy?: boolean }
function App:move_queue_item_to_project(project, item_id, target_project, opts)
  self.queue_actions:move_queue_item_to_project(project, item_id, target_project, opts)
end

--- Implements the delete_queue_item path for app.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param project CodexCli.Project
---@param item_id string
function App:delete_queue_item(project, item_id)
  self.queue_actions:delete_queue_item(project, item_id)
end

--- Adds a new app entry and keeps related state aligned.
--- This function feeds the same workflow used by interactive and scripted callers.
---@param opts? { project?: CodexCli.Project, project_value?: string }
function App:add_todo(opts)
  self:pick_or_run_todo_project(self:resolve_todo_project(opts), function(project)
    self:prompt_for_todo(project)
  end)
end

--- Adds a new app entry and keeps related state aligned.
--- This function feeds the same workflow used by interactive and scripted callers.
---@param opts? { project?: CodexCli.Project, project_value?: string, category?: CodexCli.PromptCategory }
function App:add_prompt(opts)
  self:pick_prompt_target(opts or {}, function(project, category)
    self:prompt_for_prompt_category(project, category)
  end)
end

--- Adds a new app entry and keeps related state aligned.
--- This function feeds the same workflow used by interactive and scripted callers.
---@param opts? { project?: CodexCli.Project, project_value?: string, category?: CodexCli.PromptCategory }
function App:add_prompt_for_project(opts)
  opts = vim.tbl_extend("force", { project_required = true }, opts or {})
  self:pick_prompt_target(opts, function(project, category)
    self:prompt_for_prompt_category(project, category)
  end)
end

--- Adds a new app entry and keeps related state aligned.
--- This function feeds the same workflow used by interactive and scripted callers.
---@param opts? { project?: CodexCli.Project, project_value?: string }
function App:add_error_todo(opts)
  self.prompt_actions:add_error_todo(opts)
end

--- Opens the floating queue workspace for project and queue management.
--- This is usually invoked from user commands and quick navigation flows.
function App:open_queue_workspace()
  self.queue_workspace:open()
end

--- Implements the activate_project path for app.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param root string
function App:activate_project(root)
  self.project_actions:activate_project(root)
end

--- Sets the current tab's active project and refreshes dependent terminal state.
---@param project CodexCli.Project
function App:set_current_project(project)
  self.project_actions:set_current_project(project)
end

--- Clears current tab project selection and updates session/preview state.
--- This is used by command users and when project context needs a reset.
function App:clear_active_project()
  self.project_actions:clear_active_project()
end

--- Toggles the active terminal target for the current tab.
--- It chooses the right target by current detection rules and switches focus cleanly.
function App:toggle()
  self.project_actions:toggle()
end

--- Implements the rename_project path for app.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param value? string|CodexCli.Project
function App:rename_project(value)
  self.project_actions:rename_project(value)
end

--- Adds a new app entry and keeps related state aligned.
--- This function feeds the same workflow used by interactive and scripted callers.
---@param opts? { name?: string, root?: string }
function App:add_project(opts)
  self.project_actions:add_project(opts)
end

--- Removes a app item and normalizes dependent state.
--- This cleanup keeps persistence and session state consistent with user actions.
---@param value? string|CodexCli.Project
function App:remove_project(value)
  self.project_actions:remove_project(value)
end

--- Implements the maybe_offer_project path for app.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param cwd string
function App:maybe_offer_project(cwd)
  self.project_actions:maybe_offer_project(cwd)
end

--- Implements the toggle_terminal_header path for app.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param buf? number
function App:toggle_terminal_header(buf)
  self.project_actions:toggle_terminal_header(buf)
end

return App
