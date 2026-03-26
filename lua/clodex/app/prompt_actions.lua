local Prompt = require("clodex.prompt")
local Backend = require("clodex.backend")
local PromptCreator = require("clodex.ui.prompt_creator")
local notify = require("clodex.util.notify")
local ui = require("clodex.ui.select")

---@class Clodex.AppPromptActions.ResolveOpts
---@field project? Clodex.Project
---@field project_root? string
---@field project_name? string
---@field project_value? string
---@field project_required? boolean

---@class Clodex.AppPromptActions.PickPromptOpts: Clodex.AppPromptActions.ResolveOpts
---@field category? Clodex.PromptCategory
---@field context? Clodex.PromptContext.Capture

---@class Clodex.AppPromptActions.AddTodoSpec
---@field title string
---@field details? string
---@field kind? Clodex.PromptCategory
---@field image_path? string
---@field completion_target? Clodex.QueueName

---@class Clodex.AppPromptActions
---@field app Clodex.App
local PromptActions = {}
PromptActions.__index = PromptActions

local SUBMIT_ACTIONS = {
    { value = "save", label = "plan", key = "<C-s>" },
    { value = "queue", label = "queue", key = "<C-q>" },
    { value = "exec", label = "run now", key = "<C-e>" },
    { value = "chat", label = "chat", key = "<C-l>" },
}

---@param action string?
---@param app Clodex.App
---@return Clodex.AppQueueActions.AddTodoOpts?
local function queue_submit_opts(app, action)
    if action == "exec" then
        local backend = app and app.config and app.config.get and app.config:get().backend or nil
        return {
            queue = "queued",
            implement = true,
            run_mode = Backend.supports_direct_exec(backend) and "exec" or "interactive",
        }
    end
    if action == "queue" then
        return { queue = "queued" }
    end
end

---@param app Clodex.App
---@param project Clodex.Project
local function touch_project_activity(app, project)
    local details_store = app.project_details_store
    if details_store and details_store.touch_activity then
        details_store:touch_activity(project)
    end
end

---@param category Clodex.PromptCategory
---@param context? Clodex.PromptContext.Capture
---@return table?
local function selection_default_draft(category, context)
    if not context or not context.selection_text then
        return nil
    end
    if category == "bug" then
        return nil
    end
    local definition = Prompt.categories.get(category)
    local spec = Prompt.parse(Prompt.render(definition.default_title, "&selection"))
    return spec and {
        title = spec.title,
        details = spec.details or "",
    } or nil
end

---@param app Clodex.App
---@return Clodex.AppPromptActions
function PromptActions.new(app)
    return setmetatable({ app = app }, PromptActions)
end

---@param project Clodex.Project
---@param body string
---@return boolean
function PromptActions:send_direct_to_chat(project, body)
    body = vim.trim(body or "")
    if body == "" then
        return false
    end

    local session = self.app.terminals:ensure_project_session(project)
    if not session then
        notify.warn(("Could not start a chat session for %s"):format(project.name))
        return false
    end

    local state = self.app:current_tab()
    state:set_active_project(project.root)
    self.app.terminals:show_in_tab(state, session)
    if not session:dispatch_prompt(body) then
        notify.warn(("Could not send prompt directly to chat for %s"):format(project.name))
        return false
    end

    touch_project_activity(self.app, project)
    self.app:refresh_views()
    notify.notify(("Sent prompt directly to chat for %s"):format(project.name))
    return true
end

---@param project Clodex.Project
---@param spec Clodex.AppPromptActions.AddTodoSpec
---@param action string?
function PromptActions:submit_prompt(project, spec, action)
    if action == "chat" then
        return self:send_direct_to_chat(project, Prompt.render(spec.title, spec.details))
    end
    return self.app.queue_actions:add_project_todo(project, spec, queue_submit_opts(self.app, action))
end

