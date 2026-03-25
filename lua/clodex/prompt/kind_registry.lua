---@alias Clodex.PromptCategory
---| "todo"
---| "bug"
---| "freeform"
---| "adjustment"
---| "refactor"
---| "idea"
---| "ask"
---| "explain"
---| "library"
---| "notworking"

---@class Clodex.PromptCategoryDef
---@field id Clodex.PromptCategory
---@field label string
---@field title_prefix? string
---@field highlight string
---@field default_title string
---@field picker_detail? string
---@field commit_policy? "required"|"skip"|"optional"

local M = {}

---@type Clodex.PromptCategoryDef[]
local kinds = {
    {
        id = "todo",
        label = "TODO",
        highlight = "todo_title",
        default_title = "New todo",
    },
    {
        id = "bug",
        label = "Bug",
        highlight = "bug_title",
        default_title = "Investigate runtime error",
        title_prefix = "Investigate runtime error",
    },
    {
        id = "freeform",
        label = "Freeform",
        highlight = "freeform_title",
        default_title = "",
        picker_detail = "Send any message to the agent",
        commit_policy = "optional",
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
        id = "ask",
        label = "Ask",
        highlight = "explain_title",
        default_title = "Ask about the current behavior",
        commit_policy = "skip",
    },
    {
        id = "library",
        label = "Library",
        highlight = "idea_title",
        default_title = "Use a saved prompt template",
    },
    {
        id = "notworking",
        label = "Not Working",
        highlight = "notworking_title",
        default_title = "Fix a previously implemented feature that is not working",
    },
}

local by_id = {} ---@type table<string, Clodex.PromptCategoryDef>
for _, kind in ipairs(kinds) do
    by_id[kind.id] = kind
end
by_id.adjustment = by_id.freeform
by_id.explain = by_id.ask

---@return Clodex.PromptCategoryDef[]
function M.list()
    return vim.deepcopy(kinds)
end

---@param id? string
---@return Clodex.PromptCategoryDef
function M.get(id)
    return by_id[id] or by_id.todo
end

---@param id? string
---@return boolean
function M.is_valid(id)
    return by_id[id] ~= nil
end

---@param id? string
---@return boolean
function M.requires_commit(id)
    return (M.get(id).commit_policy or "required") == "required"
end

---@param id? string
---@return "required"|"skip"|"optional"
function M.commit_policy(id)
    return M.get(id).commit_policy or "required"
end

return M
