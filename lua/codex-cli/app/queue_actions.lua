local notify = require("codex-cli.util.notify")

--- Moves/restricts options for queue rewind operations in queue actions.
--- The options are interpreted by App-level handlers when items are moved backward.
---@alias CodexCli.AppQueueActions.RewindOpts { copy?: boolean }
--- Defines options for moving an item between queues and projects.
--- It supports optional duplication and destination queue override for bulk workflows.
--- Moves/restricts options for queue item transfer operations.
--- It is used by project-to-project and adjacent project move handlers.

--- Defines the CodexCli.AppQueueActions.MoveOpts type for this module.
--- This annotation documents structured state so modules can pass data with consistent expectations.
---@alias CodexCli.AppQueueActions.MoveOpts { target_queue?: CodexCli.QueueName, copy?: boolean }

--- Defines the CodexCli.AppQueueActions type for this module.
--- This annotation documents structured state so modules can pass data with consistent expectations.
---@class CodexCli.AppQueueActions
---@field app CodexCli.App
local QueueActions = {}
QueueActions.__index = QueueActions

local PREVIOUS_QUEUE = {
  queued = "planned",
  history = "queued",
}

--- Creates a new app queue actions instance from this module.
--- It is used by callers to bootstrap module state before running higher-level plugin actions.
---@param app CodexCli.App
---@return CodexCli.AppQueueActions
function QueueActions.new(app)
  return setmetatable({ app = app }, QueueActions)
end

--- Implements the dispatch_item path for app queue actions.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param project CodexCli.Project
---@param item CodexCli.QueueItem
---@return boolean
function QueueActions:dispatch_item(project, item)
  local session = self.app.terminals:ensure_project_session(project)
  if not session then
    notify.warn(("Could not start a Codex session for %s"):format(project.name))
    return false
  end

  self.app.execution:clear_receipt(project, item)
  if not session:send(self.app.execution:dispatch_prompt(project, item)) then
    return false
  end
  self.app:touch_project_activity(project)
  return true
end

--- Checks queued items for completion receipts and updates queue/history state.
--- It runs as a polling loop and refreshes UI state when any queued item finishes.
function QueueActions:poll_prompt_execution_receipts()
  local changed = false
  for _, project in ipairs(self.app.registry:list()) do
    for _, item in ipairs(self.app.queue:queues(project).queued) do
      local receipt = self.app.execution:read_receipt(project, item)
      if receipt then
        self.app.queue:complete_queued_item(project, item.id, receipt)
        self.app.execution:clear_receipt(project, item)
        notify.notify(("Prompt completed for %s: %s"):format(project.name, item.title))
        changed = true
      end
    end
  end

  if changed then
    self.app:refresh_state_preview()
  end
end

--- Adds a new app queue actions entry and keeps related state aligned.
--- This function feeds the same workflow used by interactive and scripted callers.
---@param project CodexCli.Project
---@param spec CodexCli.AppPromptActions.AddTodoSpec
function QueueActions:add_project_todo(project, spec)
  local title = vim.trim(spec.title or "")
  if title == "" then
    notify.warn("Todo title is required")
    return
  end

  local normalized = self.app:normalize_prompt_spec(project, {
    title = title,
    details = spec.details,
  })
  self.app.queue:add_todo(project, {
    title = normalized.title,
    details = normalized.details,
    kind = spec.kind,
    image_path = spec.image_path,
  })
  notify.notify(("Added todo to %s: %s"):format(project.name, normalized.title))
  self.app:refresh_state_preview()
end

