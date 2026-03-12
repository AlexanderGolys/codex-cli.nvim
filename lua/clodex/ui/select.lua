local M = {}
local SnacksInput = require("snacks.input")
local SnacksSelect = require("snacks.picker.select")
local PromptComposer = require("clodex.prompt.composer")
local PromptContext = require("clodex.prompt.context")
local ui_win = require("clodex.ui.win")

local PROMPT_EDITOR_MIN_HEIGHT = 6
local PROMPT_EDITOR_MIN_WIDTH = 56
local PROMPT_EDITOR_MAX_MARGIN = 12
local PROMPT_EDITOR_WIDTH_PADDING = 6
local PROMPT_EDITOR_HEIGHT_MARGIN = 10
local PROMPT_EDITOR_TITLE_HEIGHT = 1
local PROMPT_EDITOR_WINDOW_GAP = 1
local PROMPT_EDITOR_BORDER_ROWS = 2
local PROMPT_EDITOR_BORDER_COLS = 2
local PROMPT_EDITOR_ZINDEX = 70

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
  return SnacksSelect.select(items, opts, on_choice)
end

---@param opts vim.ui.input.Opts
---@param on_confirm fun(value?: string)
function M.input(opts, on_confirm)
  return SnacksInput.input(opts, on_confirm)
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
local function style_prompt_editor(win)
  vim.wo[win].winhl = table.concat({
    "NormalFloat:ClodexPromptEditorNormal",
    "FloatBorder:ClodexPromptEditorBorder",
    "FloatTitle:ClodexPromptEditorTitle",
    "FloatFooter:ClodexPromptEditorHint",
  }, ",")
  vim.wo[win].winblend = 0
end

