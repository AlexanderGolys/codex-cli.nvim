local Config = require("codex-cli.config")
local Commands = require("codex-cli.commands")
local Detector = require("codex-cli.project.detector")
local Picker = require("codex-cli.project.picker")
local Registry = require("codex-cli.project.registry")
local TabManager = require("codex-cli.tab.manager")
local TerminalManager = require("codex-cli.terminal.manager")
local ui = require("codex-cli.ui.select")
local StatePreview = require("codex-cli.ui.state_preview")
local QueueWorkspace = require("codex-cli.ui.queue_workspace")
local fs = require("codex-cli.util.fs")
local notify = require("codex-cli.util.notify")
local Queue = require("codex-cli.workspace.queue")

---@class CodexCli.App
---@field config CodexCli.Config
---@field registry CodexCli.ProjectRegistry
---@field detector CodexCli.ProjectDetector
---@field picker CodexCli.ProjectPicker
---@field tabs CodexCli.TabManager
---@field terminals CodexCli.TerminalManager
---@field state_preview CodexCli.StatePreview
---@field queue CodexCli.Workspace.Queue
---@field queue_workspace CodexCli.QueueWorkspace
---@field group? integer

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
local PREVIOUS_QUEUE = {
  queued = "planned",
  history = "queued",
}

---@return CodexCli.App
function App.instance()
  singleton = singleton or App.new()
  return singleton
end

---@return CodexCli.App
function App.new()
  local self = setmetatable({}, App)
  self.config = Config.new()
  self.tabs = TabManager.new()
  self:setup({})
  return self
end

---@param opts? CodexCli.Config.Values|{}
function App:setup(opts)
  local values = self.config:setup(opts)
  self.registry = Registry.new({ path = values.storage.projects_file })
  self.detector = Detector.new(self.registry)
  self.picker = Picker.new(self.registry)
  self.terminals = self.terminals or TerminalManager.new(values)
  self.state_preview = self.state_preview or StatePreview.new(values)
  self.queue = self.queue or Queue.new(values.storage.workspaces_dir)
  self.queue_workspace = self.queue_workspace or QueueWorkspace.new(self, values)
  self.terminals:update_config(values)
  self.state_preview:update_config(values)
  self.queue_workspace:update_config(values)
  Commands.register()
  self:setup_autocmds()
  self:refresh_state_preview()
end

function App:setup_autocmds()
  if self.group then
    return
  end

  self.group = vim.api.nvim_create_augroup("codex_cli", { clear = true })
  vim.api.nvim_create_autocmd("TabClosed", {
    group = self.group,
    callback = function()
      self.tabs:cleanup()
      self:refresh_state_preview()
    end,
  })

  vim.api.nvim_create_autocmd({ "BufEnter", "DirChanged", "TabEnter" }, {
    group = self.group,
    callback = function()
      self:refresh_state_preview()
      self:maybe_prompt_active_project(vim.api.nvim_get_current_buf())
    end,
  })
end

---@param project CodexCli.Project
---@param state CodexCli.TabState
function App:prompt_set_active_project(project, state)
  if state.active_project_root then
    return
  end
  if state:has_prompted_project() then
    return
  end

  state:mark_prompted_project()
  ui.confirm(("Set %s as the active project for this tab?"):format(project.name), function(confirmed)
    if not confirmed then
      return
    end

    state:set_active_project(project.root)
    if state:has_visible_window() then
      local session, replaced_key = self.terminals:get_session({
        kind = "project",
        project = project,
      })
      if replaced_key then
        self.terminals:detach_session(replaced_key, self.tabs:list())
      end
      if session then
        self.terminals:show_in_tab(state, session)
      end
    end
    self:refresh_state_preview()
  end)
end

---@param buffer? number
function App:maybe_prompt_active_project(buffer)
  local state = self:current_tab()
  if state.active_project_root then
    return
  end
  if state:has_prompted_project() then
    return
  end

  buffer = buffer or vim.api.nvim_get_current_buf()
  if not buffer or not vim.api.nvim_buf_is_valid(buffer) then
    return
  end
  if vim.bo[buffer].buftype ~= "" then
    return
  end
  if vim.api.nvim_buf_get_name(buffer) == "" then
    return
  end

  local project = self.detector:project_for_path(self.detector:current_path(buffer))
  if not project then
    return
  end

  self:prompt_set_active_project(project, state)
end

---@return CodexCli.TabState
function App:current_tab()
  return self.tabs:get()
end

---@param state CodexCli.TabState
---@return CodexCli.TerminalTarget
function App:resolve_target(state)
  return self:resolve_target_from_path(state, self.detector:current_path(), true)
end

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

