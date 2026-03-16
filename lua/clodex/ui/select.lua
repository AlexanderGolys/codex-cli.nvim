local M = {}
local SnacksInput = require("snacks.input")
local SnacksSelect = require("snacks.picker.select")
local Prompt = require("clodex.prompt")
local PromptContext = require("clodex.prompt.context")
local ui_win = require("clodex.ui.win")
local unpack_values = require("clodex.util").unpack_values

local SELECT_ZINDEX = 70
local CONFIRM_ZINDEX = 80
local CONFIRM_BACKDROP = 40
local CONFIRM_MIN_WIDTH = 28
local CONFIRM_WIDTH_PADDING = 8
local CONFIRM_HEIGHT = 3
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
local PROMPT_EDITOR_ZINDEX = 70
local PROMPT_EDITOR_BACKDROP = 40
local PROMPT_EDITOR_HINT_HEIGHT = 2
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
---@field preview? { text: string, ft?: string, loc?: boolean }
---@field preview_title? string

---@generic T
---@param items T[]
---@param opts? vim.ui.select.Opts
---@param on_choice fun(item?: T, idx?: number)
function M.select(items, opts, on_choice)
  opts = opts or {}
  opts.snacks = vim.tbl_deep_extend("force", {
    focus = "list",
    main = {
      enter = true,
    },
    layout = {
      layout = {
        zindex = SELECT_ZINDEX,
      },
    },
  }, vim.deepcopy(opts.snacks or {}))
  local picker = SnacksSelect.select(items, opts, on_choice)

  vim.schedule(function()
    if not picker or picker.closed or not picker.focus then
      return
    end
    if picker.opts and (picker.opts.focus == false or picker.opts.enter == false) then
      return
    end
    picker:focus((picker.opts and picker.opts.focus) or "list", {
      show = true,
    })
  end)

  return picker
end

