local fs = require("codex-cli.util.fs")
local git = require("codex-cli.util.git")
local notify = require("codex-cli.util.notify")
local ui = require("codex-cli.ui.select")

--- Coordinates project-scoped actions for registry entries and tab focus.
--- Project creation, selection, deletion, and terminal lifecycle are routed through this module.
---@class CodexCli.AppProjectActions
---@field app CodexCli.App
local ProjectActions = {}
ProjectActions.__index = ProjectActions

---@param app CodexCli.App
---@return CodexCli.AppProjectActions
function ProjectActions.new(app)
  return setmetatable({ app = app }, ProjectActions)
end

---@param state CodexCli.TabState
---@param target CodexCli.TerminalTarget
---@return CodexCli.TerminalSession?
function ProjectActions:show_target(state, target)
  local session, replaced_key = self.app.terminals:get_session(target)
  if replaced_key then
    self.app.terminals:detach_session(replaced_key, self.app.tabs:list())
  end
  if not session then
    return
  end
  self.app.terminals:show_in_tab(state, session)
  return session
end

---@param project CodexCli.Project
---@param state CodexCli.TabState
function ProjectActions:prompt_set_active_project(project, state)
  if state.active_project_root or state:has_prompted_project() then
    return
  end

  state:mark_prompted_project()
  ui.confirm(("Set %s as the active project for this tab?"):format(project.name), function(confirmed)
    if not confirmed then
      return
    end

    state:set_active_project(project.root)
    if state:has_visible_window() then
      self:show_target(state, {
        kind = "project",
        project = project,
      })
    end
    self.app:refresh_state_preview()
  end)
end

---@param buffer? number
function ProjectActions:maybe_prompt_active_project(buffer)
  local state = self.app:current_tab()
  if state.active_project_root or state:has_prompted_project() then
    return
  end

  buffer = buffer or vim.api.nvim_get_current_buf()
  if not buffer or not vim.api.nvim_buf_is_valid(buffer) then
    return
  end
  if vim.bo[buffer].buftype ~= "" or vim.api.nvim_buf_get_name(buffer) == "" then
    return
  end

  local project = self.app.registry:find_for_path(fs.current_path(buffer))
  if project then
    self:prompt_set_active_project(project, state)
  end
end

---@param project CodexCli.Project
---@return CodexCli.TerminalSession?
function ProjectActions:activate_project_session(project)
  local session = self.app.terminals:ensure_project_session(project)
  if not session then
    return
  end

  self:activate_project(project.root)
  self.app.project_details_store:touch_activity(project)
  notify.notify(("Activated Codex session for %s"):format(project.name))
  return session
end

---@param project CodexCli.Project
function ProjectActions:deactivate_project_session(project)
  self.app.terminals:destroy_project_session(project.root)
  self.app.terminals:detach_session(project.root, self.app.tabs:list())
  notify.notify(("Stopped Codex session for %s"):format(project.name))
  self.app:refresh_state_preview()
end

---@param project CodexCli.Project
function ProjectActions:open_project_workspace_target(project)
  self:activate_project(project.root)

  local readme = fs.find_readme(project.root)
  if readme then
    vim.cmd.edit(vim.fn.fnameescape(readme))
  end

  local state = self.app:current_tab()
  if not self.app.terminals:ensure_project_session(project) then
    self.app:refresh_state_preview()
    return
  end

  self:show_target(state, {
    kind = "project",
    project = project,
  })
  self.app.project_details_store:touch_activity(project)
  self.app:refresh_state_preview()
end

--- Opens the current project's todo file in the active window.
--- The file lives at `TODO.md` in the project root and is created on demand.
---@param project? CodexCli.Project
function ProjectActions:open_project_todo_file(project)
  project = project or self.app:resolve_target(self.app:current_tab()).project
  if not project then
    notify.warn("No active project selected")
    return
  end

  local path = fs.join(project.root, "TODO.md")
  if not fs.exists(path) then
    fs.write_file(path, ("# %s TODO\n"):format(project.name))
  end

  self:activate_project(project.root)
  vim.cmd.edit(vim.fn.fnameescape(path))
  self.app.project_details_store:touch_activity(project)
  self.app:refresh_state_preview()
end

---@param root string
--- Updates the active tab project root and refreshes snapshot state.
--- This is the low-level state mutation used by project-switch actions.
function ProjectActions:activate_project(root)
  self.app:current_tab():set_active_project(root)
  self.app:refresh_state_preview()
end

--- Clears the active project for current tab.
--- This drops any active project lock and reopens a valid target for the tab session.
--- It is used by explicit clear commands and reset flows.
function ProjectActions:clear_active_project()
  local state = self.app:current_tab()
  state:clear_active_project()
  if state:has_visible_window() then
    if not self:show_target(state, self.app:resolve_target(state)) then
      self.app:refresh_state_preview()
      return
    end
  end
  self.app:refresh_state_preview()
end

--- Sets the current tab's active project and refreshes the resolved terminal target.
--- This is shared by workspace and command-driven project selection flows.
---@param project CodexCli.Project
function ProjectActions:set_current_project(project)
  local state = self.app:current_tab()
  state:set_active_project(project.root)
  if not self:show_target(state, self.app:resolve_target(state)) then
    self.app:refresh_state_preview()
    return
  end
  self.app.project_details_store:touch_activity(project)
  self.app:refresh_state_preview()
  notify.notify(("Set current project to %s"):format(project.name))
