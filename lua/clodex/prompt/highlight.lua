local Category = require("clodex.prompt.category")

--- Defines the Clodex.PromptHighlight type for this module.
--- This annotation documents structured state so modules can pass data with consistent expectations.
---@class Clodex.PromptHighlight
local M = {}

local TITLE_SUFFIX = {
  todo = "TodoTitle",
  error = "ErrorTitle",
  visual = "VisualTitle",
  adjustment = "AdjustmentTitle",
  refactor = "RefactorTitle",
  idea = "IdeaTitle",
  explain = "ExplainTitle",
  library = "IdeaTitle",
}

---@param kind? Clodex.PromptCategory|string
---@return Clodex.PromptCategory
function M.kind(kind)
  return Category.get(kind).id
end

---@param kind? Clodex.PromptCategory|string
---@return string
function M.title_group(kind)
  local prefix = "ClodexPrompt"
  local suffix = TITLE_SUFFIX[M.kind(kind)] or TITLE_SUFFIX.todo
  return prefix .. suffix
end

---@return string
function M.preview_group()
  return "ClodexPromptPreviewText"
end

return M
