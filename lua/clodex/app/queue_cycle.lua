local Prompt = require("clodex.prompt")

--- Provides structured queue workflow automation with embedded guidance for agents.
--- Each method performs a queue action and returns human-readable next-step instructions.
--- This ensures agents always have context about the queue state, even when handling
--- prompts directly without going through the Neovim UI.
---@class Clodex.QueueCycle
---@field app Clodex.App
local QueueCycle = {}
QueueCycle.__index = QueueCycle

---@param app Clodex.App
---@return Clodex.QueueCycle
function QueueCycle.new(app)
    return setmetatable({ app = app }, QueueCycle)
end

--- Returns the workspace directory for a project.
---@param project Clodex.Project
---@return string
local function workspace_dir(project)
    return project.root .. "/.clodex"
end

---@param project Clodex.Project
---@return string
function QueueCycle:queued_summary(project)
    local queues = self.app.queue:queues(project)
    local count = queues and queues.queued and #queues.queued or 0
    if count == 0 then
        return "No more queued items."
    end
    local next_item = queues.queued[1]
    return ("%d queued item(s) remaining. Next: `%s` (%s)"):format(count, next_item.title, next_item.kind)
end

--- Advances an item from its current queue to the next one and returns structured guidance.
--- Use this when an item has been worked on but is not yet complete.
---@param project Clodex.Project
---@param item_id string
---@param summary? string
---@param commits? string[]
---@return string # Guidance text describing the action taken and what to do next
function QueueCycle:advance_item(project, item_id, summary, commits)
    local queue_name, _, item = self.app.queue:find_item(project, item_id)
    if not queue_name or not item then
        return "Could not find queue item. Check the workspace directory: " .. workspace_dir(project)
    end

    if queue_name == "implemented" then
        return "Item is already in implemented. Use advance_to_history() to complete it, or rewind_item() to move it back."
    end
    if queue_name == "history" then
        return "Item is already in history. Use rewind_item() to move it back."
    end

    local updates = {} ---@type table<string, any>
    if summary then
        updates.history_summary = summary
    end
    if commits then
        updates.history_commits = commits
    end

    if next(updates) then
        self.app.queue:update_item(project, item_id, updates)
    end

    local next_queue = self.app.queue:advance(project, item_id)
    if not next_queue then
        return "Failed to advance item. Check the workspace directory: " .. workspace_dir(project)
    end

    self:touch_and_refresh(project)
    local next_hint = next_queue == "implemented" and
        "\n\nThe item is now in implemented. After reviewing, use advance_to_history() to complete it or rewind_item() if it needs more work." or ""
    return ("Advanced `%s` to `%s`. %s%s"):format(item.title, next_queue, self:queued_summary(project), next_hint)
end

--- Completes an item by advancing it from implemented to history with summary and commits.
--- Use this when an item is fully resolved.
---@param project Clodex.Project
---@param item_id string
---@param summary? string
---@param commits? string[]
---@return string # Guidance text
function QueueCycle:advance_to_history(project, item_id, summary, commits)
    local queue_name, _, item = self.app.queue:find_item(project, item_id)
    if not queue_name or not item then
        return "Could not find queue item. Check the workspace directory: " .. workspace_dir(project)
    end

    if queue_name ~= "implemented" then
        return ("Item `%s` is in `%s`, not implemented. Use advance_item() first."):format(item.title, queue_name)
    end

    self.app.queue:update_item(project, item_id, {
        history_summary = summary or "Completed",
        history_commits = commits or {},
        history_completed_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    })

    local next_queue = self.app.queue:advance(project, item_id)
    if not next_queue then
        return "Failed to advance item to history. Check the workspace directory: " .. workspace_dir(project)
    end

    self:touch_and_refresh(project)
    return ("Completed `%s`. Moved to history. %s"):format(item.title, self:queued_summary(project))
end

--- Rewinds an item back to its previous queue. For implemented/history items, clears history fields.
---@param project Clodex.Project
---@param item_id string
---@param opts? { note?: string, mark_not_working?: boolean, copy?: boolean }
---@return string # Guidance text
function QueueCycle:rewind_item(project, item_id, opts)
    opts = opts or {}
    local queue_name, _, item = self.app.queue:find_item(project, item_id)
    if not queue_name or not item then
        return "Could not find queue item. Check the workspace directory: " .. workspace_dir(project)
    end

    local prev_map = {
        queued = "planned",
        implemented = "queued",
        history = "implemented",
    }
    local prev = prev_map[queue_name]
    if not prev then
        return ("Item `%s` is in `%s` and cannot be rewound further."):format(item.title, queue_name)
    end

    if opts.mark_not_working then
        self.app.queue_actions:rewind_queue_item(project, item_id, {
            mark_not_working = true,
            note = opts.note,
            copy = opts.copy,
        })
    else
        if queue_name == "implemented" or queue_name == "history" then
            self.app.queue:update_item(project, item_id, {
                history_summary = false,
                history_commits = false,
                history_completed_at = false,
            })
        end
        if opts.copy then
            self.app.queue:put_item(project, prev, item, { copy = true })
        else
            self.app.queue:take_item(project, item_id, queue_name)
            self.app.queue:put_item(project, prev, item, {})
        end
    end

    self:touch_and_refresh(project)
    local reason = opts.mark_not_working and " Marked as not working." or ""
    return ("Rewound `%s` to `%s`.%s %s"):format(item.title, prev, reason, self:queued_summary(project))
end

--- Returns guidance for continuing to the next queued item.
--- Use this after completing an item to know what to work on next.
---@param project Clodex.Project
---@return string # Guidance text
function QueueCycle:next_item_guidance(project)
    local queues = self.app.queue:queues(project)
    if not queues or not queues.queued or #queues.queued == 0 then
        return "All queued items completed. No more work in the queue."
    end

    local next_item = queues.queued[1]
    local requires_commit = Prompt.categories.requires_commit(next_item.kind)
    local commit_note = requires_commit and
        "\n\nNote: this prompt kind requires a commit. After working on it, use advance_to_history() with the commit hash." or ""

    return table.concat({
        ("Next queued item: `%s`"):format(next_item.title),
        ("Kind: `%s`"):format(next_item.kind),
        ("Queue item id: `%s`"):format(next_item.id),
        ("Workspace: " .. workspace_dir(project)),
        commit_note,
        "",
        "Work on this item, then advance it using advance_to_history().",
    }, "\n")
end

---@param project Clodex.Project
function QueueCycle:touch_and_refresh(project)
    self.app.project_details_store:touch_activity(project)
    self.app.queue_actions:remember_workspace_revision(project)
    self.app:refresh_views()
end

return QueueCycle
