local M = {}

---@class Clodex.UiWin.Theme
---@field normal? string
---@field normal_nc? string
---@field normal_float? string
---@field float_border? string
---@field float_title? string
---@field float_footer? string
---@field cursor_line? string
---@field end_of_buffer? string
---@field cursor? string
---@field lcursor? string
---@field cursorim? string
---@field term_cursor? string
---@field term_cursor_nc? string
---@field winblend? integer

---@alias Clodex.UiWin.BufferPreset "scratch"|"text"|"markdown"|"workspace"
---@alias Clodex.UiWin.ViewPreset "panel"|"text"|"markdown"|"footer"
---@alias Clodex.UiWin.ThemePreset "default_float"|"prompt_editor"|"prompt_footer"|"queue_active"|"queue_inactive"

local VIEW_PRESETS = {
  panel = {
    number = false,
    relativenumber = false,
    signcolumn = "no",
    foldcolumn = "0",
    wrap = false,
    linebreak = false,
    breakindent = false,
    spell = false,
    cursorline = false,
  },
  text = {
    wrap = false,
    linebreak = false,
    breakindent = false,
  },
  markdown = {
    wrap = true,
    linebreak = true,
    breakindent = true,
  },
  footer = {
    wrap = false,
    linebreak = false,
    breakindent = false,
    cursorline = false,
  },
}

local THEME_PRESETS = {
  default_float = {
    normal = "NormalFloat",
    normal_nc = "NormalFloat",
    normal_float = "NormalFloat",
    float_border = "FloatBorder",
    float_title = "FloatTitle",
    float_footer = "FloatFooter",
    winblend = 0,
  },
  prompt_editor = {
    normal_float = "ClodexPromptEditorNormal",
    float_border = "ClodexPromptEditorBorder",
    float_title = "ClodexPromptEditorTitle",
    float_footer = "ClodexPromptEditorSubtitle",
    winblend = 0,
  },
  prompt_footer = {
    normal_float = "ClodexPromptEditorFooter",
    float_border = "ClodexPromptEditorBorder",
    float_title = "ClodexPromptEditorTitle",
    float_footer = "ClodexPromptEditorSubtitle",
    winblend = 0,
  },
  queue_active = {
    normal = "ClodexQueueFocusActive",
    normal_nc = "ClodexQueueFocusActive",
    normal_float = "ClodexQueueFocusActive",
    float_border = "ClodexQueueActiveBorder",
    float_title = "ClodexQueueActiveBorder",
    cursor_line = "ClodexQueueSelectionActive",
    end_of_buffer = "ClodexQueueFocusActive",
    cursor = "ClodexQueueCursorActive",
    lcursor = "ClodexQueueCursorActive",
    cursorim = "ClodexQueueCursorActive",
    term_cursor = "ClodexQueueCursorActive",
    term_cursor_nc = "ClodexQueueCursorActive",
    winblend = 0,
  },
  queue_inactive = {
    normal = "ClodexQueueFocusInactive",
    normal_nc = "ClodexQueueFocusInactive",
    normal_float = "ClodexQueueFocusInactive",
    float_border = "ClodexQueueInactiveBorder",
    float_title = "ClodexQueueInactiveBorder",
    cursor_line = "ClodexQueueSelectionInactive",
    end_of_buffer = "ClodexQueueFocusInactive",
    cursor = "ClodexQueueCursorInactive",
    lcursor = "ClodexQueueCursorInactive",
    cursorim = "ClodexQueueCursorInactive",
    term_cursor = "ClodexQueueCursorInactive",
    term_cursor_nc = "ClodexQueueCursorInactive",
    winblend = 0,
  },
}

local BUFFER_PRESETS = {
  scratch = {
    buftype = "nofile",
    bufhidden = "wipe",
    swapfile = false,
    modifiable = false,
  },
  text = {
    buftype = "nofile",
    bufhidden = "wipe",
    swapfile = false,
    modifiable = true,
  },
  markdown = {
    buftype = "nofile",
    bufhidden = "wipe",
    swapfile = false,
    modifiable = true,
    filetype = "markdown",
  },
  workspace = {
    buftype = "nofile",
    bufhidden = "wipe",
    swapfile = false,
    modifiable = false,
    filetype = "clodex_queue_workspace",
  },
}

---@param value Clodex.UiWin.ViewPreset|table<string, any>|nil
---@param presets table<string, table<string, any>>
---@return table<string, any>
local function resolve_named_table(value, presets)
  if value == nil then
    return {}
  end
  if type(value) == "string" then
    return vim.deepcopy(presets[value] or {})
  end
  return vim.deepcopy(value)
end

---@param theme Clodex.UiWin.ThemePreset|Clodex.UiWin.Theme|nil
---@param overrides? Clodex.UiWin.Theme
---@return Clodex.UiWin.Theme
local function resolve_theme(theme, overrides)
  local resolved = resolve_named_table(theme, THEME_PRESETS)
  return vim.tbl_deep_extend("force", resolved, overrides or {})
end

