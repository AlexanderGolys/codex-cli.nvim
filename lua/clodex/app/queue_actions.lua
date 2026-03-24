local History = require("clodex.history")
local notify = require("clodex.util.notify")

local COMMIT_ICON = "󰜘 "

--- Moves/restricts options for queue rewind operations in queue actions.
--- The options are interpreted by App-level handlers when items are moved backward.
---@alias Clodex.AppQueueActions.RewindOpts { copy?: boolean, queue?: Clodex.QueueName, mark_not_working?: boolean, note?: string }
--- Defines options for moving an item between queues and projects.
--- It supports optional duplication and destination queue override for bulk workflows.
--- Moves/restricts options for queue item transfer operations.
--- It is used by project-to-project and adjacent project move handlers.

--- Defines the Clodex.AppQueueActions.MoveOpts type for this module.
--- This annotation documents structured state so modules can pass data with consistent expectations.
---@alias Clodex.AppQueueActions.MoveOpts { target_queue?: Clodex.QueueName, source_queue?: Clodex.QueueName, copy?: boolean }

--- Defines the Clodex.AppQueueActions type for this module.
--- This annotation documents structured state so modules can pass data with consistent expectations.
---@alias Clodex.AppQueueActions.Host Clodex.App

---@class Clodex.AppQueueActions
---@field app Clodex.AppQueueActions.Host
---@field workspace_revisions table<string, string?>
local QueueActions = {}
QueueActions.__index = QueueActions

---@class Clodex.AppQueueActions.AddTodoOpts
---@field queue? Clodex.QueueName
---@field implement? boolean
---@field run_mode? "interactive"|"exec"

local PREVIOUS_QUEUE = {
    queued = "planned",
    implemented = "queued",
    history = "implemented",
}

