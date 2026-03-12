--- Defines the Clodex.PromptLibrary.Template type for this module.
--- This annotation documents structured state so modules can pass data with consistent expectations.
---@class Clodex.PromptLibrary.Template
---@field id string
---@field label string
---@field title string
---@field details string
---@field kind Clodex.PromptCategory

--- Defines the Clodex.PromptLibrary type for this module.
--- This annotation documents structured state so modules can pass data with consistent expectations.
---@class Clodex.PromptLibrary
local M = {}

---@type Clodex.PromptLibrary.Template[]
local templates = {
  {
    id = "fix-diagnostics",
    label = "Fix diagnostics",
    title = "Fix diagnostics from the current project",
    kind = "adjustment",
    details = table.concat({
      "Use `&all_diagnostics` as the primary problem list.",
      "Group related issues, fix them in a coherent order, and mention any follow-up validation.",
    }, "\n\n"),
  },
  {
    id = "explain-current-file",
    label = "Explain current file",
    title = "Explain the current file",
    kind = "explain",
    details = table.concat({
      "Explain `&file` in terms of its responsibilities, main control flow, and important assumptions.",
      "Call out any non-obvious edge cases or follow-up refactors worth considering.",
    }, "\n\n"),
  },
  {
    id = "refactor-selection",
    label = "Refactor selection",
    title = "Refactor the selected code",
    kind = "refactor",
    details = table.concat({
      "Focus on `&selection` and keep behavior intact while reducing duplication.",
      "Keep behavior intact, reduce duplication, and explain any structural tradeoffs.",
    }, "\n\n"),
  },
  {
    id = "fix-buffer-diagnostics",
    label = "Fix buffer diagnostics",
    title = "Fix diagnostics from the current buffer",
    kind = "idea",
    details = table.concat({
      "Use `&buff_diagnostics` as the main issue list.",
      "Fix what should be fixed and explain clearly why any remaining diagnostics should be ignored.",
    }, "\n\n"),
  },
}

local by_id = {} ---@type table<string, Clodex.PromptLibrary.Template>
for _, template in ipairs(templates) do
  by_id[template.id] = template
end

---@return Clodex.PromptLibrary.Template[]
function M.list()
  return vim.deepcopy(templates)
end

---@param id string
---@return Clodex.PromptLibrary.Template?
function M.get(id)
  local template = by_id[id]
  return template and vim.deepcopy(template) or nil
end

return M
