local fs = require("clodex.util.fs")
local git = require("clodex.util.git")
local unpack_values = require("clodex.util").unpack_values

--- Defines one expandable editor-context token.
--- These records drive the `&` completion list in prompt composition buffers.
---@class Clodex.PromptContext.Token
---@field token string
---@field label string
---@field detail string
---@field disabled? boolean

--- Captures editor state used for prompt expansion.
--- The prompt UI keeps one snapshot so completion stays stable while the prompt buffer is open.
---@class Clodex.PromptContext.Capture
---@field buf integer
---@field win integer
---@field file_path string
---@field project_root? string
---@field relative_path string
---@field cursor_row integer
---@field cursor_col integer
---@field line_text string
---@field current_word string
---@field visible_start integer
---@field visible_end integer
---@field selection_start_row? integer
---@field selection_end_row? integer
---@field selection_text? string
---@field selection_kind? string

--- Defines the Clodex.PromptContext.QuickPrompt type for this module.
--- This annotation documents structured state so modules can pass data with consistent expectations.
---@class Clodex.PromptContext.QuickPrompt
---@field id string
---@field label string
---@field text string
---@field disabled? boolean

--- Defines the Clodex.PromptContext type for this module.
--- This annotation documents structured state so modules can pass data with consistent expectations.
---@class Clodex.PromptContext
local M = {}
local PROJECT_DIAGNOSTICS_DISABLED = "Disabled in this session"

local TOKEN_SPECS = {
  {
    token = "&file",
    label = "&file",
    detail = "Insert the current file as a project-relative reference.",
  },
  {
    token = "&line",
    label = "&line",
    detail = "Insert the current line as a file-and-line reference.",
  },
  {
    token = "&selection",
    label = "&selection",
    detail = "Insert a plain-text summary of the current visual selection.",
  },
  {
    token = "&visible_buff",
    label = "&visible_buff",
    detail = "Insert the visible window range as a file-and-line reference.",
  },
  {
    token = "&word",
    label = "&word",
    detail = "Insert the word under the source cursor with its location.",
  },
  {
    token = "&diagnostic",
    label = "&diagnostic",
    detail = "Insert diagnostics from the current cursor line.",
  },
  {
    token = "&buff_diagnostics",
    label = "&buff_diagnostics",
    detail = "Insert every diagnostic from the current buffer.",
  },
  {
    token = "&all_diagnostics",
    label = "&all_diagnostics",
    detail = "Insert every diagnostic from the current project.",
  },
}

local function is_editor_window(win)
  if not vim.api.nvim_win_is_valid(win) then
    return false
  end
  local config = vim.api.nvim_win_get_config(win)
  if config.relative and config.relative ~= "" then
    return false
  end

  local buf = vim.api.nvim_win_get_buf(win)
  return vim.bo[buf].buftype == ""
end

local function resolve_source_window()
  local current = vim.api.nvim_get_current_win()
  if is_editor_window(current) then
    return current
  end

  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if is_editor_window(win) then
      return win
    end
  end
end

local function relative_path(path, root)
  local rel = root and vim.fs.relpath(root, path) or nil
  return rel and rel ~= "" and rel or fs.basename(path)
end

local function quote(text)
  local normalized = vim.trim((text or ""):gsub("%s+", " "))
  normalized = normalized:gsub("\\", "\\\\"):gsub('"', '\\"')
  return ('"%s"'):format(normalized)
end

