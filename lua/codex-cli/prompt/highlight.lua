local Category = require("codex-cli.prompt.category")

--- Defines the CodexCli.PromptHighlight type for this module.
--- This annotation documents structured state so modules can pass data with consistent expectations.
---@class CodexCli.PromptHighlight
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

--- Implements the kind path for prompt highlight.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param kind? CodexCli.PromptCategory|string
---@return CodexCli.PromptCategory
function M.kind(kind)
  return Category.get(kind).id
end

--- Implements the title_group path for prompt highlight.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param kind? CodexCli.PromptCategory|string
---@return string
function M.title_group(kind)
  local prefix = "CodexCliPrompt"
  local suffix = TITLE_SUFFIX[M.kind(kind)] or TITLE_SUFFIX.todo
  return prefix .. suffix
end

--- Implements the preview_group path for prompt highlight.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@return string
function M.preview_group()
  return "CodexCliPromptPreviewText"
end

return M
