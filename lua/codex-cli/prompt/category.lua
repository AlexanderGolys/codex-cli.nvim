---@alias CodexCli.PromptCategory
---| "todo"
---| "error"
---| "visual"
---| "adjustment"
---| "refactor"
---| "idea"
---| "explain"

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
}

local by_id = {} ---@type table<CodexCli.PromptCategory, CodexCli.PromptCategoryDef>
for _, category in ipairs(categories) do
  by_id[category.id] = category
end

---@return CodexCli.PromptCategoryDef[]
function M.list()
  return vim.deepcopy(categories)
end

---@param id? string
---@return CodexCli.PromptCategoryDef
function M.get(id)
  return by_id[id] or by_id.todo
end

---@param id? string
---@return boolean
function M.is_valid(id)
  return by_id[id] ~= nil
end

return M
