local Commands = require("clodex.commands")
local Extmark = require("clodex.ui.extmark")
local TextBlock = require("clodex.ui.text_block")
local ui_win = require("clodex.ui.win")
local fs = require("clodex.util.fs")

--- Defines the Clodex.StatePreview type for this module.
--- This annotation documents structured state so modules can pass data with consistent expectations.
---@class Clodex.StatePreview
---@field config Clodex.Config.Values
---@field state_buf? integer
---@field command_buf? integer
---@field state_win? integer
---@field command_win? integer
---@field state_ns integer
---@field command_ns integer
---@field max_state_width integer
---@field command_index integer
---@field commands Clodex.CommandSpec[]
---@field focus "commands"|"state"
local Preview = {}
Preview.__index = Preview

local status_hl = {
  ["session working"] = "ClodexStateStatusActive",
  ["session alive"] = "ClodexStateStatusActive",
  ["session stopped"] = "ClodexStateStatusStopped",
  ["offline"] = "ClodexStateStatusOffline",
  ["true"] = "ClodexStateBoolean",
  ["false"] = "ClodexStateBoolean",
  ["nil"] = "ClodexStateNil",
}

local FIELD_LABEL_WIDTH = 20
local FLOAT_BORDER_ROWS = 2
local FLOAT_BORDER_COLS = 2
local FLOAT_RIGHT_MARGIN_COLS = 1
local FLOAT_CONTENT_PADDING_COLS = 2
local COMMAND_WIDTH_MIN = 28
local COMMAND_WIDTH_MAX = 84
local PANEL_GAP_COLS = 1

--- Checks whether a floating window is valid before accessing win options.
--- This guard pattern is used across all state-preview window operations.
local function win_valid(win)
  return win ~= nil and vim.api.nvim_win_is_valid(win)
end

--- Checks whether a preview buffer exists and is still valid.
--- All state rendering passes use this before setting lines or marks.
local function buf_valid(buf)
  return buf ~= nil and vim.api.nvim_buf_is_valid(buf)
end

--- Ensures cursor indexes stay within a valid 1-based range.
--- This is used by movement methods to avoid invalid cursor rows.
local function clamp(index, max_value)
  if max_value <= 0 then
    return 1
  end
  return math.min(math.max(index, 1), max_value)
end

--- Normalizes values for display in text blocks.
--- Booleans and nil values become stable labels for easier scanning.
local function format_value(value)
  if value == nil then
    return "nil"
  end
  if type(value) == "boolean" then
    return value and "true" or "false"
  end
  return tostring(value)
end

---@param self Clodex.StatePreview
---@param block Clodex.TextBlock
---@param text string
---@param extmarks? Clodex.Extmark[]
---@return integer
--- Pushes a text line into a block and tracks max rendered width for sizing.
--- This keeps width calculations synced with rendered content.
local function push_line(self, block, text, extmarks)
  self.max_state_width = math.max(self.max_state_width or 0, vim.fn.strdisplaywidth(text))
  return block:append_line(text, extmarks)
end

