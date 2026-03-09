---@alias CodexCli.StatePreviewLineKind
---| "title"
---| "section"
---| "field"
---| "item"
---| "blank"

---@class CodexCli.StatePreviewLine
---@field text string
---@field kind CodexCli.StatePreviewLineKind
---@field label_end? integer
---@field value_hl? string

---@class CodexCli.StatePreview
---@field config CodexCli.Config.Values
---@field buf? integer
---@field win? integer
---@field ns integer
local Preview = {}
Preview.__index = Preview

local status_hl = {
  ["session alive"] = "String",
  ["session stopped"] = "WarningMsg",
  ["offline"] = "Comment",
  ["true"] = "@boolean",
  ["false"] = "@boolean",
  ["nil"] = "@constant",
}

local FIELD_LABEL_WIDTH = 20
local FLOAT_BORDER_ROWS = 2
local FLOAT_BORDER_COLS = 2
local FLOAT_RIGHT_MARGIN_COLS = 1
local FLOAT_CONTENT_PADDING_COLS = 2
local Snacks = require("snacks")

local function format_value(value)
  if value == nil then
    return "nil"
  end
  if type(value) == "boolean" then
    return value and "true" or "false"
  end
  return tostring(value)
end

---@param self CodexCli.StatePreview
---@param lines CodexCli.StatePreviewLine[]
---@param text string
---@param kind CodexCli.StatePreviewLineKind
---@param opts? { label_end?: integer, value_hl?: string }
local function push_line(self, lines, text, kind, opts)
  lines[#lines + 1] = vim.tbl_extend("keep", {
    text = text,
    kind = kind,
  }, opts or {})
  self.max_content_width = math.max(self.max_content_width or 0, vim.fn.strdisplaywidth(text))
end

---@param self CodexCli.StatePreview
---@param lines CodexCli.StatePreviewLine[]
---@param label string
---@param value any
local function append_field(self, lines, label, value)
  local rendered = format_value(value)
  local prefix = string.format("%-" .. FIELD_LABEL_WIDTH .. "s ", label .. ":")
  push_line(self, lines, prefix .. rendered, "field", {
    label_end = #prefix,
    value_hl = status_hl[rendered],
  })
end

---@param self CodexCli.StatePreview
---@param lines CodexCli.StatePreviewLine[]
---@param project_state CodexCli.App.ProjectStateSnapshot
local function append_project_state(self, lines, project_state)
  push_line(self, lines, string.format("> %s", project_state.project.name), "item")
  append_field(self, lines, "  root", project_state.project.root)
  append_field(self, lines, "  session_active", project_state.session_active)
  append_field(self, lines, "  window_in_active_tab", project_state.window_open_in_active_tab)
  append_field(self, lines, "  codex_working", project_state.working)
  append_field(self, lines, "  model", project_state.model)
  append_field(self, lines, "  context", project_state.context)
  append_field(self, lines, "  usage_events", project_state.usage_events)
end

---@param self CodexCli.StatePreview
---@param lines CodexCli.StatePreviewLine[]
---@param target CodexCli.App.TargetSnapshot
local function append_target(self, lines, target)
  append_field(self, lines, "kind", target.kind)
  if target.kind == "project" then
    append_field(self, lines, "project_name", target.project.name)
    append_field(self, lines, "project_root", target.project.root)
    return
  end

  append_field(self, lines, "cwd", target.cwd)
end

---@param self CodexCli.StatePreview
---@param lines CodexCli.StatePreviewLine[]
---@param session CodexCli.Terminal.SessionSnapshot
local function append_session(self, lines, session)
  push_line(self, lines, string.format("> %s", session.key), "item")
  append_field(self, lines, "  kind", session.kind)
  append_field(self, lines, "  title", session.title)
  append_field(self, lines, "  cwd", session.cwd)
  append_field(self, lines, "  project_root", session.project_root)
  append_field(self, lines, "  buf", session.buf)
  append_field(self, lines, "  buffer_valid", session.buffer_valid)
  append_field(self, lines, "  job_id", session.job_id)
  append_field(self, lines, "  running", session.running)
end

