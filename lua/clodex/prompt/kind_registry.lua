---@alias Clodex.PromptCategory
---| "todo"
---| "bug"
---| "freeform"
---| "feature"
---| "adjustment"
---| "refactor"
---| "idea"
---| "cleanup"
---| "ask"
---| "explain"
---| "notworking"

---@class Clodex.PromptCategoryDef
---@field id Clodex.PromptCategory
---@field label string
---@field title_prefix? string
---@field highlight string
---@field default_title string
---@field picker_detail? string
---@field commit_policy? "required"|"skip"|"optional"
---@field aliases? string[]
---@field modes? Clodex.PromptCategoryModeDef[]
---@field default_mode? string

---@class Clodex.PromptCategoryModeDef
---@field id string
---@field label string
---@field layout string
---@field default_draft? fun(kind: Clodex.PromptCategory, category: Clodex.PromptCategoryDef, mode: Clodex.PromptCategoryModeDef): table
---@field on_select? fun(creator: Clodex.PromptCreator)

local M = {}

---@param category Clodex.PromptCategoryDef
---@param mode Clodex.PromptCategoryModeDef
---@return table
local function mode_default_draft(category, mode)
    if mode.default_draft then
        return mode.default_draft(category.id, category, mode)
    end
    return {
        title = category.default_title,
        details = "",
    }
end

---@param id string
---@param label string
---@param layout string
---@param opts? { default_draft?: fun(kind: Clodex.PromptCategory, category: Clodex.PromptCategoryDef, mode: Clodex.PromptCategoryModeDef): table, on_select?: fun(creator: Clodex.PromptCreator) }
---@return Clodex.PromptCategoryModeDef
local function mode(id, label, layout, opts)
    opts = opts or {}
    return {
        id = id,
        label = label,
        layout = layout,
        default_draft = opts.default_draft,
        on_select = opts.on_select,
    }
end

---@type Clodex.PromptCategoryDef[]
local kinds = {
    {
        id = "todo",
        label = "Improvement",
        highlight = "todo_title",
        default_title = "Improve the current implementation",
        aliases = { "improvement" },
        default_mode = "custom",
        modes = {
            mode("custom", "Custom", "composer"),
        },
    },
    {
        id = "bug",
        label = "Bug",
        highlight = "bug_title",
        default_title = "Investigate runtime error",
        title_prefix = "Investigate runtime error",
        default_mode = "custom",
        modes = {
            mode("custom", "Custom", "composer"),
            mode("clipboard_error", "Clipboard Error", "clipboard_preview", {
                default_draft = function(_, category)
                    return {
                        title = category.default_title,
                        details = "",
                        preview_text = "",
                    }
                end,
                on_select = function(creator)
                    creator.state.preview_text = creator:read_clipboard_message() or creator.state.preview_text or ""
                end,
            }),
            mode("clipboard_screenshot", "Clipboard Screenshot", "composer", {
                default_draft = function(_, category)
                    return {
                        title = category.default_title,
                        details = "Describe the runtime failure, what you expected instead, and fix it.",
                    }
                end,
                on_select = function(creator)
                    if not creator.state.image_path then
                        creator:replace_clipboard_image(true)
                    end
                end,
            }),
        },
    },
    {
        id = "freeform",
        label = "Fix",
        highlight = "freeform_title",
        default_title = "Fix the current behavior",
        picker_detail = "Send a direct fix-oriented request to the agent",
        commit_policy = "optional",
        aliases = { "fix", "adjustment" },
        default_mode = "custom",
        modes = {
            mode("custom", "Custom", "composer"),
        },
    },
    {
        id = "feature",
        label = "Feature",
        highlight = "feature_title",
        default_title = "Add a new feature",
        default_mode = "custom",
        modes = {
            mode("custom", "Custom", "composer"),
        },
    },
    {
        id = "refactor",
        label = "Restructure",
        highlight = "refactor_title",
        default_title = "Restructure the implementation",
        aliases = { "restructure" },
        default_mode = "custom",
        modes = {
            mode("custom", "Custom", "composer"),
        },
    },
    {
        id = "idea",
        label = "Vision",
        highlight = "idea_title",
        default_title = "Explore a product vision",
        commit_policy = "skip",
        aliases = { "vision" },
        default_mode = "custom",
        modes = {
            mode("custom", "Custom", "composer"),
        },
    },
    {
        id = "cleanup",
        label = "Clean-up",
        highlight = "cleanup_title",
        default_title = "Clean up the implementation",
        aliases = { "clean-up", "clean_up" },
        default_mode = "custom",
        modes = {
            mode("custom", "Custom", "composer"),
        },
    },
    {
        id = "ask",
        label = "Ask",
        highlight = "explain_title",
        default_title = "Ask about the current behavior",
        commit_policy = "skip",
        aliases = { "explain" },
        default_mode = "custom",
        modes = {
            mode("custom", "Custom", "composer"),
        },
    },
    {
        id = "notworking",
        label = "Not Working",
        highlight = "notworking_title",
        default_title = "Fix a previously implemented feature that is not working",
        default_mode = "custom",
        modes = {
            mode("custom", "Custom", "composer"),
        },
    },
}

local by_id = {} ---@type table<string, Clodex.PromptCategoryDef>
for _, kind in ipairs(kinds) do
    by_id[kind.id] = kind
    for _, alias in ipairs(kind.aliases or {}) do
        by_id[alias] = kind
    end
end

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

---@param id? string
---@return Clodex.PromptCategoryModeDef[]
function M.modes(id)
    local category = M.get(id)
    local modes = category.modes or {
        mode("custom", "Custom", "composer"),
    }
    return vim.deepcopy(modes)
end

---@param id? string
---@return string
function M.default_mode(id)
    local category = M.get(id)
    local modes = category.modes or {}
    if category.default_mode and category.default_mode ~= "" then
        return category.default_mode
    end
    return modes[1] and modes[1].id or "custom"
end

---@param id? string
---@param mode_id? string
---@return Clodex.PromptCategoryModeDef
function M.mode(id, mode_id)
    local modes = M.modes(id)
    local default_mode = M.default_mode(id)
    for _, item in ipairs(modes) do
        if item.id == (mode_id or default_mode) then
            return item
        end
    end
    return modes[1] or mode(default_mode, "Custom", "composer")
end

---@param id? string
---@param mode_id? string
---@return string
function M.layout_id(id, mode_id)
    return M.mode(id, mode_id).layout
end

---@param id? string
---@param mode_id? string
---@return table
function M.default_draft(id, mode_id)
    local category = M.get(id)
    local selected_mode = M.mode(id, mode_id)
    return mode_default_draft(category, selected_mode)
end

return M