---@param item Clodex.QueueItem
---@param opts Clodex.AppQueueActions.RewindOpts
---@param project_root? string
---@return Clodex.QueueItem
local function rewind_item_spec(item, opts, project_root)
    local moved = vim.deepcopy(item)
    if not opts.mark_not_working then
        return moved
    end

    local sections = {} ---@type string[]

    local original_title = vim.trim(moved.title or "")
    local original_details = vim.trim(moved.details or "")
    local note = vim.trim(opts.note or "")
    local commits = moved.history_commits or {}
    local commit_summary = vim.trim(moved.history_summary or "")

    local header =
        "A previously implemented feature or fix is not working as expected. The original implementation needs to be investigated and fixed."
    sections[#sections + 1] = header

    local original_section = { "## Original Prompt" }
    if original_title ~= "" then
        original_section[#original_section + 1] = ("**Title:** %s"):format(original_title)
    end
    if original_details ~= "" then
        original_section[#original_section + 1] = original_details
    end
    if #original_section > 1 then
        sections[#sections + 1] = table.concat(original_section, "\n\n")
    end

    if #commits > 0 or commit_summary ~= "" then
        local impl_section = { "## Implementation Details" }
        if #commits > 0 then
            local commit_parts = {}
            for _, commit_id in ipairs(commits) do
                local short = commit_id:sub(1, 8)
                commit_parts[#commit_parts + 1] = ("`%s%s`"):format(COMMIT_ICON, short)
            end
            impl_section[#impl_section + 1] = ("**Commits:** %s"):format(table.concat(commit_parts, " "))
        end
        if commit_summary ~= "" then
            impl_section[#impl_section + 1] = ("**Summary:** %s"):format(commit_summary)
        end
        sections[#sections + 1] = table.concat(impl_section, "\n\n")
    end

    if note ~= "" then
        sections[#sections + 1] = "## User Note\n\n" .. note
    end

    local instructions =
        "## Instructions\n\nInvestigate why the previously implemented functionality is not working correctly. Review the original implementation, identify the regression or bug, and implement a fix. Ensure the behavior works as originally intended."
    sections[#sections + 1] = instructions

    moved.details = table.concat(sections, "\n\n")
    moved.prompt = ("%s\n\n%s"):format(moved.title, moved.details)
    moved.kind = "notworking"
    moved.history_summary = nil
    moved.history_commits = vim.deepcopy(commits)
    moved.history_completed_at = nil
    return moved
end

---@param app Clodex.AppQueueActions.Host
---@return Clodex.AppQueueActions
function QueueActions.new(app)
    return setmetatable({
        app = app,
        workspace_revisions = {},
    }, QueueActions)
end

---@param project Clodex.Project
function QueueActions:remember_workspace_revision(project)
    self.workspace_revisions[project.root] = self.app.queue:workspace_revision(project)
end

---@param project Clodex.Project
---@param item_id string
---@return Clodex.QueueItem?
function QueueActions:refresh_queue_item_instructions(project, item_id)
    local queue_name, _, item = self.app.queue:find_item(project, item_id)
    if not item then
        return
    end

    local instructions = false
    if queue_name == "queued" then
        instructions = self.app.execution:queue_item_instructions(item)
    end

    return self.app.queue:update_item(project, item_id, {
        execution_instructions = instructions,
    })
end

---@param project Clodex.Project
---@param item Clodex.QueueItem
---@return boolean
function QueueActions:dispatch_item(project, item)
    local session = self.app.terminals:ensure_project_session(project)
    if not session then
        notify.warn(("Could not start a Codex session for %s"):format(project.name))
        return false
    end

    if not session:dispatch_prompt(self.app.execution:dispatch_prompt(project, item)) then
        return false
    end
    self:remember_workspace_revision(project)
    self.app.project_details_store:touch_activity(project)
    return true
end

---@param project Clodex.Project
---@param item Clodex.QueueItem
---@return boolean
function QueueActions:dispatch_item_direct(project, item)
    if not self.app.exec_runner:start(project, item) then
        return false
    end

    self:remember_workspace_revision(project)
    self.app.project_details_store:touch_activity(project)
    return true
end

---@param project Clodex.Project
---@param item_id string
---@return Clodex.QueueItem?
local function move_item_to_implemented(app, project, item_id)
    if app.queue:advance(project, item_id) ~= "implemented" then
        return
    end

    local queue_name, _, implemented_item = app.queue:find_item(project, item_id)
    if queue_name ~= "implemented" or not implemented_item then
        return
    end

    return implemented_item
end

---@param app Clodex.App
---@param project Clodex.Project
---@param item_id string
local function move_item_back_to_queued(app, project, item_id)
    local queue_name, _, implemented_item = app.queue:find_item(project, item_id)
    if queue_name ~= "implemented" or not implemented_item then
        return
    end

    app.queue:take_item(project, item_id, "implemented")
    app.queue:put_item(project, "queued", implemented_item, {
        clear_history = true,
        execution_instructions = app.execution:queue_item_instructions(implemented_item),
    })
end

---@param project Clodex.Project
---@param item_id string
---@param mode "interactive"|"exec"
---@return boolean
function QueueActions:start_queued_item(project, item_id, mode)
    local queue_name, _, queued_item = self.app.queue:find_item(project, item_id)
    if queue_name ~= "queued" or not queued_item then
        notify.warn("Only queued items can be implemented")
        return false
    end

    if mode == "exec" then
        local implemented_item = move_item_to_implemented(self.app, project, item_id)
        if not implemented_item then
            notify.warn("Could not move the queued item to implemented")
            return false
        end

        local started = self:dispatch_item_direct(project, implemented_item)
        if not started then
            move_item_back_to_queued(self.app, project, item_id)
            return false
        end
        return true
    end

    local started = self:dispatch_item(project, queued_item)
    if started then
        return true
    end
    return false
end

--- Checks project-local queue files for external updates.
--- This keeps the editor in sync when queued prompts complete by mutating `.clodex` JSON files directly.
function QueueActions:poll_workspace_updates()
    local changed = false
    for _, project in ipairs(self.app.registry:list()) do
        local revision = self.app.queue:workspace_revision(project)
        if self.workspace_revisions[project.root] == nil then
            self.workspace_revisions[project.root] = revision
        elseif self.workspace_revisions[project.root] ~= revision then
            self.workspace_revisions[project.root] = revision
            changed = true
        end
    end

    if changed then
        self.app:refresh_views()
    end
end

--- Adds a new app queue actions entry and keeps related state aligned.
--- This function feeds the same workflow used by interactive and scripted callers.
---@param project Clodex.Project
---@param spec Clodex.AppPromptActions.AddTodoSpec
---@param opts? Clodex.AppQueueActions.AddTodoOpts
---@return Clodex.QueueItem?
function QueueActions:add_project_todo(project, spec, opts)
    opts = opts or {}
    local title = vim.trim(spec.title or "")
    if title == "" then
        notify.warn("Todo title is required")
        return
    end

    local normalized = self.app.prompt_actions:normalize_spec(project, {
        title = title,
        details = spec.details,
    })
    local queue_name = opts.queue == "queued" and "queued" or "planned"
    local item = self.app.queue:add_todo(project, {
        title = normalized.title,
        details = normalized.details,
        kind = spec.kind,
        image_path = spec.image_path,
        completion_target = spec.completion_target,
        queue = queue_name,
    })
    if queue_name == "queued" then
        item = self:refresh_queue_item_instructions(project, item.id) or item
    end
    History.append_prompt_added(project.name, normalized.title, normalized.details, spec.kind)
    self.app.project_details_store:touch_activity(project)
    local started = false
    if queue_name == "queued" and opts.implement then
        started = self:start_queued_item(project, item.id, opts.run_mode == "exec" and "exec" or "interactive")
    end

    if queue_name == "queued" and started then
        if opts.run_mode == "exec" then
            notify.notify(("Queued and started direct prompt for %s: %s"):format(project.name, normalized.title))
        else
            notify.notify(("Queued and started prompt for %s: %s"):format(project.name, normalized.title))
        end
    elseif queue_name == "queued" then
        notify.notify(("Queued prompt for %s: %s"):format(project.name, normalized.title))
    else
        notify.notify(("Added todo to %s: %s"):format(project.name, normalized.title))
    end
    self:remember_workspace_revision(project)
    self.app:refresh_views()
    return item
end

---@param project Clodex.Project
---@param item_id string
---@param spec { title: string, details?: string }
function QueueActions:edit_queue_item(project, item_id, spec)
    local title = vim.trim(spec.title or "")
    if title == "" then
        notify.warn("Todo title is required")
        return
    end

    local normalized = self.app.prompt_actions:normalize_spec(project, {
        title = title,
        details = spec.details and vim.trim(spec.details) ~= "" and spec.details or nil,
    })
    local item = self.app.queue:update_item(project, item_id, {
        title = normalized.title,
        details = normalized.details or false,
    })
    if not item then
        notify.warn("Queue item not found")
        return
    end

    notify.notify(("Updated prompt for %s: %s"):format(project.name, item.title))
    self:refresh_queue_item_instructions(project, item_id)
    self:remember_workspace_revision(project)
    self.app:refresh_views()
end

---@param project Clodex.Project
---@param item_id string
---@return boolean, "started"|"blocked"
function QueueActions:implement_queue_item(project, item_id)
    local queue_name, _, item = self.app.queue:find_item(project, item_id)
    local moved_from_planned = false

    if queue_name == "planned" then
        if not self.app.queue:advance(project, item_id) then
            notify.warn("Could not move the planned item to queued")
            return false, "blocked"
        end
        self:refresh_queue_item_instructions(project, item_id)
        queue_name, _, item = self.app.queue:find_item(project, item_id, "queued")
        moved_from_planned = true
    end

    if queue_name ~= "queued" or not item then
        notify.warn("Only planned or queued items can be implemented")
        return false, "blocked"
    end

    if self:start_queued_item(project, item_id, "interactive") then
        notify.notify(("Started %s prompt for %s: %s"):format(
            moved_from_planned and "planned" or "queued",
            project.name,
            item.title
        ))
        self:remember_workspace_revision(project)
        self.app.project_details_store:touch_activity(project)
        self.app:refresh_views()
        return true, "started"
    end

    if moved_from_planned then
        self:remember_workspace_revision(project)
        self.app.project_details_store:touch_activity(project)
        self.app:refresh_views()
    end

    return false, "blocked"
end

---@param project Clodex.Project
function QueueActions:implement_queued_items(project)
    local queued_items = vim.deepcopy(self.app.queue:queues(project).queued)
    if #queued_items == 0 then
        notify.warn(("No queued items for %s"):format(project.name))
        return
    end

    local sent = 0
    for _, item in ipairs(queued_items) do
        if self:start_queued_item(project, item.id, "interactive") then
            sent = sent + 1
        end
    end

    if sent > 0 then
        notify.notify(("Started %d queued prompt(s) for %s"):format(sent, project.name))
        self:remember_workspace_revision(project)
        self.app:refresh_views()
    end
end

---@param project Clodex.Project
function QueueActions:move_all_planned_items_to_queued(project)
    local planned_items = vim.deepcopy(self.app.queue:queues(project).planned)
    if #planned_items == 0 then
        notify.warn(("No planned items for %s"):format(project.name))
        return
    end

    local moved = 0
    for _, item in ipairs(planned_items) do
        if self.app.queue:advance(project, item.id) then
            self:refresh_queue_item_instructions(project, item.id)
            moved = moved + 1
        end
    end

    if moved > 0 then
        notify.notify(("Moved %d planned prompt(s) to queued for %s"):format(moved, project.name))
        self:remember_workspace_revision(project)
        self.app.project_details_store:touch_activity(project)
        self.app:refresh_views()
    end
end

---@param opts? Clodex.AppPromptActions.ResolveOpts
function QueueActions:implement_next_queued_item(opts)
    self.app.prompt_actions:pick_project(self.app.prompt_actions:resolve_project(opts), function(project)
        local next_item = self.app.queue:queues(project).queued[1]
        if not next_item then
            notify.warn(("No queued items for %s"):format(project.name))
            return
        end
        self:implement_queue_item(project, next_item.id)
    end)
end

---@param opts? Clodex.AppPromptActions.ResolveOpts
function QueueActions:implement_all_queued_items(opts)
    self.app.prompt_actions:pick_project(self.app.prompt_actions:resolve_project(opts), function(project)
        self:implement_queued_items(project)
    end)
end

---@param project Clodex.Project
---@param item_id string
function QueueActions:advance_queue_item(project, item_id)
    if not self.app.queue:advance(project, item_id) then
        notify.warn("Item cannot be moved further")
        return
    end
    self:remember_workspace_revision(project)
    self.app.project_details_store:touch_activity(project)
    self:refresh_queue_item_instructions(project, item_id)
    self.app:refresh_views()
end

---@param project Clodex.Project
---@param item_id string
---@param opts? Clodex.AppQueueActions.RewindOpts
function QueueActions:rewind_queue_item(project, item_id, opts)
    opts = opts or {}
    local queue_name
    local item
    if opts.queue then
        queue_name, _, item = self.app.queue:find_item(project, item_id, opts.queue)
    else
        queue_name, _, item = self.app.queue:find_item(project, item_id)
    end
    local previous_queue = queue_name and PREVIOUS_QUEUE[queue_name] or nil
    if not previous_queue or not item then
        notify.warn("Item cannot be moved back")
        return
    end
    local rewind_item = rewind_item_spec(item, opts, project.root)
    local clear_history = queue_name == "implemented" or queue_name == "history"

    local moved_item
    if opts.copy then
        moved_item = self.app.queue:put_item(project, previous_queue, rewind_item, {
            copy = true,
            clear_history = clear_history,
        })
    else
        if not self.app.queue:take_item(project, item_id, queue_name) then
            notify.warn("Queue item not found")
            return
        end
        moved_item = self.app.queue:put_item(project, previous_queue, rewind_item, {
            clear_history = clear_history,
        })
    end

    if moved_item then
        self:refresh_queue_item_instructions(project, moved_item.id)
    end
    self:remember_workspace_revision(project)
    self.app.project_details_store:touch_activity(project)
    self.app:refresh_views()
end

---@param project Clodex.Project
---@param item_id string
---@param target_project Clodex.Project
---@param opts? Clodex.AppQueueActions.MoveOpts
function QueueActions:move_queue_item_to_project(project, item_id, target_project, opts)
    opts = opts or {}
    local queue_name
    local item
    if opts.source_queue then
        queue_name, _, item = self.app.queue:find_item(project, item_id, opts.source_queue)
    else
        queue_name, _, item = self.app.queue:find_item(project, item_id)
    end
    local target_queue = opts.target_queue or queue_name
    if not queue_name or not target_queue or not item then
        notify.warn("Queue item not found")
        return
    end

    if not opts.copy and not self.app.queue:take_item(project, item_id, queue_name) then
        notify.warn("Queue item not found")
        return
    end

    local moved = self.app.queue:put_item(target_project, target_queue, item, {
        copy = true,
        clear_history = queue_name == "history" and target_queue ~= "history",
    })
    if not moved then
        notify.warn("Failed to move queue item")
        return
    end

    notify.notify(("Moved '%s' to %s"):format(item.title, target_project.name))
    self:refresh_queue_item_instructions(target_project, moved.id)
    self:remember_workspace_revision(project)
    self:remember_workspace_revision(target_project)
    self.app.project_details_store:touch_activity(project)
    self.app.project_details_store:touch_activity(target_project)
    self.app:refresh_views()
end

---@param project Clodex.Project
---@param item_id string
function QueueActions:delete_queue_item(project, item_id)
    if not self.app.queue:delete_item(project, item_id) then
        notify.warn("Queue item not found")
        return
    end
    self:remember_workspace_revision(project)
    self.app:refresh_views()
end

return QueueActions
