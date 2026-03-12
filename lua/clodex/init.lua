--- Defines the clodex type for this module.
--- This annotation documents structured state so modules can pass data with consistent expectations.
---@class clodex
local M = {}
M.lualine = require("clodex.lualine")

local function app()
    return require("clodex.app").instance()
end

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

M.toggle = call("toggle")
M.toggle_state_preview = call("toggle_state_preview")
M.open_terminal = M.toggle
M.add_project = call("add_project")
M.rename_project = call("rename_project")
M.remove_project = call("remove_project")
M.toggle_terminal_header = call("toggle_terminal_header")
M.clear_active_project = call("clear_active_project")
M.open_queue_workspace = call("open_queue_workspace")
M.open_project_todo_file = call("open_project_todo_file")
M.open_project_dictionary_file = call("open_project_dictionary_file")
M.open_project_cheatsheet_file = call("open_project_cheatsheet_file")
M.toggle_project_cheatsheet_preview = call("toggle_project_cheatsheet_preview")
M.add_project_cheatsheet_item = call("add_project_cheatsheet_item")
M.open_project_notes_picker = call("open_project_notes_picker")
M.create_project_note = call("create_project_note")
M.add_project_bookmark = call("add_project_bookmark")
M.open_project_bookmarks_picker = call("open_project_bookmarks_picker")
M.add_todo = call("add_todo")
M.implement_next_queued_item = call("implement_next_queued_item")
M.implement_all_queued_items = call("implement_all_queued_items")
M.add_prompt = call("add_prompt")
M.add_prompt_for_project = call("add_prompt_for_project")
M.add_error_todo = call("add_error_todo")

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
