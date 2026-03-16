local History = require("clodex.history")
local notify = require("clodex.util.notify")

--- Moves/restricts options for queue rewind operations in queue actions.
--- The options are interpreted by App-level handlers when items are moved backward.
---@alias Clodex.AppQueueActions.RewindOpts { copy?: boolean, queue?: Clodex.QueueName }
--- Defines options for moving an item between queues and projects.
--- It supports optional duplication and destination queue override for bulk workflows.
--- Moves/restricts options for queue item transfer operations.
--- It is used by project-to-project and adjacent project move handlers.

--- Defines the Clodex.AppQueueActions.MoveOpts type for this module.
--- This annotation documents structured state so modules can pass data with consistent expectations.
---@alias Clodex.AppQueueActions.MoveOpts { target_queue?: Clodex.QueueName, source_queue?: Clodex.QueueName, copy?: boolean }

--- Defines the Clodex.AppQueueActions type for this module.
--- This annotation documents structured state so modules can pass data with consistent expectations.
---@class Clodex.AppQueueActions
---@field app Clodex.App
---@field workspace_revisions table<string, string?>
local QueueActions = {}
QueueActions.__index = QueueActions

---@class Clodex.AppQueueActions.AddTodoOpts
---@field queue? Clodex.QueueName
---@field implement? boolean
---@field run_mode? "interactive"|"exec"

local PREVIOUS_QUEUE = {
  queued = "planned",
  history = "queued",
}

---@param app Clodex.App
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

--- Checks project-local workspace files for external queue updates.
--- This keeps the editor in sync when queued prompts complete by mutating workspace JSON directly.
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
    queue = queue_name,
  })
  History.append_prompt_added(project.name, normalized.title, normalized.details, spec.kind)
  local started = false
  if queue_name == "queued" and opts.implement then
    if opts.run_mode == "exec" then
      started = self:dispatch_item_direct(project, item)
    else
      started = self:dispatch_item(project, item)
    end
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
  self:remember_workspace_revision(project)
  self.app:refresh_views()
end

---@param project Clodex.Project
---@param item_id string
---@return boolean
function QueueActions:implement_queue_item(project, item_id)
  local queue_name, _, item = self.app.queue:find_item(project, item_id)
  if queue_name ~= "queued" or not item then
    notify.warn("Only queued items can be implemented")
    return false
  end

  if self:dispatch_item(project, item) then
    notify.notify(("Implemented queued prompt for %s: %s"):format(project.name, item.title))
    self.app:refresh_views()
    return true
  end

  return false
end

---@param project Clodex.Project
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
      moved = moved + 1
    end
  end

  if moved > 0 then
    notify.notify(("Moved %d planned prompt(s) to queued for %s"):format(moved, project.name))
    self:remember_workspace_revision(project)
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

  if opts.copy then
    self.app.queue:put_item(project, previous_queue, item, {
      copy = true,
      clear_history = queue_name == "history",
    })
  else
    if not self.app.queue:take_item(project, item_id, queue_name) then
      notify.warn("Queue item not found")
      return
    end
    self.app.queue:put_item(project, previous_queue, item, {
      clear_history = queue_name == "history",
    })
  end

  self:remember_workspace_revision(project)
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
  self:remember_workspace_revision(project)
  self:remember_workspace_revision(target_project)
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
