local Store = require("codex-cli.workspace.store")
local Category = require("codex-cli.prompt.category")

---@alias CodexCli.QueueName "planned"|"queued"|"history"

---@class CodexCli.QueueItem
---@field id string
---@field kind CodexCli.PromptCategory
---@field title string
---@field details? string
---@field prompt string
---@field image_path? string
---@field created_at string
---@field updated_at string
---@field history_summary? string
---@field history_commit? string
---@field history_completed_at? string

---@class CodexCli.ProjectQueueData
---@field version integer
---@field queues table<CodexCli.QueueName, CodexCli.QueueItem[]>

---@class CodexCli.ProjectQueueSummary
---@field project CodexCli.Project
---@field session_running boolean
---@field counts table<CodexCli.QueueName, integer>
---@field queues table<CodexCli.QueueName, CodexCli.QueueItem[]>

---@class CodexCli.Workspace.Queue
---@field store CodexCli.Workspace.Store
local Queue = {}
Queue.__index = Queue

local ORDER = { "planned", "queued", "history" }
local NEXT_QUEUE = {
  planned = "queued",
  queued = "history",
}
local KNOWN_QUEUES = {
  planned = true,
  queued = true,
  history = true,
}

local function now()
  return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

---@param project_root string
---@param title string
---@param timestamp string
---@param seed? string
---@return string
local function item_id(project_root, title, timestamp, seed)
  return vim.fn.sha256(project_root .. "\n" .. timestamp .. "\n" .. title .. "\n" .. (seed or "")):sub(1, 16)
end

