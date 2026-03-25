local Prompt = require("clodex.prompt")

local M = {}

local function composer_draft(kind)
    return {
        title = Prompt.categories.get(kind).default_title,
        details = "",
    }
end

local bug_variants = {
    {
        id = "custom",
        label = "Custom",
        layout = "composer",
        default_draft = function()
            return {
                title = Prompt.categories.get("bug").default_title,
                details = "",
            }
        end,
    },
    {
        id = "clipboard_error",
        label = "Clipboard Error",
        layout = "clipboard_preview",
        default_draft = function()
            return {
                title = Prompt.categories.get("bug").default_title,
                details = "",
                preview_text = "",
            }
        end,
    },
    {
        id = "clipboard_screenshot",
        label = "Clipboard Screenshot",
        layout = "composer",
        default_draft = function()
            return {
                title = Prompt.categories.get("bug").default_title,
                details = "Describe the runtime failure, what you expected instead, and fix it.",
            }
        end,
    },
}

local creators = {
    todo = {
        layout = "composer",
        default_draft = function()
            return composer_draft("todo")
        end,
    },
    freeform = {
        layout = "composer",
        default_draft = function()
            return composer_draft("freeform")
        end,
    },
    refactor = {
        layout = "composer",
        default_draft = function()
            return composer_draft("refactor")
        end,
    },
    idea = {
        layout = "composer",
        default_draft = function()
            return composer_draft("idea")
        end,
    },
    ask = {
        layout = "composer",
        default_draft = function()
            return composer_draft("ask")
        end,
    },
    library = {
        layout = "template_picker",
        default_draft = function()
            return composer_draft("library")
        end,
    },
    bug = {
        layout = "composer",
        variants = bug_variants,
        default_variant = "custom",
        default_draft = function(_, variant)
            for _, item in ipairs(bug_variants) do
                if item.id == variant then
                    return item.default_draft()
                end
            end
            return bug_variants[1].default_draft()
        end,
    },
}

---@param kind Clodex.PromptCategory
---@return table
function M.get(kind)
    return creators[kind] or creators.todo
end

---@param kind Clodex.PromptCategory
---@return table[]
function M.variants(kind)
    return vim.deepcopy(M.get(kind).variants or {})
end

---@param kind Clodex.PromptCategory
---@param variant? string
---@return table
function M.default_draft(kind, variant)
    local creator = M.get(kind)
    if creator.default_draft then
        return creator.default_draft(kind, variant)
    end
    return { title = Prompt.categories.get(kind).default_title, details = "" }
end

return M
