local Config = require("codex-cli.config")
local Commands = require("codex-cli.commands")
local Detector = require("codex-cli.project.detector")
local Picker = require("codex-cli.project.picker")
local Registry = require("codex-cli.project.registry")
local TabManager = require("codex-cli.tab.manager")
local TerminalManager = require("codex-cli.terminal.manager")
local ui = require("codex-cli.ui.select")
local StatePreview = require("codex-cli.ui.state_preview")
local fs = require("codex-cli.util.fs")
local notify = require("codex-cli.util.notify")

---@class CodexCli.App
---@field config CodexCli.Config
---@field registry CodexCli.ProjectRegistry
---@field detector CodexCli.ProjectDetector
---@field picker CodexCli.ProjectPicker
---@field tabs CodexCli.TabManager
---@field terminals CodexCli.TerminalManager
---@field state_preview CodexCli.StatePreview
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
  self.terminals:update_config(values)
  self.state_preview:update_config(values)
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
end

function App:toggle_state_preview()
  self.state_preview:toggle(self)
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