---@param opts vim.ui.input.Opts
---@param on_confirm fun(value?: string)
function M.input(opts, on_confirm)
  opts = vim.deepcopy(opts or {})
  opts.win = opts.win or {}

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

  vim.schedule(function()
    if active_input ~= win or not win or not win:valid() then
      return
    end
    win:focus()
    vim.cmd("startinsert!")
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

--- Provides built-in prompt context completion items for the prompt details buffer.
--- The menu inserts `&token` placeholders and only expands them when the prompt is submitted.
---@param findstart integer
---@param base string
---@return integer|vim.CompletedItem[]
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

  local matches = {} ---@type vim.CompletedItem[]
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
---@param opts? vim.ui.select.Opts
---@param on_choice fun(item?: Clodex.UiSelect.TextChoice, idx?: number)
function M.pick_text(items, opts, on_choice)
  opts = opts or {}
  local snacks_opts = vim.tbl_deep_extend("force", {
    preview = "preview",
    layout = {
      preset = "select",
      hidden = {},
    },
  }, vim.deepcopy(opts.snacks or {}))

  return M.select(items, vim.tbl_deep_extend("force", opts, {
    snacks = snacks_opts,
    format_item = function(item, supports_chunks)
      if not supports_chunks then
        if item.detail and item.detail ~= "" then
          return ("%s  %s"):format(item.label, item.detail)
        end
        return item.label
      end

      local chunks = {
        { item.label, "ClodexStateCommandName" },
      }
      if item.detail and item.detail ~= "" then
        chunks[#chunks + 1] = { "  " }
        chunks[#chunks + 1] = { item.detail, "ClodexStateCommandHint" }
      end
      return chunks
    end,
  }), on_choice)
end

---@param projects Clodex.Project[]
---@param opts? { prompt?: string, include_none?: boolean, active_root?: string }
---@param on_choice fun(project?: Clodex.Project)
function M.pick_project(projects, opts, on_choice)
  opts = opts or {}
  local items = {} ---@type { project?: Clodex.Project, label: string, spacer?: string, preview?: { text: string, ft?: string, loc?: boolean }, preview_title?: string }[]
  local name_width = 0

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

  return M.select(items, {
    prompt = opts.prompt or "Select Clodex project",
    snacks = {
      preview = "preview",
      layout = {
        preset = "select",
        hidden = {},
      },
    },
    format_item = function(item, supports_chunks)
      if not item.project or not supports_chunks then
        return item.label
      end
      return {
        { item.project.name, "ClodexPickerProject" },
        { item.spacer or "  " },
        { item.project.root, "ClodexPickerRoot" },
      }
    end,
  }, function(item)
    on_choice(item and item.project or nil)
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
---@param normal_group string?
local function style_prompt_editor(win, normal_group)
  normal_group = normal_group or "ClodexPromptEditorNormal"
  vim.wo[win].winhl = table.concat({
    ("NormalFloat:%s"):format(normal_group),
    "FloatBorder:ClodexPromptEditorBorder",
    "FloatTitle:ClodexPromptEditorTitle",
  }, ",")
  vim.wo[win].winblend = 0
end

---@param buf integer
---@param lines string[]
local function render_hint_lines(buf, lines)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  for line_index, line in ipairs(lines) do
    vim.api.nvim_buf_add_highlight(
      buf,
      -1,
      "ClodexPromptEditorHint",
      line_index - 1,
      0,
      -1
    )

    for _, key in ipairs(PROMPT_EDITOR_HINT_KEYS) do
      local start = 1
      while true do
        local from = line:find(key, start, true)
        if not from then
          break
        end
        vim.api.nvim_buf_add_highlight(
          buf,
          -1,
          "ClodexPromptEditorKey",
          line_index - 1,
          from - 1,
          from + #key - 1
        )
        start = from + #key
      end
    end
  end
  vim.bo[buf].modifiable = false
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

---@param opts { prompt: string, default?: string, min_height?: integer, context?: Clodex.PromptContext.Capture, paste_image?: fun(): string?, submit_actions?: Clodex.UiSelect.MultilineAction[] }
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
  local title_buf = vim.api.nvim_create_buf(false, true)
  local body_buf = vim.api.nvim_create_buf(false, true)
  local hint_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[title_buf].buftype = "nofile"
  vim.bo[title_buf].bufhidden = "wipe"
  vim.bo[title_buf].swapfile = false
  vim.bo[title_buf].modifiable = true
  vim.bo[body_buf].buftype = "nofile"
  vim.bo[body_buf].bufhidden = "wipe"
  vim.bo[body_buf].swapfile = false
  vim.bo[body_buf].filetype = "markdown"
  vim.bo[body_buf].modifiable = true
  vim.bo[hint_buf].buftype = "nofile"
  vim.bo[hint_buf].bufhidden = "wipe"
  vim.bo[hint_buf].swapfile = false
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
    border = "none",
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
    zindex = PROMPT_EDITOR_ZINDEX,
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
    prompt_context_completion[body_buf] = nil
    vim.schedule(function()
      on_confirm(value, action or submit_actions[1].value)
    end)
  end

  vim.api.nvim_buf_set_lines(title_buf, 0, -1, false, { title })
  vim.api.nvim_buf_set_lines(body_buf, 0, -1, false, detail_lines)
  render_hint_lines(hint_buf, hint_lines)
  style_prompt_editor(title_win.win)
  style_prompt_editor(body_win.win)
  style_prompt_editor(hint_win.win, "ClodexPromptEditorHint")
  vim.bo[body_buf].completefunc = "v:lua.require'clodex.ui.select'.prompt_context_complete"
  prompt_context_completion[body_buf] = prompt_context()

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
    callback = resize,
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
    prompt_context_completion[body_buf] = prompt_context()
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
      picker_items[#picker_items + 1] = {
        text = item.text,
        label = item.label,
        detail = spec.title,
        disabled = item.disabled,
        preview = {
          text = table.concat({
            ("# %s"):format(item.label),
            "",
            ("- Title: `%s`"):format(spec.title),
            "",
            "## Inserted prompt",
            "",
            "```text",
            item.text,
            "```",
          }, "\n"),
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
    prompt_context_completion[body_buf] = prompt_context()
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

---@param prompt string
---@param on_choice fun(confirmed: boolean)
function M.confirm(prompt, on_choice)
  local confirm_buf = vim.api.nvim_create_buf(false, true)
  local ui = vim.api.nvim_list_uis()[1]
  local editor_width = ui and ui.width or vim.o.columns
  local editor_height = ui and ui.height or vim.o.lines
  local choice_index = 1
  local closed = false
  local win ---@type { win: integer, valid: fun(self: table): boolean, close: fun(self: table) }

  vim.bo[confirm_buf].buftype = "nofile"
  vim.bo[confirm_buf].bufhidden = "hide"
  vim.bo[confirm_buf].swapfile = false
  vim.bo[confirm_buf].modifiable = false

  local width = math.min(
    math.max(vim.fn.strdisplaywidth(prompt) + CONFIRM_WIDTH_PADDING, CONFIRM_MIN_WIDTH),
    math.max(editor_width - 12, 24)
  )

  local function choice_line()
    local yes = choice_index == 1 and "[ Yes ]" or "  Yes  "
    local no = choice_index == 2 and "[ No ]" or "  No  "
    return ("%s    %s"):format(yes, no)
  end

  local function render()
    vim.bo[confirm_buf].modifiable = true
    vim.api.nvim_buf_set_lines(confirm_buf, 0, -1, false, {
      prompt,
      "",
      choice_line(),
    })
    vim.api.nvim_buf_clear_namespace(confirm_buf, -1, 0, -1)
    vim.api.nvim_buf_add_highlight(
      confirm_buf,
      -1,
      choice_index == 1 and "ClodexConfirmButtonActive" or "ClodexConfirmButton",
      2,
      0,
      7
    )
    vim.api.nvim_buf_add_highlight(
      confirm_buf,
      -1,
      choice_index == 2 and "ClodexConfirmButtonActive" or "ClodexConfirmButton",
      2,
      11,
      17
    )
    vim.bo[confirm_buf].modifiable = false
  end

  local function finish(confirmed)
    if closed then
      return
    end
    closed = true
    if win and win:valid() then
      win:close()
    end
    vim.schedule(function()
      on_choice(confirmed)
    end)
  end

  local function move_choice(delta)
    choice_index = choice_index + delta
    if choice_index < 1 then
      choice_index = 2
    elseif choice_index > 2 then
      choice_index = 1
    end
    render()
  end

  render()

  local win_id = vim.api.nvim_open_win(confirm_buf, true, {
    relative = "editor",
    style = "minimal",
    border = "rounded",
    title = " Confirm ",
    title_pos = "center",
    width = width,
    height = CONFIRM_HEIGHT,
    row = math.max(math.floor((editor_height - CONFIRM_HEIGHT) / 2), 1),
    col = math.max(math.floor((editor_width - width) / 2), 1),
    zindex = CONFIRM_ZINDEX,
    noautocmd = true,
  })
  win = {
    win = win_id,
    valid = function(self)
      return vim.api.nvim_win_is_valid(self.win)
    end,
    close = function(self)
      if self:valid() then
        vim.api.nvim_win_close(self.win, true)
      end
    end,
  }
  style_prompt_editor(win.win)
  vim.wo[win.win].cursorline = false

  local function map(lhs, rhs)
    vim.keymap.set("n", lhs, rhs, {
      buffer = confirm_buf,
      nowait = true,
      silent = true,
    })
  end

  map("<Left>", function()
    move_choice(-1)
  end)
  map("h", function()
    move_choice(-1)
  end)
  map("<Tab>", function()
    move_choice(1)
  end)
  map("<Right>", function()
    move_choice(1)
  end)
  map("l", function()
    move_choice(1)
  end)
  map("<CR>", function()
    finish(choice_index == 1)
  end)
  map("y", function()
    finish(true)
  end)
  map("n", function()
    finish(false)
  end)
  map("q", function()
    finish(false)
  end)
  map("<Esc>", function()
    finish(false)
  end)

  vim.api.nvim_create_autocmd("WinClosed", {
    once = true,
    pattern = tostring(win.win),
    callback = function()
      finish(false)
    end,
  })

  return win
end

return M
