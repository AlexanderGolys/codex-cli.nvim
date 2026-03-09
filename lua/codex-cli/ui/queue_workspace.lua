local ui = require("codex-cli.ui.select")
local Extmark = require("codex-cli.ui.extmark")
local TextBlock = require("codex-cli.ui.text_block")
local ui_win = require("codex-cli.ui.win")
local notify = require("codex-cli.util.notify")
local Category = require("codex-cli.prompt.category")

---@class CodexCli.QueueWorkspace.QueueRow
---@field kind "header"|"item"|"preview"
---@field text string
---@field queue? CodexCli.QueueName
---@field item? CodexCli.QueueItem

---@class CodexCli.QueueWorkspace.ProjectRow
---@field kind "item"|"detail"
---@field text string
---@field project? CodexCli.Project

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

---@param item CodexCli.QueueItem
---@return CodexCli.PromptCategory
local function prompt_item_kind(item)
  return Category.get(item.kind).id
end

---@param item CodexCli.QueueItem
---@return string[]
local function prompt_preview_lines(item)
  local preview = {} ---@type string[]
  local lines = vim.split(item.prompt or "", "\n", { plain = true })
  for _, line in ipairs(lines) do
    line = vim.trim(line)
    if line ~= "" then
      preview[#preview + 1] = "    " .. line
    end
    if #preview >= 3 then
      break
    end
  end
  return preview
end

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

---@param name string
---@return integer?
local function hl_fg(name)
  local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = name, link = false })
  return ok and hl and hl.fg or nil
end

---@param config CodexCli.Config.Values
local function ensure_highlights(config)
  local picker_hl = config.prompt_picker.highlights
  local visual = vim.api.nvim_get_hl(0, { name = "Visual", link = false })
  local selection_bg = visual.bg or hl_fg("Visual")
  local active_border_fg = hl_fg("Identifier") or hl_fg("FloatBorder")
  local inactive_border_fg = hl_fg("Comment") or hl_fg("FloatBorder")
  vim.api.nvim_set_hl(0, "CodexCliQueueProjectActive", {
    fg = hl_fg("Directory"),
    bold = true,
    default = true,
  })
  vim.api.nvim_set_hl(0, "CodexCliQueueProjectInactive", {
    fg = hl_fg("Comment"),
    italic = true,
    default = true,
  })
  vim.api.nvim_set_hl(0, "CodexCliQueueCounts", {
    fg = hl_fg("Identifier"),
    default = true,
  })
  vim.api.nvim_set_hl(0, "CodexCliQueueHeader", {
    fg = hl_fg("Title"),
    bold = true,
    default = true,
  })
  vim.api.nvim_set_hl(0, "CodexCliQueueItem", {
    fg = hl_fg("Normal"),
    default = true,
  })
  vim.api.nvim_set_hl(0, "CodexCliQueueItemMuted", {
    fg = hl_fg("Comment"),
    default = true,
  })
  vim.api.nvim_set_hl(0, "CodexCliQueueFooter", {
    fg = hl_fg("Comment"),
    default = true,
  })
  vim.api.nvim_set_hl(0, "CodexCliPromptPickerTodoTitle", {
    fg = hl_fg(picker_hl.todo_title),
    bold = true,
  })
  vim.api.nvim_set_hl(0, "CodexCliPromptPickerErrorTitle", {
    fg = hl_fg(picker_hl.error_title),
    bold = true,
  })
  vim.api.nvim_set_hl(0, "CodexCliPromptPickerVisualTitle", {
    fg = hl_fg(picker_hl.visual_title),
    bold = true,
  })
  vim.api.nvim_set_hl(0, "CodexCliPromptPickerAdjustmentTitle", {
    fg = hl_fg(picker_hl.adjustment_title),
    bold = true,
  })
  vim.api.nvim_set_hl(0, "CodexCliPromptPickerRefactorTitle", {
    fg = hl_fg(picker_hl.refactor_title),
    bold = true,
  })
  vim.api.nvim_set_hl(0, "CodexCliPromptPickerIdeaTitle", {
    fg = hl_fg(picker_hl.idea_title),
    bold = true,
  })
  vim.api.nvim_set_hl(0, "CodexCliPromptPickerExplainTitle", {
    fg = hl_fg(picker_hl.explain_title),
    bold = true,
  })
  vim.api.nvim_set_hl(0, "CodexCliPromptPickerPromptText", {
    fg = hl_fg(picker_hl.prompt_text),
  })
  vim.api.nvim_set_hl(0, "CodexCliQueueSelection", {
    bg = selection_bg,
    default = true,
  })
  vim.api.nvim_set_hl(0, "CodexCliQueueActiveBorder", {
    fg = active_border_fg,
    bold = true,
    default = true,
  })
  vim.api.nvim_set_hl(0, "CodexCliQueueInactiveBorder", {
    fg = inactive_border_fg,
    default = true,
  })
end

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

---@param timestamp? integer
---@return string
local function format_timestamp(timestamp)
  if not timestamp or timestamp <= 0 then
    return "-"
  end
  return os.date("%Y-%m-%d %H:%M", timestamp)
end

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

---@param value? number
---@return string
local function format_avg_lines(value)
  if not value then
    return "-"
  end
  return ("%.1f"):format(value)
end

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