---@param title string
---@param details? string
---@return string
local function render_prompt(title, details)
  local lines = { title }
  if details and details ~= "" then
    lines[#lines + 1] = ""
    lines[#lines + 1] = details
  end
  return table.concat(lines, "\n")
end

---@param root_dir string
---@return CodexCli.Workspace.Queue
function Queue.new(root_dir)
  local self = setmetatable({}, Queue)
  self.store = Store.new(root_dir)
  return self
end

---@param project CodexCli.Project
---@return CodexCli.ProjectQueueData
function Queue:load(project)
  local data = self.store:load(project.root)
  for _, queue_name in ipairs(ORDER) do
    for _, item in ipairs(data.queues[queue_name]) do
      item.kind = Category.is_valid(item.kind) and item.kind or "todo"
    end
  end
  return data
end

---@param project CodexCli.Project
---@param data CodexCli.ProjectQueueData
function Queue:save(project, data)
  self.store:save(project.root, data)
end

---@param project_root string
function Queue:delete_workspace(project_root)
  self.store:delete(project_root)
end

---@param project CodexCli.Project
---@param item_id string
---@return CodexCli.QueueName?, integer?, CodexCli.QueueItem?
function Queue:find_item(project, item_id)
  local data = self:load(project)
  for _, queue_name in ipairs(ORDER) do
    for index, item in ipairs(data.queues[queue_name]) do
      if item.id == item_id then
        return queue_name, index, item
      end
    end
  end
end

---@param project CodexCli.Project
---@param spec { title: string, details?: string, queue?: CodexCli.QueueName, kind?: CodexCli.PromptCategory, image_path?: string }
---@return CodexCli.QueueItem
function Queue:add_todo(project, spec)
  local data = self:load(project)
  local timestamp = now()
  local queue_name = KNOWN_QUEUES[spec.queue] and spec.queue or "planned"
  local item = {
    id = item_id(project.root, spec.title, timestamp),
    kind = Category.is_valid(spec.kind) and spec.kind or "todo",
    title = vim.trim(spec.title),
    details = spec.details and vim.trim(spec.details) or nil,
    prompt = render_prompt(vim.trim(spec.title), spec.details and vim.trim(spec.details) or nil),
    image_path = spec.image_path and vim.trim(spec.image_path) or nil,
    created_at = timestamp,
    updated_at = timestamp,
  }
  table.insert(data.queues[queue_name], 1, item)
  self:save(project, data)
  return item
end

---@param project CodexCli.Project
---@param item_id_value string
---@return CodexCli.QueueItem?, CodexCli.QueueName?
function Queue:take_item(project, item_id_value)
  local data = self:load(project)
  for _, queue_name in ipairs(ORDER) do
    for index, item in ipairs(data.queues[queue_name]) do
      if item.id == item_id_value then
        table.remove(data.queues[queue_name], index)
        self:save(project, data)
        return item, queue_name
      end
    end
  end
end

---@param project CodexCli.Project
---@param queue_name CodexCli.QueueName
---@param item CodexCli.QueueItem
---@param opts? {
---  copy?: boolean,
---  clear_history?: boolean,
---  history_summary?: string|false,
---  history_commit?: string|false,
---  history_completed_at?: string|false
---  image_path?: string|false
---}
---@return CodexCli.QueueItem?
function Queue:put_item(project, queue_name, item, opts)
  if not KNOWN_QUEUES[queue_name] then
    return
  end

  opts = opts or {}
  local data = self:load(project)
  local timestamp = now()
  local moved = vim.deepcopy(item)
  if opts.copy then
    moved.id = item_id(project.root, moved.title, timestamp, moved.id)
    moved.created_at = timestamp
  end
  moved.updated_at = timestamp
  if opts.clear_history then
    moved.history_summary = nil
    moved.history_commit = nil
    moved.history_completed_at = nil
  end
  if opts.history_summary ~= nil then
    moved.history_summary = opts.history_summary ~= false and opts.history_summary or nil
  end
  if opts.history_commit ~= nil then
    moved.history_commit = opts.history_commit ~= false and opts.history_commit or nil
  end
  if opts.history_completed_at ~= nil then
    moved.history_completed_at = opts.history_completed_at ~= false and opts.history_completed_at or nil
  end
  if opts.image_path ~= nil then
    moved.image_path = opts.image_path ~= false and opts.image_path or nil
  end
  table.insert(data.queues[queue_name], 1, moved)
  self:save(project, data)
  return moved
end

---@param project CodexCli.Project
---@param item_id_value string
---@param attrs {
---  title?: string,
---  details?: string|false,
---  history_summary?: string|false,
---  history_commit?: string|false,
---  history_completed_at?: string|false,
---  kind?: CodexCli.PromptCategory,
---  image_path?: string|false
---}
---@return CodexCli.QueueItem?
function Queue:update_item(project, item_id_value, attrs)
  local data = self:load(project)
  for _, queue_name in ipairs(ORDER) do
    for _, item in ipairs(data.queues[queue_name]) do
      if item.id == item_id_value then
        if attrs.title ~= nil then
          item.title = vim.trim(attrs.title)
        end
        if attrs.details ~= nil then
          item.details = attrs.details ~= false and vim.trim(attrs.details) or nil
        end
        if attrs.kind ~= nil and Category.is_valid(attrs.kind) then
          item.kind = attrs.kind
        end
        if attrs.image_path ~= nil then
          item.image_path = attrs.image_path ~= false and attrs.image_path or nil
        end
        if attrs.title ~= nil or attrs.details ~= nil then
          item.prompt = render_prompt(item.title, item.details)
        end
        if attrs.history_summary ~= nil then
          item.history_summary = attrs.history_summary ~= false and attrs.history_summary or nil
        end
        if attrs.history_commit ~= nil then
          item.history_commit = attrs.history_commit ~= false and attrs.history_commit or nil
        end
        if attrs.history_completed_at ~= nil then
          item.history_completed_at = attrs.history_completed_at ~= false and attrs.history_completed_at or nil
        end
        item.updated_at = now()
        self:save(project, data)
        return vim.deepcopy(item)
      end
    end
  end
end

---@param project CodexCli.Project
---@param item_id string
---@return boolean
function Queue:delete_item(project, item_id)
  local data = self:load(project)
  for _, queue_name in ipairs(ORDER) do
    for index, item in ipairs(data.queues[queue_name]) do
      if item.id == item_id then
        table.remove(data.queues[queue_name], index)
        self:save(project, data)
        return true
      end
    end
  end
  return false
end

---@param project CodexCli.Project
---@param item_id string
---@return CodexCli.QueueName?
function Queue:advance(project, item_id)
  local queue_name, _, item = self:find_item(project, item_id)
  local next_queue = queue_name and NEXT_QUEUE[queue_name] or nil
  if not next_queue or not item then
    return
  end

  self:take_item(project, item_id)
  self:put_item(project, next_queue, item, {
    history_summary = next_queue == "history" and (item.history_summary or "Moved to history") or false,
  })
  return next_queue
end

---@param project CodexCli.Project
---@param item_id_value string
---@param result { summary: string, commit?: string, completed_at?: string }
---@return CodexCli.QueueItem?
function Queue:complete_queued_item(project, item_id_value, result)
  local queue_name, _, item = self:find_item(project, item_id_value)
  if queue_name ~= "queued" or not item then
    return
  end

  self:take_item(project, item_id_value)
  return self:put_item(project, "history", item, {
    history_summary = result.summary,
    history_commit = result.commit or false,
    history_completed_at = result.completed_at or false,
  })
end

---@param project CodexCli.Project
---@return table<CodexCli.QueueName, CodexCli.QueueItem[]>
function Queue:queues(project)
  return self:load(project).queues
end

---@param project CodexCli.Project
---@param session_running boolean
---@return CodexCli.ProjectQueueSummary
function Queue:summary(project, session_running)
  local data = self:load(project)
  return {
    project = project,
    session_running = session_running,
    counts = {
      planned = #data.queues.planned,
      queued = #data.queues.queued,
      history = #data.queues.history,
    },
    queues = vim.deepcopy(data.queues),
  }
end

return Queue
