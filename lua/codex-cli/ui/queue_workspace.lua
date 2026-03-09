local ui = require("codex-cli.ui.select")
local notify = require("codex-cli.util.notify")

---@class CodexCli.QueueWorkspace.QueueRow
---@field kind "header"|"item"
---@field text string
---@field queue? CodexCli.QueueName
---@field item? CodexCli.QueueItem

---@class CodexCli.QueueWorkspace
---@field app CodexCli.App
---@field config CodexCli.Config.Values
---@field project_buf? integer
---@field queue_buf? integer
---@field footer_buf? integer
---@field project_win? integer
---@field queue_win? integer
---@field footer_win? integer
---@field focus "projects"|"queue"
---@field project_index integer
---@field queue_index integer
---@field projects CodexCli.Project[]
---@field queue_rows CodexCli.QueueWorkspace.QueueRow[]
---@field queue_item_rows integer[]
local Workspace = {}
Workspace.__index = Workspace

local MAIN_ZINDEX = 55
local FOOTER_ZINDEX = 56
local highlights_ready = false
local QUEUE_LABELS = {
  planned = "Planned",
  queued = "Queued",
  history = "History",
}

local function win_valid(win)
  return win ~= nil and vim.api.nvim_win_is_valid(win)
end

local function buf_valid(buf)
  return buf ~= nil and vim.api.nvim_buf_is_valid(buf)
end

local function clamp(index, max_value)
  if max_value <= 0 then
    return 1
  end
  return math.min(math.max(index, 1), max_value)
end

local function resolve_size(total, value, minimum)
  if value <= 1 then
    return math.max(math.floor(total * value), minimum)
  end
  return math.max(math.floor(value), minimum)
end

local function prompt_queue_label(queue_name)
  return QUEUE_LABELS[queue_name] or queue_name
end

local function ensure_highlights()
  if highlights_ready then
    return
  end
  highlights_ready = true

  vim.api.nvim_set_hl(0, "CodexCliQueueProjectActive", {
    fg = vim.api.nvim_get_hl(0, { name = "Directory", link = false }).fg,
    bold = true,
    default = true,
  })
  vim.api.nvim_set_hl(0, "CodexCliQueueProjectInactive", {
    fg = vim.api.nvim_get_hl(0, { name = "Comment", link = false }).fg,
    italic = true,
    default = true,
  })
  vim.api.nvim_set_hl(0, "CodexCliQueueCounts", {
    fg = vim.api.nvim_get_hl(0, { name = "Identifier", link = false }).fg,
    default = true,
  })
  vim.api.nvim_set_hl(0, "CodexCliQueueHeader", {
    fg = vim.api.nvim_get_hl(0, { name = "Title", link = false }).fg,
    bold = true,
    default = true,
  })
  vim.api.nvim_set_hl(0, "CodexCliQueueItem", {
    fg = vim.api.nvim_get_hl(0, { name = "Normal", link = false }).fg,
    default = true,
  })
  vim.api.nvim_set_hl(0, "CodexCliQueueItemMuted", {
    fg = vim.api.nvim_get_hl(0, { name = "Comment", link = false }).fg,
    default = true,
  })
  vim.api.nvim_set_hl(0, "CodexCliQueueFooter", {
    fg = vim.api.nvim_get_hl(0, { name = "Comment", link = false }).fg,
    default = true,
  })
end

---@param app CodexCli.App
---@param config CodexCli.Config.Values
---@return CodexCli.QueueWorkspace
function Workspace.new(app, config)
  local self = setmetatable({}, Workspace)
  self.app = app
  self.config = config
  self.focus = "projects"
  self.project_index = 1
  self.queue_index = 1
  self.projects = {}
  self.queue_rows = {}
  self.queue_item_rows = {}
  return self
end

---@param config CodexCli.Config.Values
function Workspace:update_config(config)
  self.config = config
end

---@return boolean
function Workspace:is_open()
  return win_valid(self.project_win) and win_valid(self.queue_win) and win_valid(self.footer_win)
end

