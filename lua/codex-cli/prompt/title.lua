--- Defines the CodexCli.PromptTitle.NormalizeResult type for this module.
--- This annotation documents structured state so modules can pass data with consistent expectations.
---@class CodexCli.PromptTitle.NormalizeResult
---@field title string
---@field details? string
---@field broken boolean

--- Defines the CodexCli.PromptTitle type for this module.
--- This annotation documents structured state so modules can pass data with consistent expectations.
---@class CodexCli.PromptTitle
local M = {}

local WHITESPACE_SUFFIX = " [...]"
local MIDWORD_SUFFIX = "-[...]"

--- Implements the trim_start path for prompt title.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param value string
---@return string
local function trim_start(value)
  return (value:gsub("^%s+", ""))
end

--- Implements the trim_end path for prompt title.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param value string
---@return string
local function trim_end(value)
  return (value:gsub("%s+$", ""))
end

--- Implements the trim path for prompt title.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param value string
---@return string
local function trim(value)
  return vim.trim(value)
end

--- Implements the prepend_details path for prompt title.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param title string
---@param details? string
---@return string?
local function prepend_details(title, details)
  local parts = {} ---@type string[]
  local head = trim(title)
  if head ~= "" then
    parts[#parts + 1] = head
  end
  local tail = details and trim(details) or ""
  if tail ~= "" then
    parts[#parts + 1] = tail
  end
  if #parts == 0 then
    return nil
  end
  return table.concat(parts, "\n\n")
end

--- Implements the char_at path for prompt title.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param value string
---@param idx integer
---@return string
local function char_at(value, idx)
  return value:sub(idx, idx)
end

--- Implements the has_space_after path for prompt title.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param value string
---@param idx integer
---@return boolean
local function has_space_after(value, idx)
  return value:sub(idx + 1):match("^%s+") ~= nil
end

--- Implements the has_nonspace_after path for prompt title.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param value string
---@param idx integer
---@return boolean
local function has_nonspace_after(value, idx)
  return value:sub(idx + 1):match("^%s*%S") ~= nil
end

--- Implements the sentence_break_at path for prompt title.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param value string
---@param idx integer
---@return boolean
local function sentence_break_at(value, idx)
  local ch = char_at(value, idx)
  if not ch:match("[%.!?]") then
    return false
  end

  local prev = idx > 1 and char_at(value, idx - 1) or ""
  if not prev:match("[%w%]%)\"']") then
    return false
  end

  return has_space_after(value, idx) and has_nonspace_after(value, idx)
end

--- Implements the comma_break_at path for prompt title.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param value string
---@param idx integer
---@return boolean
local function comma_break_at(value, idx)
  if char_at(value, idx) ~= "," then
    return false
  end
  local prev = idx > 1 and char_at(value, idx - 1) or ""
  if prev == "" or prev:match("%s") then
    return false
  end
  return has_space_after(value, idx) and has_nonspace_after(value, idx)
end

--- Implements the capitalize_leading_letter path for prompt title.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param value string
---@return string
local function capitalize_leading_letter(value)
  local first = value:sub(1, 1)
  if first:match("%l") then
    return first:upper() .. value:sub(2)
  end
  return value
end

--- Implements the find_break path for prompt title.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param title string
---@param max_width integer
---@param predicate fun(value: string, idx: integer): boolean
---@param suffix string
---@return integer?
local function find_break(title, max_width, predicate, suffix)
  local candidate ---@type integer?
  for idx = 1, #title do
    if predicate(title, idx) then
      local head = title:sub(1, idx)
      if vim.fn.strdisplaywidth(head .. suffix) <= max_width then
        candidate = idx
      end
    end
  end
  return candidate
end

--- Implements the find_whitespace_break path for prompt title.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param title string
---@param max_width integer
---@return integer?
local function find_whitespace_break(title, max_width)
  local candidate ---@type integer?
  for idx = 1, #title do
    if char_at(title, idx):match("%s") then
      local head = trim_end(title:sub(1, idx - 1))
      if head ~= "" and vim.fn.strdisplaywidth(head .. WHITESPACE_SUFFIX) <= max_width then
        candidate = idx
      end
    end
  end
  return candidate
end

--- Implements the cut_midword path for prompt title.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param title string
---@param max_width integer
---@return string
local function cut_midword(title, max_width)
  local best = ""
  for idx = 1, #title do
    local head = title:sub(1, idx)
    if vim.fn.strdisplaywidth(head .. MIDWORD_SUFFIX) > max_width then
      break
    end
    best = head
  end

  if best == "" then
    return MIDWORD_SUFFIX:sub(1, math.max(max_width, 1))
  end

  return best .. MIDWORD_SUFFIX
end

--- Implements the normalize path for prompt title.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param opts { title: string, details?: string, max_width?: integer }
---@return CodexCli.PromptTitle.NormalizeResult
function M.normalize(opts)
  local title = trim(opts.title or "")
  local details = opts.details and trim(opts.details) or nil
  local max_width = math.max(tonumber(opts.max_width) or 0, 1)
  if title == "" or vim.fn.strdisplaywidth(title) <= max_width then
    return {
      title = title,
      details = details,
      broken = false,
    }
  end

  local sentence_idx = find_break(title, max_width, sentence_break_at, "")
  if sentence_idx then
    return {
      title = trim_end(title:sub(1, sentence_idx)),
      details = prepend_details(trim_start(title:sub(sentence_idx + 1)), details),
      broken = true,
    }
  end

  local comma_idx = find_break(title, max_width, comma_break_at, "")
  if comma_idx then
    return {
      title = trim_end(title:sub(1, comma_idx)),
      details = prepend_details(capitalize_leading_letter(trim_start(title:sub(comma_idx + 1))), details),
      broken = true,
    }
  end

  local whitespace_idx = find_whitespace_break(title, max_width)
  if whitespace_idx then
    return {
      title = trim_end(title:sub(1, whitespace_idx - 1)) .. WHITESPACE_SUFFIX,
      details = prepend_details(trim_start(title:sub(whitespace_idx + 1)), details),
      broken = true,
    }
  end

  local split_title = cut_midword(title, max_width)
  local cut_len = math.max(#split_title - #MIDWORD_SUFFIX, 0)
  return {
    title = split_title,
    details = prepend_details(title:sub(cut_len + 1), details),
    broken = true,
  }
end

return M
