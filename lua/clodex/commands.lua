local M = {}

local did_register = false
local Category = require("clodex.prompt.category")
local PRIMARY_COMMAND_PREFIX = "Clodex"
local REQUIRE_CLODEX = function()
    return require("clodex")
end

local command_suffix = {
    todo = "Todo",
    error = "Error",
    visual = "Visual",
    adjustment = "Adjustment",
    refactor = "Refactor",
    idea = "Idea",
    explain = "Explain",
}

---@param suffix string
---@return string
local function command_name(suffix)
    return PRIMARY_COMMAND_PREFIX .. suffix
end

--- Describes a Neovim `:Clodex*` command and its execution callback.
--- This shape is shared by both static and generated category-specific command registrations.
---@class Clodex.CommandSpec
---@field name string
---@field desc string
---@field nargs? string
---@field handler fun(command: vim.api.keyset.create_user_command.command_args)

---@class Clodex.KeymapSpec
---@field context string
---@field mode string
---@field lhs string
---@field desc string

---@class Clodex.GlobalKeymapDefinition
---@field field keyof Clodex.Config.Keymaps
---@field mode string
---@field action string
---@field desc string

---@class Clodex.CommandDefinition
---@field suffix string
---@field desc string
---@field nargs? string
---@field run fun(command: vim.api.keyset.create_user_command.command_args, clodex: clodex)

local BASE_COMMANDS = {
    {
        suffix = "Toggle",
        desc = "Toggle Codex terminal",
        run = function(_, clodex)
            clodex.toggle()
        end,
    },
    {
        suffix = "StateToggle",
        desc = "Toggle Codex state preview panel",
        run = function(_, clodex)
            clodex.toggle_state_preview()
        end,
    },
    {
        suffix = "ProjectAdd",
        desc = "Add current directory as a Clodex project",
        nargs = "?",
        run = function(command, clodex)
            clodex.add_project({ name = command.args ~= "" and command.args or nil })
        end,
    },
    {
        suffix = "ProjectRename",
        desc = "Rename a Clodex project",
        nargs = "?",
        run = function(command, clodex)
            clodex.rename_project(command.args ~= "" and command.args or nil)
        end,
    },
    {
        suffix = "ProjectRemove",
        desc = "Remove a Clodex project",
        nargs = "?",
        run = function(command, clodex)
            clodex.remove_project(command.args ~= "" and command.args or nil)
        end,
    },
    {
        suffix = "TerminalHeaderToggle",
        desc = "Toggle header line in the active Codex terminal buffer",
        run = function(_, clodex)
            clodex.toggle_terminal_header()
        end,
    },
    {
        suffix = "ProjectClear",
        desc = "Clear the active Clodex project for the current tab",
        run = function(_, clodex)
            clodex.clear_active_project()
        end,
    },
    {
        suffix = "QueueWorkspace",
        desc = "Open Clodex project queue workspace",
        run = function(_, clodex)
            clodex.open_queue_workspace()
        end,
    },
    {
        suffix = "History",
        desc = "Open global Clodex conversation history",
        run = function(_, clodex)
            clodex.open_history()
        end,
    },
    {
        suffix = "ProjectReadme",
        desc = "Open the current project's README.md",
        run = function(_, clodex)
            clodex.open_project_readme_file()
        end,
    },
    {
        suffix = "ProjectTodo",
        desc = "Open the current project's TODO.md",
        run = function(_, clodex)
            clodex.open_project_todo_file()
        end,
    },
    {
        suffix = "ProjectDictionary",
        desc = "Open the current project's dictionary",
        run = function(_, clodex)
            clodex.open_project_dictionary_file()
        end,
    },
    {
        suffix = "ProjectCheatsheet",
        desc = "Open the current project's cheatsheet",
        run = function(_, clodex)
            clodex.open_project_cheatsheet_file()
        end,
    },
    {
        suffix = "ProjectCheatsheetToggle",
        desc = "Toggle the current project's cheatsheet preview",
        run = function(_, clodex)
            clodex.toggle_project_cheatsheet_preview()
        end,
    },
    {
        suffix = "ProjectCheatsheetAdd",
        desc = "Add a one-line cheatsheet item",
        run = function(_, clodex)
            clodex.add_project_cheatsheet_item()
        end,
    },
    {
        suffix = "ProjectNotes",
        desc = "Open the current project's notes picker",
        run = function(_, clodex)
            clodex.open_project_notes_picker()
        end,
    },
    {
        suffix = "ProjectNoteAdd",
        desc = "Create a project note",
        run = function(_, clodex)
            clodex.create_project_note()
        end,
    },
    {
        suffix = "ProjectBookmarks",
        desc = "Open the current project's bookmarks picker",
        run = function(_, clodex)
            clodex.open_project_bookmarks_picker()
        end,
    },
    {
        suffix = "ProjectBookmarkAdd",
        desc = "Add a bookmark for the current line",
        run = function(_, clodex)
            clodex.add_project_bookmark()
        end,
    },
    {
        suffix = "TodoAdd",
        desc = "Add a todo prompt to a project's planned queue",
        nargs = "?",
        run = function(command, clodex)
            clodex.add_todo({
                project_value = command.args ~= "" and command.args or nil,
            })
        end,
    },
    {
        suffix = "TodoError",
        desc = "Add an error-investigation todo prompt",
        nargs = "?",
        run = function(command, clodex)
            clodex.add_error_todo({
                project_value = command.args ~= "" and command.args or nil,
            })
        end,
    },
    {
        suffix = "TodoErrorFor",
        desc = "Pick a project and add an error-investigation todo prompt",
        nargs = "?",
        run = function(command, clodex)
            clodex.add_error_todo({
                project_required = true,
                project_value = command.args ~= "" and command.args or nil,
            })
        end,
    },
    {
        suffix = "TodoImplement",
        desc = "Implement the next queued prompt for a project",
        nargs = "?",
        run = function(command, clodex)
            clodex.implement_next_queued_item({
                project_value = command.args ~= "" and command.args or nil,
            })
        end,
    },
    {
        suffix = "TodoImplementAll",
        desc = "Implement all queued prompts for a project",
        nargs = "?",
        run = function(command, clodex)
            clodex.implement_all_queued_items({
                project_value = command.args ~= "" and command.args or nil,
            })
        end,
    },
    {
        suffix = "PromptAdd",
        desc = "Add a prompt to the current or detected project",
        run = function(_, clodex)
            clodex.add_prompt()
        end,
    },
    {
        suffix = "PromptAddFor",
        desc = "Pick a project and prompt category to add",
        run = function(_, clodex)
            clodex.add_prompt_for_project()
        end,
    },
    {
        suffix = "DebugReload",
        desc = "Reload clodex modules for debugging",
        run = function(_, clodex)
            clodex.debug_reload()
        end,
    },
} ---@type Clodex.CommandDefinition[]