---@param item CodexCli.QueueItem
---@return string
local function prompt_title_highlight(item)
  local id = prompt_item_kind(item)
  local map = {
    todo = "CodexCliPromptPickerTodoTitle",
    error = "CodexCliPromptPickerErrorTitle",
    visual = "CodexCliPromptPickerVisualTitle",
    adjustment = "CodexCliPromptPickerAdjustmentTitle",
    refactor = "CodexCliPromptPickerRefactorTitle",
    idea = "CodexCliPromptPickerIdeaTitle",
    explain = "CodexCliPromptPickerExplainTitle",
  }
  return map[id] or map.todo
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
  self.project_rows = {}
  self.project_item_rows = {}
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

  ensure_highlights(self.config)
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
    title = " Actions ",
    zindex = FOOTER_ZINDEX,
  }).win

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
  self:update_window_highlights()
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
end

---@param focus "projects"|"queue"
function Workspace:set_focus(focus)
  if focus == "queue" and not self:selected_project() then
    return
  end
  self.focus = focus
  self:apply_focus()
end

function Workspace:update_window_highlights()
  local function apply(win, active)
    if not win_valid(win) then
      return
    end
    local border = active and "CodexCliQueueActiveBorder" or "CodexCliQueueInactiveBorder"
    vim.wo[win].winhl = ("NormalFloat:NormalFloat,FloatBorder:%s"):format(border)
  end

  apply(self.project_win, self.focus == "projects")
  apply(self.queue_win, self.focus == "queue")
  apply(self.footer_win, false)
end

function Workspace:apply_focus()
  self:update_window_highlights()
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
    local row = self.project_item_rows[self.project_index] or 1
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
  ensure_highlights(self.config)
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
    local end_row = math.min(selected_row + 2, block:line_count())
    block:add_extmarks(Extmark.block(selected_row - 1, end_row, "CodexCliQueueSelection"))
  end

  block:render(self.project_buf, PROJECT_NS)
end

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
      local header_text = string.format("%s (%d)", prompt_queue_label(queue_name), #items)
      self.queue_rows[#self.queue_rows + 1] = {
        kind = "header",
        text = header_text,
        queue = queue_name,
      }
      block:append_line(header_text, {
        Extmark.inline(0, 0, #header_text, "CodexCliQueueHeader"),
      })

      if #items == 0 then
        self.queue_rows[#self.queue_rows + 1] = {
          kind = "item",
          text = "  (empty)",
          queue = queue_name,
        }
        block:append_line("  (empty)", {
          Extmark.inline(0, 0, #"  (empty)", "CodexCliQueueItem"),
        })
      else
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
            Extmark.inline(0, 0, #title_text, prompt_title_highlight(item)),
          }
          if #item_text > #title_text then
            item_extmarks[#item_extmarks + 1] =
              Extmark.inline(0, #title_text, #item_text, "CodexCliQueueItemMuted")
          end
          block:append_line(item_text, item_extmarks)

          for _, preview in ipairs(prompt_preview_lines(item)) do
            self.queue_rows[#self.queue_rows + 1] = {
              kind = "preview",
              text = preview,
              queue = queue_name,
              item = item,
            }
            block:append_line(preview, {
              Extmark.inline(0, 0, #preview, "CodexCliPromptPickerPromptText"),
            })
          end
        end
      end

      block:append_line("")
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

  local selected_row = self.queue_item_rows[self.queue_index]
  if selected_row then
    local item = self.queue_rows[selected_row]
    if item and item.item then
      local last_row = selected_row
      while self.queue_rows[last_row + 1] and self.queue_rows[last_row + 1].item == item.item do
        last_row = last_row + 1
      end
      block:add_extmarks(Extmark.block(selected_row - 1, last_row, "CodexCliQueueSelection"))
    end
  end

  block:render(self.queue_buf, QUEUE_NS)
end

function Workspace:render_footer()
  local lines = {
    "Focus: h/l or ←/→   Move: j/k or ↑/↓   Enter: open README + terminal   A/X: start/stop session",
    "Active pane border shows focus   a: add todo   e: edit prompt   i/I: implement one/all queued   q: close",
    "m/M: move forward/back   p: move project   H/L: prev/next project   d/D: delete item/project   Ctrl-S: save body",
  }
  local block = TextBlock.new()
  for _, line in ipairs(lines) do
    block:append_line(line, {
      Extmark.inline(0, 0, #line, "CodexCliQueueFooter"),
    })
  end
  block:render(self.footer_buf, FOOTER_NS)
end

function Workspace:activate_selected_project()
  local project = self:selected_project()
  if not project then
    return
  end
  self.app:activate_project_session(project)
  self:refresh()
end

function Workspace:deactivate_selected_project()
  local project = self:selected_project()
  if not project then
    return
  end
  self.app:deactivate_project_session(project)
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

    ui.multiline_input({
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

function Workspace:edit_queue_item()
  local project = self:selected_project()
  local item = self:selected_queue_item()
  if not project or not item then
    notify.warn("No queue item selected")
    return
  end

  ui.input({
    prompt = ("Edit title for %s"):format(project.name),
    default = item.title,
  }, function(title)
    title = title and vim.trim(title) or ""
    if title == "" then
      return
    end

    ui.multiline_input({
      prompt = "Edit details (optional)",
      default = item.details or "",
    }, function(details)
      self.app:edit_queue_item(project, item.id, {
        title = title,
        details = details,
      })
      self:refresh()
    end)
  end)
end

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

function Workspace:implement_queued_items()
  local project = self:selected_project()
  if not project then
    notify.warn("No project selected")
    return
  end

  self.app:implement_queued_items(project)
  self:refresh()
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

---@param project CodexCli.Project
---@param item CodexCli.QueueItem
---@param queue_name CodexCli.QueueName
---@param target_project CodexCli.Project
---@param on_complete fun()
function Workspace:prompt_move_to_project(project, item, queue_name, target_project, on_complete)
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
