--- Defines the CodexCli.PromptComposer.Spec type for this module.
--- This annotation documents structured state so modules can pass data with consistent expectations.
---@class CodexCli.PromptComposer.Spec
---@field title string
---@field details? string

--- Defines the CodexCli.PromptComposer type for this module.
--- This annotation documents structured state so modules can pass data with consistent expectations.
---@class CodexCli.PromptComposer
local M = {}

--- Renders a queue-style prompt body from title plus optional details.
--- Prompt editors use this to prefill existing prompts in a single multiline buffer.
---@param title string
---@param details? string
---@return string
function M.render(title, details)
  local lines = { vim.trim(title or "") }
  local body = details and vim.trim(details) or ""
  if body ~= "" then
    lines[#lines + 1] = ""
    lines[#lines + 1] = body
  end
  return table.concat(lines, "\n")
end

--- Splits a freeform prompt body into queue title and optional details.
--- The first non-empty line becomes the queue title while the remainder stays in the details block.
---@param body string
---@return CodexCli.PromptComposer.Spec?
function M.parse(body)
  local trimmed = vim.trim(body or "")
  if trimmed == "" then
    return nil
  end

  local lines = vim.split(trimmed, "\n", { plain = true })
  local title_index ---@type integer?
  for index, line in ipairs(lines) do
    if vim.trim(line) ~= "" then
      title_index = index
      break
    end
  end
  if not title_index then
    return nil
  end

  local title = vim.trim(lines[title_index])
  if title == "" then
    return nil
  end

  local detail_lines = {}
  for index = title_index + 1, #lines do
    detail_lines[#detail_lines + 1] = lines[index]
  end

  local details = vim.trim(table.concat(detail_lines, "\n"))
  return {
    title = title,
    details = details ~= "" and details or nil,
  }
end

return M