---@param self CodexCli.StatePreview
---@param lines CodexCli.StatePreviewLine[]
---@param tab CodexCli.Tab.StateSnapshot
local function append_tab(self, lines, tab)
  push_line(self, lines, string.format("> tab %d", tab.tabpage), "item")
  append_field(self, lines, "  active_project_root", tab.active_project_root)
  append_field(self, lines, "  has_visible_window", tab.has_visible_window)
  append_field(self, lines, "  window_id", tab.window_id)
  append_field(self, lines, "  session_key", tab.session_key)
end

---@param config CodexCli.Config.Values
---@return CodexCli.StatePreview
function Preview.new(config)
  local self = setmetatable({}, Preview)
  self.config = config
  self.ns = vim.api.nvim_create_namespace("codex-cli-state-preview")
  return self
end

---@param config CodexCli.Config.Values
function Preview:update_config(config)
  self.config = config
end

---@return boolean
function Preview:is_open()
  if self.win == nil then
    return false
  end

  if self.win:win_valid() then
    return true
  end

  self.win = nil
  return false
end

function Preview:ensure_buffer()
  if self.buf and vim.api.nvim_buf_is_valid(self.buf) then
    return
  end

  self.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[self.buf].buftype = "nofile"
  vim.bo[self.buf].bufhidden = "wipe"
  vim.bo[self.buf].swapfile = false
  vim.bo[self.buf].modifiable = false
  vim.bo[self.buf].filetype = "codex_cli_state"
  vim.api.nvim_buf_set_name(self.buf, "codex-cli://state-preview")
end

---@return integer
function Preview:window_width()
  local preview = self.config.state_preview
  local reserved_cols = FLOAT_BORDER_COLS + FLOAT_RIGHT_MARGIN_COLS
  local available = math.max(vim.o.columns - (preview.col + reserved_cols), preview.min_width)
  local target = math.max(preview.min_width, (self.max_content_width or 0) + FLOAT_CONTENT_PADDING_COLS)
  return math.min(target, preview.max_width, available)
end

---@return integer
function Preview:window_height()
  local preview = self.config.state_preview
  local ui = vim.api.nvim_list_uis()[1]
  local editor_height = ui and ui.height or vim.o.lines
  local row = math.max(math.floor(preview.row or 0), 0)
  local available = math.max(editor_height - row - FLOAT_BORDER_ROWS, 1)
  local max_height = math.floor(preview.max_height or 0)
  if max_height <= 0 then
    return available
  end
  return math.min(max_height, available)
end

function Preview:apply_window_style()
  if not self:is_open() then
    return
  end

  local win = self.win.win
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].wrap = false
  vim.wo[win].winfixwidth = true
  vim.wo[win].cursorline = false
  vim.wo[win].foldcolumn = "0"
  vim.wo[win].winblend = self.config.state_preview.winblend
  vim.wo[win].winhl = "Normal:NormalFloat,FloatBorder:FloatBorder"
end

---@param line_count integer
function Preview:update_window(line_count)
  local config = self.config.state_preview
  local win_config = {
    relative = "editor",
    anchor = "NW",
    row = config.row,
    col = config.col,
    width = self:window_width(),
    height = self:window_height(),
    style = "minimal",
    border = "rounded",
    title = "Codex CLI State",
    title_pos = "center",
    zindex = 60,
  }

  if self:is_open() then
    vim.api.nvim_win_set_config(self.win.win, win_config)
    self:apply_window_style()
    return
  end

  self.win = Snacks.win({
    buf = self.buf,
    enter = false,
    relative = "editor",
    anchor = "NW",
    row = config.row,
    col = config.col,
    width = self:window_width(),
    height = self:window_height(),
    style = "minimal",
    border = "rounded",
    title = "Codex CLI State",
    title_pos = "center",
    zindex = 60,
  })
  self:apply_window_style()
end

function Preview:show()
  if self:is_open() then
    return
  end

  self:ensure_buffer()
  self:update_window(1)
end

function Preview:hide()
  if self:is_open() then
    self.win:hide()
  end
  self.win = nil
end

