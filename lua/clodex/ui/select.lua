local M = {}
local SnacksInput = require("snacks.input")
local SnacksSelect = require("snacks.picker.select")
local Prompt = require("clodex.prompt")
local PromptContext = require("clodex.prompt.context")
local ui_win = require("clodex.ui.win")
local unpack_values = require("clodex.util").unpack_values

local MODAL_ZINDEX = 100
local PROMPT_EDITOR_MIN_HEIGHT = 8
local PROMPT_EDITOR_MIN_WIDTH = 72
local PROMPT_EDITOR_MAX_MARGIN = 12
local PROMPT_EDITOR_WIDTH_PADDING = 10
local PROMPT_EDITOR_HEIGHT_MARGIN = 10
local PROMPT_EDITOR_TITLE_HEIGHT = 1
local PROMPT_EDITOR_FIELD_GAP = 0
local PROMPT_EDITOR_HINT_GAP = 1
local PROMPT_EDITOR_BORDER_ROWS = 2
local PROMPT_EDITOR_BORDER_COLS = 2
local PROMPT_EDITOR_ZINDEX = MODAL_ZINDEX
local PROMPT_EDITOR_BACKDROP = 90
local PROMPT_EDITOR_HINT_HEIGHT = 2
local PROMPT_CONTEXT_HIGHLIGHT_NS = vim.api.nvim_create_namespace("clodex_prompt_context_highlight")
local PROMPT_EDITOR_HINT_KEYS = {
  "<CR>",
  "<Down>",
  "<Tab>",
  "<S-Tab>",
  "<C-s>",
  "<C-q>",
  "<C-v>",
  "&",
  "<C-x>",
  "x",
  "q",
  "Esc",
}
local active_input
local prompt_context_completion = {} ---@type table<integer, Clodex.PromptContext.Capture?>

---@param win? snacks.win
local function focus_input_window(win)
  if active_input ~= win or not win or not win:valid() then
    return
  end
  win:focus()
  vim.cmd("startinsert!")
end

---@param picker? table
local function focus_picker_list(picker)
  if not picker or picker.closed then
    return
  end

  local picker_opts = picker.opts or {}
  if picker_opts.focus == false or picker_opts.enter == false then
    return
  end

  if picker.focus then
    picker:focus(picker_opts.focus or "list", {
      show = true,
    })
  end

  local list_win = picker.list and picker.list.win or nil
  local list_win_id = type(list_win) == "table" and list_win.win or list_win
  if type(list_win_id) == "number" and vim.api.nvim_win_is_valid(list_win_id) then
    vim.api.nvim_set_current_win(list_win_id)
  end
end

---@class Clodex.UiSelect.MultilineAction
---@field value string
---@field label string
---@field key string

---@param input? snacks.win
local function clear_active_input(input)
  if input ~= nil and active_input ~= input then
    return
  end
  active_input = nil
end

---@class Clodex.UiSelect.TextChoice
---@field label string
---@field detail? string
---@field badge? string
---@field icon? string
---@field accent_hl? string
---@field preview? { text: string, ft?: string, loc?: boolean }
---@field preview_title? string

---@class Clodex.UiSelect.PickerEntry<T>
---@field value T
---@field text string
---@field chunks? snacks.picker.Highlight[]
---@field preview? { text: string, ft?: string, loc?: boolean }
---@field preview_title? string

---@class Clodex.UiSelect.MapContext<T>
---@field index integer
---@field items T[]

---@class Clodex.UiSelect.InputOpts
---@field prompt? string
---@field default? string
---@field completion? string
---@field changed? fun(value: string)
---@field win? table<string, any>

---@class Clodex.UiSelect.SelectOpts
---@field prompt? string
---@field format_item? fun(item: any, supports_chunks: boolean): string|snacks.picker.Highlight[]
---@field kind? string
---@field snacks? table

---@class Clodex.UiSelect.CompletedItem
---@field word string
---@field abbr? string
---@field menu? string
---@field info? string

---@class Clodex.UiSelect.MultilineOpts
---@field prompt string
---@field default? string
---@field min_height? integer
---@field context? Clodex.PromptContext.Capture
---@field paste_image? fun(): string?
---@field submit_actions? Clodex.UiSelect.MultilineAction[]

