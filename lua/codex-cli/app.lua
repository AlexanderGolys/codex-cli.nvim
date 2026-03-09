local Config = require("codex-cli.config")
local Commands = require("codex-cli.commands")
local Detector = require("codex-cli.project.detector")
local Picker = require("codex-cli.project.picker")
local Registry = require("codex-cli.project.registry")
local TabManager = require("codex-cli.tab.manager")
local TerminalManager = require("codex-cli.terminal.manager")
local ui = require("codex-cli.ui.select")
local fs = require("codex-cli.util.fs")
local notify = require("codex-cli.util.notify")

---@class CodexCli.App
---@field config CodexCli.Config
---@field registry CodexCli.ProjectRegistry
---@field detector CodexCli.ProjectDetector
---@field picker CodexCli.ProjectPicker
---@field tabs CodexCli.TabManager
---@field terminals CodexCli.TerminalManager
---@field group? integer
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
  self.terminals:update_config(values)
  Commands.register()
  self:setup_autocmds()
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
    end,
  })
end

---@return CodexCli.TabState
function App:current_tab()
  return self.tabs:get()
end

---@param state CodexCli.TabState
---@return CodexCli.TerminalTarget
function App:resolve_target(state)
  local active_root = state.active_project_root
  if active_root then
    local active_project = self.registry:get(active_root)
    if active_project then
      return {
        kind = "project",
        project = active_project,
      }
    end
    state:clear_active_project()
  end

  local path = self.detector:current_path()
  local project = self.detector:project_for_path(path)
  if project then
    state:set_active_project(project.root)
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

---@param root string
function App:activate_project(root)
  self:current_tab():set_active_project(root)
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
      return
    end
    self.terminals:show_in_tab(state, session)
  end
end

function App:toggle()
  local state = self:current_tab()
  local target = self:resolve_target(state)
  local session, replaced_key = self.terminals:get_session(target)
  if replaced_key then
    self.terminals:detach_session(replaced_key, self.tabs:list())
  end
  if not session then
    return
  end

  if state:is_showing(session.key) then
    self.terminals:hide_in_tab(state)
    return
  end

  self.terminals:show_in_tab(state, session)
  if target.kind == "free" then
    self:maybe_offer_project(target.cwd)
  end
end

function App:select_project()
  self.picker:pick({ include_none = true }, function(project)
    local state = self:current_tab()
    state:set_active_project(project and project.root or nil)

    if not state:has_visible_window() then
      return
    end

    local target = self:resolve_target(state)
    local session, replaced_key = self.terminals:get_session(target)
    if replaced_key then
      self.terminals:detach_session(replaced_key, self.tabs:list())
    end
    if not session then
      return
    end
    self.terminals:show_in_tab(state, session)
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
        return
      end
      self.terminals:show_in_tab(state, session)
    end
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
  local function remove(project)
    if not project then
      notify.warn("Project not found")
      return
    end

    self.registry:remove(project.root)
    self.terminals:destroy_project_session(project.root)
    self.tabs:clear_project(project.root)
    self.terminals:detach_session(project.root, self.tabs:list())
  end

  if value then
    remove(self.registry:find_by_name_or_root(value))
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

return App