function App:refresh_state_preview()
  self.state_preview:refresh(self)
  if self.queue_workspace then
    self.queue_workspace:refresh()
  end
end

function App:toggle_state_preview()
  self.state_preview:toggle(self)
end

---@param project CodexCli.Project
---@return boolean
function App:is_project_session_running(project)
  return self.terminals:is_project_session_running(project.root)
end

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

---@param project CodexCli.Project
---@return CodexCli.ProjectQueueSummary
function App:queue_summary(project)
  return self.queue:summary(project, self:is_project_session_running(project))
end

---@param project CodexCli.Project
---@return CodexCli.TerminalSession?
function App:activate_project_session(project)
  local session = self.terminals:ensure_project_session(project)
  if not session then
    return
  end
  self:activate_project(project.root)
  notify.notify(("Activated Codex session for %s"):format(project.name))
  return session
end

---@param project CodexCli.Project
function App:open_project_workspace_target(project)
  self:activate_project(project.root)

  local readme = fs.find_readme(project.root)
  if readme then
    vim.cmd.edit(vim.fn.fnameescape(readme))
  end

  local state = self:current_tab()
  local session = self.terminals:ensure_project_session(project)
  if not session then
    self:refresh_state_preview()
    return
  end

  self.terminals:show_in_tab(state, session)
  self:refresh_state_preview()
end

---@param opts? { project?: CodexCli.Project, project_value?: string }
---@return CodexCli.Project?
function App:resolve_todo_project(opts)
  opts = opts or {}
  local project = opts.project
  if not project and opts.project_value then
    project = self.registry:find_by_name_or_root(opts.project_value)
  end
  if project then
    return project
  end

  local state = self:current_tab()
  local target = self:resolve_target(state)
  if target.kind == "project" then
    return target.project
  end
end

---@param target_project CodexCli.Project?
---@param callback fun(project: CodexCli.Project)
function App:pick_or_run_todo_project(target_project, callback)
  if target_project then
    callback(target_project)
    return
  end
  self.picker:pick({ prompt = "Select project for todo" }, function(project)
    if project then
      callback(project)
    end
  end)
end

---@param target_project CodexCli.Project
function App:prompt_for_todo(target_project)
  ui.input({
    prompt = ("Todo title for %s"):format(target_project.name),
  }, function(title)
    title = title and vim.trim(title) or ""
    if title == "" then
      return
    end

    ui.input({
      prompt = "Todo details (optional)",
    }, function(details)
      self:add_project_todo(target_project, {
        title = title,
        details = details,
      })
    end)
  end)
end

---@param project CodexCli.Project
---@param item CodexCli.QueueItem
---@return boolean
function App:dispatch_queue_item(project, item)
  local session = self.terminals:ensure_project_session(project)
  if not session then
    notify.warn(("Could not start a Codex session for %s"):format(project.name))
    return false
  end
  if not session:send(item.prompt) then
    return false
  end
  return true
end

---@param project CodexCli.Project
---@param spec { title: string, details?: string }
function App:add_project_todo(project, spec)
  local title = vim.trim(spec.title or "")
  if title == "" then
    notify.warn("Todo title is required")
    return
  end

  self.queue:add_todo(project, {
    title = title,
    details = spec.details,
  })
  notify.notify(("Added todo to %s: %s"):format(project.name, title))
  self:refresh_state_preview()
end

---@param project CodexCli.Project
---@param item_id string
function App:advance_queue_item(project, item_id)
  local item = nil ---@type CodexCli.QueueItem?
  local next_queue = self.queue:advance(project, item_id)
  if not next_queue then
    notify.warn("Item cannot be moved further")
    return
  end
  if next_queue == "queued" then
    _, _, item = self.queue:find_item(project, item_id)
    if item then
      self:dispatch_queue_item(project, item)
    end
  end
  self:refresh_state_preview()
end

---@param project CodexCli.Project
---@param item_id string
---@param opts? { copy?: boolean }
function App:rewind_queue_item(project, item_id, opts)
  opts = opts or {}
  local queue_name, _, item = self.queue:find_item(project, item_id)
  local previous_queue = queue_name and PREVIOUS_QUEUE[queue_name] or nil
  if not previous_queue or not item then
    notify.warn("Item cannot be moved back")
    return
  end

  if opts.copy then
    local copied = self.queue:put_item(project, previous_queue, item, {
      copy = true,
      clear_history = queue_name == "history",
    })
    if copied and previous_queue == "queued" then
      self:dispatch_queue_item(project, copied)
    end
  else
    local taken = self.queue:take_item(project, item_id)
    if not taken then
      notify.warn("Queue item not found")
      return
    end
    local moved = self.queue:put_item(project, previous_queue, item, {
      clear_history = queue_name == "history",
    })
    if moved and previous_queue == "queued" then
      self:dispatch_queue_item(project, moved)
    end
  end

  self:refresh_state_preview()