---@param item Clodex.UiSelect.TextChoice
---@return string|snacks.picker.Highlight[]
local function text_choice_chunks(item)
  local accent_hl = item.accent_hl or "ClodexStateCommandName"
  local chunks = {} ---@type snacks.picker.Highlight[]

  if item.icon and item.icon ~= "" then
    chunks[#chunks + 1] = { item.icon .. " ", "ClodexPickerRoot" }
  end

  if item.badge and item.badge ~= "" then
    chunks[#chunks + 1] = { "[", "ClodexQueueItemMuted" }
    chunks[#chunks + 1] = { item.badge, accent_hl }
    chunks[#chunks + 1] = { "] ", "ClodexQueueItemMuted" }
  end

  chunks[#chunks + 1] = { item.label, accent_hl }
  if item.detail and item.detail ~= "" then
    chunks[#chunks + 1] = { "  " }
    chunks[#chunks + 1] = { item.detail, "ClodexStateCommandHint" }
  end
  return chunks
end

---@param heading string
---@param lines string[]
---@return string
local function markdown_section(heading, lines)
  local parts = { heading, "" }
  for _, line in ipairs(lines) do
    parts[#parts + 1] = line
  end
  return table.concat(parts, "\n")
end

---@param snacks_opts? table
---@param with_preview boolean
---@return table
local function picker_snacks(snacks_opts, with_preview)
  return vim.tbl_deep_extend("force", {
    preview = with_preview and "preview" or false,
    layout = {
      preset = "select",
      hidden = with_preview and {} or { "input", "preview" },
    },
  }, vim.deepcopy(snacks_opts or {}))
end

---@param snacks_opts table
---@param key string
---@param action_name string
local function bind_picker_action_key(snacks_opts, key, action_name)
  snacks_opts.win = snacks_opts.win or {}
  for _, field in ipairs({ "input", "list" }) do
    snacks_opts.win[field] = snacks_opts.win[field] or {}
    snacks_opts.win[field].keys = snacks_opts.win[field].keys or {}
    snacks_opts.win[field].keys[key] = { action_name, mode = { "n", "i" } }
  end
end

---@generic T
---@param items T[]
---@param opts { prompt?: string, snacks?: table, with_preview?: boolean, map_item?: fun(item: T, ctx: Clodex.UiSelect.MapContext<T>): Clodex.UiSelect.PickerEntry<T> }
---@param on_choice fun(value?: T, idx?: number, entry?: Clodex.UiSelect.PickerEntry<T>)
function M.pick_mapped(items, opts, on_choice)
  opts = opts or {}
  local entries = {}

  for index, item in ipairs(items) do
    local entry = opts.map_item and opts.map_item(item, {
      index = index,
      items = items,
    }) or {
      value = item,
      text = tostring(item),
    }
    entry.value = entry.value ~= nil and entry.value or item
    entry.text = entry.text or tostring(entry.value)
    entries[#entries + 1] = entry
  end

  return M.select(entries, {
    prompt = opts.prompt,
    snacks = picker_snacks(opts.snacks, opts.with_preview ~= false),
    format_item = function(entry, supports_chunks)
      if supports_chunks and entry.chunks then
        return entry.chunks
      end
      return entry.text
    end,
  }, function(entry, idx)
    on_choice(entry and entry.value or nil, idx, entry)
  end)
end

---@generic T
---@param items T[]
---@param opts? Clodex.UiSelect.SelectOpts
---@param on_choice fun(item?: T, idx?: number)
function M.select(items, opts, on_choice)
  opts = opts or {}
  opts.snacks = vim.tbl_deep_extend("force", {
    focus = "list",
    main = {
      enter = true,
    },
    win = {
      list = {
        enter = true,
      },
    },
    layout = {
      layout = {
        zindex = MODAL_ZINDEX,
      },
    },
  }, vim.deepcopy(opts.snacks or {}))
  local picker = SnacksSelect.select(items, opts, on_choice)

  vim.schedule(function()
    focus_picker_list(picker)
    vim.defer_fn(function()
      focus_picker_list(picker)
    end, 20)
  end)

  return picker
end

---@param opts Clodex.UiSelect.InputOpts
---@param on_confirm fun(value?: string)
function M.input(opts, on_confirm)
  opts = vim.deepcopy(opts or {})
  opts.win = opts.win or {}
  opts.win.zindex = math.max(opts.win.zindex or 0, MODAL_ZINDEX + 1)

  local previous_on_close = opts.win.on_close
  opts.win.on_close = function(win)
    clear_active_input(win)
    if previous_on_close then
      previous_on_close(win)
    end
  end

  M.close_active_input()

  local win
  win = SnacksInput.input(opts, function(value)
    clear_active_input(win)
    on_confirm(value)
  end)
  active_input = win

  if type(opts.changed) == "function" then
    win:on({ "TextChangedI", "TextChanged" }, function()
      if not win:valid() then
        return
      end
      opts.changed(win:text())
    end, { buf = true })
  end

  vim.schedule(function()
    focus_input_window(win)
    vim.defer_fn(function()
      focus_input_window(win)
    end, 20)
  end)

  return win
end

--- Closes any tracked one-line input popup that is still alive.
--- This prevents stale rename/search prompts from outliving their parent panels.
function M.close_active_input()
  local win = active_input
  active_input = nil
  if not win or not win:valid() then
    return
  end
  win:close()
end

---@return boolean
function M.has_active_input()
  return active_input ~= nil and active_input:valid()
end

---@param line string
---@param cursor_col integer
---@return integer
local function completion_start_col(line, cursor_col)
  local start_col = cursor_col
  while start_col > 0 do
    local char = line:sub(start_col, start_col)
    if char:match("[%w_&]") == nil then
      break
    end
    start_col = start_col - 1
  end
  return start_col
end

---@param buf integer
local function configure_prompt_context_completeopt(buf)
  local completeopt = vim.bo[buf].completeopt
  if completeopt == "" then
    completeopt = vim.o.completeopt
  end
  local options = vim.split(completeopt, ",", { plain = true, trimempty = true })
  local filtered = {} ---@type string[]
  local seen = {} ---@type table<string, boolean>

  for _, option in ipairs(options) do
    if option ~= "noinsert" and option ~= "" and not seen[option] then
      seen[option] = true
      filtered[#filtered + 1] = option
    end
  end

  if not seen.longest then
    filtered[#filtered + 1] = "longest"
  end

  vim.bo[buf].completeopt = table.concat(filtered, ",")
end

--- Provides built-in prompt context completion items for the prompt details buffer.
--- The menu inserts `&token` placeholders and only expands them when the prompt is submitted.
---@param findstart integer
---@param base string
---@return integer|Clodex.UiSelect.CompletedItem[]
function M.prompt_context_complete(findstart, base)
  local buf = vim.api.nvim_get_current_buf()
  local context = prompt_context_completion[buf]
  if findstart == 1 then
    local line = vim.api.nvim_get_current_line()
    local cursor_col = vim.api.nvim_win_get_cursor(0)[2]
    return completion_start_col(line, cursor_col)
  end

  if type(base) ~= "string" or base == "" or not vim.startswith(base, "&") or not context then
    return {}
  end

  local matches = {} ---@type Clodex.UiSelect.CompletedItem[]
  for _, item in ipairs(PromptContext.tokens(context)) do
    if not item.disabled and vim.startswith(item.token, base) then
      local expansion = PromptContext.expand_token(item.token, context)
      if expansion and expansion ~= "" then
        matches[#matches + 1] = {
          word = item.token,
          abbr = item.label,
          menu = item.detail,
          info = expansion,
        }
      end
    end
  end
  return matches
end

---@param items Clodex.UiSelect.TextChoice[]
---@param opts? Clodex.UiSelect.SelectOpts
---@param on_choice fun(item?: Clodex.UiSelect.TextChoice, idx?: number)
function M.pick_text(items, opts, on_choice)
  opts = opts or {}
  return M.pick_mapped(items, {
    prompt = opts.prompt,
    snacks = opts.snacks,
    with_preview = true,
    map_item = function(item)
      local prefix = item.icon and item.icon ~= "" and (item.icon .. " ") or ""
      local badge = item.badge and item.badge ~= "" and ("[%s] "):format(item.badge) or ""
      local detail = item.detail and item.detail ~= "" and ("  " .. item.detail) or ""
      return {
        value = item,
        text = prefix .. badge .. item.label .. detail,
        chunks = text_choice_chunks(item),
        preview = item.preview,
        preview_title = item.preview_title,
      }
    end,
  }, function(item, idx)
    on_choice(item, idx)
  end)
end

---@param projects Clodex.Project[]
---@param opts? { prompt?: string, include_none?: boolean, active_root?: string, on_delete?: fun(project: Clodex.Project), on_rename?: fun(project: Clodex.Project), snacks?: table }
---@param on_choice fun(project?: Clodex.Project)
function M.pick_project(projects, opts, on_choice)
  opts = opts or {}
  local items = {} ---@type { project?: Clodex.Project, label: string, spacer?: string, preview?: { text: string, ft?: string, loc?: boolean }, preview_title?: string }[]
  local name_width = 0
  local snacks_opts = picker_snacks(opts.snacks, true)
  local action_hints = {} ---@type string[]

  for _, project in ipairs(projects) do
    name_width = math.max(name_width, vim.fn.strdisplaywidth(project.name))
  end

  if opts.include_none then
    items[#items + 1] = {
      label = "No active project",
      preview = {
        text = "# Clodex Project\n\n- Active project override is disabled for this tab.",
        ft = "markdown",
        loc = false,
      },
      preview_title = "No active project",
    }
  end

  for _, project in ipairs(projects) do
    local spacer = (" "):rep(math.max(name_width - vim.fn.strdisplaywidth(project.name), 0) + 2)
    items[#items + 1] = {
      project = project,
      label = project.name .. spacer .. project.root,
      spacer = spacer,
      preview = {
        text = table.concat({
          "# Clodex Project",
          "",
          ("- Name: `%s`"):format(project.name),
          ("- Root: `%s`"):format(project.root),
          ("- Exists on disk: `%s`"):format(vim.uv.fs_stat(project.root) ~= nil and "yes" or "no"),
          ("- Active in this tab: `%s`"):format(opts.active_root == project.root and "yes" or "no"),
        }, "\n"),
        ft = "markdown",
        loc = false,
      },
      preview_title = project.name,
    }
  end

  if #items == 0 then
    on_choice(nil)
    return
  end

  local function add_project_action(key, name, description, callback)
    snacks_opts.actions = snacks_opts.actions or {}
    snacks_opts.actions[name] = {
      desc = description,
      action = function(picker, entry)
        entry = entry and entry.item or entry
        local selected = entry and entry.value or nil
        if not selected then
          return
        end
        if picker and picker.close then
          picker:close()
        end
        vim.schedule(function()
          callback(selected)
        end)
      end,
    }
    bind_picker_action_key(snacks_opts, key, name)
    action_hints[#action_hints + 1] = ("%s: %s"):format(key, description)
  end

  if opts.on_delete then
    add_project_action("d", "clodex_project_delete", "Delete project", function(project)
      opts.on_delete(project)
    end)
  end

  if opts.on_rename then
    add_project_action("r", "clodex_project_rename", "Rename project", function(project)
      opts.on_rename(project)
    end)
  end

  if #action_hints > 0 then
    snacks_opts.help = snacks_opts.help or true
  end

  return M.pick_mapped(items, {
    prompt = opts.prompt or "Select Clodex project",
    snacks = snacks_opts,
    with_preview = true,
    map_item = function(item)
      local project = item.project
      return {
        value = project,
        text = item.label,
        chunks = project and {
          { project.name, "ClodexPickerProject" },
          { item.spacer or "  " },
          { project.root, "ClodexPickerRoot" },
        } or nil,
        preview = item.preview,
        preview_title = item.preview_title,
      }
    end,
  }, function(project)
    on_choice(project)
  end)
end

--- Joins multiline input lines into a single string for submission.
--- This keeps `multiline_input` consistent regardless of how the buffer is edited.
---@param lines string[]
---@return string
local function join_lines(lines)
  return table.concat(lines, "\n")
end

--- Computes the widest line width for the dynamic dialog sizing.
--- Used by popup width sizing to avoid clipping when default text is long.
---@param lines string[]
---@return integer
local function longest_width(lines)
  local width = 1
  for _, line in ipairs(lines) do
    width = math.max(width, vim.fn.strdisplaywidth(line))
  end
  return width
end

--- Inserts text into the prompt buffer at the current cursor position.
--- This keeps context expansion and quick prompts working in both normal and insert mode.
---@param buf integer
---@param win integer
---@param text string
local function insert_text(buf, win, text)
  local cursor = vim.api.nvim_win_get_cursor(win)
  local row = cursor[1] - 1
  local col = cursor[2]
  local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
  local before = line:sub(1, col)
  local after = line:sub(col + 1)
  local pieces = vim.split(text, "\n", { plain = true })

  if #pieces == 1 then
    vim.api.nvim_buf_set_lines(buf, row, row + 1, false, {
      before .. pieces[1] .. after,
    })
    vim.api.nvim_win_set_cursor(win, { row + 1, col + #pieces[1] })
    return
  end

  pieces[1] = before .. pieces[1]
  pieces[#pieces] = pieces[#pieces] .. after
  vim.api.nvim_buf_set_lines(buf, row, row + 1, false, pieces)
  vim.api.nvim_win_set_cursor(win, { row + #pieces, #pieces[#pieces] - #after })
end

---@param win integer
---@param theme? Clodex.UiWin.ThemePreset
local function style_prompt_editor(win, theme)
  ui_win.apply_theme(win, theme or "prompt_editor")
end

---@param buf integer
---@param lines string[]
local function render_hint_lines(buf, lines)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  for line_index, line in ipairs(lines) do
    for _, key in ipairs(PROMPT_EDITOR_HINT_KEYS) do
      local start = 1
      while true do
        local from = line:find(key, start, true)
        if not from then
          break
        end
        vim.api.nvim_buf_set_extmark(buf, PROMPT_CONTEXT_HIGHLIGHT_NS, line_index - 1, from - 1, {
          end_row = line_index - 1,
          end_col = from + #key - 1,
          hl_group = "ClodexPromptEditorKey",
        })
        start = from + #key
      end
    end
  end
  vim.bo[buf].modifiable = false
end

---@param context Clodex.PromptContext.Capture?
---@return table<string, boolean>
local function prompt_context_token_lookup(context)
  local lookup = {} ---@type table<string, boolean>
  for _, item in ipairs(PromptContext.tokens(context)) do
    if not item.disabled then
      lookup[item.token] = true
    end
  end
  return lookup
end

---@param buf integer
---@param context Clodex.PromptContext.Capture?
local function render_prompt_context_highlights(buf, context)
  vim.api.nvim_buf_clear_namespace(buf, PROMPT_CONTEXT_HIGHLIGHT_NS, 0, -1)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  local token_lookup = prompt_context_token_lookup(context)
  if next(token_lookup) == nil then
    return
  end

  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  for row, line in ipairs(lines) do
    local search_from = 1
    while true do
      local start_col, end_col = line:find("&[%a_][%w_]*", search_from)
      if not start_col then
        break
      end

      local token = line:sub(start_col, end_col)
      if token_lookup[token] then
        vim.api.nvim_buf_set_extmark(buf, PROMPT_CONTEXT_HIGHLIGHT_NS, row - 1, start_col - 1, {
          end_row = row - 1,
          end_col = end_col,
          hl_group = "ClodexPromptEditorContext",
        })
      end
      search_from = end_col + 1
    end
  end
end

---@param buf integer
---@param context Clodex.PromptContext.Capture?
function M.refresh_prompt_context(buf, context)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  vim.bo[buf].completefunc = "v:lua.require'clodex.ui.select'.prompt_context_complete"
  configure_prompt_context_completeopt(buf)
  prompt_context_completion[buf] = context
  render_prompt_context_highlights(buf, context)
end

---@param buf integer
function M.clear_prompt_context(buf)
  prompt_context_completion[buf] = nil
  if vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_clear_namespace(buf, PROMPT_CONTEXT_HIGHLIGHT_NS, 0, -1)
  end
end

---@param buf integer
local function disable_prompt_pair_highlights(buf)
  vim.bo[buf].syntax = "off"
  vim.b[buf].matchup_matchparen_enabled = 0
  vim.b[buf].ts_rainbow = false
  pcall(vim.treesitter.stop, buf)
end

---@param actions Clodex.UiSelect.MultilineAction[]
---@return string[]
local function prompt_editor_hint_lines(actions)
  local action_chunks = {}
  for _, action in ipairs(actions) do
    action_chunks[#action_chunks + 1] = ("%s %s"):format(action.key, action.label)
  end

  return {
    ("  <CR>/<Down> details   <Tab> switch fields   <Up>/<S-Tab> title   %s"):format(
      table.concat(action_chunks, "   ")
    ),
    "  <C-v> paste   & context   <C-x>/x quick prompt   q / Esc cancel",
  }
end

---@param actions Clodex.UiSelect.MultilineAction[]
---@return string[]
local function single_field_hint_lines(actions)
  local action_chunks = {}
  for _, action in ipairs(actions) do
    action_chunks[#action_chunks + 1] = ("%s %s"):format(action.key, action.label)
  end

  return {
    ("  <CR> submit   %s"):format(table.concat(action_chunks, "   ")),
    "  <C-v> paste   & context   <C-x>/x quick prompt   q / Esc cancel",
  }
end

---@param opts Clodex.UiSelect.MultilineOpts
---@param on_confirm fun(value?: string, action?: string)
function M.multiline_input(opts, on_confirm)
  opts = opts or {}
  local submit_actions = vim.deepcopy(opts.submit_actions or {
    { value = "save", label = "save", key = "<C-s>" },
    { value = "queue", label = "queue", key = "<C-q>" },
  })
  local hint_lines = prompt_editor_hint_lines(submit_actions)
  local default = opts.default or ""
  local captured_context = opts.context
  local parsed = Prompt.parse(default) or {
    title = vim.trim(default),
    details = nil,
  }
  local title = parsed.title or ""
  local detail_lines = parsed.details and vim.split(parsed.details, "\n", { plain = true }) or { "" }
  local ui = vim.api.nvim_list_uis()[1]
  local editor_width = ui and ui.width or vim.o.columns
  local editor_height = ui and ui.height or vim.o.lines
  local min_height = math.max(opts.min_height or PROMPT_EDITOR_MIN_HEIGHT, PROMPT_EDITOR_MIN_HEIGHT)
  local max_height = math.max(editor_height - PROMPT_EDITOR_HEIGHT_MARGIN, min_height)
  local width = math.min(
    math.max(
      longest_width(vim.tbl_flatten({ title, unpack_values(detail_lines), hint_lines }))
        + PROMPT_EDITOR_WIDTH_PADDING,
      PROMPT_EDITOR_MIN_WIDTH
    ),
    math.max(editor_width - PROMPT_EDITOR_MAX_MARGIN - PROMPT_EDITOR_BORDER_COLS, 24)
  )
  local title_buf = ui_win.create_buffer({ preset = "text" })
  local body_buf = ui_win.create_buffer({ preset = "markdown" })
  local hint_buf = ui_win.create_buffer({ preset = "scratch" })
  vim.bo[hint_buf].modifiable = false

  --- Calculates current required popup height from buffer content.
  --- The value is shared by size callback and repositioning math.
  local function calc_height()
    local count = math.max(#vim.api.nvim_buf_get_lines(body_buf, 0, -1, false), min_height)
    return math.min(count, max_height)
  end

  local function total_height()
    return PROMPT_EDITOR_TITLE_HEIGHT
      + calc_height()
      + PROMPT_EDITOR_HINT_HEIGHT
      + (PROMPT_EDITOR_BORDER_ROWS * 2)
      + PROMPT_EDITOR_FIELD_GAP
      + PROMPT_EDITOR_HINT_GAP
  end

  local function hint_row()
    return math.max(math.floor((editor_height - total_height()) / 2), 1)
      + PROMPT_EDITOR_TITLE_HEIGHT
      + PROMPT_EDITOR_BORDER_ROWS
      + PROMPT_EDITOR_FIELD_GAP
      + PROMPT_EDITOR_BORDER_ROWS
      + calc_height()
      + PROMPT_EDITOR_HINT_GAP
  end

  local function prompt_context()
    if captured_context == nil then
      captured_context = PromptContext.capture()
    end
    return captured_context
  end

  local title_win = ui_win.open({
    buf = title_buf,
    enter = true,
    backdrop = PROMPT_EDITOR_BACKDROP,
    border = "rounded",
    title = (" %s "):format(opts.prompt),
    title_pos = "center",
    width = width,
    height = PROMPT_EDITOR_TITLE_HEIGHT,
    row = function()
      return math.max(math.floor((editor_height - total_height()) / 2), 1)
    end,
    col = function()
      return math.max(math.floor((editor_width - width) / 2), 1)
    end,
    wo = {
      wrap = false,
      number = false,
      relativenumber = false,
      signcolumn = "no",
      foldcolumn = "0",
      cursorline = false,
      spell = false,
    },
    bo = {
      buftype = "nofile",
      modifiable = true,
    },
    zindex = PROMPT_EDITOR_ZINDEX,
  })
  local body_win = ui_win.open({
    buf = body_buf,
    enter = false,
    backdrop = PROMPT_EDITOR_BACKDROP,
    border = "rounded",
    title = " Details ",
    title_pos = "center",
    width = width,
    height = function()
      return calc_height()
    end,
    row = function()
      return math.max(math.floor((editor_height - total_height()) / 2), 1)
        + PROMPT_EDITOR_TITLE_HEIGHT
        + PROMPT_EDITOR_BORDER_ROWS
        + PROMPT_EDITOR_FIELD_GAP
    end,
    col = function()
      return math.max(math.floor((editor_width - width) / 2), 1)
    end,
    wo = {
      wrap = true,
      linebreak = true,
      breakindent = true,
      number = false,
      relativenumber = false,
      signcolumn = "no",
      foldcolumn = "0",
      cursorline = false,
      spell = false,
    },
    bo = {
      filetype = "markdown",
      buftype = "nofile",
      modifiable = true,
    },
    zindex = PROMPT_EDITOR_ZINDEX,
  })
  local hint_win = ui_win.open({
    buf = hint_buf,
    enter = false,
    backdrop = PROMPT_EDITOR_BACKDROP,
    border = "rounded",
    width = width,
    height = PROMPT_EDITOR_HINT_HEIGHT,
    row = function()
      return hint_row()
    end,
    col = function()
      return math.max(math.floor((editor_width - width) / 2), 1)
    end,
    wo = {
      wrap = false,
      linebreak = false,
      breakindent = false,
      number = false,
      relativenumber = false,
      signcolumn = "no",
      foldcolumn = "0",
      cursorline = false,
      spell = false,
    },
    bo = {
      buftype = "nofile",
      modifiable = false,
    },
    zindex = PROMPT_EDITOR_ZINDEX - 1,
  })

  --- Updates floating window dimensions after every content change.
  --- This keeps the edit popup responsive without manual user action.
  local function resize()
    if not title_win:valid() or not body_win:valid() or not hint_win:valid() then
      return
    end
    local next_total_height = total_height()
    local next_body_height = calc_height()
    local next_hint_row = hint_row()
    if title_win.opts._clodex_total_height == next_total_height
      and body_win.opts._clodex_height == next_body_height
      and hint_win.opts._clodex_hint_row == next_hint_row then
      return
    end
    title_win.opts._clodex_total_height = next_total_height
    body_win.opts._clodex_height = next_body_height
    hint_win.opts._clodex_hint_row = next_hint_row
    title_win:update()
    body_win:update()
    hint_win:update()
  end

  local function focus_title()
    if not title_win:valid() then
      return
    end
    vim.api.nvim_set_current_win(title_win.win)
    vim.cmd.startinsert()
  end

  local function focus_body()
    if not body_win:valid() then
      return
    end
    vim.api.nvim_set_current_win(body_win.win)
    vim.cmd.startinsert()
  end

  --- Keeps body navigation intuitive by only jumping back to title from the first line.
  --- Later lines should preserve their normal cursor movement within the details buffer.
  local function should_focus_title_from_body()
    if not body_win:valid() then
      return false
    end
    if vim.fn.pumvisible() == 1 then
      return false
    end
    return vim.api.nvim_win_get_cursor(body_win.win)[1] <= 1
  end

  local done = false
  --- Closes the popup once and dispatches final content to caller.
  --- A guard flag prevents duplicate callbacks from multiple close triggers.
  local function close(value, action)
    if done then
      return
    end
    done = true
    if body_win:valid() then
      body_win:close()
    end
    if title_win:valid() then
      title_win:close()
    end
    if hint_win:valid() then
      hint_win:close()
    end
    M.clear_prompt_context(body_buf)
    vim.schedule(function()
      on_confirm(value, action or submit_actions[1].value)
    end)
  end

  vim.api.nvim_buf_set_lines(title_buf, 0, -1, false, { title })
  vim.api.nvim_buf_set_lines(body_buf, 0, -1, false, detail_lines)
  render_hint_lines(hint_buf, hint_lines)
  disable_prompt_pair_highlights(title_buf)
  disable_prompt_pair_highlights(body_buf)
  disable_prompt_pair_highlights(hint_buf)
  style_prompt_editor(title_win.win)
  style_prompt_editor(body_win.win)
  style_prompt_editor(hint_win.win, "prompt_footer")
  M.refresh_prompt_context(body_buf, prompt_context())

  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = hint_buf,
    callback = function()
      if title_win:valid() and body_win:valid() then
        body_win:close()
        title_win:close()
      end
    end,
  })

  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    buffer = title_buf,
    callback = resize,
  })
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    buffer = body_buf,
    callback = function()
      resize()
      M.refresh_prompt_context(body_buf, prompt_context())
    end,
  })

  --- Submits the full current buffer content into the confirm callback.
  --- It is used by Enter and Ctrl-S as explicit commit actions.
  local function submit(action)
    local current_title = vim.trim(vim.api.nvim_buf_get_lines(title_buf, 0, 1, false)[1] or "")
    local details = vim.trim(join_lines(vim.api.nvim_buf_get_lines(body_buf, 0, -1, false)))
    if current_title == "" and details == "" then
      close(nil, action)
      return
    end
    local rendered = Prompt.render(current_title, details ~= "" and details or nil)
    close(PromptContext.expand_text(rendered, prompt_context()), action)
  end

  --- Starts Neovim's built-in completion popup for prompt context tokens.
  --- Keeping this native makes prompt authoring feel like ordinary insert completion.
  local function trigger_context_completion()
    M.refresh_prompt_context(body_buf, prompt_context())
    if not body_win:valid() then
      return
    end
    vim.api.nvim_set_current_win(body_win.win)
    vim.cmd.startinsert()
    vim.schedule(function()
      if not body_win:valid() or vim.api.nvim_get_current_buf() ~= body_buf then
        return
      end
      vim.api.nvim_feedkeys(vim.keycode("&<C-x><C-u>"), "n", false)
    end)
  end

  --- Opens the canned prompt picker and replaces or inserts the selected template.
  --- An empty prompt buffer is replaced wholesale so quick prompts behave like shortcuts.
  local function insert_quick_prompt()
    local items = PromptContext.quick_prompts(prompt_context())
    local picker_items = {}
    for _, item in ipairs(items) do
      local spec = Prompt.parse(item.text) or {
        title = vim.trim(item.text),
        details = nil,
      }
      local category = item.kind and Prompt.categories.get(item.kind) or nil
      local preview_lines = {
        markdown_section(("# %s"):format(item.label), vim.tbl_filter(function(line)
          return line ~= nil
        end, {
          category and ("- Kind: `%s`"):format(category.label) or nil,
          ("- Shortcut title: `%s`"):format(spec.title),
          item.disabled and "- Status: unavailable in current context" or "- Status: ready to insert",
        })),
        "",
        markdown_section("## What gets inserted", {
          "```text",
          item.text,
          "```",
        }),
      }
      picker_items[#picker_items + 1] = {
        text = item.text,
        label = item.label,
        detail = spec.title,
        badge = category and category.label or nil,
        accent_hl = category and Prompt.title_group(category.id) or nil,
        disabled = item.disabled,
        preview = {
          text = table.concat(preview_lines, "\n"),
          ft = "markdown",
          loc = false,
        },
        preview_title = item.label,
      }
    end

    M.pick_text(picker_items, {
      prompt = "Prompt shortcuts",
    }, function(item)
      if not item then
        focus_body()
        return
      end
      if item.disabled then
        focus_body()
        return
      end

      local spec = Prompt.parse(item.text) or {
        title = vim.trim(item.text),
        details = nil,
      }
      local current_title = vim.trim(vim.api.nvim_buf_get_lines(title_buf, 0, 1, false)[1] or "")
      local current_text = vim.trim(join_lines(vim.api.nvim_buf_get_lines(body_buf, 0, -1, false)))

      if current_title == "" and current_text == "" then
        vim.api.nvim_buf_set_lines(title_buf, 0, -1, false, { spec.title or "" })
        vim.api.nvim_buf_set_lines(
          body_buf,
          0,
          -1,
          false,
          spec.details and vim.split(spec.details, "\n", { plain = true }) or { "" }
        )
        vim.api.nvim_win_set_cursor(body_win.win, { 1, 0 })
      else
        insert_text(body_buf, body_win.win, item.text)
      end
      resize()
      focus_body()
    end)
  end

  --- Saves the current clipboard image and inserts its prompt text at the cursor.
  --- Storage details are delegated to the caller so this editor stays reusable.
  local function paste_image()
    if type(opts.paste_image) ~= "function" then
      return
    end
    local text = opts.paste_image()
    if not text or text == "" then
      return
    end
    insert_text(body_buf, body_win.win, text)
    resize()
    focus_body()
  end

  vim.keymap.set({ "n", "i" }, "<CR>", focus_body, { buffer = title_buf, silent = true })
  vim.keymap.set({ "n", "i" }, "<Down>", focus_body, { buffer = title_buf, silent = true })
  vim.keymap.set({ "n", "i" }, "<Tab>", focus_body, { buffer = title_buf, silent = true })
  for _, action in ipairs(submit_actions) do
    vim.keymap.set({ "n", "i" }, action.key, function()
      submit(action.value)
    end, { buffer = title_buf, silent = true })
  end
  vim.keymap.set({ "n", "i" }, "<C-v>", function()
    focus_body()
    paste_image()
  end, { buffer = title_buf, silent = true })
  vim.keymap.set("n", "q", function()
    close(nil)
  end, { buffer = title_buf, silent = true })
  vim.keymap.set({ "n", "i" }, "<Esc>", function()
    close(nil)
  end, { buffer = title_buf, silent = true })

  vim.keymap.set("n", "<CR>", function()
    submit(submit_actions[1].value)
  end, { buffer = body_buf, silent = true })
  for _, action in ipairs(submit_actions) do
    vim.keymap.set({ "n", "i" }, action.key, function()
      submit(action.value)
    end, { buffer = body_buf, silent = true })
  end
  vim.keymap.set("n", "&", trigger_context_completion, { buffer = body_buf, silent = true })
  vim.keymap.set("i", "&", function()
    M.refresh_prompt_context(body_buf, prompt_context())
    return "&" .. vim.keycode("<C-x><C-u>")
  end, {
    buffer = body_buf,
    silent = true,
    expr = true,
  })
  vim.keymap.set("n", "x", insert_quick_prompt, { buffer = body_buf, silent = true })
  vim.keymap.set("i", "<C-x>", insert_quick_prompt, { buffer = body_buf, silent = true })
  vim.keymap.set({ "n", "i" }, "<C-v>", paste_image, { buffer = body_buf, silent = true })
  vim.keymap.set({ "n", "i" }, "<Tab>", focus_title, { buffer = body_buf, silent = true })
  vim.keymap.set({ "n", "i" }, "<S-Tab>", focus_title, { buffer = body_buf, silent = true })
  vim.keymap.set({ "n", "i" }, "<Up>", function()
    if should_focus_title_from_body() then
      vim.schedule(focus_title)
      return vim.keycode("<Ignore>")
    end
    return vim.keycode("<Up>")
  end, {
    buffer = body_buf,
    silent = true,
    expr = true,
  })
  vim.keymap.set("n", "q", function()
    close(nil)
  end, { buffer = body_buf, silent = true })
  vim.keymap.set("n", "<Esc>", function()
    close(nil)
  end, { buffer = body_buf, silent = true })
  vim.api.nvim_create_autocmd("WinClosed", {
    once = true,
    pattern = tostring(hint_win.win),
    callback = function()
      close(nil)
    end,
  })
  vim.api.nvim_create_autocmd("WinClosed", {
    once = true,
    pattern = tostring(title_win.win),
    callback = function()
      close(nil)
    end,
  })
  vim.api.nvim_create_autocmd("WinClosed", {
    once = true,
    pattern = tostring(body_win.win),
    callback = function()
      close(nil)
    end,
  })

  focus_title()
end

---@param opts { prompt: string, default?: string, min_height?: integer, context?: Clodex.PromptContext.Capture, paste_image?: fun(): string?, submit_actions?: Clodex.UiSelect.MultilineAction[] }
---@param on_confirm fun(value?: string, action?: string)
function M.multiline_message_input(opts, on_confirm)
  opts = opts or {}
  local submit_actions = vim.deepcopy(opts.submit_actions or {
    { value = "save", label = "save", key = "<C-s>" },
  })
  local hint_lines = single_field_hint_lines(submit_actions)
  local default_lines = vim.split(opts.default or "", "\n", { plain = true })
  local captured_context = opts.context
  local ui = vim.api.nvim_list_uis()[1]
  local editor_width = ui and ui.width or vim.o.columns
  local editor_height = ui and ui.height or vim.o.lines
  local min_height = math.max(opts.min_height or PROMPT_EDITOR_MIN_HEIGHT, PROMPT_EDITOR_MIN_HEIGHT)
  local max_height = math.max(editor_height - PROMPT_EDITOR_HEIGHT_MARGIN, min_height)
  local width = math.min(
    math.max(
      longest_width(vim.tbl_flatten({ unpack_values(default_lines), hint_lines })) + PROMPT_EDITOR_WIDTH_PADDING,
      PROMPT_EDITOR_MIN_WIDTH
    ),
    math.max(editor_width - PROMPT_EDITOR_MAX_MARGIN - PROMPT_EDITOR_BORDER_COLS, 24)
  )
  local body_buf = ui_win.create_buffer({ preset = "markdown" })
  local hint_buf = ui_win.create_buffer({ preset = "scratch" })
  vim.bo[hint_buf].modifiable = false

  local function calc_height()
    local count = math.max(#vim.api.nvim_buf_get_lines(body_buf, 0, -1, false), min_height)
    return math.min(count, max_height)
  end

  local function total_height()
    return calc_height() + PROMPT_EDITOR_HINT_HEIGHT + (PROMPT_EDITOR_BORDER_ROWS * 2) + PROMPT_EDITOR_HINT_GAP
  end

  local function body_row()
    return math.max(math.floor((editor_height - total_height()) / 2), 1)
  end

  local function hint_row()
    return body_row() + calc_height() + PROMPT_EDITOR_BORDER_ROWS + PROMPT_EDITOR_HINT_GAP
  end

  local function prompt_context()
    if captured_context == nil then
      captured_context = PromptContext.capture()
    end
    return captured_context
  end

  local body_win = ui_win.open({
    buf = body_buf,
    enter = true,
    backdrop = PROMPT_EDITOR_BACKDROP,
    border = "rounded",
    title = (" %s "):format(opts.prompt),
    title_pos = "center",
    width = width,
    height = function()
      return calc_height()
    end,
    row = body_row,
    col = function()
      return math.max(math.floor((editor_width - width) / 2), 1)
    end,
    wo = {
      wrap = true,
      linebreak = true,
      breakindent = true,
      number = false,
      relativenumber = false,
      signcolumn = "no",
      foldcolumn = "0",
      cursorline = false,
      spell = false,
    },
    bo = {
      filetype = "markdown",
      buftype = "nofile",
      modifiable = true,
    },
    zindex = PROMPT_EDITOR_ZINDEX,
  })
  local hint_win = ui_win.open({
    buf = hint_buf,
    enter = false,
    backdrop = PROMPT_EDITOR_BACKDROP,
    border = "rounded",
    width = width,
    height = PROMPT_EDITOR_HINT_HEIGHT,
    row = hint_row,
    col = function()
      return math.max(math.floor((editor_width - width) / 2), 1)
    end,
    wo = {
      wrap = false,
      linebreak = false,
      breakindent = false,
      number = false,
      relativenumber = false,
      signcolumn = "no",
      foldcolumn = "0",
      cursorline = false,
      spell = false,
    },
    bo = {
      buftype = "nofile",
      modifiable = false,
    },
    zindex = PROMPT_EDITOR_ZINDEX - 1,
  })

  local function resize()
    if not body_win:valid() or not hint_win:valid() then
      return
    end
    local next_body_height = calc_height()
    local next_hint_row = hint_row()
    if body_win.opts._clodex_height == next_body_height and hint_win.opts._clodex_hint_row == next_hint_row then
      return
    end
    body_win.opts._clodex_height = next_body_height
    hint_win.opts._clodex_hint_row = next_hint_row
    body_win:update()
    hint_win:update()
  end

  local done = false
  local function close(value, action)
    if done then
      return
    end
    done = true
    if body_win:valid() then
      body_win:close()
    end
    if hint_win:valid() then
      hint_win:close()
    end
    M.clear_prompt_context(body_buf)
    vim.schedule(function()
      on_confirm(value, action or submit_actions[1].value)
    end)
  end

  vim.api.nvim_buf_set_lines(body_buf, 0, -1, false, #default_lines > 0 and default_lines or { "" })
  render_hint_lines(hint_buf, hint_lines)
  disable_prompt_pair_highlights(body_buf)
  disable_prompt_pair_highlights(hint_buf)
  style_prompt_editor(body_win.win)
  style_prompt_editor(hint_win.win, "prompt_footer")
  M.refresh_prompt_context(body_buf, prompt_context())

  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    buffer = body_buf,
    callback = function()
      resize()
      M.refresh_prompt_context(body_buf, prompt_context())
    end,
  })

  local function submit(action)
    local details = vim.trim(join_lines(vim.api.nvim_buf_get_lines(body_buf, 0, -1, false)))
    if details == "" then
      close(nil, action)
      return
    end
    close(PromptContext.expand_text(details, prompt_context()), action)
  end

  local function trigger_context_completion()
    M.refresh_prompt_context(body_buf, prompt_context())
    vim.api.nvim_set_current_win(body_win.win)
    vim.cmd.startinsert()
    vim.schedule(function()
      if not body_win:valid() or vim.api.nvim_get_current_buf() ~= body_buf then
        return
      end
      vim.api.nvim_feedkeys(vim.keycode("&<C-x><C-u>"), "n", false)
    end)
  end

  local function insert_quick_prompt()
    local items = PromptContext.quick_prompts(prompt_context())
    local picker_items = {}
    for _, item in ipairs(items) do
      picker_items[#picker_items + 1] = {
        text = item.text,
        label = item.label,
        detail = item.text,
        badge = item.kind and Prompt.categories.get(item.kind).label or nil,
        accent_hl = item.kind and Prompt.title_group(item.kind) or nil,
        disabled = item.disabled,
      }
    end

    M.pick_text(picker_items, {
      prompt = "Prompt shortcuts",
      snacks = {
        preview = false,
      },
    }, function(item)
      if not item or item.disabled then
        vim.api.nvim_set_current_win(body_win.win)
        return
      end
      insert_text(body_buf, body_win.win, item.text)
      resize()
      vim.api.nvim_set_current_win(body_win.win)
    end)
  end

  local function paste_image()
    if type(opts.paste_image) ~= "function" then
      return
    end
    local text = opts.paste_image()
    if not text or text == "" then
      return
    end
    insert_text(body_buf, body_win.win, text)
    resize()
    vim.api.nvim_set_current_win(body_win.win)
  end

  vim.keymap.set("n", "<CR>", function()
    submit(submit_actions[1].value)
  end, { buffer = body_buf, silent = true })
  for _, action in ipairs(submit_actions) do
    vim.keymap.set({ "n", "i" }, action.key, function()
      submit(action.value)
    end, { buffer = body_buf, silent = true })
  end
  vim.keymap.set("n", "&", trigger_context_completion, { buffer = body_buf, silent = true })
  vim.keymap.set("i", "&", function()
    M.refresh_prompt_context(body_buf, prompt_context())
    return "&" .. vim.keycode("<C-x><C-u>")
  end, {
    buffer = body_buf,
    silent = true,
    expr = true,
  })
  vim.keymap.set("n", "x", insert_quick_prompt, { buffer = body_buf, silent = true })
  vim.keymap.set("i", "<C-x>", insert_quick_prompt, { buffer = body_buf, silent = true })
  vim.keymap.set({ "n", "i" }, "<C-v>", paste_image, { buffer = body_buf, silent = true })
  vim.keymap.set("n", "q", function()
    close(nil)
  end, { buffer = body_buf, silent = true })
  vim.keymap.set({ "n", "i" }, "<Esc>", function()
    close(nil)
  end, { buffer = body_buf, silent = true })
  vim.api.nvim_create_autocmd("WinClosed", {
    once = true,
    pattern = tostring(hint_win.win),
    callback = function()
      close(nil)
    end,
  })
  vim.api.nvim_create_autocmd("WinClosed", {
    once = true,
    pattern = tostring(body_win.win),
    callback = function()
      close(nil)
    end,
  })

  vim.api.nvim_set_current_win(body_win.win)
  vim.cmd.startinsert()
end

---@param prompt string
---@param on_choice fun(confirmed: boolean)
function M.confirm(prompt, on_choice)
  local items = {
    {
      label = "Yes",
      detail = "Confirm action",
      value = true,
    },
    {
      label = "No",
      detail = "Cancel action",
      value = false,
    },
  }

  return M.select(items, {
    prompt = prompt,
    format_item = function(item, supports_chunks)
      if not supports_chunks then
        return item.label
      end
      local hl = item.value and "ClodexConfirmButtonActive" or "ClodexConfirmButton"
      return {
        { item.label, hl },
        { item.detail and ("  " .. item.detail) or "", "ClodexStateCommandHint" },
      }
    end,
    snacks = {
      preview = false,
      layout = {
        preset = "select",
        hidden = { "input", "preview" },
        layout = {
          width = 0.45,
          min_width = 36,
        },
      },
    },
  }, function(item)
    on_choice(item and item.value == true or false)
  end)
end

return M
