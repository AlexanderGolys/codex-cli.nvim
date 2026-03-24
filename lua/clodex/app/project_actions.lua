local fs = require("clodex.util.fs")
local Backend = require("clodex.backend")
local git = require("clodex.util.git")
local notify = require("clodex.util.notify")
local MarkdownPreview = require("clodex.ui.markdown_preview")
local ui = require("clodex.ui.select")

local SWAPFILE_ERROR_CODE = "E325"

--- Coordinates project-scoped actions for registry entries and tab focus.
--- Project creation, selection, deletion, and terminal lifecycle are routed through this module.
---@class Clodex.AppProjectActions
---@field app Clodex.App
local ProjectActions = {}
ProjectActions.__index = ProjectActions

---@param value Clodex.Project?
---@return Clodex.Project?
local function ensure_project(value)
    if value then
        return value
    end
    notify.warn("No active project selected")
end

---@param path string
---@return boolean
local function edit_if_safe(path)
    local current_buf = vim.api.nvim_get_current_buf()
    local current_path = vim.api.nvim_buf_get_name(current_buf)
    local same_path = current_path ~= "" and fs.normalize(current_path) == fs.normalize(path)
    if vim.bo[current_buf].modified and not same_path then
        notify.warn("Current buffer has unsaved changes; keeping it open instead of replacing it.")
        return false
    end

    local ok, err = pcall(vim.cmd.edit, vim.fn.fnameescape(path))
    if ok then
        return true
    end

    local message = tostring(err or "")
    if message:find(SWAPFILE_ERROR_CODE, 1, true) then
        notify.warn(("Swap file already exists for %s; keeping the current buffer unchanged."):format(path))
        return false
    end

    notify.error(("Failed to open %s\n%s"):format(path, message))
    return false
end

---@param self Clodex.AppProjectActions
---@param project Clodex.Project?
---@param path string
---@param default_lines string[]
local function open_project_file(self, project, path, default_lines)
    project = ensure_project(project)
    if not project then
        return
    end

    if not fs.exists(path) then
        fs.write_file(path, table.concat(default_lines, "\n") .. "\n")
    end

    self:activate_project(project.root)
    edit_if_safe(path)
    self.app.project_details_store:touch_activity(project)
    self.app:refresh_views()
end

---@class Clodex.AppProjectActions.ProjectPicker
---@field registry Clodex.ProjectRegistry
local ProjectPicker = {}
ProjectPicker.__index = ProjectPicker

---@param registry Clodex.ProjectRegistry
---@return Clodex.AppProjectActions.ProjectPicker
function ProjectPicker.new(registry)
    local self = setmetatable({}, ProjectPicker)
    self.registry = registry
    return self
end

---@param self Clodex.AppProjectActions.ProjectPicker
---@param opts? { include_none?: boolean, prompt?: string, active_root?: string, on_delete?: fun(project: Clodex.Project), on_rename?: fun(project: Clodex.Project), snacks?: table }
---@param on_choice fun(project?: Clodex.Project)
function ProjectPicker:pick(opts, on_choice)
    opts = opts or {}
    local projects = self.registry:list()
    if #projects == 0 then
        notify.warn("No Clodex projects configured")
        return
    end

    return ui.pick_project(projects, opts, on_choice)
end

---@param self Clodex.AppProjectActions.ProjectPicker
---@param on_choice fun(project?: Clodex.Project)
function ProjectPicker:pick_for_removal(on_choice)
    return self:pick({ prompt = "Remove Clodex project" }, on_choice)
end

---@param self Clodex.AppProjectActions.ProjectPicker
---@param active_root? string
---@param on_choice fun(project?: Clodex.Project)
function ProjectPicker:pick_for_rename(active_root, on_choice)
    return self:pick({
        prompt = "Rename Clodex project",
        active_root = active_root,
        on_rename = on_choice,
    }, on_choice)
end