---@param self Clodex.StatePreview
---@param block Clodex.TextBlock
---@param label string
---@param value any
--- Appends a labeled state field and applies status highlight when recognized.
--- Keeps project and tab fields visually consistent across render passes.
local function append_field(self, block, label, value)
  local rendered = format_value(value)
  local prefix = string.format("%-" .. FIELD_LABEL_WIDTH .. "s ", label .. ":")
  local text = prefix .. rendered
  local extmarks = {
    Extmark.inline(0, 0, #prefix, "ClodexStateFieldLabel"),
  }
  if status_hl[rendered] then
    extmarks[#extmarks + 1] = Extmark.inline(0, #prefix, #text, status_hl[rendered])
  end
  push_line(self, block, text, extmarks)
end

---@param project? Clodex.Project
---@return string
--- Returns user-friendly project name text for snapshot rendering.
--- This avoids duplicate nil-checking for optional project references.
local function project_name(project)
  return project and project.name or "none"
end

---@param target Clodex.App.TargetSnapshot
---@return string
--- Builds a compact display label for the current target snapshot.
--- It distinguishes whether focus is on a project session or free terminal.
local function target_label(target)
  if target.kind == "project" then
    return ("project:%s"):format(target.project.name)
  end
  return ("free:%s"):format(target.cwd)
end

---@param project_state Clodex.App.ProjectStateSnapshot
--- Builds human-readable status text for a project's workspace state.
--- Includes tracking and visibility flags used in project line summaries.
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

---@param self Clodex.StatePreview
---@param block Clodex.TextBlock
---@param project_state Clodex.App.ProjectStateSnapshot
--- Appends one project line and key metadata fields to the state block.
--- It is called for every project snapshot while rendering the main state pane.
local function append_project_state(self, block, project_state)
  local text = string.format("> %s  %s", project_state.project.name, project_status(project_state))
  push_line(self, block, text, {
    Extmark.inline(0, 0, 1, "ClodexStateMarker"),
    Extmark.inline(0, 2, #text, "ClodexStateEntryTitle"),
  })
  append_field(self, block, "  root", project_state.project.root)
  append_field(self, block, "  bookmarks", project_state.bookmark_count)
  append_field(self, block, "  notes", project_state.notes_count)
  append_field(self, block, "  cheatsheet", project_state.cheatsheet_count)
  for index, item in ipairs(project_state.cheatsheet_items or {}) do
    if index > 3 then
      break
    end
    push_line(self, block, ("    - %s"):format(item), {
      Extmark.inline(0, 0, #"    - ", "ClodexStateFieldLabel"),
    })
  end
end

---@param self Clodex.StatePreview
---@param block Clodex.TextBlock
---@param target Clodex.App.TargetSnapshot
--- Adds active target data to the state output, including project or free path target.
--- This keeps the selected project/session context obvious to the user.
local function append_target(self, block, target)
  append_field(self, block, "target", target_label(target))
end

---@param self Clodex.StatePreview
---@param block Clodex.TextBlock
---@param tab Clodex.Tab.StateSnapshot
--- Adds tab state summary rows with visibility and window metadata.
--- It shows what session each tab is currently showing if any.
local function append_tab(self, block, tab)
  local active = tab.active_project_root or "none"
  local showing = tab.session_key or "none"
  local text = string.format("> tab %d  active=%s  showing=%s", tab.tabpage, active, showing)
  push_line(self, block, text, {
    Extmark.inline(0, 0, 1, "ClodexStateMarker"),
    Extmark.inline(0, 2, #text, "ClodexStateEntryTitle"),
  })
  if tab.window_id ~= nil then
    append_field(self, block, "  window", tab.window_id)
  end
end

---@param command Clodex.CommandSpec
--- Adds an optional argument marker for commands that accept arguments.
--- This signals command handlers that additional input is expected.
---@return string
local function command_hint(command)
  if command.nargs and command.nargs ~= "0" then
    return " [arg]"
  end
  return ""
end

---@param command Clodex.CommandSpec
---@return string
local function command_text(command)
  return ("%s%s"):format(command.name, command_hint(command))
end

---@param self Clodex.StatePreview
--- Computes adaptive width for the command pane based on available labels and hints.
--- The width is bounded by min/max constants and used during window layout.
---@return integer
local function command_width(self)
  local width = COMMAND_WIDTH_MIN
  for _, command in ipairs(self.commands) do
    local text = command_text(command)
    width = math.max(width, vim.fn.strdisplaywidth(text) + FLOAT_CONTENT_PADDING_COLS)
  end
  return math.min(width, COMMAND_WIDTH_MAX)
end

---@param self Clodex.StatePreview
--- Computes adaptive width for the state pane from rendered content and config limits.
--- This keeps the panel flexible across larger or smaller editor windows.
---@return integer
local function state_width(self)
  local preview = self.config.state_preview
  local reserved_cols = FLOAT_BORDER_COLS + FLOAT_RIGHT_MARGIN_COLS + PANEL_GAP_COLS + command_width(self)
  local available = math.max(vim.o.columns - (preview.col + reserved_cols), preview.min_width)
  local target = math.max(preview.min_width, (self.max_state_width or 0) + FLOAT_CONTENT_PADDING_COLS)
  return math.min(target, preview.max_width, available)
end

---@param self Clodex.StatePreview
--- Computes safe height for both panels based on UI and config constraints.
--- The result avoids clipping when the editor is resized or constrained.
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

---@param config Clodex.Config.Values
---@return Clodex.StatePreview
function Preview.new(config)
  local self = setmetatable({}, Preview)
  self.config = config
  self.state_ns = vim.api.nvim_create_namespace("clodex-state-preview")
  self.command_ns = vim.api.nvim_create_namespace("clodex-state-preview-commands")
  self.commands = Commands.list()
  self.command_index = 1
  self.focus = "commands"
  self.max_state_width = 0
  return self
end

---@param config Clodex.Config.Values
function Preview:update_config(config)
  self.config = config
end

--- Checks a open condition for ui state preview.
--- This gate keeps callers safe before continuing higher-level state transitions.
---@return boolean
function Preview:is_open()
  return win_valid(self.command_win) and win_valid(self.state_win)
end

--- Creates or reuses state preview buffers.
--- A small buffer cache avoids recreating state each render and keeps UI snappy.
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
    or make_buffer("clodex-state-preview-commands", "clodex_state")
  self.state_buf = buf_valid(self.state_buf) and self.state_buf
    or make_buffer("clodex-state-preview-state", "clodex_state")
end

--- Applies shared styling for both preview windows.
--- Keeps numbering, wrapping, and focus cursorline behavior synchronized.
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
  --- Repositions the command cursor after selection changes.
  --- No-op when command window is unavailable.
  if not win_valid(self.command_win) or not buf_valid(self.command_buf) then
    return
  end

  local line_count = vim.api.nvim_buf_line_count(self.command_buf)
  if line_count <= 0 then
    return
  end

  local target_row = clamp(self.command_index, math.min(math.max(#self.commands, 1), line_count))
  vim.api.nvim_win_set_cursor(self.command_win, { target_row, 0 })
end

--- Sets active pane focus and aligns highlight/cursor in the focused window.
--- Callers use this when users press pane switching keys.
function Preview:set_focus(focus)
  self.focus = focus
  self:apply_window_style()
  local win = focus == "commands" and self.command_win or self.state_win
  if win_valid(win) then
    vim.api.nvim_set_current_win(win)
  end
  self:update_cursor()
end

--- Binds keymaps used for closing, navigation, and command execution.
--- Keeps both panes in sync and delegates to command/project-level handlers.
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

--- Re-renders or creates the two floating windows and reapplies layout.
--- Works on top of computed pane sizes and current state preview config.
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
    title = " Clodex CLI State ",
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

--- Shows the state preview windows and enters the command pane by default.
--- This is the preferred path when users toggle the feature on.
function Preview:show()
  if self:is_open() then
    return
  end

  self:ensure_buffers()
  self:attach_keymaps()
  self:update_windows()
  self:set_focus("commands")
end

--- Closes both preview windows and releases tracked window ids.
--- Buffer reuse allows quick re-open with preserved display content.
function Preview:hide()
  require("clodex.ui.select").close_active_input()
  for _, win in ipairs({ self.command_win, self.state_win }) do
    ui_win.close(win)
  end
  self.command_win = nil
  self.state_win = nil
end

--- Renders the command list and updates the cursor for current command selection.
--- This keeps the command panel aligned with command registry state.
function Preview:render_commands()
  self.commands = Commands.list()
  self.command_index = clamp(self.command_index, #self.commands)

  local block = TextBlock.new()
  for _, command in ipairs(self.commands) do
    local text = command_text(command)
    block:append_line(text, {
      Extmark.inline(0, 0, #text, "ClodexStateCommandName"),
    })
  end

  if block:is_empty() then
    block:append_line("No commands")
  end

  block:render(self.command_buf, self.command_ns)
  self:update_cursor()
end

---@param self Clodex.StatePreview
---@param block Clodex.TextBlock
local function append_keymaps(self, block)
  local keymaps = Commands.list_keymaps(self.config)
  if #keymaps == 0 then
    push_line(self, block, "> none", {
      Extmark.inline(0, 0, 1, "ClodexStateMarker"),
      Extmark.inline(0, 2, #"> none", "ClodexStateEntryTitle"),
    })
    return
  end

  local current_context = nil
  for _, keymap in ipairs(keymaps) do
    if keymap.context ~= current_context then
      current_context = keymap.context
      push_line(self, block, ("> %s"):format(current_context), {
        Extmark.inline(0, 0, 1, "ClodexStateMarker"),
        Extmark.inline(0, 2, 2 + #current_context, "ClodexStateEntryTitle"),
      })
    end

    local text = ("  [%s] %s  %s"):format(keymap.mode, keymap.lhs, keymap.desc)
    local mode_prefix = ("  [%s] "):format(keymap.mode)
    local lhs_start = #mode_prefix
    local lhs_end = lhs_start + #keymap.lhs
    push_line(self, block, text, {
      Extmark.inline(0, 0, #mode_prefix, "ClodexStateFieldLabel"),
      Extmark.inline(0, lhs_start, lhs_end, "ClodexStateCommandName"),
      Extmark.inline(0, lhs_end, #text, "ClodexStateCommandHint"),
    })
  end
end

---@param path string
---@return string
local function read_file(path)
  local file = io.open(path, "r")
  if not file then
    return ""
  end
  local content = file:read("*a") or ""
  file:close()
  return content
end

---@param self Clodex.StatePreview
---@param block Clodex.TextBlock
---@param snapshot Clodex.App.StateSnapshot
local function append_prompt_skill(self, block, snapshot)
  push_line(self, block, "Prompt Skill", {
    Extmark.inline(0, 0, #"Prompt Skill", "ClodexStateSection"),
  })

  local app = self.app
  local execution = app and app.execution or nil
  if not execution or not execution.uses_prompt_skill or not execution:uses_prompt_skill() then
    append_field(self, block, "status", "disabled")
    return
  end

  local project = snapshot.active_project or snapshot.detected_project
  local ok, skill_file = pcall(execution.skill_file, execution, project)
  if not ok or type(skill_file) ~= "string" or skill_file == "" then
    append_field(self, block, "status", "unresolved")
    return
  end
  local created = fs.is_file(skill_file)
  append_field(self, block, "status", created and "synced" or "not installed")
  append_field(self, block, "path", skill_file)

  if not created then
    return
  end

  for _, line in ipairs(vim.split(read_file(skill_file), "\n", { plain = true })) do
    push_line(self, block, ("  %s"):format(line), {
      Extmark.inline(0, 0, 2, "ClodexStateFieldLabel"),
    })
  end
end

---@param snapshot Clodex.App.StateSnapshot
--- Renders project/tab/state details from an app snapshot into the state pane.
--- The snapshot is assumed to already include project details and resolved target.
---@param snapshot Clodex.App.StateSnapshot
function Preview:render_state(snapshot)
  self.max_state_width = 0
  local active_project_states = {} ---@type Clodex.App.ProjectStateSnapshot[]
  for _, project_state in ipairs(snapshot.project_states) do
    if project_state.session_active then
      active_project_states[#active_project_states + 1] = project_state
    end
  end

  local block = TextBlock.new()
  push_line(self, block, "Focus", {
    Extmark.inline(0, 0, #"Focus", "ClodexStateSection"),
  })
  append_field(self, block, "tab", snapshot.current_tab.tabpage)
  append_field(self, block, "path", snapshot.current_path)
  append_field(self, block, "active", project_name(snapshot.active_project))
  append_field(self, block, "detected", project_name(snapshot.detected_project))
  append_target(self, block, snapshot.resolved_target)

  push_line(self, block, "")
  push_line(self, block, "Current Tab", {
    Extmark.inline(0, 0, #"Current Tab", "ClodexStateSection"),
  })
  append_field(self, block, "visible", snapshot.current_tab.has_visible_window)
  append_field(self, block, "session", snapshot.current_tab.session_key or "none")
  append_field(self, block, "window", snapshot.current_tab.window_id or "none")

  push_line(self, block, "")
  push_line(self, block, "Active Sessions", {
    Extmark.inline(0, 0, #"Active Sessions", "ClodexStateSection"),
  })
  if #active_project_states == 0 then
    push_line(self, block, "> none", {
      Extmark.inline(0, 0, 1, "ClodexStateMarker"),
      Extmark.inline(0, 2, #"> none", "ClodexStateEntryTitle"),
    })
  else
    for _, project_state in ipairs(active_project_states) do
      append_project_state(self, block, project_state)
    end
  end

  push_line(self, block, "")
  push_line(self, block, "Tabs", {
    Extmark.inline(0, 0, #"Tabs", "ClodexStateSection"),
  })
  if #snapshot.tabs == 0 then
    push_line(self, block, "> none", {
      Extmark.inline(0, 0, 1, "ClodexStateMarker"),
      Extmark.inline(0, 2, #"> none", "ClodexStateEntryTitle"),
    })
  else
    for _, tab in ipairs(snapshot.tabs) do
      append_tab(self, block, tab)
    end
  end

  push_line(self, block, "")
  push_line(self, block, "Keymaps", {
    Extmark.inline(0, 0, #"Keymaps", "ClodexStateSection"),
  })
  append_keymaps(self, block)

  push_line(self, block, "")
  append_prompt_skill(self, block, snapshot)

  block:render(self.state_buf, self.state_ns)
end

---@param delta integer
--- Moves command selection by delta and updates cursor.
--- No-op when command list is empty.
---@param delta integer
function Preview:move_command_selection(delta)
  if #self.commands == 0 then
    return
  end
  self.command_index = clamp(self.command_index + delta, #self.commands)
  self:update_cursor()
end

--- Executes the currently selected command and closes preview unless it's a toggle.
--- Command execution is routed through Vim commands to reuse existing Ex entry points.
function Preview:execute_selected_command()
  local command = self.commands[self.command_index]
  if not command then
    return
  end

  if command.name == "ClodexStateToggle" then
    self:hide()
    return
  end

  self:hide()
  vim.schedule(function()
    vim.cmd(command.name)
  end)
end

---@param snapshot Clodex.App.StateSnapshot
--- Full render pass for both command and state windows.
--- It ensures buffer creation and updates all panels in one call.
---@param snapshot Clodex.App.StateSnapshot
function Preview:render(snapshot)
  self:ensure_buffers()
  self:render_commands()
  self:render_state(snapshot)
  self:update_windows()
end

---@param app Clodex.App
--- Refreshes the currently open preview from latest app state.
---@param app Clodex.App
function Preview:refresh(app)
  if not self:is_open() then
    return
  end
  self.app = app
  self:render(app:state_snapshot())
end

--- Toggles the ui state preview state for the active context.
--- It is typically invoked from user commands and keeps preview/session state in sync.
---@param app Clodex.App
function Preview:toggle(app)
  if self:is_open() then
    self:hide()
    return
  end

  self:show()
  self.app = app
  self:render(app:state_snapshot())
end

return Preview