end

--- Toggles visibility of the current tab's terminal target.
--- The method opens/closes the selected target and optionally prompts for project creation.
--- It keeps state preview synchronized with resulting terminal visibility.
function ProjectActions:toggle()
  local state = self.app:current_tab()
  local target = self.app:resolve_target(state)
  if target.kind == "project" then
    self:prompt_set_active_project(target.project, state)
  end

  local session, replaced_key = self.app.terminals:get_session(target)
  if replaced_key then
    self.app.terminals:detach_session(replaced_key, self.app.tabs:list())
  end
  if not session then
    self.app:refresh_state_preview()
    return
  end
  if state:is_showing(session.key) then
    self.app.terminals:hide_in_tab(state)
    self.app:refresh_state_preview()
    return
  end
  self.app.terminals:show_in_tab(state, session)

  if target.kind == "project" then
    self.app.project_details_store:touch_activity(target.project)
  end
  self.app:refresh_state_preview()
  if target.kind == "free" then
    self:maybe_offer_project(target.cwd)
  end
end

---@param value? string|CodexCli.Project
---@return CodexCli.Project?
function ProjectActions:resolve_project(value)
  if type(value) == "table" and value.root and value.name then
    return value
  end
  if type(value) == "string" and value ~= "" then
    return self.app.registry:find_by_name_or_root(value)
  end
end

---@param value? string|CodexCli.Project
function ProjectActions:rename_project(value)
  local project = self:resolve_project(value)
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

    local updated = self.app.registry:add({
      name = name,
      root = project.root,
    })
    self.app.terminals:update_project_identity(updated)
    notify.notify(("Renamed project to %s"):format(updated.name))
    self.app:refresh_state_preview()
  end)
end

---@param project CodexCli.Project
function ProjectActions:focus_project_session(project)
  local state = self.app:current_tab()
  if not state:has_visible_window() then
    return
  end

  if not self:show_target(state, {
    kind = "project",
    project = project,
  }) then
    self.app:refresh_state_preview()
    return
  end

  self.app.project_details_store:touch_activity(project)
end

---@param project CodexCli.Project
---@param message string
function ProjectActions:use_existing_project(project, message)
  self.app.terminals:promote_free_session(project)
  self:activate_project(project.root)
  self:focus_project_session(project)
  notify.notify(message:format(project.name))
  self.app:refresh_state_preview()
end

---@param opts? { name?: string, root?: string }
--- Registers a new project if needed and activates terminal context.
--- Called from command paths and picker flow; it can auto-use existing projects.
---@param opts? { name?: string, root?: string }
function ProjectActions:add_project(opts)
  opts = opts or {}
  local path = fs.current_path()
  local root = opts.root
  if not root then
    local git_root = git.get_root(path)
    if git_root and not self.app.registry:has_root(git_root) then
      root = git_root
    else
      root = fs.cwd_for_path(path)
    end
  end
  root = fs.normalize(root)

  local existing = self.app.registry:get(root)
  if existing then
    self:use_existing_project(existing, "Using existing project %s")
    return
  end

  --- Finalizes project creation after name resolution.
  --- It normalizes the chosen name, updates registry, and focuses the new project session.
  local function finalize(name)
    name = name and vim.trim(name) or ""
    if name == "" then
      return
    end

    local project = self.app.registry:add({
      name = name,
      root = root,
    })
    self.app.terminals:promote_free_session(project)
    self:activate_project(project.root)
    self:focus_project_session(project)
    self.app:refresh_state_preview()
  end

  if opts.name then
    finalize(opts.name)
    return
  end

  ui.input({
    prompt = "Project name",
    default = self.app.registry:suggest_name(root),
  }, finalize)
end

--- Removes a app project actions item and normalizes dependent state.
--- This cleanup keeps persistence and session state consistent with user actions.
---@param value? string|CodexCli.Project
function ProjectActions:remove_project(value)
  local direct = self:resolve_project(value)
  --- Internal helper that removes registry state, workspace data, and sessions.
  --- It is reused by explicit removal and picker-provided selection.
  local function remove(project)
    if not project then
      notify.warn("Project not found")
      return
    end

    self.app.registry:remove(project.root)
    self.app.queue:delete_workspace(project.root)
    self.app.project_details_store:delete(project.root)
    self.app.terminals:destroy_project_session(project.root)
    self.app.tabs:clear_project(project.root)
    self.app.terminals:detach_session(project.root, self.app.tabs:list())
    self.app:refresh_state_preview()
  end

  if direct then
    remove(direct)
    return
  end
  if type(value) == "string" and value ~= "" then
    remove(nil)
    return
  end

  ui.pick_project(self.app.registry:list(), {
    prompt = "Remove Codex project",
  }, remove)
end

---@param cwd string
function ProjectActions:maybe_offer_project(cwd)
  if not self.app.config:get().project_detection.auto_suggest_git_root then
    return
  end

  local root = git.get_root(cwd)
  if root and self.app.registry:has_root(root) then
    root = nil
  end
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
function ProjectActions:toggle_terminal_header(buf)
  local toggled = self.app.terminals:toggle_header_for_buf(buf or vim.api.nvim_get_current_buf())
  if not toggled then
    notify.warn("Current buffer is not a Codex terminal")
    return
  end

  notify.notify(("Codex terminal header %s"):format(toggled and "enabled" or "disabled"))
end

return ProjectActions
