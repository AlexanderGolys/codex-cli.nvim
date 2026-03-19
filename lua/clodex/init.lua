---@alias Clodex.PublicAction
---| "toggle"
---| "toggle_state_preview"
---| "toggle_backend"
---| "add_project"
---| "rename_project"
---| "remove_project"
---| "toggle_terminal_header"
---| "clear_active_project"
---| "open_queue_workspace"
---| "open_project_readme_file"
---| "open_project_todo_file"
---| "open_project_dictionary_file"
---| "open_project_cheatsheet_file"
---| "toggle_project_cheatsheet_preview"
---| "add_project_cheatsheet_item"
---| "open_project_notes_picker"
---| "create_project_note"
---| "add_project_bookmark"
---| "open_project_bookmarks_picker"
---| "add_todo"
---| "implement_next_queued_item"
---| "implement_all_queued_items"
---| "add_prompt"
---| "add_prompt_for_project"
---| "add_bug_todo"
---| "open_history"

--- Defines the clodex type for this module.
--- This annotation documents structured state so modules can pass data with consistent expectations.
---@class clodex
local M = {}
M.lualine = require("clodex.lualine")

local PUBLIC_ACTIONS = {
    "toggle",
    "toggle_state_preview",
    "toggle_backend",
    "add_project",
    "rename_project",
    "remove_project",
    "toggle_terminal_header",
    "clear_active_project",
    "open_queue_workspace",
    "open_project_readme_file",
    "open_project_todo_file",
    "open_project_dictionary_file",
    "open_project_cheatsheet_file",
    "toggle_project_cheatsheet_preview",
    "add_project_cheatsheet_item",
    "open_project_notes_picker",
    "create_project_note",
    "add_project_bookmark",
    "open_project_bookmarks_picker",
    "add_todo",
    "implement_next_queued_item",
    "implement_all_queued_items",
    "add_prompt",
    "add_prompt_for_project",
    "add_bug_todo",
    "open_history",
} ---@type Clodex.PublicAction[]

local function app()
    return require("clodex.app").instance()
end

---@param method Clodex.PublicAction
---@return fun(...): any
local function call(method)
    return function(...)
        local instance = app()
        return instance[method](instance, ...)
    end
end

local function current_config()
    local ok, app_module = pcall(require, "clodex.app")
    if not ok or type(app_module.instance) ~= "function" then
        return {}
    end

    local ok_app, instance = pcall(app_module.instance)
    if not ok_app or not instance or not instance.config then
        return {}
    end

    return vim.deepcopy(instance.config:get() or {})
end

---@param opts? Clodex.Config.Values|{}
function M.setup(opts)
    app():setup(opts)
end

function M.register()
    require("clodex.commands").register()
end

for _, method in ipairs(PUBLIC_ACTIONS) do
    M[method] = call(method)
end

function M.debug_reload()
    local opts = current_config()

    for key in pairs(package.loaded) do
        if key:match("^clodex") then
            package.loaded[key] = nil
        end
    end

    require("clodex").setup(opts)
    vim.notify("clodex reloaded", vim.log.levels.INFO)
end

return M
