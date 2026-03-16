local Category = require("clodex.prompt.category")
local fs = require("clodex.util.fs")
local util = require("clodex.util")

--- Queue names represent the supported lanes for prompt entries: planned, queued, and history.
--- They are used by persistence and queue transitions to coordinate scheduling and history visibility.
---@alias Clodex.QueueName "planned"|"queued"|"history"

--- Canonical representation of one queued prompt item.
--- Entries are written to and loaded from per-project workspace storage.
--- This type tracks queue position metadata needed by action handlers and UI rendering.
---@class Clodex.QueueItem
---@field id string
---@field kind Clodex.PromptCategory
---@field title string
---@field details? string
---@field prompt string
---@field image_path? string
---@field created_at string
---@field updated_at string
---@field history_summary? string
---@field history_commit? string
---@field history_completed_at? string

--- Full persisted queue payload for a single project root.
---@class Clodex.ProjectQueueData
---@field version integer
---@field queues table<Clodex.QueueName, Clodex.QueueItem[]>

--- Human-friendly queue summary assembled for UI and project-level diagnostics.
--- It contains both aggregate counts and full queue contents.
---@class Clodex.ProjectQueueSummary
---@field project Clodex.Project
---@field session_running boolean
---@field counts table<Clodex.QueueName, integer>
---@field queues table<Clodex.QueueName, Clodex.QueueItem[]>

---@class Clodex.Workspace.Queue
---@field root_dir string
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
local DEFAULT_DATA = {
  version = 1,
  queues = {
    planned = {},
    queued = {},
    history = {},
  },
}

local function is_absolute_path(path)
  path = fs.normalize(path)
  return vim.startswith(path, "/") or path:match("^%a:[/\\]") ~= nil
end

local function project_storage_dir(root_dir, project_root)
  local normalized = fs.normalize(root_dir)
  if is_absolute_path(normalized) then
    return normalized
  end
  return fs.join(project_root, normalized)
end

local function legacy_global_storage_dir()
  return fs.join(vim.fn.stdpath("data"), "clodex", "workspaces")
end

local function workspace_path(root_dir, project_root)
  root_dir = project_storage_dir(root_dir, project_root)
  local id = vim.fn.sha256(fs.normalize(project_root)):sub(1, 16)
  return fs.join(root_dir, id .. ".json")
end

