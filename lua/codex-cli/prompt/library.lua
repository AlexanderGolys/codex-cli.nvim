--- Defines the CodexCli.PromptLibrary.Template type for this module.
--- This annotation documents structured state so modules can pass data with consistent expectations.
---@class CodexCli.PromptLibrary.Template
---@field id string
---@field label string
---@field title string
---@field details string
---@field kind CodexCli.PromptCategory

--- Defines the CodexCli.PromptLibrary type for this module.
--- This annotation documents structured state so modules can pass data with consistent expectations.
---@class CodexCli.PromptLibrary
local M = {}

---@type CodexCli.PromptLibrary.Template[]
local templates = {
  {
    id = "fix-diagnostics",
    label = "Fix diagnostics",
    title = "Fix diagnostics from the current project",
    kind = "adjustment",
    details = table.concat({
      "Use `&(diagnostics)` as the primary problem list.",
      "Group related issues, fix them in a coherent order, and mention any follow-up validation.",
    }, "\n\n"),
  },
  {
    id = "explain-current-file",
    label = "Explain current file",
    title = "Explain the current file",
    kind = "explain",
    details = table.concat({
      "Explain `&(current file)` in terms of its responsibilities, main control flow, and important assumptions.",
      "Call out any non-obvious edge cases or follow-up refactors worth considering.",
    }, "\n\n"),
  },
  {
    id = "refactor-selection",
    label = "Refactor selection",
    title = "Refactor the selected code",
    kind = "refactor",
    details = table.concat({
      "Focus on `&(range<start, end>)` or the current visual selection once prompt expansion exists.",
      "Keep behavior intact, reduce duplication, and explain any structural tradeoffs.",
    }, "\n\n"),
  },
  {
    id = "summarize-qf",
    label = "Summarize quickfix",
    title = "Summarize the quickfix list",
    kind = "idea",
    details = table.concat({
      "Review `&(qf list)` and summarize the problems by theme.",
      "Suggest the smallest sensible execution plan before making changes.",
    }, "\n\n"),
  },
}

local by_id = {} ---@type table<string, CodexCli.PromptLibrary.Template>
for _, template in ipairs(templates) do
  by_id[template.id] = template
end

--- Implements the list path for prompt library.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@return CodexCli.PromptLibrary.Template[]
function M.list()
  return vim.deepcopy(templates)
end

--- Implements the get path for prompt library.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param id string
---@return CodexCli.PromptLibrary.Template?
function M.get(id)
  local template = by_id[id]
  return template and vim.deepcopy(template) or nil
end

return M
