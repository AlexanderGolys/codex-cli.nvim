---@class CodexCli.PromptTitle.NormalizeResult
---@field title string
---@field details? string
---@field broken boolean

---@class CodexCli.PromptTitle
local M = {}

local WHITESPACE_SUFFIX = " [...]"
local MIDWORD_SUFFIX = "-[...]"

local function prepend_details(title, details)
  local parts = {} ---@type string[]
  local head = vim.trim(title or "")
  local tail = vim.trim(details or "")
  if head ~= "" then
    parts[#parts + 1] = head
  end
  if tail ~= "" then
    parts[#parts + 1] = tail
  end
  return #parts > 0 and table.concat(parts, "\n\n") or nil
end

---@param opts { title: string, details?: string, max_width?: integer }
---@return CodexCli.PromptTitle.NormalizeResult
function M.normalize(opts)
  local title = vim.trim(opts.title or "")
  local details = vim.trim(opts.details or "")
  local max_width = math.max(tonumber(opts.max_width) or 0, 1)
  if title == "" or vim.fn.strdisplaywidth(title) <= max_width then
    return {
      title = title,
      details = details ~= "" and details or nil,
      broken = false,
    }
  end

  for idx = 1, #title do
    local ch = title:sub(idx, idx)
    local next_text = title:sub(idx + 1)
    if ch:match("[%.!?]") and next_text:match("^%s+%S") then
      local prev = idx > 1 and title:sub(idx - 1, idx - 1) or ""
      if prev:match("[%w%]%)\"']") and vim.fn.strdisplaywidth(title:sub(1, idx)) <= max_width then
        return {
          title = vim.trim(title:sub(1, idx)),
          details = prepend_details(next_text, details),
          broken = true,
        }
      end
    end
  end

  for idx = 1, #title do
    if title:sub(idx, idx) == "," then
      local prev = idx > 1 and title:sub(idx - 1, idx - 1) or ""
      local next_text = title:sub(idx + 1)
      if prev ~= "" and not prev:match("%s") and next_text:match("^%s+%S") then
        if vim.fn.strdisplaywidth(title:sub(1, idx)) <= max_width then
          local tail = vim.trim(next_text)
          if tail:sub(1, 1):match("%l") then
            tail = tail:sub(1, 1):upper() .. tail:sub(2)
          end
          return {
            title = vim.trim(title:sub(1, idx)),
            details = prepend_details(tail, details),
            broken = true,
          }
        end
      end
    end
  end

  local whitespace_idx ---@type integer?
  for idx = 1, #title do
    if title:sub(idx, idx):match("%s") then
      local head = title:sub(1, idx - 1):gsub("%s+$", "")
      if head ~= "" and vim.fn.strdisplaywidth(head .. WHITESPACE_SUFFIX) <= max_width then
        whitespace_idx = idx
      end
    end
  end
  if whitespace_idx then
    return {
      title = title:sub(1, whitespace_idx - 1):gsub("%s+$", "") .. WHITESPACE_SUFFIX,
      details = prepend_details(title:sub(whitespace_idx + 1), details),
      broken = true,
    }
  end

  local best = ""
  for idx = 1, #title do
    local head = title:sub(1, idx)
    if vim.fn.strdisplaywidth(head .. MIDWORD_SUFFIX) > max_width then
      break
    end
    best = head
  end

  if best == "" then
    return {
      title = MIDWORD_SUFFIX:sub(1, math.max(max_width, 1)),
      details = prepend_details(title, details),
      broken = true,
    }
  end

  return {
    title = best .. MIDWORD_SUFFIX,
    details = prepend_details(title:sub(#best + 1), details),
    broken = true,
  }
end

return M
