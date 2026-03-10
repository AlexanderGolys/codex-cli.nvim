local M = {}
local SnacksInput = require("snacks.input")
local SnacksSelect = require("snacks.picker.select")
local PromptContext = require("codex-cli.prompt.context")
local ui_win = require("codex-cli.ui.win")

--- Implements the select path for ui select.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@generic T
---@param items T[]
---@param opts? vim.ui.select.Opts
---@param on_choice fun(item?: T, idx?: number)
function M.select(items, opts, on_choice)
  return SnacksSelect.select(items, opts, on_choice)
end

--- Implements the input path for ui select.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param opts vim.ui.input.Opts
---@param on_confirm fun(value?: string)
function M.input(opts, on_confirm)
  return SnacksInput.input(opts, on_confirm)
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

--- Implements the multiline_input path for ui select.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param opts { prompt: string, default?: string, min_height?: integer, context?: CodexCli.PromptContext.Capture }
---@param on_confirm fun(value?: string)
function M.multiline_input(opts, on_confirm)
  opts = opts or {}
  local default = opts.default or ""
  local context = opts.context or PromptContext.capture()
  local lines = default ~= "" and vim.split(default, "\n", { plain = true }) or { "" }
  local ui = vim.api.nvim_list_uis()[1]
  local editor_width = ui and ui.width or vim.o.columns
  local editor_height = ui and ui.height or vim.o.lines
  local min_height = math.max(opts.min_height or 5, 5)
  local max_height = math.max(editor_height - 8, min_height)
  local width = math.min(math.max(longest_width(lines) + 4, 48), math.max(editor_width - 8, 24))

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "markdown"
  vim.bo[buf].modifiable = true

  --- Calculates current required popup height from buffer content.
  --- The value is shared by size callback and repositioning math.
  local function calc_height()
    local count = math.max(#vim.api.nvim_buf_get_lines(buf, 0, -1, false), min_height)
    return math.min(count, max_height)
  end

  local win = ui_win.open({
    buf = buf,
    enter = true,
    backdrop = false,
    border = "rounded",
    title = (" %s "):format(opts.prompt),
    width = width,
--- Implements the height path for ui select.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
    height = function()
      return calc_height()
    end,
--- Implements the row path for ui select.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
    row = function()
      return math.max(math.floor((editor_height - calc_height()) / 2), 1)
    end,
--- Implements the col path for ui select.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
    col = function()
      return math.max(math.floor((editor_width - width) / 2), 1)
    end,
    wo = {
      wrap = false,
    },
    bo = {
      filetype = "markdown",
      buftype = "nofile",
      modifiable = true,
    },
  })

  --- Updates floating window dimensions after every content change.
  --- This keeps the edit popup responsive without manual user action.
  local function resize()
    if not win:valid() then
      return
    end
    win:update()
  end

  local done = false
  --- Closes the popup once and dispatches final content to caller.
  --- A guard flag prevents duplicate callbacks from multiple close triggers.
  local function close(value)
    if done then
      return
    end
    done = true
    if win:valid() then
      win:close()
    end
    on_confirm(value)
  end

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    buffer = buf,
    callback = resize,
  })

  --- Submits the full current buffer content into the confirm callback.
  --- It is used by Enter and Ctrl-S as explicit commit actions.
  local function submit()
    close(join_lines(vim.api.nvim_buf_get_lines(buf, 0, -1, false)))
  end

  --- Opens the `&` completion list and inserts the chosen expansion into the buffer.
  --- Canceling from insert mode falls back to a literal `&` so normal typing still works.
  local function insert_context_token(insert_literal_on_cancel)
    local items = PromptContext.tokens(context)
    if #items == 0 then
      if insert_literal_on_cancel then
        insert_text(buf, win.win, "&")
      end
      return
    end

    M.select(items, {
      prompt = "Insert editor context",
      format_item = function(item)
        return ("%s  %s"):format(item.label, item.detail)
      end,
    }, function(item)
      if not item then
        if insert_literal_on_cancel then
          insert_text(buf, win.win, "&")
        end
        vim.api.nvim_set_current_win(win.win)
        vim.cmd.startinsert()
        return
      end

      local expansion = PromptContext.expand_token(item.token, context)
      if expansion then
        insert_text(buf, win.win, expansion)
        resize()
      end
      vim.api.nvim_set_current_win(win.win)
      vim.cmd.startinsert()
    end)
  end

  --- Opens the canned prompt picker and replaces or inserts the selected template.
  --- An empty prompt buffer is replaced wholesale so quick prompts behave like shortcuts.
  local function insert_quick_prompt()
    local items = PromptContext.quick_prompts(context)
    M.select(items, {
      prompt = "Prompt shortcuts",
      format_item = function(item)
        return item.label
      end,
    }, function(item)
      if not item then
        vim.api.nvim_set_current_win(win.win)
        vim.cmd.startinsert()
        return
      end

      local current = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      local current_text = vim.trim(join_lines(current))
      if current_text == "" then
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(item.text, "\n", { plain = true }))
        vim.api.nvim_win_set_cursor(win.win, { 1, 0 })
      else
        insert_text(buf, win.win, item.text)
      end
      resize()
      vim.api.nvim_set_current_win(win.win)
      vim.cmd.startinsert()
    end)
  end

  vim.keymap.set("n", "<CR>", submit, { buffer = buf, silent = true })
  vim.keymap.set({ "n", "i" }, "<C-s>", submit, { buffer = buf, silent = true })
  vim.keymap.set("n", "&", function()
    insert_context_token(false)
  end, { buffer = buf, silent = true })
  vim.keymap.set("i", "&", function()
    insert_context_token(true)
  end, { buffer = buf, silent = true })
  vim.keymap.set("n", "x", insert_quick_prompt, { buffer = buf, silent = true })
  vim.keymap.set("i", "<C-x>", insert_quick_prompt, { buffer = buf, silent = true })
  vim.keymap.set("n", "q", function()
    close(nil)
  end, { buffer = buf, silent = true })
  vim.keymap.set("n", "<Esc>", function()
    close(nil)
  end, { buffer = buf, silent = true })
  vim.api.nvim_create_autocmd("WinClosed", {
    once = true,
    pattern = tostring(win.win),
--- Implements the callback path for ui select.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
    callback = function()
      close(nil)
    end,
  })

  vim.api.nvim_set_current_win(win.win)
  vim.cmd.startinsert()
end

--- Implements the confirm path for ui select.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param prompt string
---@param on_choice fun(confirmed: boolean)
function M.confirm(prompt, on_choice)
  local items = {
    { label = "Yes", value = true },
    { label = "No", value = false },
  }

  return M.select(items, {
    prompt = prompt,
--- Implements the format_item path for ui select.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
    format_item = function(item)
      return item.label
    end,
  }, function(item)
    on_choice(item and item.value or false)
  end)
end

return M