end

---@param project CodexCli.Project
---@param item_id string
---@param target_project CodexCli.Project
---@param opts? { target_queue?: CodexCli.QueueName, copy?: boolean }
function App:move_queue_item_to_project(project, item_id, target_project, opts)
  opts = opts or {}
  local queue_name, _, item = self.queue:find_item(project, item_id)
  local target_queue = opts.target_queue or queue_name
  if not queue_name or not target_queue or not item then
    notify.warn("Queue item not found")
    return
  end

  if not opts.copy then
    local taken = self.queue:take_item(project, item_id)
    if not taken then
      notify.warn("Queue item not found")
      return
    end
  end

  local moved = self.queue:put_item(target_project, target_queue, item, {
    copy = true,
    clear_history = queue_name == "history" and target_queue ~= "history",
  })
  if not moved then
    notify.warn("Failed to move queue item")
    return
  end

  if target_queue == "queued" then
    self:dispatch_queue_item(target_project, moved)
  end
  notify.notify(("Moved '%s' to %s"):format(item.title, target_project.name))
  self:refresh_state_preview()
end

---@param project CodexCli.Project
---@param item_id string
function App:delete_queue_item(project, item_id)
  if not self.queue:delete_item(project, item_id) then
    notify.warn("Queue item not found")
    return
  end
  self:refresh_state_preview()
end

---@param opts? { project?: CodexCli.Project, project_value?: string }
function App:add_todo(opts)
  self:pick_or_run_todo_project(self:resolve_todo_project(opts), function(project)
    self:prompt_for_todo(project)
  end)
end

---@param opts? { project?: CodexCli.Project, project_value?: string }
function App:add_error_todo(opts)
  local screenshot_dir = self.config:get().error_prompt.screenshot_dir
  local latest_screenshot = screenshot_dir and fs.latest_file(screenshot_dir) or nil

  self:pick_or_run_todo_project(self:resolve_todo_project(opts), function(project)
    local sources = {} ---@type { label: string, value: string }[]
    if latest_screenshot then
      sources[#sources + 1] = {
        label = ("Use latest screenshot (%s)"):format(fs.basename(latest_screenshot)),
        value = "screenshot",
      }
    end
    sources[#sources + 1] = {
      label = "Paste error message",
      value = "message",
    }

    ui.select(sources, {
      prompt = ("Error prompt source for %s"):format(project.name),
      format_item = function(item)
        return item.label
      end,
    }, function(choice)
      if not choice then
        return
      end

      ui.input({
        prompt = "Short error summary (optional)",
      }, function(summary)
        summary = summary and vim.trim(summary) or ""
        local title = summary ~= "" and ("Investigate runtime error: " .. summary) or "Investigate runtime error"

        local function add_from_details(source_details)
          self:add_project_todo(project, {
            title = title,
            details = table.concat({
              "Investigate the runtime failure reported by the user.",
              source_details,
              "Explain the cause, implement a fix, and mention any follow-up validation that should be run.",
            }, "\n\n"),
          })
        end

        if choice.value == "screenshot" and latest_screenshot then
          add_from_details(
            ("Use screenshot file `%s` from the configured screenshot directory `%s` as the main artifact."):format(
              fs.basename(latest_screenshot),
              screenshot_dir
            )
          )
          return
        end

        ui.input({
          prompt = "Paste the error message",
        }, function(message)
          message = message and vim.trim(message) or ""
          if message == "" then
            return
          end
          add_from_details(("Error message:\n```\n%s\n```"):format(message))
        end)
      end)
    end)
  end)
end

function App:open_queue_workspace()
  self.queue_workspace:open()
end

---@param root string
function App:activate_project(root)
  self:current_tab():set_active_project(root)
  self:refresh_state_preview()
end

function App:clear_active_project()
  local state = self:current_tab()
  state:clear_active_project()
  if state:has_visible_window() then
    local target = self:resolve_target(state)
    local session, replaced_key = self.terminals:get_session(target)
    if replaced_key then
      self.terminals:detach_session(replaced_key, self.tabs:list())
    end
    if not session then
      self:refresh_state_preview()
      return
    end
    self.terminals:show_in_tab(state, session)
  end
  self:refresh_state_preview()
end

function App:toggle()
  local state = self:current_tab()
  local target = self:resolve_target(state)
  if target.kind == "project" then
    self:prompt_set_active_project(target.project, state)
  end
  local session, replaced_key = self.terminals:get_session(target)
  if replaced_key then
    self.terminals:detach_session(replaced_key, self.tabs:list())
  end
  if not session then
    self:refresh_state_preview()
    return
  end

  if state:is_showing(session.key) then
    self.terminals:hide_in_tab(state)
    self:refresh_state_preview()
    return
  end

  self.terminals:show_in_tab(state, session)
  self:refresh_state_preview()
  if target.kind == "free" then
    self:maybe_offer_project(target.cwd)
  end