---@param lines CodexCli.StatePreviewLine[]
function Preview:apply_highlights(lines)
  vim.api.nvim_buf_clear_namespace(self.buf, self.ns, 0, -1)

  for row, line in ipairs(lines) do
    local line_nr = row - 1
    if line.kind == "title" then
      vim.api.nvim_buf_set_extmark(self.buf, self.ns, line_nr, 0, {
        end_col = #line.text,
        hl_group = "Title",
      })
    elseif line.kind == "section" then
      vim.api.nvim_buf_set_extmark(self.buf, self.ns, line_nr, 0, {
        end_col = #line.text,
        hl_group = "Directory",
      })
    elseif line.kind == "item" then
      vim.api.nvim_buf_set_extmark(self.buf, self.ns, line_nr, 0, {
        end_col = 1,
        hl_group = "SpecialChar",
      })
      vim.api.nvim_buf_set_extmark(self.buf, self.ns, line_nr, 2, {
        end_col = #line.text,
        hl_group = "Identifier",
      })
    elseif line.kind == "field" and line.label_end then
      vim.api.nvim_buf_set_extmark(self.buf, self.ns, line_nr, 0, {
        end_col = line.label_end,
        hl_group = "@constructor",
      })
      if line.value_hl then
        vim.api.nvim_buf_set_extmark(self.buf, self.ns, line_nr, line.label_end, {
          end_col = #line.text,
          hl_group = line.value_hl,
        })
      end
    end
  end
end

---@param snapshot CodexCli.App.StateSnapshot
function Preview:render(snapshot)
  self:ensure_buffer()
  self.max_content_width = 0

  ---@type CodexCli.StatePreviewLine[]
  local lines = {}
  push_line(self, lines, "Current", "section")
  append_field(self, lines, "current_tab", snapshot.current_tab.tabpage)
  append_field(self, lines, "current_path", snapshot.current_path)
  append_field(self, lines, "active_project_name", snapshot.active_project and snapshot.active_project.name or nil)
  append_field(self, lines, "active_project_root", snapshot.active_project and snapshot.active_project.root or nil)
  append_field(self, lines, "detected_project_name", snapshot.detected_project and snapshot.detected_project.name or nil)
  append_field(self, lines, "detected_project_root", snapshot.detected_project and snapshot.detected_project.root or nil)

  push_line(self, lines, "", "blank")
  push_line(self, lines, "Resolved Target", "section")
  append_target(self, lines, snapshot.resolved_target)

  push_line(self, lines, "", "blank")
  push_line(self, lines, "Current Tab State", "section")
  append_tab(self, lines, snapshot.current_tab)

  push_line(self, lines, "", "blank")
  push_line(self, lines, "Per-Project State", "section")
  if #snapshot.project_states == 0 then
    push_line(self, lines, "> none", "item")
  else
    for _, project_state in ipairs(snapshot.project_states) do
      append_project_state(self, lines, project_state)
    end
  end

  push_line(self, lines, "", "blank")
  push_line(self, lines, "Tracked Sessions", "section")
  if #snapshot.sessions == 0 then
    push_line(self, lines, "> none", "item")
  else
    for _, session in ipairs(snapshot.sessions) do
      append_session(self, lines, session)
    end
  end

  push_line(self, lines, "", "blank")
  push_line(self, lines, "Tab States", "section")
  if #snapshot.tabs == 0 then
    push_line(self, lines, "> none", "item")
  else
    for _, tab in ipairs(snapshot.tabs) do
      append_tab(self, lines, tab)
    end
  end

  local text = vim.tbl_map(function(line)
    return line.text
  end, lines)

  vim.bo[self.buf].modifiable = true
  vim.api.nvim_buf_set_lines(self.buf, 0, -1, false, text)
  vim.bo[self.buf].modifiable = false
  self:apply_highlights(lines)
  self:update_window(#lines)
end

---@param app CodexCli.App
function Preview:refresh(app)
  if not self:is_open() then
    return
  end

  self:render(app:state_snapshot())
end

---@param app CodexCli.App
function Preview:toggle(app)
  if self:is_open() then
    self:hide()
    return
  end

  self:show()
  self:render(app:state_snapshot())
end

return Preview