---@param theme Clodex.UiWin.Theme
---@return string?
local function theme_winhl(theme)
  local parts = {} ---@type string[]
  local mapping = {
    Normal = theme.normal,
    NormalNC = theme.normal_nc,
    NormalFloat = theme.normal_float,
    FloatBorder = theme.float_border,
    FloatTitle = theme.float_title,
    FloatFooter = theme.float_footer,
    CursorLine = theme.cursor_line,
    EndOfBuffer = theme.end_of_buffer,
    Cursor = theme.cursor,
    lCursor = theme.lcursor,
    CursorIM = theme.cursorim,
    TermCursor = theme.term_cursor,
    TermCursorNC = theme.term_cursor_nc,
  }

  for source, target in pairs(mapping) do
    if type(target) == "string" and target ~= "" then
      parts[#parts + 1] = ("%s:%s"):format(source, target)
    end
  end

  if #parts == 0 then
    return nil
  end
  table.sort(parts)
  return table.concat(parts, ",")
end

---@param buf integer
---@param opts table<string, any>
local function apply_buf_options(buf, opts)
  for key, value in pairs(opts) do
    vim.bo[buf][key] = value
  end
end

---@param win integer
---@param opts table<string, any>
local function apply_win_options(win, opts)
  for key, value in pairs(opts) do
    vim.wo[win][key] = value
  end
end

---@param win any
---@return boolean
local function winid_is_valid(win)
  return type(win) == "number" and win > 0 and vim.api.nvim_win_is_valid(win)
end

---@param win snacks.win
---@return snacks.win
local function harden_snacks_window(win)
  function win:win_valid()
    return winid_is_valid(self.win)
  end

  function win:valid()
    return self:win_valid() and self:buf_valid() and vim.api.nvim_win_get_buf(self.win) == self.buf
  end

  return win
end

---@param opts? { preset?: Clodex.UiWin.BufferPreset|table<string, any>, name?: string, listed?: boolean, scratch?: boolean, bo?: table<string, any> }
---@return integer
function M.create_buffer(opts)
  opts = opts or {}
  local preset = resolve_named_table(opts.preset or "scratch", BUFFER_PRESETS)
  local buf = vim.api.nvim_create_buf(opts.listed == true, opts.scratch ~= false)
  apply_buf_options(buf, vim.tbl_deep_extend("force", preset, opts.bo or {}))
  if opts.name and opts.name ~= "" then
    vim.api.nvim_buf_set_name(buf, opts.name)
  end
  return buf
end

--- Opens or activates the selected ui win target in the workspace.
--- This is used by navigation flows that need to display the most recent selection.
---@param opts snacks.win.Config|{}
---@return snacks.win
function M.open(opts)
  local Snacks = require("snacks")
  opts = vim.deepcopy(opts or {})
  local style = opts.style or "float"
  local view = opts.view
  local theme = opts.theme
  local theme_overrides = opts.theme_overrides
  opts.view = nil
  opts.theme = nil
  opts.theme_overrides = nil
  local resolved = Snacks.win.resolve({
    position = "float",
    show = true,
    -- Clodex uses this helper for dedicated float views whose buffers should not
    -- be "fixed" by Snacks buffer-swapping autocommands.
    fixbuf = false,
  }, style, opts)
  local win = Snacks.win(resolved)
  if win then
    win = harden_snacks_window(win)
  end
  if win and winid_is_valid(win.win) then
    M.configure(win.win, {
      view = view,
      theme = theme,
      theme_overrides = theme_overrides,
    })
  end
  return win
end

--- Checks a valid condition for ui win.
--- This gate keeps callers safe before continuing higher-level state transitions.
---@param win? integer
---@return boolean
function M.is_valid(win)
  return winid_is_valid(win)
end

--- Closes or deactivates ui win behavior for the current context.
--- This is used by command flows when a view or session should stop being active.
---@param win? integer
function M.close(win)
  if not M.is_valid(win) then
    return
  end
  pcall(vim.api.nvim_win_close, win, true)
end

---@param win integer
---@param opts? { view?: Clodex.UiWin.ViewPreset|table<string, any>, wo?: table<string, any>, theme?: Clodex.UiWin.ThemePreset|Clodex.UiWin.Theme, theme_overrides?: Clodex.UiWin.Theme }
function M.configure(win, opts)
  if not M.is_valid(win) then
    return
  end
  opts = opts or {}
  local view = resolve_named_table(opts.view or nil, VIEW_PRESETS)
  apply_win_options(win, vim.tbl_deep_extend("force", view, opts.wo or {}))
  if opts.theme or opts.theme_overrides then
    M.apply_theme(win, opts.theme, opts.theme_overrides)
  end
end

---@param win integer
---@param theme Clodex.UiWin.ThemePreset|Clodex.UiWin.Theme|nil
---@param overrides? Clodex.UiWin.Theme
function M.apply_theme(win, theme, overrides)
  if not M.is_valid(win) then
    return
  end
  local resolved = resolve_theme(theme, overrides)
  local winhl = theme_winhl(resolved)
  if winhl then
    vim.wo[win].winhl = winhl
  end
  if resolved.winblend ~= nil then
    vim.wo[win].winblend = resolved.winblend
  end
end

---@param win integer
---@param active boolean
function M.set_focus_border(win, active)
  M.apply_theme(win, active and "queue_active" or "queue_inactive")
end

return M
