local M = {}

local did_register = false
local Prompt = require('clodex.prompt')
local PRIMARY_COMMAND_PREFIX = 'Clodex'
local REQUIRE_CLODEX = function()
    return require('clodex')
end

local function emit_commands_updated()
    pcall(vim.api.nvim_exec_autocmds, "User", {
        pattern = "ClodexCommandsUpdated",
    })
end

local command_suffix = {
    todo = 'Todo',
    bug = 'Bug',
    visual = 'Visual',
    freeform = 'Freeform',
    adjustment = 'Adjustment',
    refactor = 'Refactor',
    idea = 'Idea',
    notworking = 'NotWorking',
    ask = 'Ask',
    explain = 'Explain',
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

---@class Clodex.ResolvedKeymap
---@field mode string|string[]
---@field lhs string
---@field desc string
---@field opts vim.api.keyset.keymap

---@class Clodex.CommandDefinition
---@field suffix string
---@field desc string
---@field nargs? string
---@field run fun(command: vim.api.keyset.create_user_command.command_args, clodex: clodex)

local BASE_COMMANDS = {
    {
        suffix = 'Toggle',
        desc = 'Toggle Codex terminal',
        run = function(_, clodex)
            clodex.toggle()
        end,
    },
    {
        suffix = 'StateToggle',
        desc = 'Toggle Codex state preview panel',
        run = function(_, clodex)
            clodex.toggle_state_preview()
        end,
    },
    {
        suffix = 'BackendToggle',
        desc = 'Toggle between Codex and OpenCode backends',
        run = function(_, clodex)
            clodex.toggle_backend()
        end,
    },
    {
        suffix = 'ProjectAdd',
        desc = 'Add current directory as a Clodex project',
        nargs = '?',
        run = function(command, clodex)
            clodex.add_project({ name = command.args ~= '' and command.args or nil })
        end,
    },
    {
        suffix = 'TerminalHeaderToggle',
        desc = 'Toggle header line in the active Codex terminal buffer',
        run = function(_, clodex)
            clodex.toggle_terminal_header()
        end,
    },
    {
        suffix = 'QueueWorkspace',
        desc = 'Open Clodex project queue workspace',
        run = function(_, clodex)
            clodex.open_queue_workspace()
        end,
    },
    {
        suffix = 'History',
        desc = 'Open global Clodex conversation history',
        run = function(_, clodex)
            clodex.open_history()
        end,
    },
    {
        suffix = 'ProjectReadme',
        desc = "Open the current project's README.md",
        run = function(_, clodex)
            clodex.open_project_readme_file()
        end,
    },
    {
        suffix = 'ProjectDictionary',
        desc = "Open the current project's dictionary",
        run = function(_, clodex)
            clodex.open_project_dictionary_file()
        end,
    },
    {
        suffix = 'ProjectCheatsheet',
        desc = "Open the current project's cheatsheet",
        run = function(_, clodex)
            clodex.open_project_cheatsheet_file()
        end,
    },
    {
        suffix = 'ProjectCheatsheetToggle',
        desc = "Toggle the current project's cheatsheet preview",
        run = function(_, clodex)
            clodex.toggle_project_cheatsheet_preview()
        end,
    },
    {
        suffix = 'ProjectCheatsheetAdd',
        desc = 'Add a one-line cheatsheet item',
        run = function(_, clodex)
            clodex.add_project_cheatsheet_item()
        end,
    },
    {
        suffix = 'ProjectNotes',
        desc = "Open the current project's notes picker",
        run = function(_, clodex)
            clodex.open_project_notes_picker()
        end,
    },
    {
        suffix = 'ProjectNoteAdd',
        desc = 'Create a project note',
        run = function(_, clodex)
            clodex.create_project_note()
        end,
    },
    {
        suffix = 'ProjectBookmarks',
        desc = "Open the current project's bookmarks picker",
        run = function(_, clodex)
            clodex.open_project_bookmarks_picker()
        end,
    },
    {
        suffix = 'ProjectBookmarkAdd',
        desc = "Add a bookmark for the current line",
        run = function(_, clodex)
            clodex.add_project_bookmark()
        end,
    },
    {
        suffix = 'TodoAdd',
        desc = "Add a todo prompt to a project's planned queue",
        nargs = '?',
        run = function(command, clodex)
            clodex.add_todo({
                project_value = command.args ~= '' and command.args or nil,
            })
        end,
    },
    {
        suffix = 'BugAdd',
        desc = 'Add a bug-investigation todo prompt',
        nargs = '?',
        run = function(command, clodex)
            clodex.add_bug_todo({
                project_value = command.args ~= '' and command.args or nil,
            })
        end,
    },
    {
        suffix = 'BugAddFor',
        desc = 'Pick a project and add a bug-investigation prompt',
        nargs = '?',
        run = function(command, clodex)
            clodex.add_bug_todo({
                project_required = true,
                project_value = command.args ~= '' and command.args or nil,
            })
        end,
    },
    {
        suffix = 'Implement',
        desc = 'Implement the next queued prompt for a project',
        nargs = '?',
        run = function(command, clodex)
            clodex.implement_next_queued_item({
                project_value = command.args ~= '' and command.args or nil,
            })
        end,
    },
    {
        suffix = 'TodoImplementAll',
        desc = 'Implement all queued prompts for a project',
        nargs = '?',
        run = function(command, clodex)
            clodex.implement_all_queued_items({
                project_value = command.args ~= '' and command.args or nil,
            })
        end,
    },
    {
        suffix = 'PromptAdd',
        desc = 'Add a prompt to the current or detected project',
        run = function(_, clodex)
            clodex.add_prompt()
        end,
    },
    {
        suffix = 'PromptAddFor',
        desc = 'Pick a project and prompt category to add',
        run = function(_, clodex)
            clodex.add_prompt_for_project()
        end,
    },
    {
        suffix = 'DebugReload',
        desc = 'Reload clodex modules for debugging',
        run = function(_, clodex)
            clodex.debug_reload()
        end,
    },
} ---@type Clodex.CommandDefinition[]

local REGISTERED_KEYMAPS = {} ---@type { mode: string, lhs: string }[]
local GLOBAL_KEYMAPS = {
    {
        field = 'toggle',
        mode = 'n',
        action = 'toggle',
        desc = 'Toggle Codex terminal',
    },
    {
        field = 'queue_workspace',
        mode = 'n',
        action = 'open_queue_workspace',
        desc = 'Open Clodex project queue workspace',
    },
    {
        field = 'state_preview',
        mode = 'n',
        action = 'toggle_state_preview',
        desc = 'Toggle Codex state preview panel',
    },
    {
        field = 'backend_toggle',
        mode = 'n',
        action = 'toggle_backend',
        desc = 'Toggle Clodex backend',
    },
} ---@type Clodex.GlobalKeymapDefinition[]

---@param values Clodex.Config.Values
---@param field keyof Clodex.Config.Keymaps
---@param definition Clodex.GlobalKeymapDefinition
---@return Clodex.ResolvedKeymap?
local function resolve_keymap(values, field, definition)
    local configured = values.keymaps or {}
    local value = configured[field]
    if value == false then
        return nil
    end

    local lhs = nil ---@type string|nil
    local mode = definition.mode
    local opts = {
        desc = ('Clodex: %s'):format(definition.desc),
        silent = true,
        noremap = true,
    } ---@type vim.api.keyset.keymap

    local value_type = type(value)
    if value_type == 'string' then
        if value == '' then
            return nil
        end
        lhs = value
    elseif value_type == 'table' then
        if value.enabled == false or value.enable == false then
            return nil
        end
        lhs = value.lhs or value.key
        if lhs == nil then
            lhs = value[1]
        end
        if value.mode ~= nil then
            mode = value.mode
        end
        if type(value.desc) == 'string' then
            opts.desc = value.desc
        end
        if type(value.opts) == 'table' then
            for option_key, option_value in pairs(value.opts) do
                opts[option_key] = option_value
            end
        end
        for option_key, option_value in pairs(value) do
            local reserved_key = option_key == 'lhs'
                or option_key == 'key'
                or option_key == 'mode'
                or option_key == 'desc'
                or option_key == 'enabled'
                or option_key == 'enable'
                or option_key == 'opts'
                or type(option_key) == 'number'
            if not reserved_key then
                opts[option_key] = option_value
            end
        end
    else
        return nil
    end

    if type(lhs) ~= 'string' or lhs == '' then
        return nil
    end

    return {
        lhs = lhs,
        mode = mode,
        desc = opts.desc,
        opts = opts,
    }
end

---@param definition Clodex.CommandDefinition
---@return Clodex.CommandSpec
local function command_spec(definition, name)
    return {
        name = name or command_name(definition.suffix),
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
            suffix = 'Prompt' .. suffix,
            desc = ('Add a %s prompt'):format(category.label:lower()),
            nargs = '?',
            run = function(command, clodex)
                clodex.add_prompt({
                    project_value = command.args ~= '' and command.args or nil,
                    category = category.id,
                })
            end,
        }),
        command_spec({
            suffix = 'Prompt' .. suffix .. 'For',
            desc = ('Pick a project and add a %s prompt'):format(category.label:lower()),
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

    for _, category in ipairs(Prompt.categories.list()) do
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
    for _, definition in ipairs(GLOBAL_KEYMAPS) do
        local keymap = resolve_keymap(values, definition.field, definition)
        if keymap ~= nil then
            local mode = keymap.mode
            if type(mode) == 'table' then
                mode = table.concat(mode, ',')
            end

            keymaps[#keymaps + 1] = {
                context = 'Global',
                mode = mode,
                lhs = keymap.lhs,
                desc = keymap.desc,
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

    for _, definition in ipairs(GLOBAL_KEYMAPS) do
        local keymap = resolve_keymap(values, definition.field, definition)
        if keymap ~= nil then
            vim.keymap.set(keymap.mode, keymap.lhs, function()
                return REQUIRE_CLODEX()[definition.action]()
            end, keymap.opts)
            REGISTERED_KEYMAPS[#REGISTERED_KEYMAPS + 1] = {
                mode = keymap.mode,
                lhs = keymap.lhs,
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

    emit_commands_updated()
end

return M