function Workspace:ensure_buffers()
  local function make_buffer(name)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].buftype = "nofile"
    vim.bo[buf].bufhidden = "wipe"
    vim.bo[buf].swapfile = false
    vim.bo[buf].modifiable = false
    vim.bo[buf].filetype = "codex_cli_queue_workspace"
    vim.api.nvim_buf_set_name(buf, name)
    return buf
  end

  self.project_buf = buf_valid(self.project_buf) and self.project_buf or make_buffer("codex-cli://queue-projects")
  self.queue_buf = buf_valid(self.queue_buf) and self.queue_buf or make_buffer("codex-cli://queue-items")
  self.footer_buf = buf_valid(self.footer_buf) and self.footer_buf or make_buffer("codex-cli://queue-footer")
end

---@return integer, integer, integer, integer, integer, integer
function Workspace:layout()
  local ui_state = vim.api.nvim_list_uis()[1]
  local columns = ui_state and ui_state.width or vim.o.columns
  local lines = ui_state and ui_state.height or vim.o.lines
  local cfg = self.config.queue_workspace
  local width = resolve_size(columns, cfg.width, 72)
  local height = resolve_size(lines, cfg.height, 18)
  local footer_height = math.max(cfg.footer_height, 2)
  local row = math.max(math.floor((lines - height - footer_height - 1) / 2), 1)
  local col = math.max(math.floor((columns - width) / 2), 1)
  local project_width = math.max(math.floor(width * cfg.project_width), 24)
  local queue_width = math.max(width - project_width - 1, 32)
  return row, col, project_width, queue_width, height, footer_height
end

function Workspace:open()
  if self:is_open() then
    self:refresh()
    return
  end

  ensure_highlights()
  self:ensure_buffers()

  local row, col, project_width, queue_width, height, footer_height = self:layout()
  self.project_win = vim.api.nvim_open_win(self.project_buf, true, {
    relative = "editor",
    row = row,
    col = col,
    width = project_width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = " Projects ",
    zindex = MAIN_ZINDEX,
  })
  self.queue_win = vim.api.nvim_open_win(self.queue_buf, false, {
    relative = "editor",
    row = row,
    col = col + project_width + 1,
    width = queue_width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = " Queue ",
    zindex = MAIN_ZINDEX,
  })
  self.footer_win = vim.api.nvim_open_win(self.footer_buf, false, {
    relative = "editor",
    row = row + height + 1,
    col = col,
    width = project_width + queue_width + 1,
    height = footer_height,
    style = "minimal",
    border = "rounded",
    title = " Actions ",
    zindex = FOOTER_ZINDEX,
  })

  self:configure_windows()
  self:attach_keymaps()
  self:refresh(true)
end

function Workspace:configure_windows()
  for _, win in ipairs({ self.project_win, self.queue_win, self.footer_win }) do
    if win_valid(win) then
      vim.wo[win].number = false
      vim.wo[win].relativenumber = false
      vim.wo[win].signcolumn = "no"
      vim.wo[win].foldcolumn = "0"
      vim.wo[win].wrap = false
      vim.wo[win].spell = false
    end
  end

  for _, win in ipairs({ self.project_win, self.queue_win }) do
    if win_valid(win) then
      vim.wo[win].cursorline = true
    end
  end

  if win_valid(self.footer_win) then
    vim.wo[self.footer_win].cursorline = false
  end
end

function Workspace:close()
  for _, win in ipairs({ self.project_win, self.queue_win, self.footer_win }) do
    if win_valid(win) then
      pcall(vim.api.nvim_win_close, win, true)
    end
  end
  self.project_win = nil
  self.queue_win = nil
  self.footer_win = nil
end

