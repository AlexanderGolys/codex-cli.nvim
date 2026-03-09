local Commands = require("codex-cli.commands")
local Extmark = require("codex-cli.ui.extmark")
local TextBlock = require("codex-cli.ui.text_block")
local ui_win = require("codex-cli.ui.win")

---@class CodexCli.StatePreview
---@field config CodexCli.Config.Values
---@field state_buf? integer
---@field command_buf? integer
---@field state_win? integer
---@field command_win? integer
---@field state_ns integer
---@field command_ns integer
---@field max_state_width integer
---@field command_index integer
---@field commands CodexCli.CommandSpec[]
---@field focus "commands"|"state"
local Preview = {}
Preview.__index = Preview

local status_hl = {
  ["session alive"] = "@diff.plus",
  ["session stopped"] = "ErrorMsg",
  ["offline"] = "@error",
  ["true"] = "@boolean",
  ["false"] = "@boolean",
  ["nil"] = "@constant",
}

local FIELD_LABEL_WIDTH = 20
local FLOAT_BORDER_ROWS = 2
local FLOAT_BORDER_COLS = 2
local FLOAT_RIGHT_MARGIN_COLS = 1
local FLOAT_CONTENT_PADDING_COLS = 2
local COMMAND_WIDTH_MIN = 28
local COMMAND_WIDTH_MAX = 40
local PANEL_GAP_COLS = 1

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
---@param block CodexCli.TextBlock
---@param text string
---@param extmarks? CodexCli.Extmark[]
---@return integer
local function push_line(self, block, text, extmarks)
  self.max_state_width = math.max(self.max_state_width or 0, vim.fn.strdisplaywidth(text))
  return block:append_line(text, extmarks)
end