---@param opts { prompt: string, default?: string, min_height?: integer, context?: Clodex.PromptContext.Capture }
---@param on_confirm fun(value?: string, action?: "save"|"queue")
function M.multiline_input(opts, on_confirm)
  opts = opts or {}
  local default = opts.default or ""
  local captured_context = opts.context
  local parsed = PromptComposer.parse(default) or {
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
    math.max(longest_width({ title, unpack(detail_lines) }) + PROMPT_EDITOR_WIDTH_PADDING, PROMPT_EDITOR_MIN_WIDTH),
    math.max(editor_width - PROMPT_EDITOR_MAX_MARGIN - PROMPT_EDITOR_BORDER_COLS, 24)
  )
  local title_footer = " Start with a short title, then add the implementation details below. "
  local body_footer = " Enter details   Ctrl-S save   Ctrl-Q queue+run   Esc cancel   & editor context   Ctrl-X prompt shortcut "

  local title_buf = vim.api.nvim_create_buf(false, true)
  local body_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[title_buf].buftype = "nofile"
  vim.bo[title_buf].bufhidden = "wipe"
  vim.bo[title_buf].swapfile = false
  vim.bo[title_buf].modifiable = true
  vim.bo[body_buf].buftype = "nofile"
  vim.bo[body_buf].bufhidden = "wipe"
  vim.bo[body_buf].swapfile = false
  vim.bo[body_buf].filetype = "markdown"
  vim.bo[body_buf].modifiable = true

  --- Calculates current required popup height from buffer content.
  --- The value is shared by size callback and repositioning math.
  local function calc_height()
    local count = math.max(#vim.api.nvim_buf_get_lines(body_buf, 0, -1, false), min_height)
    return math.min(count, max_height)
  end

  local function total_height()
    return PROMPT_EDITOR_TITLE_HEIGHT
      + calc_height()
      + (PROMPT_EDITOR_BORDER_ROWS * 2)
      + PROMPT_EDITOR_WINDOW_GAP
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
    backdrop = false,
    border = "rounded",
    title = (" %s "):format(opts.prompt),
    title_pos = "center",
    footer = title_footer,
    footer_pos = "center",
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
    backdrop = false,
    border = "rounded",
    title = " Details ",
    title_pos = "center",
    footer = body_footer,
    footer_pos = "center",
    width = width,
    height = function()
      return calc_height()
    end,
    row = function()
      return math.max(math.floor((editor_height - total_height()) / 2), 1)
        + PROMPT_EDITOR_TITLE_HEIGHT
        + PROMPT_EDITOR_BORDER_ROWS
        + PROMPT_EDITOR_WINDOW_GAP
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

  --- Updates floating window dimensions after every content change.
  --- This keeps the edit popup responsive without manual user action.
  local function resize()
    if not title_win:valid() or not body_win:valid() then
      return
    end
    local next_total_height = total_height()
    local next_body_height = calc_height()
    if title_win.opts._clodex_total_height == next_total_height
      and body_win.opts._clodex_height == next_body_height then
      return
    end
    title_win.opts._clodex_total_height = next_total_height
    body_win.opts._clodex_height = next_body_height
    title_win:update()
    body_win:update()
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
    vim.schedule(function()
      on_confirm(value, action or "save")
    end)
  end

  vim.api.nvim_buf_set_lines(title_buf, 0, -1, false, { title })
  vim.api.nvim_buf_set_lines(body_buf, 0, -1, false, detail_lines)
  style_prompt_editor(title_win.win)
  style_prompt_editor(body_win.win)

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
    close(PromptComposer.render(current_title, details ~= "" and details or nil), action)
  end

  --- Opens the `&` completion list and inserts the chosen expansion into the buffer.
  --- Canceling from insert mode falls back to a literal `&` so normal typing still works.
  local function insert_context_token(insert_literal_on_cancel)
    local items = PromptContext.tokens(prompt_context())
    if #items == 0 then
      if insert_literal_on_cancel then
        insert_text(body_buf, body_win.win, "&")
      end
      return
    end

    local picker_items = {}
    for _, item in ipairs(items) do
      local expansion = PromptContext.expand_token(item.token, prompt_context())
      picker_items[#picker_items + 1] = {
        token = item.token,
        label = item.label,
        detail = item.detail,
        preview = {
          text = table.concat({
            ("# %s"):format(item.label),
            "",
            item.detail,
            "",
            "## Expansion preview",
            "",
            "```text",
            expansion or "(currently unavailable)",
            "```",
          }, "\n"),
          ft = "markdown",
          loc = false,
        },
        preview_title = item.label,
      }
    end

    M.pick_text(picker_items, {
      prompt = "Insert editor context",
    }, function(item)
      if not item then
        if insert_literal_on_cancel then
          insert_text(body_buf, body_win.win, "&")
        end
        focus_body()
        return
      end

      local expansion = PromptContext.expand_token(item.token, prompt_context())
      if expansion then
        insert_text(body_buf, body_win.win, expansion)
        resize()
      end
      focus_body()
    end)
  end

  --- Opens the canned prompt picker and replaces or inserts the selected template.
  --- An empty prompt buffer is replaced wholesale so quick prompts behave like shortcuts.
  local function insert_quick_prompt()
    local items = PromptContext.quick_prompts(prompt_context())
    local picker_items = {}
    for _, item in ipairs(items) do
      local spec = PromptComposer.parse(item.text) or {
        title = vim.trim(item.text),
        details = nil,
      }
      picker_items[#picker_items + 1] = {
        text = item.text,
        label = item.label,
        detail = spec.title,
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

      local spec = PromptComposer.parse(item.text) or {
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

  vim.keymap.set({ "n", "i" }, "<CR>", focus_body, { buffer = title_buf, silent = true })
  vim.keymap.set({ "n", "i" }, "<Down>", focus_body, { buffer = title_buf, silent = true })
  vim.keymap.set({ "n", "i" }, "<Tab>", focus_body, { buffer = title_buf, silent = true })
  vim.keymap.set({ "n", "i" }, "<C-s>", function()
    submit("save")
  end, { buffer = title_buf, silent = true })
  vim.keymap.set({ "n", "i" }, "<C-q>", function()
    submit("queue")
  end, { buffer = title_buf, silent = true })
  vim.keymap.set("n", "q", function()
    close(nil)
  end, { buffer = title_buf, silent = true })
  vim.keymap.set({ "n", "i" }, "<Esc>", function()
    close(nil)
  end, { buffer = title_buf, silent = true })

  vim.keymap.set("n", "<CR>", function()
    submit("save")
  end, { buffer = body_buf, silent = true })
  vim.keymap.set({ "n", "i" }, "<C-s>", function()
    submit("save")
  end, { buffer = body_buf, silent = true })
  vim.keymap.set({ "n", "i" }, "<C-q>", function()
    submit("queue")
  end, { buffer = body_buf, silent = true })
  vim.keymap.set("n", "&", function()
    insert_context_token(false)
  end, { buffer = body_buf, silent = true })
  vim.keymap.set("i", "&", function()
    insert_context_token(true)
  end, { buffer = body_buf, silent = true })
  vim.keymap.set("n", "x", insert_quick_prompt, { buffer = body_buf, silent = true })
  vim.keymap.set("i", "<C-x>", insert_quick_prompt, { buffer = body_buf, silent = true })
  vim.keymap.set({ "n", "i" }, "<S-Tab>", focus_title, { buffer = body_buf, silent = true })
  vim.keymap.set("n", "q", function()
    close(nil)
  end, { buffer = body_buf, silent = true })
  vim.keymap.set("n", "<Esc>", function()
    close(nil)
  end, { buffer = body_buf, silent = true })
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
  local items = {
    { label = "Yes", value = true },
    { label = "No", value = false },
  }

  return M.select(items, {
    prompt = prompt,
    format_item = function(item)
      return item.label
    end,
  }, function(item)
    on_choice(item and item.value or false)
  end)
end

return M