--- Implements the edit_queue_item path for app queue actions.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param project CodexCli.Project
---@param item_id string
---@param spec { title: string, details?: string }
function QueueActions:edit_queue_item(project, item_id, spec)
  local title = vim.trim(spec.title or "")
  if title == "" then
    notify.warn("Todo title is required")
    return
  end

  local normalized = self.app:normalize_prompt_spec(project, {
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

  self.app.execution:clear_receipt(project, item)
  notify.notify(("Updated prompt for %s: %s"):format(project.name, item.title))
  self.app:refresh_state_preview()
end

--- Implements the implement_queue_item path for app queue actions.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param project CodexCli.Project
---@param item_id string
function QueueActions:implement_queue_item(project, item_id)
  local queue_name, _, item = self.app.queue:find_item(project, item_id)
  if queue_name ~= "queued" or not item then
    notify.warn("Only queued items can be implemented")
    return
  end

  if self:dispatch_item(project, item) then
    notify.notify(("Implemented queued prompt for %s: %s"):format(project.name, item.title))
    self.app:refresh_state_preview()
  end
end

--- Implements the implement_queued_items path for app queue actions.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param project CodexCli.Project
function QueueActions:implement_queued_items(project)
  local queued_items = self.app.queue:queues(project).queued
  if #queued_items == 0 then
    notify.warn(("No queued items for %s"):format(project.name))
    return
  end

  local sent = 0
  for _, item in ipairs(queued_items) do
    if self:dispatch_item(project, item) then
      sent = sent + 1
    end
  end

  if sent > 0 then
    notify.notify(("Implemented %d queued prompt(s) for %s"):format(sent, project.name))
    self.app:refresh_state_preview()
  end
end

--- Implements the implement_next_queued_item path for app queue actions.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param opts? CodexCli.AppPromptActions.ResolveOpts
function QueueActions:implement_next_queued_item(opts)
  self.app:pick_or_run_todo_project(self.app:resolve_todo_project(opts), function(project)
    local next_item = self.app.queue:queues(project).queued[1]
    if not next_item then
      notify.warn(("No queued items for %s"):format(project.name))
      return
    end
    self:implement_queue_item(project, next_item.id)
  end)
end

--- Implements the implement_all_queued_items path for app queue actions.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param opts? CodexCli.AppPromptActions.ResolveOpts
function QueueActions:implement_all_queued_items(opts)
  self.app:pick_or_run_todo_project(self.app:resolve_todo_project(opts), function(project)
    self:implement_queued_items(project)
  end)
end

--- Implements the advance_queue_item path for app queue actions.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param project CodexCli.Project
---@param item_id string
function QueueActions:advance_queue_item(project, item_id)
  local queue_name, _, item = self.app.queue:find_item(project, item_id)
  if not self.app.queue:advance(project, item_id) then
    notify.warn("Item cannot be moved further")
    return
  end
  if queue_name == "queued" and item then
    self.app.execution:clear_receipt(project, item)
  end
  self.app:refresh_state_preview()
end

--- Implements the rewind_queue_item path for app queue actions.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param project CodexCli.Project
---@param item_id string
---@param opts? CodexCli.AppQueueActions.RewindOpts
function QueueActions:rewind_queue_item(project, item_id, opts)
  opts = opts or {}
  local queue_name, _, item = self.app.queue:find_item(project, item_id)
  local previous_queue = queue_name and PREVIOUS_QUEUE[queue_name] or nil
  if not previous_queue or not item then
    notify.warn("Item cannot be moved back")
    return
  end
  if queue_name == "queued" then
    self.app.execution:clear_receipt(project, item)
  end

  if opts.copy then
    self.app.queue:put_item(project, previous_queue, item, {
      copy = true,
      clear_history = queue_name == "history",
    })
  else
    if not self.app.queue:take_item(project, item_id) then
      notify.warn("Queue item not found")
      return
    end
    self.app.queue:put_item(project, previous_queue, item, {
      clear_history = queue_name == "history",
    })
  end

  self.app:refresh_state_preview()
end

--- Implements the move_queue_item_to_project path for app queue actions.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param project CodexCli.Project
---@param item_id string
---@param target_project CodexCli.Project
---@param opts? CodexCli.AppQueueActions.MoveOpts
function QueueActions:move_queue_item_to_project(project, item_id, target_project, opts)
  opts = opts or {}
  local queue_name, _, item = self.app.queue:find_item(project, item_id)
  local target_queue = opts.target_queue or queue_name
  if not queue_name or not target_queue or not item then
    notify.warn("Queue item not found")
    return
  end
  if queue_name == "queued" then
    self.app.execution:clear_receipt(project, item)
  end

  if not opts.copy and not self.app.queue:take_item(project, item_id) then
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
  self.app:refresh_state_preview()
end

--- Implements the delete_queue_item path for app queue actions.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param project CodexCli.Project
---@param item_id string
function QueueActions:delete_queue_item(project, item_id)
  local _, _, item = self.app.queue:find_item(project, item_id)
  if not self.app.queue:delete_item(project, item_id) then
    notify.warn("Queue item not found")
    return
  end
  if item then
    self.app.execution:clear_receipt(project, item)
  end
  self.app:refresh_state_preview()
end

return QueueActions
