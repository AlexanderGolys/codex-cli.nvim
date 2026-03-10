local ui = require("codex-cli.ui.select")
local Extmark = require("codex-cli.ui.extmark")
local PromptComposer = require("codex-cli.prompt.composer")
local TextBlock = require("codex-cli.ui.text_block")
local PromptHighlight = require("codex-cli.prompt.highlight")
local ui_win = require("codex-cli.ui.win")
local notify = require("codex-cli.util.notify")
local Category = require("codex-cli.prompt.category")

--- Defines the CodexCli.QueueWorkspace.QueueRow type for this module.
--- This annotation documents structured state so modules can pass data with consistent expectations.
---@class CodexCli.QueueWorkspace.QueueRow
---@field kind "header"|"item"|"preview"
---@field text string
---@field queue? CodexCli.QueueName
---@field item? CodexCli.QueueItem

--- Defines the CodexCli.QueueWorkspace.ActionSet type for this module.
--- This annotation documents structured state so modules can pass data with consistent expectations.
---@class CodexCli.QueueWorkspace.ActionSet
---@field title string
---@field lines string[]

--- Defines the CodexCli.QueueWorkspace.ProjectRow type for this module.
--- This annotation documents structured state so modules can pass data with consistent expectations.
---@class CodexCli.QueueWorkspace.ProjectRow
---@field kind "item"|"detail"
---@field text string
---@field project? CodexCli.Project

--- Defines the CodexCli.QueueWorkspace type for this module.
--- This annotation documents structured state so modules can pass data with consistent expectations.
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
---@field project_rows CodexCli.QueueWorkspace.ProjectRow[]
---@field project_item_rows integer[]
---@field queue_rows CodexCli.QueueWorkspace.QueueRow[]
---@field queue_item_rows integer[]
local Workspace = {}
Workspace.__index = Workspace

local MAIN_ZINDEX = 55
local FOOTER_ZINDEX = 56
local PROJECT_NS = vim.api.nvim_create_namespace("codex-cli-queue-projects")
local QUEUE_NS = vim.api.nvim_create_namespace("codex-cli-queue-items")
local FOOTER_NS = vim.api.nvim_create_namespace("codex-cli-queue-footer")
local QUEUE_LABELS = {
  planned = "Planned",
  queued = "Queued",
  history = "History",
}
local ITEM_TITLE_PREFIX_WIDTH = 2

--- Implements the win_valid path for ui queue workspace.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
local function win_valid(win)
  return win ~= nil and vim.api.nvim_win_is_valid(win)
end

--- Implements the buf_valid path for ui queue workspace.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
local function buf_valid(buf)
  return buf ~= nil and vim.api.nvim_buf_is_valid(buf)
end

--- Implements the clamp path for ui queue workspace.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
local function clamp(index, max_value)
  if max_value <= 0 then
    return 1
  end
  return math.min(math.max(index, 1), max_value)
end

--- Implements the row_index path for ui queue workspace.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param line integer
---@param rows integer[]
---@return integer?
local function row_index(line, rows)
  for index, first_row in ipairs(rows) do
    local next_row = rows[index + 1] or math.huge
    if line >= first_row and line < next_row then
      return index
    end
  end
  return nil
end

--- Implements the resolve_size path for ui queue workspace.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
local function resolve_size(total, value, minimum)
  if value <= 1 then
    return math.max(math.floor(total * value), minimum)
  end
  return math.max(math.floor(value), minimum)
end