---@param app Clodex.App
---@return Clodex.AppProjectActions
function ProjectActions.new(app)
    return setmetatable({
        app = app,
        cheatsheet_preview = MarkdownPreview.new("clodex-project-cheatsheet"),
    }, ProjectActions)
end

---@param self Clodex.AppProjectActions
---@param project? Clodex.Project
---@return Clodex.Project?
local function current_or_target_project(self, project)
    if project then
        return project
    end
    local target = self.app:resolve_target(self.app:current_tab())
    return target.kind == "project" and target.project or nil
end

---@param path string
---@return boolean
local function path_is_bookmarkable(path)
    return path ~= "" and not fs.is_virtual_path(path) and fs.is_file(path)
end

---@param state Clodex.TabState
---@param target Clodex.TerminalTarget
---@return Clodex.TerminalSession?
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

---@param project Clodex.Project
---@param state Clodex.TabState
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
        self.app:refresh_views()
    end)
end

---@param state Clodex.TabState
function ProjectActions:prompt_new_tab_active_project(state)
    if state:has_prompted_project() then
        return
    end

    state:mark_prompted_project()
    local active_root = state.active_project_root
    state:clear_active_project()

    local projects = self.app.registry:list()
    if #projects == 0 then
        self.app:refresh_views()
        return
    end

    ui.pick_project(projects, {
        prompt = "Active project for new tab",
        include_none = true,
        active_root = active_root,
    }, function(project)
        if project then
            state:set_active_project(project.root)
            self.app.project_details_store:touch_activity(project)
            if state:has_visible_window() then
                self:show_target(state, {
                    kind = "project",
                    project = project,
                })
            end
        end
        self.app:refresh_views()
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

---@param project Clodex.Project
---@return Clodex.TerminalSession?
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

---@param project Clodex.Project
function ProjectActions:deactivate_project_session(project)
    self.app.terminals:destroy_project_session(project.root)
    self.app.terminals:detach_session(project.root, self.app.tabs:list())
    notify.notify(("Stopped Codex session for %s"):format(project.name))
    self.app:refresh_views()
end

---@param project Clodex.Project
function ProjectActions:open_project_workspace_target(project)
    self:activate_project(project.root)

    local readme = fs.find_readme(project.root)
    if readme then
        edit_if_safe(readme)
    end

    local state = self.app:current_tab()
    if not self.app.terminals:ensure_project_session(project) then
        self.app:refresh_views()
        return
    end

    self:show_target(state, {
        kind = "project",
        project = project,
    })
    self.app.project_details_store:touch_activity(project)
    self.app:refresh_views()
end

--- Opens the current project's README in the active window.
--- The file prefers an existing README and falls back to creating `README.md` on demand.
---@param project? Clodex.Project
function ProjectActions:open_project_readme_file(project)
    project = current_or_target_project(self, project)
    local path = project and (fs.find_readme(project.root) or fs.join(project.root, "README.md")) or ""
    open_project_file(self, project, path, {
        ("# %s"):format(project and project.name or "Project"),
        "",
    })
end

--- Opens the current project's todo file in the active window.
--- The file lives at `TODO.md` in the project root and is created on demand.
---@param project? Clodex.Project
function ProjectActions:open_project_todo_file(project)
    project = current_or_target_project(self, project)
    local path = project and fs.join(project.root, "TODO.md") or ""
    open_project_file(self, project, path, {
        ("# %s TODO"):format(project and project.name or "Project"),
        "",
    })
end

--- Opens the current project's shared glossary in the active window.
--- The dictionary lives under `.clodex/PROJECT_DICTIONARY.md` and is created on demand.
---@param project? Clodex.Project
function ProjectActions:open_project_dictionary_file(project)
    project = current_or_target_project(self, project)
    local path = project and fs.join(project.root, ".clodex", "PROJECT_DICTIONARY.md") or ""
    open_project_file(self, project, path, {
        ("# %s Project Dictionary"):format(project and project.name or "Project"),
        "",
        "Use this file for project-specific terms, acronyms, and local definitions.",
        "",
        "## Definitions",
        "",
        "- Term: Meaning",
    })
end

---@param project? Clodex.Project
function ProjectActions:open_project_cheatsheet_file(project)
    project = current_or_target_project(self, project)
    local path = project and self.app.project_cheatsheet:path(project) or ""
    open_project_file(self, project, path, {
        "# Project Cheatsheet",
        "",
        "- One-line reminder",
    })
end

---@param project? Clodex.Project
function ProjectActions:toggle_project_cheatsheet_preview(project)
    project = current_or_target_project(self, project)
    project = ensure_project(project)
    if not project then
        return
    end

    self.cheatsheet_preview:toggle({
        title = ("%s Cheatsheet"):format(project.name),
        lines = self.app.project_cheatsheet:read_lines(project),
    })
end

---@param project? Clodex.Project
function ProjectActions:add_project_cheatsheet_item(project)
    project = current_or_target_project(self, project)
    project = ensure_project(project)
    if not project then
        return
    end

    ui.input({
        prompt = ("Cheatsheet item for %s"):format(project.name),
    }, function(value)
        value = value and vim.trim(value) or ""
        if value == "" then
            return
        end

        local path = self.app.project_cheatsheet:path(project)
        local lines = self.app.project_cheatsheet:read_lines(project)
        lines[#lines + 1] = ("- %s"):format(value)
        fs.write_file(path, table.concat(lines, "\n") .. "\n")
        self.app.project_details_store:touch_activity(project)
        notify.notify(("Added cheatsheet item for %s"):format(project.name))
        if self.cheatsheet_preview:is_open() then
            self.cheatsheet_preview:show({
                title = ("%s Cheatsheet"):format(project.name),
                lines = self.app.project_cheatsheet:read_lines(project),
            })
        end
        self.app:refresh_views()
    end)
end

---@param project? Clodex.Project
function ProjectActions:open_project_notes_picker(project)
    project = current_or_target_project(self, project)
    project = ensure_project(project)
    if not project then
        return
    end

    local notes = self.app.project_notes:list(project)
    if #notes == 0 then
        notify.warn(("No project notes for %s"):format(project.name))
        return
    end

    ui.pick_mapped(notes, {
        prompt = ("Project notes: %s"):format(project.name),
        map_item = function(note)
            local summary = #note.summary > 0 and table.concat(note.summary, " | ") or "No summary yet"
            return {
                value = note,
                text = ("%s  %s"):format(note.title, summary),
                preview = {
                    text = table.concat(vim.fn.readfile(note.path), "\n"),
                    ft = "markdown",
                    loc = false,
                },
                preview_title = note.title,
            }
        end,
    }, function(note)
        if not note then
            return
        end
        self:activate_project(project.root)
        edit_if_safe(note.path)
        self.app.project_details_store:touch_activity(project)
        self.app:refresh_views()
    end)
end

---@param project? Clodex.Project
function ProjectActions:create_project_note(project)
    project = current_or_target_project(self, project)
    project = ensure_project(project)
    if not project then
        return
    end

    ui.input({
        prompt = ("New note for %s"):format(project.name),
    }, function(title)
        title = title and vim.trim(title) or ""
        if title == "" then
            return
        end
        local path = self.app.project_notes:create(project, title)
        self:activate_project(project.root)
        edit_if_safe(path)
        self.app.project_details_store:touch_activity(project)
        notify.notify(("Created project note for %s: %s"):format(project.name, title))
        self.app:refresh_views()
    end)
end

---@param project? Clodex.Project
function ProjectActions:add_project_bookmark(project)
    project = current_or_target_project(self, project)
    project = ensure_project(project)
    if not project then
        return
    end

    local path = fs.normalize(vim.api.nvim_buf_get_name(0))
    if not path_is_bookmarkable(path) or not fs.is_relative_to(path, project.root) then
        notify.warn("Bookmarks can only be created from a file inside the active project")
        return
    end

    local line = vim.api.nvim_win_get_cursor(0)[1]
    ui.input({
        prompt = "Bookmark title (one word)",
    }, function(title)
        title = title and vim.trim(title) or ""
        if title == "" then
            return
        end
        title = title:gsub("%s+", "")
        ui.input({
            prompt = "Bookmark description",
        }, function(description)
            description = description and vim.trim(description) or ""
            if description == "" then
                return
            end
            local bookmark = self.app.project_bookmarks:add(project, {
                path = path,
                line = line,
                title = title,
                description = description,
            })
            self.app.project_bookmarks:decorate_buffer(project, vim.api.nvim_get_current_buf())
            self.app.project_details_store:touch_activity(project)
            notify.notify(("Added bookmark for %s: %s"):format(project.name, bookmark.title))
            self.app:refresh_views()
        end)
    end)
end

---@param project? Clodex.Project
function ProjectActions:open_project_bookmarks_picker(project)
    project = current_or_target_project(self, project)
    project = ensure_project(project)
    if not project then
        return
    end

    local bookmarks = self.app.project_bookmarks:list(project)
    if #bookmarks == 0 then
        notify.warn(("No bookmarks for %s"):format(project.name))
        return
    end

    ui.pick_mapped(bookmarks, {
        prompt = ("Bookmarks: %s"):format(project.name),
        map_item = function(bookmark)
            return {
                value = bookmark,
                text = ("%s  %s:%d  %s"):format(bookmark.title, bookmark.path, bookmark.line, bookmark.description),
                preview = {
                    text = table.concat(self.app.project_bookmarks:preview_lines(project, bookmark), "\n"),
                    ft = "markdown",
                    loc = false,
                },
                preview_title = bookmark.title,
            }
        end,
    }, function(bookmark)
        if not bookmark then
            return
        end
        self.app.project_bookmarks:jump(project, bookmark)
        self.app.project_bookmarks:decorate_buffer(project, vim.api.nvim_get_current_buf())
        self.app.project_details_store:touch_activity(project)
    end)
end

---@param root string
--- Updates the active tab project root and refreshes snapshot state.
--- This is the low-level state mutation used by project-switch actions.
function ProjectActions:activate_project(root)
    self.app:current_tab():set_active_project(root)
    self.app:refresh_views()
end

--- Clears the active project for current tab.
--- This drops any active project lock and reopens a valid target for the tab session.
--- It is used by explicit clear commands and reset flows.
function ProjectActions:clear_active_project()
    local state = self.app:current_tab()
    state:clear_active_project()
    if state:has_visible_window() then
        if not self:show_target(state, self.app:resolve_target(state)) then
            self.app:refresh_views()
            return
        end
    end
    self.app:refresh_views()
end

function ProjectActions:toggle_backend()
    local values = self.app.config:get()
    local next_backend = values.backend == "opencode" and "codex" or "opencode"
    values.backend = Backend.normalize(next_backend)
    values.prompt_execution.skills_dir = Backend.default_skills_dir(values.backend)
    self.app.terminals:update_config(values)
    self.app.state_preview:update_config(values)
    self.app.execution:update_config(values)
    self.app.exec_runner:update_config(values)
    self.app.queue_workspace:update_config(values)
    self.app:refresh_views()
    notify.notify(("Switched Clodex backend to %s"):format(Backend.display_name(values.backend)))
end

--- Sets the current tab's active project and refreshes the resolved terminal target.
--- This is shared by workspace and command-driven project selection flows.
---@param project Clodex.Project
function ProjectActions:set_current_project(project)
    local state = self.app:current_tab()
    state:set_active_project(project.root)
    if state:has_visible_window() then
        if not self:show_target(state, self.app:resolve_target(state)) then
            self.app:refresh_views()
            return
        end
    end
    self.app.project_details_store:touch_activity(project)
    self.app:refresh_views()
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
        self.app:refresh_views()
        return
    end
    if state:is_showing(session.key) then
        self.app.terminals:hide_in_tab(state)
        self.app:refresh_views()
        return
    end
    self.app.terminals:show_in_tab(state, session)

    if target.kind == "project" then
        self.app.project_details_store:touch_activity(target.project)
    end
    self.app:refresh_views()
end

---@param value? string|Clodex.Project
---@return Clodex.Project?
function ProjectActions:resolve_project(value)
    if type(value) == "table" and value.root and value.name then
        return value
    end
    if type(value) == "string" and value ~= "" then
        return self.app.registry:get(value) or self.app.registry:find_by_name(value)
    end
end

---@return Clodex.AppProjectActions.ProjectPicker
function ProjectActions:project_picker()
    return ProjectPicker.new(self.app.registry)
end

---@param project Clodex.Project
function ProjectActions:prompt_project_rename(project)
    ui.input({
        prompt = ("Rename %s"):format(project.name),
        default = project.name,
    }, function(name)
        name = name and vim.trim(name) or ""
        if name == "" or name == project.name then
            return
        end

        local updated = self.app.registry:add({
            name = name,
            root = project.root,
        })
        self.app.terminals:update_project_identity(updated)
        notify.notify(("Renamed project to %s"):format(updated.name))
        self.app:refresh_views()
    end)
end

---@param value? string|Clodex.Project
function ProjectActions:rename_project(value)
    local project = self:resolve_project(value)
    if project then
        self:prompt_project_rename(project)
        return
    end
    if type(value) == "string" and value ~= "" then
        notify.warn("Project not found")
        return
    end

    self:project_picker():pick_for_rename(self.app:current_tab().active_project_root, function(selected)
        if selected then
            self:prompt_project_rename(selected)
        end
    end)
end

---@param project? Clodex.Project
function ProjectActions:perform_project_removal(project)
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
    self.app:refresh_views()
    notify.notify(("Removed project %s"):format(project.name))
end

---@param project Clodex.Project
function ProjectActions:focus_project_session(project)
    local state = self.app:current_tab()
    if not state:has_visible_window() then
        return
    end

    if not self:show_target(state, {
            kind = "project",
            project = project,
        }) then
        self.app:refresh_views()
        return
    end

    self.app.project_details_store:touch_activity(project)
end

---@param project Clodex.Project
---@param message string
function ProjectActions:use_existing_project(project, message)
    self.app.terminals:promote_free_session(project)
    self:activate_project(project.root)
    self:focus_project_session(project)
    notify.notify(message:format(project.name))
    self.app:refresh_views()
end

---@param opts? { name?: string, root?: string }
--- Registers a new project if needed and activates terminal context.
--- Called from command paths and picker flow; it can auto-use existing projects.
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
        self.app:refresh_views()
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
---@param value? string|Clodex.Project
function ProjectActions:remove_project(value)
    local direct = self:resolve_project(value)

    if direct then
        self:perform_project_removal(direct)
        return
    end
    if type(value) == "string" and value ~= "" then
        self:perform_project_removal(nil)
        return
    end

    self:project_picker():pick({
        prompt = "Remove Clodex project",
        active_root = self.app:current_tab().active_project_root,
        on_rename = function(project)
            self:prompt_project_rename(project)
        end,
    }, function(project)
        self:perform_project_removal(project)
    end)
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

    ui.confirm(("Add %s as a Clodex project?"):format(root), function(confirmed)
        if confirmed then
            self:add_project({ root = root })
        end
    end)
end

---@param buf? number
function ProjectActions:toggle_terminal_header(buf)
    local toggled = self.app.terminals:toggle_header_for_buf(buf or vim.api.nvim_get_current_buf())
    if not toggled then
        notify.warn("Current buffer is not a Clodex terminal")
        return
    end

    notify.notify(("Clodex terminal header %s"):format(toggled and "enabled" or "disabled"))
end

return ProjectActions