function Workspace:attach_keymaps()
  local function map(buf, lhs, rhs)
    vim.keymap.set("n", lhs, rhs, { buffer = buf, nowait = true, silent = true })
  end

  for _, buf in ipairs({ self.project_buf, self.queue_buf }) do
    map(buf, "q", function()
      self:close()
    end)
    map(buf, "<Esc>", function()
      self:close()
    end)
    map(buf, "h", function()
      self:set_focus("projects")
    end)
    map(buf, "<Left>", function()
      self:set_focus("projects")
    end)
    map(buf, "l", function()
      self:set_focus("queue")
    end)
    map(buf, "<Right>", function()
      self:set_focus("queue")
    end)
    map(buf, "k", function()
      self:move_selection(-1)
    end)
    map(buf, "<Up>", function()
      self:move_selection(-1)
    end)
    map(buf, "j", function()
      self:move_selection(1)
    end)
    map(buf, "<Down>", function()
      self:move_selection(1)
    end)
    map(buf, "<CR>", function()
      self:open_selected_project()
    end)
    map(buf, "A", function()
      self:activate_selected_project()
    end)
    map(buf, "a", function()
      self:add_todo()
    end)
    map(buf, "m", function()
      self:move_queue_item()
    end)
    map(buf, "M", function()
      self:move_queue_item_back()
    end)
    map(buf, "p", function()
      self:move_queue_item_to_project()
    end)
    map(buf, "d", function()
      self:delete_queue_item()
    end)
    map(buf, "D", function()
      self:delete_project()
    end)
  end
end

---@param focus "projects"|"queue"
function Workspace:set_focus(focus)
  if focus == "queue" and not self:selected_project() then
    return
  end
  self.focus = focus
  self:apply_focus()
end

function Workspace:apply_focus()
  local win = self.focus == "projects" and self.project_win or self.queue_win
  if win_valid(win) then
    vim.api.nvim_set_current_win(win)
  end
  self:update_cursor()
end

---@return CodexCli.Project?
function Workspace:selected_project()
  return self.projects[self.project_index]
end