local function get_selection(buf, mode)
  local block_mode = string.char(22)
  if mode ~= "v" and mode ~= "V" and mode ~= block_mode then
    return nil, nil, nil, nil
  end

  local start_row, start_col = unpack_values(vim.api.nvim_buf_get_mark(buf, "<"))
  local end_row, end_col = unpack_values(vim.api.nvim_buf_get_mark(buf, ">"))
  if start_row == 0 or end_row == 0 then
    return nil, nil, nil, nil
  end

  if start_row > end_row or (start_row == end_row and start_col > end_col) then
    start_row, end_row = end_row, start_row
    start_col, end_col = end_col, start_col
  end

  local lines = vim.api.nvim_buf_get_lines(buf, start_row - 1, end_row, false)
  if #lines == 0 then
    return nil, nil, nil, nil
  end

  if mode == "v" then
    lines[1] = lines[1]:sub(start_col + 1)
    lines[#lines] = lines[#lines]:sub(1, end_col + 1)
  end

  return table.concat(lines, "\n"), mode, start_row, end_row
end

local function diagnostic_sort(a, b)
  if a.lnum ~= b.lnum then
    return a.lnum < b.lnum
  end
  return a.col < b.col
end

local function severity_name(value)
  local severity = vim.diagnostic.severity
  local map = {
    [severity.ERROR] = "ERROR",
    [severity.WARN] = "WARN",
    [severity.INFO] = "INFO",
    [severity.HINT] = "HINT",
  }
  return map[value] or "UNKNOWN"
end

local function format_diagnostics(diags, fallback_path, root)
  if #diags == 0 then
    return nil
  end

  table.sort(diags, diagnostic_sort)
  local lines = {}
  for _, diag in ipairs(diags) do
    local path = diag.bufnr and vim.api.nvim_buf_get_name(diag.bufnr) or fallback_path
    path = path ~= "" and fs.normalize(path) or fallback_path
    lines[#lines + 1] = ("%s generated by Neovim diagnostics on line %d, column %d in file @{%s}."):format(
      quote(("%s [%s]"):format(vim.trim((diag.message or ""):gsub("%s+", " ")), severity_name(diag.severity))),
      (diag.lnum or 0) + 1,
      (diag.col or 0) + 1,
      relative_path(path, root)
    )
  end
  return table.concat(lines, "\n")
end

local function current_buffer_diags(context)
  return vim.diagnostic.get(context.buf)
end

local function current_line_diags(context)
  if context.buf == nil or context.cursor_row == nil then
    return {}
  end
  return vim.diagnostic.get(context.buf, { lnum = context.cursor_row - 1 })
end

local function project_diagnostics(context)
  local diags = {} ---@type vim.Diagnostic[]
  for _, diag in ipairs(vim.diagnostic.get(nil)) do
    local path = diag.bufnr and vim.api.nvim_buf_get_name(diag.bufnr) or ""
    if path ~= "" and fs.is_relative_to(path, context.project_root) then
      diags[#diags + 1] = diag
    end
  end
  return diags
end

---@class Clodex.PromptContext.CaptureOpts
---@field project? Clodex.Project
---@field project_root? string

--- Captures the best available editor buffer/window for prompt expansions.
--- Floating plugin windows are skipped so prompt state comes from the user's code buffer instead.
---@param opts? Clodex.PromptContext.CaptureOpts
---@return Clodex.PromptContext.Capture?
function M.capture(opts)
  opts = opts or {}
  local win = resolve_source_window()
  if not win then
    return nil
  end

  local buf = vim.api.nvim_win_get_buf(win)
  local cursor = vim.api.nvim_win_get_cursor(win)
  local mode = vim.fn.mode(1)
  local visible_start, visible_end = vim.api.nvim_win_call(win, function()
    return vim.fn.line("w0"), vim.fn.line("w$")
  end)
  local selection_text, selection_kind, selection_start_row, selection_end_row = vim.api.nvim_win_call(win, function()
    return get_selection(buf, mode)
  end)
  local current_word = vim.api.nvim_win_call(win, function()
    return vim.fn.expand("<cword>")
  end)
  local file_path = fs.current_path(buf)
  local project_root = opts.project and opts.project.root
    or (opts.project_root and fs.normalize(opts.project_root))
    or git.get_root(file_path)

  return {
    buf = buf,
    win = win,
    file_path = file_path,
    project_root = project_root,
    relative_path = relative_path(file_path, project_root),
    cursor_row = cursor[1],
    cursor_col = cursor[2],
    line_text = vim.api.nvim_buf_get_lines(buf, cursor[1] - 1, cursor[1], false)[1] or "",
    current_word = current_word or "",
    visible_start = visible_start,
    visible_end = visible_end,
    selection_start_row = selection_start_row,
    selection_end_row = selection_end_row,
    selection_text = selection_text,
    selection_kind = selection_kind,
  }
end

--- Returns the available `&` completion items for a captured editor state.
--- Availability is filtered so prompt completion only offers context that can actually be expanded.
---@param context Clodex.PromptContext.Capture?
---@return Clodex.PromptContext.Token[]
function M.tokens(context)
  if not context then
    return {}
  end

  local items = {}
  for _, spec in ipairs(TOKEN_SPECS) do
    local item = vim.deepcopy(spec)
    local available = true
    if spec.token == "&selection" and not context.selection_text then
      available = false
    end
    if spec.token == "&diagnostic" and #current_line_diags(context) == 0 then
      available = false
    end
    if spec.token == "&all_diagnostics" and not context.project_root then
      item.disabled = true
      item.detail = ("%s (%s)"):format(item.detail, PROJECT_DIAGNOSTICS_DISABLED)
    end
    if available then
      items[#items + 1] = item
    end
  end
  return items
end

--- Expands one `&token` into prompt-ready plain text.
--- The editor resolves context up front so the agent only receives ordinary text references.
---@param token string
---@param context Clodex.PromptContext.Capture?
---@return string?
function M.expand_token(token, context)
  if not context then
    return nil
  end

  if token == "&file" then
    if context.relative_path == nil then
      return nil
    end
    return ("@{%s}"):format(context.relative_path)
  end

  if token == "&line" then
    if context.relative_path == nil or context.cursor_row == nil then
      return nil
    end
    return ("@{%s}: line %d"):format(context.relative_path, context.cursor_row)
  end

  if token == "&selection" and context.selection_text then
    local start_row = context.selection_start_row or context.cursor_row
    local end_row = context.selection_end_row or start_row
    if start_row == end_row then
      return ("Line %d selected in @{%s}: %s"):format(start_row, context.relative_path, quote(context.selection_text))
    end
    return ("Lines %d-%d selected in @{%s}: %s"):format(
      start_row,
      end_row,
      context.relative_path,
      quote(context.selection_text)
    )
  end

  if token == "&visible_buff" then
    if context.visible_start == nil or context.visible_end == nil then
      return nil
    end
    return ("@{%s}: lines %d-%d are currently visible in the editor"):format(
      context.relative_path,
      context.visible_start,
      context.visible_end
    )
  end

  if token == "&word" and context.current_word ~= "" then
    if context.relative_path == nil or context.cursor_row == nil then
      return nil
    end
    return ("%s under the cursor in @{%s}: line %d"):format(
      quote(context.current_word),
      context.relative_path,
      context.cursor_row
    )
  end

  if token == "&diagnostic" then
    if context.buf == nil or context.cursor_row == nil then
      return nil
    end
    return format_diagnostics(current_line_diags(context), context.file_path, context.project_root)
  end

  if token == "&buff_diagnostics" then
    if context.buf == nil then
      return nil
    end
    return format_diagnostics(current_buffer_diags(context), context.file_path, context.project_root)
      or ("No Neovim diagnostics are currently reported for @{%s}."):format(context.relative_path)
  end

  if token == "&all_diagnostics" then
    if context.project_root == nil then
      return nil
    end
    return format_diagnostics(project_diagnostics(context), context.file_path, context.project_root)
      or ("No Neovim diagnostics are currently reported under project root `%s`."):format(context.project_root)
  end
end

--- Expands all supported `&token` occurrences inside prompt text.
--- Quick prompt templates use this so generated prompts include live editor context immediately.
---@param text string
---@param context Clodex.PromptContext.Capture?
---@return string
function M.expand_text(text, context)
  local expanded = text
  for _, spec in ipairs(TOKEN_SPECS) do
    local replacement = M.expand_token(spec.token, context)
    if replacement then
      expanded = expanded:gsub(vim.pesc(spec.token), replacement)
    end
  end
  return expanded
end

--- Returns canned prompt bodies that expand against the current editor state.
--- The prompt editor uses these as one-key shortcuts for common explain and fix flows.
---@param context Clodex.PromptContext.Capture?
---@return Clodex.PromptContext.QuickPrompt[]
function M.quick_prompts(context)
  local prompts = {
    {
      id = "explain-line",
      label = "Explain current line",
      text = "Explain the current line, including what it does here and any assumptions around it.\n\n&line",
    },
    {
      id = "explain-file",
      label = "Explain current file",
      text = "Explain how the current file fits into the project and walk through the important control flow.\n\n&file",
    },
    {
      id = "fix-buffer-diagnostics",
      label = "Fix buffer diagnostics",
      text = "Fix the current buffer diagnostics, or explain clearly why any remaining ones should be ignored.\n\n&buff_diagnostics",
    },
    {
      id = "fix-all-diagnostics",
      label = context and context.project_root and "Fix all diagnostics" or "Fix all diagnostics (disabled)",
      text = "Fix the project diagnostics in a sensible order, grouping related issues together and noting any follow-up validation.\n\n&all_diagnostics",
      disabled = not (context and context.project_root),
    },
  }

  if context and context.selection_text then
    prompts[#prompts + 1] = {
      id = "explain-selection",
      label = "Explain selection",
      text = "Explain the selected code in detail, including how it is used and any edge cases around it.\n\n&selection",
    }
  end

  if context and #current_line_diags(context) > 0 then
    prompts[#prompts + 1] = {
      id = "fix-line-diagnostic",
      label = "Fix current-line diagnostic",
      text = "Fix the diagnostic on the current line, or explain why it should be ignored.\n\n&line\n\n&diagnostic",
    }
  end

  for _, prompt in ipairs(prompts) do
    prompt.text = M.expand_text(prompt.text, context)
  end

  return prompts
end

return M