--- Implements the selection_marks path for ui queue workspace.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param first_row integer
---@param last_row integer
---@param hl_group string
---@return CodexCli.Extmark[]
local function selection_marks(first_row, last_row, hl_group)
  local marks = {} ---@type CodexCli.Extmark[]
  for row = first_row, last_row do
    marks[#marks + 1] = Extmark.line(row - 1, hl_group)
  end
  return marks
end

--- Implements the prompt_queue_label path for ui queue workspace.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
local function prompt_queue_label(queue_name)
  return QUEUE_LABELS[queue_name] or queue_name
end

--- Implements the prompt_item_kind path for ui queue workspace.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param item CodexCli.QueueItem
---@return CodexCli.PromptCategory
local function prompt_item_kind(item)
  return Category.get(item.kind).id
end

--- Implements the prompt_preview_lines path for ui queue workspace.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param item CodexCli.QueueItem
---@param opts? { max_lines?: integer, fold?: boolean }
---@return string[]
local function prompt_preview_lines(item, opts)
  opts = opts or {}
  local preview = {} ---@type string[]
  local lines = vim.split(item.prompt or "", "\n", { plain = true })
  local max_lines = math.max(tonumber(opts.max_lines) or 3, 1)
  local folded = opts.fold ~= false
  local remaining = 0
  local skipped_title = false
  for _, line in ipairs(lines) do
    line = vim.trim(line)
    if line ~= "" then
      if not skipped_title then
        skipped_title = true
        goto continue
      end
      if #preview >= max_lines then
        remaining = remaining + 1
      else
        preview[#preview + 1] = "    " .. line
      end
    end
    ::continue::
  end

  if folded and remaining > 0 then
    if #preview >= max_lines then
      preview[#preview] = ("    ... (+%d more line%s)"):format(
        remaining + 1,
        remaining == 0 and "" or "s"
      )
    else
      preview[#preview + 1] = ("    ... (+%d more line%s)"):format(remaining, remaining == 1 and "" or "s")
    end
  else
    while #preview > max_lines do
      preview[#preview] = nil
    end
  end

  return preview
end

--- Implements the queue_header_groups path for ui queue workspace.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param queue_name CodexCli.QueueName
---@return string, string, string
local function queue_header_groups(queue_name)
  local map = {
    planned = {
      "CodexCliQueueTodoName",
      "CodexCliQueueTodoBracket",
      "CodexCliQueueTodoCount",
    },
    queued = {
      "CodexCliQueueQueuedName",
      "CodexCliQueueQueuedBracket",
      "CodexCliQueueQueuedCount",
    },
    history = {
      "CodexCliQueueHistoryName",
      "CodexCliQueueHistoryBracket",
      "CodexCliQueueHistoryCount",
    },
  }
  local groups = map[queue_name] or map.planned
  return groups[1], groups[2], groups[3]
end

--- Implements the queue_header_line path for ui queue workspace.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param queue_name CodexCli.QueueName
---@param count integer
---@return string, CodexCli.Extmark[]
local function queue_header_line(queue_name, count)
  local label = prompt_queue_label(queue_name)
  local text = ("%s (%d)"):format(label, count)
  local name_hl, bracket_hl, count_hl = queue_header_groups(queue_name)
  local marks = {
    Extmark.inline(0, 0, #label, name_hl),
    Extmark.inline(0, #label, #label + 2, bracket_hl),
    Extmark.inline(0, #label + 2, #label + 2 + #tostring(count), count_hl),
    Extmark.inline(0, #label + 2 + #tostring(count), #text, bracket_hl),
  }
  return text, marks
end

--- Implements the footer_actions path for ui queue workspace.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param focus "projects"|"queue"
---@return CodexCli.QueueWorkspace.ActionSet
local function footer_actions(focus)
  if focus == "projects" then
    return {
      title = " Project Actions ",
      lines = {
        "Focus: h/l or Left/Right   Move: j/k or Up/Down   Enter: open README + terminal   q: close",
        "s: set current project   A: start session   X: stop session   a: add prompt   D: delete project",
        "&: insert editor context in prompt editor   x: canned prompt in prompt editor",
      },
    }
  end

  return {
    title = " Queue Actions ",
    lines = {
      "Focus: h/l or Left/Right   Move: j/k or Up/Down   Enter: open README + terminal   q: close",
      "a: add prompt   e: edit prompt   i/I: implement one/all queued   m/M: move forward/back",
      "p: move project   H/L: prev/next project   d: delete item   &: context   x: canned prompt   Ctrl-S: save",
    },
  }
end

--- Implements the should_render_queue path for ui queue workspace.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param _queue_name CodexCli.QueueName
---@param items CodexCli.QueueItem[]
---@return boolean
local function should_render_queue(_queue_name, items)
  return #items > 0
end

--- Implements the footer_text path for ui queue workspace.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param text string
---@return string
local function footer_text(text)
  return text:gsub("Left/Right", "←/→"):gsub("Up/Down", "↑/↓")
end

--- Implements the history_suffix path for ui queue workspace.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param item CodexCli.QueueItem
---@return string
local function history_suffix(item)
  local parts = {} ---@type string[]
  if item.history_summary and item.history_summary ~= "" then
    parts[#parts + 1] = item.history_summary
  end
  if item.history_commit and item.history_commit ~= "" then
    parts[#parts + 1] = item.history_commit
  end
  return #parts > 0 and ("  [" .. table.concat(parts, " | ") .. "]") or ""
end

--- Implements the queue_kind_counts path for ui queue workspace.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param items CodexCli.QueueItem[]
---@return table<CodexCli.PromptCategory, integer>
local function queue_kind_counts(items)
  local counts = {} ---@type table<CodexCli.PromptCategory, integer>
  for _, item in ipairs(items) do
    local kind = prompt_item_kind(item)
    counts[kind] = (counts[kind] or 0) + 1
  end
  return counts
end

--- Implements the format_timestamp path for ui queue workspace.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param timestamp? integer
---@return string
local function format_timestamp(timestamp)
  if not timestamp or timestamp <= 0 then
    return "-"
  end
  return os.date("%Y-%m-%d %H:%M", timestamp)
end

--- Implements the format_languages path for ui queue workspace.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param languages CodexCli.ProjectDetails.LanguageStat[]
---@return string
local function format_languages(languages)
  if #languages == 0 then
    return "-"
  end

  local parts = {} ---@type string[]
  local max_items = 3
  for index, language in ipairs(languages) do
    if index > max_items then
      break
    end
    parts[#parts + 1] = ("%s %d%%"):format(language.name, language.percent)
  end
  if #languages > max_items then
    parts[#parts + 1] = ("+%d"):format(#languages - max_items)
  end
  return table.concat(parts, ", ")
end

--- Implements the format_avg_lines path for ui queue workspace.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param value? number
---@return string
local function format_avg_lines(value)
  if not value then
    return "-"
  end
  return ("%.1f"):format(value)
end

--- Implements the project_detail_lines path for ui queue workspace.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param app CodexCli.App
---@param summary CodexCli.ProjectQueueSummary
---@return string[]
local function project_detail_lines(app, summary)
  local details = app:project_details(summary.project)
  return {
    ("    Files:%d  Avg LOC:%s  Remote:%s  Codex:%s"):format(
      details.file_count,
      format_avg_lines(details.avg_code_lines_per_file),
      details.remote_name or "-",
      format_timestamp(details.last_codex_activity_at)
    ),
    ("    Lang:%s  Mod:%s"):format(
      format_languages(details.languages),
      format_timestamp(details.last_file_modified_at)
    ),
  }
end

--- Creates a new ui queue workspace instance from this module.
--- It is used by callers to bootstrap module state before running higher-level plugin actions.
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
  self.project_rows = {}
  self.project_item_rows = {}
  self.queue_rows = {}
  self.queue_item_rows = {}
  return self
end

--- Implements the update_config path for ui queue workspace.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param config CodexCli.Config.Values
function Workspace:update_config(config)
  self.config = config
end

--- Focuses a project row by root so selection commands can land on the right entry.
---@param root? string
function Workspace:focus_project(root)
  self.projects = self.app:projects_for_queue_workspace()
  self.project_index = 1
  if root and root ~= "" then
    for index, project in ipairs(self.projects) do
      if project.root == root then
        self.project_index = index
        break
      end
    end
  end
  self.queue_index = 1
  self.focus = "projects"
end

--- Checks a open condition for ui queue workspace.
--- This gate keeps callers safe before continuing higher-level state transitions.
---@return boolean
function Workspace:is_open()
  return win_valid(self.project_win) and win_valid(self.queue_win) and win_valid(self.footer_win)
end

--- Implements the ensure_buffers path for ui queue workspace.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
function Workspace:ensure_buffers()
--- Implements the make_buffer path for ui queue workspace.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
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

  self.project_buf = buf_valid(self.project_buf) and self.project_buf or make_buffer("codex-cli-queue-projects")
  self.queue_buf = buf_valid(self.queue_buf) and self.queue_buf or make_buffer("codex-cli-queue-items")
  self.footer_buf = buf_valid(self.footer_buf) and self.footer_buf or make_buffer("codex-cli-queue-footer")
end

--- Implements the layout path for ui queue workspace.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
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

--- Implements the prompt_title_width path for ui queue workspace.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@return integer
function Workspace:prompt_title_width()
  local queue_width = win_valid(self.queue_win) and vim.api.nvim_win_get_width(self.queue_win) or select(4, self:layout())
  return math.max(queue_width - ITEM_TITLE_PREFIX_WIDTH, 1)
end

--- Opens or activates the selected ui queue workspace target in the workspace.
--- This is used by navigation flows that need to display the most recent selection.
function Workspace:open()
  if self:is_open() then
    self:refresh()
    return
  end

  self:ensure_buffers()

  local row, col, project_width, queue_width, height, footer_height = self:layout()
  self.project_win = ui_win.open({
    buf = self.project_buf,
    enter = true,
    row = row,
    col = col,
    width = project_width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = " Projects ",
    zindex = MAIN_ZINDEX,
  }).win
  self.queue_win = ui_win.open({
    buf = self.queue_buf,
    enter = false,
    row = row,
    col = col + project_width + 1,
    width = queue_width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = " Queue ",
    zindex = MAIN_ZINDEX,
  }).win
  self.footer_win = ui_win.open({
    buf = self.footer_buf,
    enter = false,
    row = row + height + 1,
    col = col,
    width = project_width + queue_width + 1,
    height = footer_height,
    style = "minimal",
    border = "rounded",
    title = footer_actions(self.focus).title,
    zindex = FOOTER_ZINDEX,
  }).win

  self:configure_windows()
  self:attach_keymaps()
  self:refresh(true)
end

--- Implements the configure_windows path for ui queue workspace.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
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
      vim.wo[win].cursorline = false
    end
  end

  if win_valid(self.footer_win) then
    vim.wo[self.footer_win].cursorline = false
  end
  self:update_window_highlights()
end

--- Closes or deactivates ui queue workspace behavior for the current context.
--- This is used by command flows when a view or session should stop being active.
function Workspace:close()
  for _, win in ipairs({ self.project_win, self.queue_win, self.footer_win }) do
    ui_win.close(win)
  end
  self.project_win = nil
  self.queue_win = nil
  self.footer_win = nil
end

--- Implements the attach_keymaps path for ui queue workspace.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
function Workspace:attach_keymaps()
--- Implements the map path for ui queue workspace.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
  local function map(buf, lhs, rhs)
    vim.keymap.set("n", lhs, rhs, { buffer = buf, nowait = true, silent = true })
  end

--- Implements the project_click path for ui queue workspace.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
  local function project_click(confirm)
    local mouse = vim.fn.getmousepos()
    if mouse.winid ~= self.project_win then
      return
    end
    local index = row_index(mouse.line, self.project_item_rows)
    if not index then
      return
    end
    self.project_index = index
    self.queue_index = 1
    self:set_focus("projects")
    self:refresh()
    if confirm then
      self:open_selected_project()
    end
  end

--- Implements the queue_click path for ui queue workspace.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
  local function queue_click(confirm)
    local mouse = vim.fn.getmousepos()
    if mouse.winid ~= self.queue_win then
      return
    end
    local index = row_index(mouse.line, self.queue_item_rows)
    if not index then
      return
    end
    self.queue_index = index
    self:set_focus("queue")
    self:update_cursor()
    self:render_footer()
    if confirm then
      self:open_selected_project()
    end
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
    map(buf, "s", function()
      self:set_current_project()
    end)
    map(buf, "A", function()
      self:activate_selected_project()
    end)
    map(buf, "X", function()
      self:deactivate_selected_project()
    end)
    map(buf, "a", function()
      self:add_todo()
    end)
    map(buf, "e", function()
      self:edit_queue_item()
    end)
    map(buf, "i", function()
      self:implement_queue_item()
    end)
    map(buf, "I", function()
      self:implement_queued_items()
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
    map(buf, "H", function()
      self:move_queue_item_to_adjacent_project(-1)
    end)
    map(buf, "L", function()
      self:move_queue_item_to_adjacent_project(1)
    end)
    map(buf, "d", function()
      self:delete_queue_item()
    end)
    map(buf, "D", function()
      self:delete_project()
    end)
  end

  map(self.project_buf, "<LeftMouse>", function()
    project_click(false)
  end)
  map(self.project_buf, "<2-LeftMouse>", function()
    project_click(true)
  end)
  map(self.queue_buf, "<LeftMouse>", function()
    queue_click(false)
  end)
  map(self.queue_buf, "<2-LeftMouse>", function()
    queue_click(true)
  end)
end

--- Implements the set_focus path for ui queue workspace.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param focus "projects"|"queue"
function Workspace:set_focus(focus)
  if focus == "queue" and not self:selected_project() then
    return
  end
  self.focus = focus
  self:apply_focus()
end

--- Implements the update_window_highlights path for ui queue workspace.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
function Workspace:update_window_highlights()
--- Implements the apply path for ui queue workspace.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
  local function apply(win, active)
    ui_win.set_focus_border(win, active)
  end

  apply(self.project_win, self.focus == "projects")
  apply(self.queue_win, self.focus == "queue")
  apply(self.footer_win, false)
end

--- Implements the apply_focus path for ui queue workspace.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
function Workspace:apply_focus()
  self:update_window_highlights()
  local win = self.focus == "projects" and self.project_win or self.queue_win
  if win_valid(win) then
    vim.api.nvim_set_current_win(win)
  end
  self:update_cursor()
end

--- Implements the selected_project path for ui queue workspace.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@return CodexCli.Project?
function Workspace:selected_project()
  return self.projects[self.project_index]
end

--- Implements the update_cursor path for ui queue workspace.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
function Workspace:update_cursor()
  if win_valid(self.project_win) then
    local row = self.project_item_rows[self.project_index] or 1
    vim.api.nvim_win_set_cursor(self.project_win, { row, 0 })
  end
  if win_valid(self.queue_win) then
    local selectable = self.queue_item_rows[self.queue_index] or 1
    vim.api.nvim_win_set_cursor(self.queue_win, { selectable, 0 })
  end
end

--- Implements the move_selection path for ui queue workspace.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
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

--- Updates ui queue workspace state after local changes.
--- Higher-level callers use this to keep the UI and terminal state consistent.
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
  if win_valid(self.footer_win) then
    vim.api.nvim_win_set_config(self.footer_win, {
      title = footer_actions(self.focus).title,
      title_pos = "center",
    })
  end
  self:apply_focus()
end

--- Implements the render_projects path for ui queue workspace.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
function Workspace:render_projects()
  self.project_rows = {}
  self.project_item_rows = {}
  local block = TextBlock.new()
  for _, project in ipairs(self.projects) do
    local summary = self.app:queue_summary(project)
    local prefix = summary.session_running and "●" or "//"
    local title = string.format(
      "%s %s  P:%d Q:%d H:%d",
      prefix,
      project.name,
      summary.counts.planned,
      summary.counts.queued,
      summary.counts.history
    )
    self.project_rows[#self.project_rows + 1] = {
      kind = "item",
      text = title,
      project = project,
    }
    self.project_item_rows[#self.project_item_rows + 1] = #self.project_rows
    local item_hl = summary.session_running and "CodexCliQueueProjectActive" or "CodexCliQueueProjectInactive"
    local item_extmarks = {
      Extmark.inline(0, 0, #title, item_hl),
    }
    local counts_start = title:find("P:")
    if counts_start then
      item_extmarks[#item_extmarks + 1] = Extmark.inline(0, counts_start - 1, #title, "CodexCliQueueCounts")
    end
    block:append_line(title, item_extmarks)

    for _, detail in ipairs(project_detail_lines(self.app, summary)) do
      self.project_rows[#self.project_rows + 1] = {
        kind = "detail",
        text = detail,
        project = project,
      }
      block:append_line(detail, {
        Extmark.inline(0, 0, #detail, "CodexCliQueueItemMuted"),
      })
    end
  end

  if block:is_empty() then
    block:append_line("No projects configured")
  end

  local selected_row = self.project_item_rows[self.project_index]
  if selected_row then
    local selected = self.project_rows[selected_row]
    local last_row = selected_row
    while self.project_rows[last_row + 1] and self.project_rows[last_row + 1].project == selected.project do
      last_row = last_row + 1
    end
    block:add_extmarks(selection_marks(selected_row, last_row, "CodexCliQueueSelection"))
  end

  block:render(self.project_buf, PROJECT_NS)
end

--- Implements the render_queue path for ui queue workspace.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
function Workspace:render_queue()
  local project = self:selected_project()
  self.queue_rows = {}
  self.queue_item_rows = {}

  local block = TextBlock.new()
  if not project then
    block:append_line("No project selected")
  else
    local summary = self.app:queue_summary(project)
    for _, queue_name in ipairs({ "planned", "queued", "history" }) do
      local items = summary.queues[queue_name]
      if not should_render_queue(queue_name, items) then
        goto continue
      end

      local header_text, header_marks = queue_header_line(queue_name, #items)
      self.queue_rows[#self.queue_rows + 1] = {
        kind = "header",
        text = header_text,
        queue = queue_name,
      }
      block:append_line(header_text, header_marks)

      for _, item in ipairs(items) do
        local suffix = queue_name == "history" and history_suffix(item) or ""
        local item_text = "  " .. item.title .. suffix
        local title_text = "  " .. item.title
        self.queue_rows[#self.queue_rows + 1] = {
          kind = "item",
          text = item_text,
          queue = queue_name,
          item = item,
        }
        self.queue_item_rows[#self.queue_item_rows + 1] = #self.queue_rows
        local item_extmarks = {
          Extmark.inline(0, 0, #title_text, PromptHighlight.title_group(prompt_item_kind(item), "prompt")),
        }
        if #item_text > #title_text then
          item_extmarks[#item_extmarks + 1] =
            Extmark.inline(0, #title_text, #item_text, "CodexCliQueueItemMuted")
        end
        block:append_line(item_text, item_extmarks)

        for _, preview in ipairs(prompt_preview_lines(item, {
          max_lines = self.config.queue_workspace.preview_max_lines,
          fold = self.config.queue_workspace.fold_preview,
        })) do
          self.queue_rows[#self.queue_rows + 1] = {
            kind = "preview",
            text = preview,
            queue = queue_name,
            item = item,
          }
          block:append_line(preview, {
            Extmark.inline(0, 0, #preview, PromptHighlight.preview_group()),
          })
        end
      end

      block:append_line("")
      self.queue_rows[#self.queue_rows + 1] = {
        kind = "header",
        text = "",
      }
      ::continue::
    end

    if block:is_empty() then
      block:append_line("No prompts queued for this project", {
        Extmark.inline(0, 0, #"No prompts queued for this project", "CodexCliQueueItemMuted"),
      })
    end
  end

  if #self.queue_item_rows == 0 then
    self.queue_index = 1
  else
    self.queue_index = clamp(self.queue_index, #self.queue_item_rows)
  end

  local selected_row = self.queue_item_rows[self.queue_index]
  if selected_row then
    local item = self.queue_rows[selected_row]
    if item and item.item then
      local last_row = selected_row
      while self.queue_rows[last_row + 1] and self.queue_rows[last_row + 1].item == item.item do
        last_row = last_row + 1
      end
      block:add_extmarks(selection_marks(selected_row, last_row, "CodexCliQueueSelection"))
    end
  end

  block:render(self.queue_buf, QUEUE_NS)
end

--- Implements the render_footer path for ui queue workspace.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
function Workspace:render_footer()
  local action_set = footer_actions(self.focus)
  local block = TextBlock.new()
  for _, line in ipairs(action_set.lines) do
    line = footer_text(line)
    block:append_line(line, {
      Extmark.inline(0, 0, #line, "CodexCliQueueFooter"),
    })
  end
  block:render(self.footer_buf, FOOTER_NS)
end

--- Implements the activate_selected_project path for ui queue workspace.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
function Workspace:activate_selected_project()
  local project = self:selected_project()
  if not project then
    return
  end
  self.app:activate_project_session(project)
  self:refresh()
end

--- Implements the deactivate_selected_project path for ui queue workspace.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
function Workspace:deactivate_selected_project()
  local project = self:selected_project()
  if not project then
    return
  end
  self.app:deactivate_project_session(project)
  self:refresh()
end

--- Implements the open_selected_project path for ui queue workspace.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
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

--- Pins the selected project as the current project for the active tab.
--- This reuses the normal project-target routing so terminal and preview state stay in sync.
function Workspace:set_current_project()
  local project = self:selected_project()
  if not project then
    notify.warn("No project selected")
    return
  end
  self.app:set_current_project(project)
  self:refresh()
end

--- Implements the selected_queue_item path for ui queue workspace.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@return CodexCli.QueueItem?, CodexCli.QueueName?
function Workspace:selected_queue_item()
  local row_index = self.queue_item_rows[self.queue_index]
  local row = row_index and self.queue_rows[row_index] or nil
  if not row or not row.item then
    return nil, nil
  end
  return row.item, row.queue
end

--- Adds a new ui queue workspace entry and keeps related state aligned.
--- This function feeds the same workflow used by interactive and scripted callers.
function Workspace:add_todo()
  local project = self:selected_project()
  if not project then
    notify.warn("No project selected")
    return
  end

  ui.multiline_input({
    prompt = ("Todo prompt for %s"):format(project.name),
  }, function(body)
    local spec = body and PromptComposer.parse(body) or nil
    if not spec then
      return
    end
    self.app:add_project_todo(project, {
      title = spec.title,
      details = spec.details,
    })
    self.queue_index = 1
    self:refresh()
  end)
end

--- Implements the edit_queue_item path for ui queue workspace.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
function Workspace:edit_queue_item()
  local project = self:selected_project()
  local item = self:selected_queue_item()
  if not project or not item then
    notify.warn("No queue item selected")
    return
  end

  ui.multiline_input({
    prompt = ("Edit prompt for %s"):format(project.name),
    default = PromptComposer.render(item.title, item.details),
  }, function(body)
    local spec = body and PromptComposer.parse(body) or nil
    if not spec then
      return
    end
    self.app:edit_queue_item(project, item.id, {
      title = spec.title,
      details = spec.details,
    })
    self:refresh()
  end)
end

--- Implements the implement_queue_item path for ui queue workspace.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
function Workspace:implement_queue_item()
  local project = self:selected_project()
  local item, queue_name = self:selected_queue_item()
  if not project or not item then
    notify.warn("No queue item selected")
    return
  end
  if queue_name ~= "queued" then
    notify.warn("Select an item from the queued section")
    return
  end

  self.app:implement_queue_item(project, item.id)
  self:refresh()
end

--- Implements the implement_queued_items path for ui queue workspace.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
function Workspace:implement_queued_items()
  local project = self:selected_project()
  if not project then
    notify.warn("No project selected")
    return
  end

  self.app:implement_queued_items(project)
  self:refresh()
end

--- Implements the move_queue_item path for ui queue workspace.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
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

--- Implements the move_queue_item_back path for ui queue workspace.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
function Workspace:move_queue_item_back()
  local project = self:selected_project()
  local item, queue_name = self:selected_queue_item()
  if not project or not item or not queue_name then
    notify.warn("No queue item selected")
    return
  end

--- Implements the move_back path for ui queue workspace.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
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
--- Implements the format_item path for ui queue workspace.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
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

--- Implements the move_queue_item_to_project path for ui queue workspace.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
function Workspace:move_queue_item_to_project()
  local project = self:selected_project()
  local item, queue_name = self:selected_queue_item()
  if not project or not item or not queue_name then
    notify.warn("No queue item selected")
    return
  end

  local current_index = self.project_index
  self:close()
  vim.schedule(function()
    self.app.picker:pick({
      prompt = ("Move '%s' to project"):format(item.title),
    }, function(target_project)
      if not target_project then
        self:open()
        self.project_index = current_index
        self:refresh()
        return
      end

      self:prompt_move_to_project(project, item, queue_name, target_project, function()
        for index, candidate in ipairs(self.app:projects_for_queue_workspace()) do
          if candidate.root == target_project.root then
            self.project_index = index
            break
          end
        end
        self.queue_index = 1
        self:open()
        self:refresh()
      end)
    end)
  end)
end

--- Implements the prompt_move_to_project path for ui queue workspace.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param project CodexCli.Project
---@param item CodexCli.QueueItem
---@param queue_name CodexCli.QueueName
---@param target_project CodexCli.Project
---@param on_complete fun()
function Workspace:prompt_move_to_project(project, item, queue_name, target_project, on_complete)
--- Implements the move_to_project path for ui queue workspace.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
  local function move_to_project(copy)
    self.app:move_queue_item_to_project(project, item.id, target_project, {
      copy = copy,
    })
    on_complete()
  end

  if queue_name == "history" then
    ui.select({
      { label = "Move history item", copy = false },
      { label = "Duplicate history item", copy = true },
    }, {
      prompt = ("Transfer '%s' to %s"):format(item.title, target_project.name),
--- Implements the format_item path for ui queue workspace.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
      format_item = function(choice)
        return choice.label
      end,
    }, function(choice)
      if not choice then
        on_complete()
        return
      end
      move_to_project(choice.copy)
    end)
    return
  end

  move_to_project(false)
end

--- Implements the move_queue_item_to_adjacent_project path for ui queue workspace.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param delta integer
function Workspace:move_queue_item_to_adjacent_project(delta)
  local project = self:selected_project()
  local item, queue_name = self:selected_queue_item()
  if not project or not item or not queue_name then
    notify.warn("No queue item selected")
    return
  end

  local target_index = self.project_index + delta
  if target_index < 1 or target_index > #self.projects then
    notify.warn("No adjacent project in that direction")
    return
  end

  local target_project = self.projects[target_index]
  if not target_project or target_project.root == project.root then
    notify.warn("No adjacent project in that direction")
    return
  end

  self:prompt_move_to_project(project, item, queue_name, target_project, function()
    self.project_index = target_index
    self.queue_index = 1
    self:refresh()
  end)
end

--- Implements the delete_queue_item path for ui queue workspace.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
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

--- Implements the delete_project path for ui queue workspace.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
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