function Workspace:update_cursor()
  if win_valid(self.project_win) then
    local row = clamp(self.project_index, #self.projects)
    vim.api.nvim_win_set_cursor(self.project_win, { row, 0 })
  end
  if win_valid(self.queue_win) then
    local selectable = self.queue_item_rows[self.queue_index] or 1
    vim.api.nvim_win_set_cursor(self.queue_win, { selectable, 0 })
  end
end

---@param delta integer
function Workspace:move_selection(delta)
  if self.focus == "projects" then
    if #self.projects == 0 then
      return
    end
    local next_index = clamp(self.project_index + delta, #self.projects)
    if next_index ~= self.project_index then
      self.project_index = next_index
      self.queue_index = 1
      self:refresh()
      return
    end
  else
    if #self.queue_item_rows == 0 then
      return
    end
    self.queue_index = clamp(self.queue_index + delta, #self.queue_item_rows)
  end
  self:update_cursor()
end

---@param initial? boolean
function Workspace:refresh(initial)
  if not self:is_open() then
    return
  end

  self.projects = self.app:projects_for_queue_workspace()
  if #self.projects == 0 then
    self.project_index = 1
    self.queue_index = 1
  else
    self.project_index = clamp(self.project_index, #self.projects)
  end

  self:render_projects()
  self:render_queue()
  self:render_footer()
  if initial then
    self.focus = "projects"
  end
  self:apply_focus()
end

function Workspace:render_projects()
  local lines = {}
  for _, project in ipairs(self.projects) do
    local summary = self.app:queue_summary(project)
    local prefix = summary.session_running and "●" or "//"
    lines[#lines + 1] = string.format(
      "%s %s  P:%d Q:%d H:%d",
      prefix,
      project.name,
      summary.counts.planned,
      summary.counts.queued,
      summary.counts.history
    )
  end

  if #lines == 0 then
    lines = { "No projects configured" }
  end

  vim.bo[self.project_buf].modifiable = true
  vim.api.nvim_buf_set_lines(self.project_buf, 0, -1, false, lines)
  vim.bo[self.project_buf].modifiable = false

  local ns = vim.api.nvim_create_namespace("codex-cli-queue-projects")
  vim.api.nvim_buf_clear_namespace(self.project_buf, ns, 0, -1)
  for index, project in ipairs(self.projects) do
    local hl = self.app:is_project_session_running(project) and "CodexCliQueueProjectActive"
      or "CodexCliQueueProjectInactive"
    vim.api.nvim_buf_set_extmark(self.project_buf, ns, index - 1, 0, {
      end_col = #lines[index],
      hl_group = hl,
    })
    local counts_start = lines[index]:find("P:")
    if counts_start then
      vim.api.nvim_buf_set_extmark(self.project_buf, ns, index - 1, counts_start - 1, {
        end_col = #lines[index],
        hl_group = "CodexCliQueueCounts",
      })
    end
  end
end

function Workspace:render_queue()
  local project = self:selected_project()
  self.queue_rows = {}
  self.queue_item_rows = {}

  local lines = {} ---@type string[]
  if not project then
    lines = { "No project selected" }
  else
    local summary = self.app:queue_summary(project)
    for _, queue_name in ipairs({ "planned", "queued", "history" }) do
      local items = summary.queues[queue_name]
      self.queue_rows[#self.queue_rows + 1] = {
        kind = "header",
        text = string.format("%s (%d)", prompt_queue_label(queue_name), #items),
        queue = queue_name,
      }
      lines[#lines + 1] = self.queue_rows[#self.queue_rows].text

      if #items == 0 then
        self.queue_rows[#self.queue_rows + 1] = {
          kind = "item",
          text = "  (empty)",
          queue = queue_name,
        }
        lines[#lines + 1] = "  (empty)"
      else
        for _, item in ipairs(items) do
          local suffix = queue_name == "history" and ("  [" .. (item.history_summary or "done") .. "]") or ""
          self.queue_rows[#self.queue_rows + 1] = {
            kind = "item",
            text = "  " .. item.title .. suffix,
            queue = queue_name,
            item = item,
          }
          lines[#lines + 1] = "  " .. item.title .. suffix
          self.queue_item_rows[#self.queue_item_rows + 1] = #self.queue_rows
        end
      end

      lines[#lines + 1] = ""
      self.queue_rows[#self.queue_rows + 1] = {
        kind = "header",
        text = "",
      }
    end
  end

  if #self.queue_item_rows == 0 then
    self.queue_index = 1
  else
    self.queue_index = clamp(self.queue_index, #self.queue_item_rows)
  end

  vim.bo[self.queue_buf].modifiable = true
  vim.api.nvim_buf_set_lines(self.queue_buf, 0, -1, false, lines)
  vim.bo[self.queue_buf].modifiable = false

  local ns = vim.api.nvim_create_namespace("codex-cli-queue-items")
  vim.api.nvim_buf_clear_namespace(self.queue_buf, ns, 0, -1)
  for row, item in ipairs(self.queue_rows) do
    if item.text ~= "" then
      local hl = item.kind == "header" and "CodexCliQueueHeader"
        or (item.item and "CodexCliQueueItem" or "CodexCliQueueItemMuted")
      vim.api.nvim_buf_set_extmark(self.queue_buf, ns, row - 1, 0, {
        end_col = #item.text,
        hl_group = hl,
      })
    end
  end
end

function Workspace:render_footer()
  local lines = {
    "Focus: h/l or ←/→   Move: j/k or ↑/↓   Enter: open README + terminal   A: activate session",
    "a: add todo   m/M: move forward/back   p: move project   d: delete item   D: delete project   q: close",
  }
  vim.bo[self.footer_buf].modifiable = true
  vim.api.nvim_buf_set_lines(self.footer_buf, 0, -1, false, lines)
  vim.bo[self.footer_buf].modifiable = false

  local ns = vim.api.nvim_create_namespace("codex-cli-queue-footer")
  vim.api.nvim_buf_clear_namespace(self.footer_buf, ns, 0, -1)
  for row, line in ipairs(lines) do
    vim.api.nvim_buf_set_extmark(self.footer_buf, ns, row - 1, 0, {
      end_col = #line,
      hl_group = "CodexCliQueueFooter",
    })
  end
end

function Workspace:activate_selected_project()
  local project = self:selected_project()
  if not project then
    return
  end
  self.app:activate_project_session(project)
  self:refresh()
end

function Workspace:open_selected_project()
  local project = self:selected_project()
  if not project then
    return
  end
  self:close()
  vim.schedule(function()
    self.app:open_project_workspace_target(project)
  end)
end

---@return CodexCli.QueueItem?, CodexCli.QueueName?
function Workspace:selected_queue_item()
  local row_index = self.queue_item_rows[self.queue_index]
  local row = row_index and self.queue_rows[row_index] or nil
  if not row or not row.item then
    return nil, nil
  end
  return row.item, row.queue
end

function Workspace:add_todo()
  local project = self:selected_project()
  if not project then
    notify.warn("No project selected")
    return
  end

  ui.input({
    prompt = ("Todo title for %s"):format(project.name),
  }, function(title)
    title = title and vim.trim(title) or ""
    if title == "" then
      return
    end

    ui.input({
      prompt = "Todo details (optional)",
    }, function(details)
      self.app:add_project_todo(project, {
        title = title,
        details = details,
      })
      self.queue_index = 1
      self:refresh()
    end)
  end)
end

function Workspace:move_queue_item()
  local project = self:selected_project()
  local item = self:selected_queue_item()
  if not project or not item then
    notify.warn("No queue item selected")
    return
  end
  self.app:advance_queue_item(project, item.id)
  self.queue_index = 1
  self:refresh()
end

function Workspace:move_queue_item_back()
  local project = self:selected_project()
  local item, queue_name = self:selected_queue_item()
  if not project or not item or not queue_name then
    notify.warn("No queue item selected")
    return
  end

  local function move_back(copy)
    self.app:rewind_queue_item(project, item.id, { copy = copy })
    self.queue_index = 1
    self:refresh()
  end

  if queue_name == "history" then
    ui.select({
      { label = "Move back to queued", copy = false },
      { label = "Duplicate back to queued", copy = true },
    }, {
      prompt = ("Move '%s' back"):format(item.title),
      format_item = function(choice)
        return choice.label
      end,
    }, function(choice)
      if choice then
        move_back(choice.copy)
      end
    end)
    return
  end

  move_back(false)
end

function Workspace:move_queue_item_to_project()
  local project = self:selected_project()
  local item, queue_name = self:selected_queue_item()
  if not project or not item or not queue_name then
    notify.warn("No queue item selected")
    return
  end

  self.app.picker:pick({
    prompt = ("Move '%s' to project"):format(item.title),
  }, function(target_project)
    if not target_project then
      return
    end

    local function move_to_project(copy)
      self.app:move_queue_item_to_project(project, item.id, target_project, {
        copy = copy,
      })
      self.queue_index = 1
      self:refresh()
    end

    if queue_name == "history" then
      ui.select({
        { label = "Move history item", copy = false },
        { label = "Duplicate history item", copy = true },
      }, {
        prompt = ("Transfer '%s' to %s"):format(item.title, target_project.name),
        format_item = function(choice)
          return choice.label
        end,
      }, function(choice)
        if choice then
          move_to_project(choice.copy)
        end
      end)
      return
    end

    move_to_project(false)
  end)
end

function Workspace:delete_queue_item()
  local project = self:selected_project()
  local item = self:selected_queue_item()
  if not project or not item then
    notify.warn("No queue item selected")
    return
  end

  ui.confirm(("Delete '%s'?"):format(item.title), function(confirmed)
    if not confirmed then
      return
    end
    self.app:delete_queue_item(project, item.id)
    self.queue_index = 1
    self:refresh()
  end)
end

function Workspace:delete_project()
  local project = self:selected_project()
  if not project then
    notify.warn("No project selected")
    return
  end

  ui.confirm(("Remove project %s?"):format(project.name), function(confirmed)
    if not confirmed then
      return
    end
    self.app:remove_project(project)
    local projects = self.app:projects_for_queue_workspace()
    self.project_index = clamp(self.project_index, #projects)
    self.queue_index = 1
    self:refresh()
  end)
end

return Workspace
