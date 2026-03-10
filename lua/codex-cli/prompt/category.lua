--- Defines the CodexCli.PromptCategory type for this module.
--- This annotation documents structured state so modules can pass data with consistent expectations.
---@alias CodexCli.PromptCategory
---| "todo"
---| "error"
---| "visual"
---| "adjustment"
---| "refactor"
---| "idea"
---| "explain"
---| "library"

--- Defines the CodexCli.PromptCategoryDef type for this module.
--- This annotation documents structured state so modules can pass data with consistent expectations.
---@class CodexCli.PromptCategoryDef
---@field id CodexCli.PromptCategory
---@field label string
---@field title_prefix? string
---@field highlight string
---@field default_title string

local M = {}

---@type CodexCli.PromptCategoryDef[]
local categories = {
  {
    id = "todo",
    label = "TODO",
    highlight = "todo_title",
    default_title = "New todo",
  },
  {
    id = "error",
    label = "Error",
    highlight = "error_title",
    default_title = "Investigate runtime error",
    title_prefix = "Investigate runtime error",
  },
  {
    id = "visual",
    label = "Visual",
    highlight = "visual_title",
    default_title = "Review image and implement requested changes",
  },
  {
    id = "adjustment",
    label = "Adjustment",
    highlight = "adjustment_title",
    default_title = "Adjust existing behavior",
  },
  {
    id = "refactor",
    label = "Refactor",
    highlight = "refactor_title",
    default_title = "Refactor implementation",
  },
  {
    id = "idea",
    label = "Idea",
    highlight = "idea_title",
    default_title = "Explore an idea",
  },
  {
    id = "explain",
    label = "Explain",
    highlight = "explain_title",
    default_title = "Explain the current behavior",
  },
  {
    id = "library",
    label = "Library",
    highlight = "idea_title",
    default_title = "Use a saved prompt template",
  },
}

local by_id = {} ---@type table<CodexCli.PromptCategory, CodexCli.PromptCategoryDef>
for _, category in ipairs(categories) do
  by_id[category.id] = category
end

--- Implements the list path for prompt category.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@return CodexCli.PromptCategoryDef[]
function M.list()
  return vim.deepcopy(categories)
end

--- Implements the get path for prompt category.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param id? string
---@return CodexCli.PromptCategoryDef
function M.get(id)
  return by_id[id] or by_id.todo
end

--- Checks a valid condition for prompt category.
--- This gate keeps callers safe before continuing higher-level state transitions.
---@param id? string
---@return boolean
function M.is_valid(id)
  return by_id[id] ~= nil
end

return M