---@param opts? Clodex.AppPromptActions.ResolveOpts
---@return Clodex.Project?
function PromptActions:resolve_project(opts)
    opts = opts or {}
    local project = opts.project
    if not project and opts.project_root then
        project = self.app.registry:get(opts.project_root)
    end
    if not project and opts.project_name then
        project = self.app.registry:find_by_name(opts.project_name)
    end
    if not project and opts.project_value then
        project = self.app.registry:find_by_name_or_root(opts.project_value)
    end
    if project then
        return project
    end
    if opts.project_required then
        return nil
    end
    local state = self.app.current_tab and self.app:current_tab() or nil
    local target = state and self.app.resolve_target and self.app:resolve_target(state) or nil
    if target and target.kind == "project" then
        return target.project
    end
end

---@param target_project Clodex.Project?
---@param callback fun(project: Clodex.Project)
function PromptActions:pick_project(target_project, callback)
    if target_project then
        callback(target_project)
        return
    end
    local projects = self.app.registry and self.app.registry.list and self.app.registry:list() or {}
    ui.pick_project(projects, { prompt = "Select project" }, function(project)
        if project then
            callback(project)
        end
    end)
end

---@param opts? Clodex.AppPromptActions.PickPromptOpts
---@param callback fun(project: Clodex.Project, category: Clodex.PromptCategory)
function PromptActions:pick_target(opts, callback)
    opts = opts or {}
    local category = Prompt.categories.is_valid(opts.category) and Prompt.categories.get(opts.category).id or "todo"
    local project = self:resolve_project(opts)
    if project then
        callback(project, category)
        return
    end

    if not project then
        self:pick_project(nil, function(selected_project)
            if not selected_project then
                return
            end
            callback(selected_project, category)
        end)
    end
end

---@param project Clodex.Project
---@param opts? { category?: Clodex.PromptCategory, context?: Clodex.PromptContext.Capture, initial_draft?: table, submit_actions?: Clodex.UiSelect.MultilineAction[], lock_kind?: boolean, mode?: "new"|"edit", active_project_root?: string, on_submit?: fun(spec: Clodex.AppPromptActions.AddTodoSpec, action?: string, project?: Clodex.Project) }
function PromptActions:open_creator(project, opts)
    opts = opts or {}
    local category = Prompt.categories.is_valid(opts.category) and Prompt.categories.get(opts.category).id or "todo"
    local draft = opts.initial_draft or selection_default_draft(category, opts.context)
    local current_tab = self.app.current_tab and self.app:current_tab() or nil
    local projects = self.app.registry and self.app.registry.list and self.app.registry:list() or nil
    return PromptCreator.open({
        app = self.app,
        project = project,
        projects = projects,
        active_project_root = opts.active_project_root or current_tab and current_tab.active_project_root or nil,
        context = opts.context,
        initial_kind = category,
        initial_draft = draft,
        submit_actions = opts.submit_actions or SUBMIT_ACTIONS,
        mode = opts.mode or "new",
        lock_kind = opts.lock_kind == true,
        on_submit = opts.on_submit or function(spec, action, selected_project)
            return self:submit_prompt(selected_project or project, spec, action)
        end,
    })
end

---@param project Clodex.Project
---@param context? Clodex.PromptContext.Capture
function PromptActions:prompt_for_todo(project, context)
    return self:open_creator(project, {
        category = "todo",
        context = context,
    })
end

---@param project Clodex.Project
---@param category Clodex.PromptCategory
---@param opts? { context?: Clodex.PromptContext.Capture }
function PromptActions:prompt_for_category_kind(project, category, opts)
    opts = opts or {}
    return self:open_creator(project, {
        category = category,
        context = opts.context,
    })
end

---@param project Clodex.Project
---@param spec { title: string, details?: string }
---@return { title: string, details?: string, broken: boolean }
function PromptActions:normalize_spec(project, spec)
    local normalized = Prompt.normalize_title({
        title = spec.title,
        details = spec.details,
        max_width = self.app.queue_workspace:prompt_title_width(),
    })
    if normalized.broken then
        notify.notify(("Prompt title was shortened for %s to fit the queue list"):format(project.name))
    end
    return normalized
end

---@param opts? Clodex.AppPromptActions.ResolveOpts
function PromptActions:add_bug_todo(opts)
    self:pick_project(self:resolve_project(opts), function(project)
        self:open_creator(project, {
            category = "bug",
        })
    end)
end

return PromptActions