local REGISTERED_KEYMAPS = {} ---@type { mode: string, lhs: string }[]
local GLOBAL_KEYMAPS = {
    {
        field = "toggle",
        mode = "n",
        action = "toggle",
        desc = "Toggle Codex terminal",
    },
    {
        field = "queue_workspace",
        mode = "n",
        action = "open_queue_workspace",
        desc = "Open Clodex project queue workspace",
    },
    {
        field = "state_preview",
        mode = "n",
        action = "toggle_state_preview",
        desc = "Toggle Codex state preview panel",
    },
} ---@type Clodex.GlobalKeymapDefinition[]

---@param definition Clodex.CommandDefinition
---@return Clodex.CommandSpec
local function command_spec(definition)
    return {
        name = command_name(definition.suffix),
        desc = definition.desc,
        nargs = definition.nargs,
        handler = function(command)
            definition.run(command, REQUIRE_CLODEX())
        end,
    }
end

---@param category Clodex.PromptCategoryDef
---@return Clodex.CommandSpec[]
local function category_command_specs(category)
    local suffix = command_suffix[category.id]
    if not suffix then
        return {}
    end

    return {
        command_spec({
            suffix = "Prompt" .. suffix,
            desc = ("Add a %s prompt"):format(category.label:lower()),
            nargs = "?",
            run = function(command, clodex)
                clodex.add_prompt({
                    project_value = command.args ~= "" and command.args or nil,
                    category = category.id,
                })
            end,
        }),
        command_spec({
            suffix = "Prompt" .. suffix .. "For",
            desc = ("Pick a project and add a %s prompt"):format(category.label:lower()),
            run = function(_, clodex)
                clodex.add_prompt_for_project({
                    category = category.id,
                })
            end,
        }),
    }
end

---@return Clodex.CommandSpec[]
--- Builds the complete command list and injects category-specific variants.
--- Keeping this in one place guarantees consistent naming, docs, and handlers.
local function command_specs()
    local specs = {} ---@type Clodex.CommandSpec[]
    for _, definition in ipairs(BASE_COMMANDS) do
        specs[#specs + 1] = command_spec(definition)
    end

    for _, category in ipairs(Category.list()) do
        for _, spec in ipairs(category_command_specs(category)) do
            specs[#specs + 1] = spec
        end
    end

    return specs
end

---@return Clodex.CommandSpec[]
function M.list()
    return command_specs()
end

---@param values Clodex.Config.Values
---@return Clodex.KeymapSpec[]
function M.list_keymaps(values)
    local keymaps = {} ---@type Clodex.KeymapSpec[]
    local configured = values.keymaps or {}
    for _, definition in ipairs(GLOBAL_KEYMAPS) do
        local lhs = configured[definition.field]
        if type(lhs) == "string" and lhs ~= "" then
            keymaps[#keymaps + 1] = {
                context = "Global",
                mode = definition.mode,
                lhs = lhs,
                desc = definition.desc,
            }
        end
    end
    return keymaps
end

---@param values Clodex.Config.Values
function M.register_keymaps(values)
    for _, keymap in ipairs(REGISTERED_KEYMAPS) do
        pcall(vim.keymap.del, keymap.mode, keymap.lhs)
    end
    REGISTERED_KEYMAPS = {}

    local configured = values.keymaps or {}
    for _, definition in ipairs(GLOBAL_KEYMAPS) do
        local lhs = configured[definition.field]
        if type(lhs) == "string" and lhs ~= "" then
            vim.keymap.set(definition.mode, lhs, function()
                REQUIRE_CLODEX()[definition.action]()
            end, {
                desc = ("Clodex: %s"):format(definition.desc),
                silent = true,
            })
            REGISTERED_KEYMAPS[#REGISTERED_KEYMAPS + 1] = {
                mode = definition.mode,
                lhs = lhs,
            }
        end
    end
end

function M.register()
    if did_register then
        return
    end
    did_register = true

    for _, spec in ipairs(command_specs()) do
        local opts = {
            desc = spec.desc,
        }
        if spec.nargs ~= nil then
            opts.nargs = spec.nargs
        end
        vim.api.nvim_create_user_command(spec.name, spec.handler, opts)
    end
end

return M