---@param root_dir string
---@param project_root string
---@param current_path string
---@return string?
local function renamed_local_workspace_path(root_dir, project_root, current_path)
  local storage_dir = project_storage_dir(root_dir, project_root)
  if not fs.is_dir(storage_dir) then
    return
  end

  local matches = {} ---@type string[]
  for _, entry in ipairs(vim.fn.readdir(storage_dir)) do
    if entry:sub(-5) == ".json" then
      local candidate = fs.join(storage_dir, entry)
      if candidate ~= current_path and fs.is_file(candidate) then
        matches[#matches + 1] = candidate
      end
    end
  end

  if #matches == 1 then
    return matches[1]
  end
end

---@param storage_dir string
---@param current_path string
---@return string?
local function unique_workspace_file(storage_dir, current_path)
  if not fs.is_dir(storage_dir) then
    return
  end

  local matches = {} ---@type string[]
  for _, entry in ipairs(vim.fn.readdir(storage_dir)) do
    if entry:sub(-5) == ".json" then
      local candidate = fs.join(storage_dir, entry)
      if candidate ~= current_path and fs.is_file(candidate) then
        matches[#matches + 1] = candidate
      end
    end
  end

  if #matches == 1 then
    return matches[1]
  end
end

local function load_data(root_dir, project_root)
  local path = workspace_path(root_dir, project_root)
  local data = fs.read_json(path, nil)
  if type(data) ~= "table" then
    local legacy_path = workspace_path(legacy_global_storage_dir(), project_root)
    data = fs.read_json(legacy_path, nil)
    if type(data) == "table" and fs.is_file(legacy_path) then
      fs.write_json(path, data)
      fs.remove(legacy_path)
    end
  end
  if type(data) ~= "table" then
    local renamed_path = renamed_local_workspace_path(root_dir, project_root, path)
    if renamed_path then
      data = fs.read_json(renamed_path, nil)
      if type(data) == "table" then
        fs.write_json(path, data)
        fs.remove(renamed_path)
      end
    end
  end
  if type(data) ~= "table" then
    data = vim.deepcopy(DEFAULT_DATA)
  end
  data.version = data.version or DEFAULT_DATA.version
  data.queues = data.queues or {}
  data.queues.planned = data.queues.planned or {}
  data.queues.queued = data.queues.queued or {}
  data.queues.history = data.queues.history or {}
  return data
end

local function save_data(root_dir, project_root, data)
  fs.write_json(workspace_path(root_dir, project_root), data)
end

local function migrate_project_asset(root_dir, project_root, item)
  local image_path = item.image_path
  if not image_path or not fs.is_file(image_path) then
    return false
  end

  local legacy_assets_dirs = {
    fs.join(legacy_global_storage_dir(), "prompt-assets"),
  }
  local is_legacy_asset = false
  for _, legacy_assets_dir in ipairs(legacy_assets_dirs) do
    if fs.is_relative_to(image_path, legacy_assets_dir) then
      is_legacy_asset = true
      break
    end
  end
  if not is_legacy_asset then
    return false
  end

  local category = Category.is_valid(item.kind) and item.kind or "todo"
  local destination = fs.join(project_storage_dir(root_dir, project_root), "prompt-assets", category, fs.basename(image_path))
  if destination == image_path then
    return false
  end

  fs.copy_file(image_path, destination)
  local escaped = vim.pesc(image_path)
  item.image_path = destination
  if item.details then
    item.details = item.details:gsub(escaped, destination)
  end
  if item.prompt then
    item.prompt = item.prompt:gsub(escaped, destination)
  end
  return true
end

local function now()
  return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

---@param value any
---@return boolean
local function has_item_id(value)
  return type(value) == "string" and vim.trim(value) ~= ""
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
---@return Clodex.Workspace.Queue
function Queue.new(root_dir)
  local self = setmetatable({}, Queue)
  self.root_dir = fs.normalize(root_dir)
  return self
end

---@param project Clodex.Project
---@return Clodex.ProjectQueueData
function Queue:load(project)
  local data = load_data(self.root_dir, project.root)
  local changed = false
  for _, queue_name in ipairs(ORDER) do
    for _, item in ipairs(data.queues[queue_name]) do
      if not has_item_id(item.id) then
        item.id = util.uuid_v4()
        changed = true
      end
      item.kind = Category.is_valid(item.kind) and item.kind or "todo"
      changed = migrate_project_asset(self.root_dir, project.root, item) or changed
    end
  end
  if changed then
    self:save(project, data)
  end
  return data
end

---@param project Clodex.Project
---@param data Clodex.ProjectQueueData
function Queue:save(project, data)
  save_data(self.root_dir, project.root, data)
end

---@param project_root string
function Queue:delete_workspace(project_root)
  fs.remove(workspace_path(self.root_dir, project_root))
end

---@param project Clodex.Project
---@return string
function Queue:workspace_path(project)
  return workspace_path(self.root_dir, project.root)
end

---@param project Clodex.Project
---@return string?
function Queue:workspace_revision(project)
  local stat = fs.stat(self:workspace_path(project))
  if not stat or not stat.mtime then
    return nil
  end

  local mtime = stat.mtime
  return ("%s:%s:%s"):format(mtime.sec or 0, mtime.nsec or 0, stat.size or 0)
end

---@param project Clodex.Project
---@param item_id string
---@param expected_queue? Clodex.QueueName
---@return Clodex.QueueName?, integer?, Clodex.QueueItem?
function Queue:find_item(project, item_id, expected_queue)
  local data = self:load(project)
  if expected_queue and not KNOWN_QUEUES[expected_queue] then
    return
  end
  local queues = expected_queue and { expected_queue } or ORDER
  for _, queue_name in ipairs(queues) do
    for index, item in ipairs(data.queues[queue_name]) do
      if item.id == item_id then
        return queue_name, index, item
      end
    end
  end
end

--- Adds a new workspace queue entry and keeps related state aligned.
--- This function feeds the same workflow used by interactive and scripted callers.
---@param project Clodex.Project
---@param spec { title: string, details?: string, queue?: Clodex.QueueName, kind?: Clodex.PromptCategory, image_path?: string }
---@return Clodex.QueueItem
function Queue:add_todo(project, spec)
  local data = self:load(project)
  local timestamp = now()
  local queue_name = KNOWN_QUEUES[spec.queue] and spec.queue or "planned"
  local item = {
    id = util.uuid_v4(),
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

---@param project Clodex.Project
---@param item_id_value string
---@return Clodex.QueueItem?, Clodex.QueueName?
function Queue:take_item(project, item_id_value, expected_queue)
  local data = self:load(project)
  local queues = expected_queue and { expected_queue } or ORDER
  for _, queue_name in ipairs(queues) do
    for index, item in ipairs(data.queues[queue_name]) do
      if item.id == item_id_value then
        table.remove(data.queues[queue_name], index)
        self:save(project, data)
        return item, queue_name
      end
    end
  end
end

---@param project Clodex.Project
---@param queue_name Clodex.QueueName
---@param item Clodex.QueueItem
---@param opts? {
---  copy?: boolean,
---  clear_history?: boolean,
---  history_summary?: string|false,
---  history_commit?: string|false,
---  history_completed_at?: string|false
---  image_path?: string|false
---}
---@return Clodex.QueueItem?
function Queue:put_item(project, queue_name, item, opts)
  if not KNOWN_QUEUES[queue_name] then
    return
  end

  opts = opts or {}
  local data = self:load(project)
  local timestamp = now()
  local moved = vim.deepcopy(item)
  if opts.copy then
    moved.id = util.uuid_v4()
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

---@param project Clodex.Project
---@param item_id_value string
---@param attrs {
---  title?: string,
---  details?: string|false,
---  history_summary?: string|false,
---  history_commit?: string|false,
---  history_completed_at?: string|false,
---  kind?: Clodex.PromptCategory,
---  image_path?: string|false
---}
---@return Clodex.QueueItem?
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

---@param project Clodex.Project
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

---@param project Clodex.Project
---@param item_id string
---@return Clodex.QueueName?
function Queue:advance(project, item_id)
  local queue_name, _, item = self:find_item(project, item_id)
  local next_queue = queue_name and NEXT_QUEUE[queue_name] or nil
  if not next_queue or not item then
    return
  end

  self:take_item(project, item_id, queue_name)
  self:put_item(project, next_queue, item, {
    history_summary = next_queue == "history" and (item.history_summary or "Moved to history") or false,
  })
  return next_queue
end

---@param project Clodex.Project
---@param item_id_value string
---@param result { summary: string, commit?: string, completed_at?: string }
---@return Clodex.QueueItem?
function Queue:complete_queued_item(project, item_id_value, result)
  local queue_name, _, item = self:find_item(project, item_id_value)
  if queue_name ~= "queued" or not item then
    return
  end

  self:take_item(project, item_id_value, queue_name)
  return self:put_item(project, "history", item, {
    history_summary = result.summary,
    history_commit = result.commit or false,
    history_completed_at = result.completed_at or false,
  })
end

---@param project Clodex.Project
---@return table<Clodex.QueueName, Clodex.QueueItem[]>
function Queue:queues(project)
  return self:load(project).queues
end

---@param project Clodex.Project
---@param session_running boolean
---@return Clodex.ProjectQueueSummary
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
