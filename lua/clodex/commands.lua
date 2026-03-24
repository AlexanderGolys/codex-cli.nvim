local notify = require("clodex.util.notify")
local Prompt = require("clodex.prompt")
local PromptContext = require("clodex.prompt.context")

local M = {}

local did_register = false

---@class Clodex.CommandEnumChoice
---@field value string
---@field aliases string[]
---@field desc string

---@class Clodex.CommandEnum
---@field label string
---@field choices Clodex.CommandEnumChoice[]
---@field aliases table<string, string>
---@field completions string[]

---@class Clodex.CommandSpec
---@field name string
---@field desc string
---@field nargs? string
---@field invoke? string
---@field keep_open? boolean

---@class Clodex.KeymapSpec
---@field context string
---@field mode string
---@field lhs string
---@field desc string

---@alias Clodex.KeymapField "toggle"|"queue_workspace"|"state_preview"|"mini_state_preview"|"backend_toggle"

---@class Clodex.GlobalKeymapDefinition
---@field field Clodex.KeymapField
---@field mode string
---@field action string
---@field desc string

---@class Clodex.ResolvedKeymap
---@field mode string|string[]
---@field lhs string
---@field desc string
---@field opts vim.api.keyset.keymap

---@alias Clodex.Commands.KeymapValues Clodex.Config.Values|{ keymaps?: table<string, string|Clodex.Config.KeymapConfig|false> }

---@class Clodex.RegisteredCommandSpec
---@field name string
---@field desc string
---@field nargs? string
---@field range? boolean|string|integer
---@field complete? fun(arg_lead: string, cmd_line: string, cursor_pos: integer): string[]
---@field handler fun(command: vim.api.keyset.create_user_command.command_args)

local function require_clodex()
    return require("clodex")
end

local function app_instance()
    return require("clodex.app").instance()
end

local function emit_commands_updated()
    pcall(vim.api.nvim_exec_autocmds, "User", {
        pattern = "ClodexCommandsUpdated",
    })
end