---@param self CodexCli.StatePreview
---@param block CodexCli.TextBlock
---@param label string
---@param value any
local function append_field(self, block, label, value)
  local rendered = format_value(value)
  local prefix = string.format("%-" .. FIELD_LABEL_WIDTH .. "s ", label .. ":")
  local text = prefix .. rendered
  local extmarks = {
    Extmark.inline(0, 0, #prefix, "@constructor"),
  }
  if status_hl[rendered] then
    extmarks[#extmarks + 1] = Extmark.inline(0, #prefix, #text, status_hl[rendered])
  end
  push_line(self, block, text, extmarks)
end

---@param project? CodexCli.Project
---@return string
local function project_name(project)
  return project and project.name or "none"
end

---@param target CodexCli.App.TargetSnapshot
---@return string
local function target_label(target)
  if target.kind == "project" then
    return ("project:%s"):format(target.project.name)
  end
  return ("free:%s"):format(target.cwd)
end

---@param project_state CodexCli.App.ProjectStateSnapshot
---@return string
local function project_status(project_state)
  local parts = { project_state.working }
  if project_state.session_active then
    parts[#parts + 1] = "tracked"
  end
  if project_state.window_open_in_active_tab then
    parts[#parts + 1] = "visible"
  end
  return table.concat(parts, ", ")
end

---@param self CodexCli.StatePreview
---@param block CodexCli.TextBlock
---@param project_state CodexCli.App.ProjectStateSnapshot
local function append_project_state(self, block, project_state)
  local text = string.format("> %s  %s", project_state.project.name, project_status(project_state))
  push_line(self, block, text, {
    Extmark.inline(0, 0, 1, "SpecialChar"),
    Extmark.inline(0, 2, #text, "Identifier"),
  })
  append_field(self, block, "  root", project_state.project.root)
end

---@param self CodexCli.StatePreview
---@param block CodexCli.TextBlock
---@param target CodexCli.App.TargetSnapshot
local function append_target(self, block, target)
  append_field(self, block, "target", target_label(target))
end

---@param self CodexCli.StatePreview
---@param block CodexCli.TextBlock
---@param tab CodexCli.Tab.StateSnapshot
local function append_tab(self, block, tab)
  local active = tab.active_project_root or "none"
  local showing = tab.session_key or "none"
  local text = string.format("> tab %d  active=%s  showing=%s", tab.tabpage, active, showing)
  push_line(self, block, text, {
    Extmark.inline(0, 0, 1, "SpecialChar"),
    Extmark.inline(0, 2, #text, "Identifier"),
  })
  if tab.window_id ~= nil then
    append_field(self, block, "  window", tab.window_id)
  end
end

---@param command CodexCli.CommandSpec
---@return string
local function command_label(command)
  return command.name:gsub("^Codex", "")
end

---@param command CodexCli.CommandSpec
---@return string
local function command_hint(command)
  if command.nargs and command.nargs ~= "0" then
    return "?"
  end
  return ""
end

---@param self CodexCli.StatePreview
---@return integer
local function command_width(self)
  local width = COMMAND_WIDTH_MIN
  for _, command in ipairs(self.commands) do
    local text = command_label(command) .. command_hint(command)
    width = math.max(width, vim.fn.strdisplaywidth(text) + FLOAT_CONTENT_PADDING_COLS)
  end
  return math.min(width, COMMAND_WIDTH_MAX)
end

---@param self CodexCli.StatePreview
---@return integer
local function state_width(self)
  local preview = self.config.state_preview
  local reserved_cols = FLOAT_BORDER_COLS + FLOAT_RIGHT_MARGIN_COLS + PANEL_GAP_COLS + command_width(self)
  local available = math.max(vim.o.columns - (preview.col + reserved_cols), preview.min_width)
  local target = math.max(preview.min_width, (self.max_state_width or 0) + FLOAT_CONTENT_PADDING_COLS)
  return math.min(target, preview.max_width, available)
end

---@param self CodexCli.StatePreview
---@return integer
local function panel_height(self)
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

---@param config CodexCli.Config.Values
---@return CodexCli.StatePreview
function Preview.new(config)
  local self = setmetatable({}, Preview)
  self.config = config
  self.state_ns = vim.api.nvim_create_namespace("codex-cli-state-preview")
  self.command_ns = vim.api.nvim_create_namespace("codex-cli-state-preview-commands")
  self.commands = Commands.list()
  self.command_index = 1
  self.focus = "commands"
  self.max_state_width = 0
  return self
end

---@param config CodexCli.Config.Values
function Preview:update_config(config)
  self.config = config
end

---@return boolean
function Preview:is_open()
  return win_valid(self.command_win) and win_valid(self.state_win)
end

function Preview:ensure_buffers()
  local function make_buffer(name, filetype)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].buftype = "nofile"
    vim.bo[buf].bufhidden = "wipe"
    vim.bo[buf].swapfile = false
    vim.bo[buf].modifiable = false
    vim.bo[buf].filetype = filetype
    vim.api.nvim_buf_set_name(buf, name)
    return buf
  end

  self.command_buf = buf_valid(self.command_buf) and self.command_buf
    or make_buffer("codex-cli://state-preview-commands", "codex_cli_state")
  self.state_buf = buf_valid(self.state_buf) and self.state_buf
    or make_buffer("codex-cli://state-preview-state", "codex_cli_state")
end

function Preview:apply_window_style()
  local function apply(win, active)
    if not win_valid(win) then
      return
    end
    vim.wo[win].number = false
    vim.wo[win].relativenumber = false
    vim.wo[win].signcolumn = "no"
    vim.wo[win].wrap = false
    vim.wo[win].foldcolumn = "0"
    vim.wo[win].winblend = self.config.state_preview.winblend
    vim.wo[win].cursorline = active
    vim.wo[win].winhl = "Normal:NormalFloat,FloatBorder:FloatBorder"
  end

  apply(self.command_win, self.focus == "commands")
  apply(self.state_win, self.focus == "state")
end

function Preview:update_cursor()
  if win_valid(self.command_win) then
    vim.api.nvim_win_set_cursor(self.command_win, { clamp(self.command_index, math.max(#self.commands, 1)), 0 })
  end
end

function Preview:set_focus(focus)
  self.focus = focus
  self:apply_window_style()
  local win = focus == "commands" and self.command_win or self.state_win
  if win_valid(win) then
    vim.api.nvim_set_current_win(win)
  end
  self:update_cursor()
end

function Preview:attach_keymaps()
  local function map(buf, lhs, rhs)
    vim.keymap.set("n", lhs, rhs, { buffer = buf, nowait = true, silent = true })
  end

  for _, buf in ipairs({ self.command_buf, self.state_buf }) do
    map(buf, "q", function()
      self:hide()
    end)
    map(buf, "<Esc>", function()
      self:hide()
    end)
    map(buf, "h", function()
      self:set_focus("commands")
    end)
    map(buf, "<Left>", function()
      self:set_focus("commands")
    end)
    map(buf, "l", function()
      self:set_focus("state")
    end)
    map(buf, "<Right>", function()
      self:set_focus("state")
    end)
  end

  map(self.command_buf, "j", function()
    self:move_command_selection(1)
  end)
  map(self.command_buf, "<Down>", function()
    self:move_command_selection(1)
  end)
  map(self.command_buf, "k", function()
    self:move_command_selection(-1)
  end)
  map(self.command_buf, "<Up>", function()
    self:move_command_selection(-1)
  end)
  map(self.command_buf, "<CR>", function()
    self:execute_selected_command()
  end)
end

function Preview:update_windows()
  self:ensure_buffers()
  local config = self.config.state_preview
  local left_width = command_width(self)
  local right_width = state_width(self)
  local height = panel_height(self)

  local command_config = {
    relative = "editor",
    anchor = "NW",
    row = config.row,
    col = config.col,
    width = left_width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = " Commands ",
    title_pos = "center",
    zindex = 60,
  }
  local state_config = {
    relative = "editor",
    anchor = "NW",
    row = config.row,
    col = config.col + left_width + PANEL_GAP_COLS,
    width = right_width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = " Codex CLI State ",
    title_pos = "center",
    zindex = 60,
  }

  if win_valid(self.command_win) then
    vim.api.nvim_win_set_config(self.command_win, command_config)
  else
    self.command_win = ui_win.open(vim.tbl_extend("force", command_config, {
      buf = self.command_buf,
      enter = true,
    })).win
  end

  if win_valid(self.state_win) then
    vim.api.nvim_win_set_config(self.state_win, state_config)
  else
    self.state_win = ui_win.open(vim.tbl_extend("force", state_config, {
      buf = self.state_buf,
      enter = false,
    })).win
  end

  self:apply_window_style()
  self:update_cursor()
end

function Preview:show()
  if self:is_open() then
    return
  end

  self:ensure_buffers()
  self:attach_keymaps()
  self:update_windows()
  self:set_focus("commands")
end

function Preview:hide()
  for _, win in ipairs({ self.command_win, self.state_win }) do
    if win_valid(win) then
      pcall(vim.api.nvim_win_close, win, true)
    end
  end
  self.command_win = nil
  self.state_win = nil
end

function Preview:render_commands()
  self.commands = Commands.list()
  self.command_index = clamp(self.command_index, #self.commands)

  local block = TextBlock.new()
  for _, command in ipairs(self.commands) do
    local name = command_label(command)
    local text = ("%s%s"):format(name, command_hint(command))
    local extmarks = {
      Extmark.inline(0, 0, #name, "Identifier"),
    }
    if #text > #name then
      extmarks[#extmarks + 1] = Extmark.inline(0, #name, #text, "Comment")
    end
    block:append_line(text, extmarks)
  end

  if block:is_empty() then
    block:append_line("No commands")
  end

  block:render(self.command_buf, self.command_ns)
  self:update_cursor()
end

---@param snapshot CodexCli.App.StateSnapshot
function Preview:render_state(snapshot)
  self.max_state_width = 0

  local block = TextBlock.new()
  push_line(self, block, "Focus", {
    Extmark.inline(0, 0, #"Focus", "Directory"),
  })
  append_field(self, block, "tab", snapshot.current_tab.tabpage)
  append_field(self, block, "path", snapshot.current_path)
  append_field(self, block, "active", project_name(snapshot.active_project))
  append_field(self, block, "detected", project_name(snapshot.detected_project))
  append_target(self, block, snapshot.resolved_target)

  push_line(self, block, "")
  push_line(self, block, "Current Tab", {
    Extmark.inline(0, 0, #"Current Tab", "Directory"),
  })
  append_field(self, block, "visible", snapshot.current_tab.has_visible_window)
  append_field(self, block, "session", snapshot.current_tab.session_key or "none")
  append_field(self, block, "window", snapshot.current_tab.window_id or "none")

  push_line(self, block, "")
  push_line(self, block, "Projects", {
    Extmark.inline(0, 0, #"Projects", "Directory"),
  })
  if #snapshot.project_states == 0 then
    push_line(self, block, "> none", {
      Extmark.inline(0, 0, 1, "SpecialChar"),
      Extmark.inline(0, 2, #"> none", "Identifier"),
    })
  else
    for _, project_state in ipairs(snapshot.project_states) do
      append_project_state(self, block, project_state)
    end
  end

  push_line(self, block, "")
  push_line(self, block, "Tabs", {
    Extmark.inline(0, 0, #"Tabs", "Directory"),
  })
  if #snapshot.tabs == 0 then
    push_line(self, block, "> none", {
      Extmark.inline(0, 0, 1, "SpecialChar"),
      Extmark.inline(0, 2, #"> none", "Identifier"),
    })
  else
    for _, tab in ipairs(snapshot.tabs) do
      append_tab(self, block, tab)
    end
  end

  block:render(self.state_buf, self.state_ns)
end

---@param delta integer
function Preview:move_command_selection(delta)
  if #self.commands == 0 then
    return
  end
  self.command_index = clamp(self.command_index + delta, #self.commands)
  self:update_cursor()
end

function Preview:execute_selected_command()
  local command = self.commands[self.command_index]
  if not command then
    return
  end

  if command.name == "CodexStateToggle" then
    vim.cmd(command.name)
    return
  end

  self:hide()
  vim.schedule(function()
    vim.cmd(command.name)
  end)
end

---@param snapshot CodexCli.App.StateSnapshot
function Preview:render(snapshot)
  self:ensure_buffers()
  self:render_commands()
  self:render_state(snapshot)
  self:update_windows()
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