end

function App:select_project()
  local state = self:current_tab()
  self.picker:pick({
    active_root = state.active_project_root,
    on_delete = function(project)
      self:remove_project(project)
    end,
    on_rename = function(project)
      self:rename_project(project)
    end,
  }, function(project)
    state:set_active_project(project and project.root or nil)

    if not state:has_visible_window() then
      self:refresh_state_preview()
      return
    end

    local target = self:resolve_target(state)
    local session, replaced_key = self.terminals:get_session(target)
    if replaced_key then
      self.terminals:detach_session(replaced_key, self.tabs:list())
    end
    if not session then
      self:refresh_state_preview()
      return
    end
    self.terminals:show_in_tab(state, session)
    self:refresh_state_preview()
  end)
end

---@param value? string|CodexCli.Project
function App:rename_project(value)
  local project = nil
  if type(value) == "table" and value.root and value.name then
    project = value
  elseif type(value) == "string" and value ~= "" then
    project = self.registry:find_by_name_or_root(value)
  end

  if not project then
    notify.warn("Project not found")
    return
  end

  ui.input({
    prompt = ("Rename %s"):format(project.name),
    default = project.name,
  }, function(name)
    name = name and vim.trim(name) or ""
    if name == "" then
      return
    end

    local updated = self.registry:add({
      name = name,
      root = project.root,
    })
    self.terminals:update_project_identity(updated)
    notify.notify(("Renamed project to %s"):format(updated.name))
    self:refresh_state_preview()
  end)
end

---@param opts? { name?: string, root?: string }
function App:add_project(opts)
  opts = opts or {}
  local root = opts.root
    or self.detector:git_candidate(self.detector:current_path())
    or self.detector:cwd_for_path(self.detector:current_path())
  root = fs.normalize(root)

  local existing = self.registry:get(root)
  if existing then
    self.terminals:promote_free_session(existing)
    self:activate_project(existing.root)
    local state = self:current_tab()
    if state:has_visible_window() then
      local session = self.terminals:get_session({ kind = "project", project = existing })
      if session then
        self.terminals:show_in_tab(state, session)
      end
    end
    notify.notify(("Using existing project %s"):format(existing.name))
    self:refresh_state_preview()
    return
  end

  local function finalize(name)
    name = name and vim.trim(name) or ""
    if name == "" then
      return
    end

    local project = self.registry:add({
      name = name,
      root = root,
    })

    self.terminals:promote_free_session(project)
    self:activate_project(project.root)

    local state = self:current_tab()
    if state:has_visible_window() then
      local session = self.terminals:get_session({ kind = "project", project = project })
      if not session then
        self:refresh_state_preview()
        return
      end
      self.terminals:show_in_tab(state, session)
    end
    self:refresh_state_preview()
  end

  if opts.name then
    finalize(opts.name)
    return
  end

  ui.input({
    prompt = "Project name",
    default = self.registry:suggest_name(root),
  }, finalize)
end

---@param value? string
function App:remove_project(value)
  local direct = nil
  if type(value) == "table" and value.root and value.name then
    direct = value
  end
  local function remove(project)
    if not project then
      notify.warn("Project not found")
      return
    end

    self.registry:remove(project.root)
    self.queue:delete_workspace(project.root)
    self.terminals:destroy_project_session(project.root)
    self.tabs:clear_project(project.root)
    self.terminals:detach_session(project.root, self.tabs:list())
    self:refresh_state_preview()
  end

  if direct or (type(value) == "string" and value ~= "") then
    remove(direct or self.registry:find_by_name_or_root(value))
    return
  end

  self.picker:pick_for_removal(remove)
end

---@param cwd string
function App:maybe_offer_project(cwd)
  if not self.config:get().project_detection.auto_suggest_git_root then
    return
  end

  local root = self.detector:git_candidate(cwd)
  if not root then
    return
  end

  ui.confirm(("Add %s as a Codex project?"):format(root), function(confirmed)
    if confirmed then
      self:add_project({ root = root })
    end
  end)
end

---@param buf? number
function App:toggle_terminal_header(buf)
  local toggled = self.terminals:toggle_header_for_buf(buf or vim.api.nvim_get_current_buf())
  if not toggled then
    notify.warn("Current buffer is not a Codex terminal")
    return
  end

  notify.notify(("Codex terminal header %s"):format(toggled and "enabled" or "disabled"))
end

return App