---@param label string
---@param choices { value: string, aliases?: string[], desc: string }[]
---@return Clodex.CommandEnum
local function enum(label, choices)
    local aliases = {} ---@type table<string, string>
    local completions = {} ---@type string[]
    local normalized = {} ---@type Clodex.CommandEnumChoice[]

    for _, choice in ipairs(choices) do
        local names = { choice.value }
        for _, alias in ipairs(choice.aliases or {}) do
            names[#names + 1] = alias
        end
        normalized[#normalized + 1] = {
            value = choice.value,
            aliases = names,
            desc = choice.desc,
        }
        for _, alias in ipairs(names) do
            aliases[alias] = choice.value
            completions[#completions + 1] = alias
        end
    end

    table.sort(completions)
    return {
        label = label,
        choices = normalized,
        aliases = aliases,
        completions = completions,
    }
end

local CLODEX_ACTION = enum("action", {
    { value = "panel", desc = "Toggle the queue workspace panel" },
    { value = "terminal", aliases = { "cli", "term", "chat" }, desc = "Toggle the project terminal" },
    { value = "history", desc = "Open global Clodex history" },
    { value = "backend", desc = "Toggle the active backend" },
    { value = "header", aliases = { "term-header", "terminal-header", "terminal_header" }, desc = "Toggle the active terminal header" },
})

local DEBUG_ACTION = enum("action", {
    { value = "panel", desc = "Toggle the debug state panel" },
    { value = "mini", aliases = { "mini-panel", "mini_panel" }, desc = "Toggle the compact debug panel" },
    { value = "reload", desc = "Reload clodex modules" },
})

local PROJECT_ACTION = enum("action", {
    { value = "add", desc = "Register the current workspace as a project" },
    { value = "readme", desc = "Open the current project's README" },
    { value = "dictionary", aliases = { "dict" }, desc = "Open the current project's dictionary" },
    { value = "cheatsheet", desc = "Open the current project's cheatsheet file" },
    { value = "cheatsheet-panel", aliases = { "cheatsheet_panel", "cheatsheet-preview", "cheatsheet_preview" }, desc = "Toggle the project cheatsheet preview" },
    { value = "cheatsheet-add", aliases = { "cheatsheet_add" }, desc = "Add a cheatsheet item" },
    { value = "notes", desc = "Open the current project's notes picker" },
    { value = "note-add", aliases = { "note_add" }, desc = "Create a project note" },
    { value = "bookmarks", desc = "Open the current project's bookmarks picker" },
    { value = "bookmark-add", aliases = { "bookmark_add" }, desc = "Add a bookmark at the current line" },
})

local TODO_ACTION = enum("action", {
    { value = "add", desc = "Add a todo prompt" },
    { value = "bug", aliases = { "error" }, desc = "Add a bug-investigation prompt" },
    { value = "implement", desc = "Implement the next queued item" },
    { value = "all", aliases = { "implement-all", "implement_all" }, desc = "Implement all queued items" },
})

local TARGET_SCOPE = enum("scope", {
    { value = "pick", aliases = { "for" }, desc = "Pick the target project explicitly" },
})

---@return Clodex.CommandEnum
local function prompt_kind_enum()
    local choices = {} ---@type { value: string, aliases?: string[], desc: string }[]
    for _, category in ipairs(Prompt.categories.list()) do
        local aliases = {} ---@type string[]
        if category.id == "ask" then
            aliases[#aliases + 1] = "explain"
        elseif category.id == "freeform" then
            aliases[#aliases + 1] = "adjustment"
        end
        choices[#choices + 1] = {
            value = category.id,
            aliases = aliases,
            desc = category.default_title ~= "" and category.default_title or category.label,
        }
    end
    return enum("kind", choices)
end

local PROMPT_KIND = prompt_kind_enum()

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
    {
        field = "mini_state_preview",
        mode = "n",
        action = "toggle_mini_state_preview",
        desc = "Toggle compact Codex state preview",
    },
    {
        field = "backend_toggle",
        mode = "n",
        action = "toggle_backend",
        desc = "Toggle Clodex backend",
    },
} ---@type Clodex.GlobalKeymapDefinition[]

local REGISTERED_KEYMAPS = {} ---@type { mode: string|string[], lhs: string }[]

---@param values Clodex.Commands.KeymapValues
---@param field Clodex.KeymapField
---@param definition Clodex.GlobalKeymapDefinition
---@return Clodex.ResolvedKeymap?
local function resolve_keymap(values, field, definition)
    local configured = values.keymaps or {}
    local value = configured[field]
    if value == false then
        return nil
    end

    local lhs = nil ---@type string?
    local mode = definition.mode
    local opts = {
        desc = ("Clodex: %s"):format(definition.desc),
        silent = true,
        noremap = true,
    } ---@type vim.api.keyset.keymap

    local value_type = type(value)
    if value_type == "string" then
        if value == "" then
            return nil
        end
        lhs = value
    elseif value_type == "table" then
        if value.enabled == false or value.enable == false then
            return nil
        end
        lhs = value.lhs or value.key or value[1]
        if value.mode ~= nil then
            mode = value.mode
        end
        if type(value.desc) == "string" then
            opts.desc = value.desc
        end
        if type(value.opts) == "table" then
            for option_key, option_value in pairs(value.opts) do
                opts[option_key] = option_value
            end
        end
        for option_key, option_value in pairs(value) do
            local reserved_key = option_key == "lhs"
                or option_key == "key"
                or option_key == "mode"
                or option_key == "desc"
                or option_key == "enabled"
                or option_key == "enable"
                or option_key == "opts"
                or type(option_key) == "number"
            if not reserved_key then
                opts[option_key] = option_value
            end
        end
    else
        return nil
    end

    if type(lhs) ~= "string" or lhs == "" then
        return nil
    end

    return {
        lhs = lhs,
        mode = mode,
        desc = opts.desc,
        opts = opts,
    }
end

---@param cmd_line string
---@param cursor_pos integer
---@return integer
local function completion_arg_index(cmd_line, cursor_pos)
    local before = cmd_line:sub(1, cursor_pos)
    local parts = vim.split(before, "%s+", { trimempty = true })
    if before:match("%s$") then
        return #parts
    end
    return math.max(#parts - 1, 0)
end

---@param enum_spec Clodex.CommandEnum
---@return string
local function enum_hint(enum_spec)
    return table.concat(enum_spec.completions, ", ")
end

---@param token string
---@param enum_spec Clodex.CommandEnum
---@param command_name string
---@return string?
local function resolve_enum(token, enum_spec, command_name)
    local value = enum_spec.aliases[token]
    if value ~= nil then
        return value
    end
    notify.error(("%s: invalid %s '%s'. Expected one of: %s"):format(
        command_name,
        enum_spec.label,
        token,
        enum_hint(enum_spec)
    ))
end

---@param command_name string
---@param args string[]
---@param expected string
---@return boolean
local function check_extra_args(command_name, args, expected)
    if #args == 0 then
        return true
    end
    notify.error(("%s: unexpected arguments '%s'. Expected %s"):format(
        command_name,
        table.concat(args, " "),
        expected
    ))
    return false
end

---@param command_name string
---@param value string?
---@return Clodex.Project?
local function resolve_project_value(command_name, value)
    if not value or value == "" then
        return nil
    end
    local project = app_instance().registry:find_by_name_or_root(value)
    if project then
        return project
    end
    notify.error(("%s: project '%s' not found"):format(command_name, value))
end

---@param command_name string
---@param fargs string[]
---@param start_index integer
---@return { project?: Clodex.Project, project_required?: boolean }?
local function parse_target(command_name, fargs, start_index)
    local first = fargs[start_index]
    if not first then
        return {}
    end

    local scope = TARGET_SCOPE.aliases[first]
    if scope then
        local project_value = table.concat(vim.list_slice(fargs, start_index + 1), " ")
        if project_value ~= "" then
            notify.error(("%s: '%s' does not accept an explicit project name"):format(command_name, first))
            return nil
        end
        return { project_required = true }
    end

    local project_value = table.concat(vim.list_slice(fargs, start_index), " ")
    local project = resolve_project_value(command_name, project_value)
    if project_value ~= "" and not project then
        return nil
    end
    return project and { project = project } or {}
end

---@param command vim.api.keyset.create_user_command.command_args
---@return Clodex.PromptContext.Capture?
local function visual_selection_context(command)
    if not command or (command.range or 0) <= 0 then
        return nil
    end

    local selection_mode = vim.fn.visualmode()
    if selection_mode == "" then
        selection_mode = "v"
    end

    return PromptContext.capture({
        selection_mode = selection_mode,
    })
end

---@param enum_spec Clodex.CommandEnum
---@param arg_index integer
---@return fun(arg_lead: string, cmd_line: string, cursor_pos: integer): string[]
local function enum_completion(enum_spec, arg_index)
    return function(_, cmd_line, cursor_pos)
        if completion_arg_index(cmd_line, cursor_pos) ~= arg_index then
            return {}
        end
        return enum_spec.completions
    end
end

---@return string[]
local function project_completions()
    local ok, app = pcall(app_instance)
    if not ok or not app or not app.registry or type(app.registry.list) ~= "function" then
        return {}
    end

    local seen = {} ---@type table<string, boolean>
    local completions = {} ---@type string[]
    for _, project in ipairs(app.registry:list()) do
        for _, value in ipairs({ project.name, project.root }) do
            if type(value) == "string" and value ~= "" and not seen[value] then
                seen[value] = true
                completions[#completions + 1] = value
            end
        end
    end
    table.sort(completions)
    return completions
end

---@param ... string[]
---@return string[]
local function merge_completions(...)
    local seen = {} ---@type table<string, boolean>
    local merged = {} ---@type string[]
    for _, items in ipairs({ ... }) do
        for _, item in ipairs(items) do
            if not seen[item] then
                seen[item] = true
                merged[#merged + 1] = item
            end
        end
    end
    table.sort(merged)
    return merged
end

---@param action_enum Clodex.CommandEnum
---@param fargs string[]
---@return integer
local function completion_target_start(action_enum, fargs)
    if fargs[1] and action_enum.aliases[fargs[1]] ~= nil then
        return 2
    end
    return 1
end

---@param cmd_line string
---@param cursor_pos integer
---@return string[]
local function completion_fargs(cmd_line, cursor_pos)
    local parts = vim.split(cmd_line:sub(1, cursor_pos), "%s+", { trimempty = true })
    table.remove(parts, 1)
    return parts
end

---@param enum_spec Clodex.CommandEnum
---@return fun(arg_lead: string, cmd_line: string, cursor_pos: integer): string[]
local function scoped_completion(enum_spec)
    return function(_, cmd_line, cursor_pos)
        local index = completion_arg_index(cmd_line, cursor_pos)
        local before = completion_fargs(cmd_line, cursor_pos)
        local target_start = completion_target_start(enum_spec, before)
        if index < target_start then
            return enum_spec.completions
        end
        if index == target_start then
            if target_start == 1 then
                return merge_completions(enum_spec.completions, TARGET_SCOPE.completions, project_completions())
            end
            return merge_completions(TARGET_SCOPE.completions, project_completions())
        end
        if index == target_start + 1 and TARGET_SCOPE.aliases[before[target_start]] == nil then
            return project_completions()
        end
        return {}
    end
end

---@param command vim.api.keyset.create_user_command.command_args
---@param category? Clodex.PromptCategory
---@return table
local function prompt_command_opts(command, category)
    local context = visual_selection_context(command)
    return vim.tbl_extend("force", category and {
        category = category,
    } or {}, context and {
        context = context,
    } or {})
end

local function top_level_palette_specs()
    return {
        { name = "Clodex", desc = "Toggle the queue workspace panel", invoke = "Clodex" },
        { name = "Clodex panel", desc = "Toggle the queue workspace panel", invoke = "Clodex panel" },
        { name = "Clodex cli", desc = "Toggle the project terminal", invoke = "Clodex cli" },
        { name = "Clodex history", desc = "Open global Clodex history", invoke = "Clodex history" },
        { name = "Clodex backend", desc = "Toggle the active backend", invoke = "Clodex backend" },
        { name = "Clodex header", desc = "Toggle the active terminal header", invoke = "Clodex header" },
        { name = "ClodexDebug panel", desc = "Toggle the debug state panel", invoke = "ClodexDebug panel", keep_open = true },
        { name = "ClodexDebug mini", desc = "Toggle the compact debug panel", invoke = "ClodexDebug mini" },
        { name = "ClodexDebug reload", desc = "Reload clodex modules", invoke = "ClodexDebug reload" },
        { name = "ClodexProject add", desc = "Register the current workspace as a project", invoke = "ClodexProject add" },
        { name = "ClodexProject readme", desc = "Open the current project's README", invoke = "ClodexProject readme" },
        { name = "ClodexProject dictionary", desc = "Open the current project's dictionary", invoke = "ClodexProject dictionary" },
        { name = "ClodexProject cheatsheet", desc = "Open the current project's cheatsheet file", invoke = "ClodexProject cheatsheet" },
        { name = "ClodexProject cheatsheet-panel", desc = "Toggle the project cheatsheet preview", invoke = "ClodexProject cheatsheet-panel" },
        { name = "ClodexProject cheatsheet-add", desc = "Add a cheatsheet item", invoke = "ClodexProject cheatsheet-add" },
        { name = "ClodexProject notes", desc = "Open the current project's notes picker", invoke = "ClodexProject notes" },
        { name = "ClodexProject note-add", desc = "Create a project note", invoke = "ClodexProject note-add" },
        { name = "ClodexProject bookmarks", desc = "Open the current project's bookmarks picker", invoke = "ClodexProject bookmarks" },
        { name = "ClodexProject bookmark-add", desc = "Add a bookmark at the current line", invoke = "ClodexProject bookmark-add" },
        { name = "ClodexTodo", desc = "Add a todo prompt", invoke = "ClodexTodo" },
        { name = "ClodexTodo bug", desc = "Add a bug-investigation prompt", invoke = "ClodexTodo bug" },
        { name = "ClodexTodo implement", desc = "Implement the next queued item", invoke = "ClodexTodo implement" },
        { name = "ClodexTodo all", desc = "Implement all queued items", invoke = "ClodexTodo all" },
        { name = "ClodexPromptFile", desc = "Add a prompt for the current file's project", invoke = "ClodexPromptFile" },
    } ---@type Clodex.CommandSpec[]
end

---@return Clodex.CommandSpec[]
local function prompt_palette_specs()
    local specs = {
        { name = "ClodexPrompt", desc = "Pick a prompt category for the current project", invoke = "ClodexPrompt" },
    } ---@type Clodex.CommandSpec[]

    for _, category in ipairs(Prompt.categories.list()) do
        specs[#specs + 1] = {
            name = ("ClodexPrompt %s"):format(category.id),
            desc = ("Add a %s prompt"):format(category.label:lower()),
            invoke = ("ClodexPrompt %s"):format(category.id),
        }
    end

    return specs
end

---@return Clodex.CommandSpec[]
local function command_specs()
    local specs = top_level_palette_specs()
    vim.list_extend(specs, prompt_palette_specs())
    return specs
end

---@return Clodex.RegisteredCommandSpec[]
local function registered_command_specs()
    return {
        {
            name = "Clodex",
            desc = "Open the Clodex panel or run a top-level action",
            nargs = "?",
            complete = enum_completion(CLODEX_ACTION, 1),
            handler = function(command)
                local clodex = require_clodex()
                local token = command.fargs[1]
                local action = token and resolve_enum(token, CLODEX_ACTION, "Clodex") or "panel"
                if not action then
                    return
                end
                if not check_extra_args("Clodex", vim.list_slice(command.fargs, 2), "at most one action argument") then
                    return
                end
                if action == "panel" then
                    clodex.open_queue_workspace()
                elseif action == "terminal" then
                    clodex.toggle()
                elseif action == "history" then
                    clodex.open_history()
                elseif action == "backend" then
                    clodex.toggle_backend()
                elseif action == "header" then
                    clodex.toggle_terminal_header()
                end
            end,
        },
        {
            name = "ClodexDebug",
            desc = "Run a Clodex debugging action",
            nargs = "?",
            complete = enum_completion(DEBUG_ACTION, 1),
            handler = function(command)
                local clodex = require_clodex()
                local token = command.fargs[1]
                local action = token and resolve_enum(token, DEBUG_ACTION, "ClodexDebug") or "panel"
                if not action then
                    return
                end
                if not check_extra_args("ClodexDebug", vim.list_slice(command.fargs, 2), "at most one action argument") then
                    return
                end
                if action == "panel" then
                    clodex.toggle_state_preview()
                elseif action == "mini" then
                    clodex.toggle_mini_state_preview()
                elseif action == "reload" then
                    clodex.debug_reload()
                end
            end,
        },
        {
            name = "ClodexProject",
            desc = "Run a project-scoped Clodex action",
            nargs = "*",
            complete = enum_completion(PROJECT_ACTION, 1),
            handler = function(command)
                local clodex = require_clodex()
                local token = command.fargs[1]
                local action = token and resolve_enum(token, PROJECT_ACTION, "ClodexProject") or "add"
                if not action then
                    return
                end
                local trailing = vim.list_slice(command.fargs, 2)
                if action == "add" then
                    clodex.add_project({
                        name = #trailing > 0 and table.concat(trailing, " ") or nil,
                    })
                    return
                end
                if not check_extra_args("ClodexProject", trailing, "only an optional name for 'add'") then
                    return
                end
                if action == "readme" then
                    clodex.open_project_readme_file()
                elseif action == "dictionary" then
                    clodex.open_project_dictionary_file()
                elseif action == "cheatsheet" then
                    clodex.open_project_cheatsheet_file()
                elseif action == "cheatsheet-panel" then
                    clodex.toggle_project_cheatsheet_preview()
                elseif action == "cheatsheet-add" then
                    clodex.add_project_cheatsheet_item()
                elseif action == "notes" then
                    clodex.open_project_notes_picker()
                elseif action == "note-add" then
                    clodex.create_project_note()
                elseif action == "bookmarks" then
                    clodex.open_project_bookmarks_picker()
                elseif action == "bookmark-add" then
                    clodex.add_project_bookmark()
                end
            end,
        },
        {
            name = "ClodexTodo",
            desc = "Add or implement todo queue items",
            nargs = "*",
            complete = scoped_completion(TODO_ACTION),
            handler = function(command)
                local clodex = require_clodex()
                local token = command.fargs[1]
                local action = "add"
                local start_index = 1
                if token and TODO_ACTION.aliases[token] ~= nil then
                    action = resolve_enum(token, TODO_ACTION, "ClodexTodo") or action
                    start_index = 2
                elseif #command.fargs > 1 and TARGET_SCOPE.aliases[command.fargs[2]] ~= nil then
                    notify.error(("ClodexTodo: invalid action '%s'. Expected one of: %s"):format(
                        token,
                        enum_hint(TODO_ACTION)
                    ))
                    return
                end
                if not action then
                    return
                end
                local target = parse_target("ClodexTodo", command.fargs, start_index)
                if not target then
                    return
                end
                if action == "add" then
                    clodex.add_todo(target)
                elseif action == "bug" then
                    clodex.add_bug_todo(target)
                elseif action == "implement" then
                    clodex.implement_next_queued_item(target)
                elseif action == "all" then
                    clodex.implement_all_queued_items(target)
                end
            end,
        },
        {
            name = "ClodexPrompt",
            desc = "Add a prompt with an optional category and project target",
            nargs = "*",
            range = true,
            complete = scoped_completion(PROMPT_KIND),
            handler = function(command)
                local clodex = require_clodex()
                local fargs = command.fargs
                local kind = nil ---@type Clodex.PromptCategory?
                local start_index = 1

                if fargs[1] and PROMPT_KIND.aliases[fargs[1]] ~= nil then
                    kind = resolve_enum(fargs[1], PROMPT_KIND, "ClodexPrompt")
                    if not kind then
                        return
                    end
                    start_index = 2
                elseif #fargs > 1 and TARGET_SCOPE.aliases[fargs[2]] ~= nil then
                    notify.error(("ClodexPrompt: invalid kind '%s'. Expected one of: %s"):format(
                        fargs[1],
                        enum_hint(PROMPT_KIND)
                    ))
                    return
                end

                local target = parse_target("ClodexPrompt", fargs, start_index)
                if not target then
                    return
                end

                local opts = vim.tbl_extend("force", target, prompt_command_opts(command, kind))
                if target.project_required then
                    clodex.add_prompt_for_project(opts)
                    return
                end
                clodex.add_prompt(opts)
            end,
        },
        {
            name = "ClodexPromptFile",
            desc = "Add a prompt for the project that owns the current file",
            nargs = "?",
            range = true,
            complete = enum_completion(PROMPT_KIND, 1),
            handler = function(command)
                local clodex = require_clodex()
                local kind = nil ---@type Clodex.PromptCategory?
                if command.fargs[1] then
                    kind = resolve_enum(command.fargs[1], PROMPT_KIND, "ClodexPromptFile")
                    if not kind then
                        return
                    end
                end
                if not check_extra_args("ClodexPromptFile", vim.list_slice(command.fargs, 2), "at most one kind argument") then
                    return
                end

                clodex.add_prompt_for_current_file_project(prompt_command_opts(command, kind))
            end,
        },
    }
end

---@return Clodex.CommandSpec[]
function M.list()
    return command_specs()
end

---@param values Clodex.Commands.KeymapValues
---@return Clodex.KeymapSpec[]
function M.list_keymaps(values)
    local keymaps = {} ---@type Clodex.KeymapSpec[]
    for _, definition in ipairs(GLOBAL_KEYMAPS) do
        local keymap = resolve_keymap(values, definition.field, definition)
        if keymap ~= nil then
            local mode = keymap.mode
            if type(mode) == "table" then
                mode = table.concat(mode, ",")
            end
            keymaps[#keymaps + 1] = {
                context = "Global",
                mode = mode,
                lhs = keymap.lhs,
                desc = keymap.desc,
            }
        end
    end
    return keymaps
end

---@param values Clodex.Commands.KeymapValues
function M.register_keymaps(values)
    for _, keymap in ipairs(REGISTERED_KEYMAPS) do
        pcall(vim.keymap.del, keymap.mode, keymap.lhs)
    end
    REGISTERED_KEYMAPS = {}

    for _, definition in ipairs(GLOBAL_KEYMAPS) do
        local keymap = resolve_keymap(values, definition.field, definition)
        if keymap ~= nil then
            vim.keymap.set(keymap.mode, keymap.lhs, function()
                return require_clodex()[definition.action]()
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

    for _, spec in ipairs(registered_command_specs()) do
        local opts = {
            desc = spec.desc,
        }
        if spec.nargs ~= nil then
            opts.nargs = spec.nargs
        end
        if spec.complete ~= nil then
            opts.complete = spec.complete
        end
        if spec.range ~= nil then
            opts.range = spec.range
        end
        vim.api.nvim_create_user_command(spec.name, spec.handler, opts)
    end

    emit_commands_updated()
end

return M
