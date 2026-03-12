local M = {}

local did_register = false
local Category = require("clodex.prompt.category")
local PRIMARY_COMMAND_PREFIX = "Clodex"
local COMPAT_COMMAND_PREFIX = "Codex"
local LEGACY_TYPO_ALIASES = {
    ClodexStateToggle = { "CodeStateToggle" },
}

local command_suffix = {
    todo = "Todo",
    error = "Error",
    visual = "Visual",
    adjustment = "Adjustment",
    refactor = "Refactor",
    idea = "Idea",
    explain = "Explain",
}

--- Describes a Neovim `:Clodex*` command and its execution callback.
--- This shape is shared by both static and generated category-specific command registrations.
---@class Clodex.CommandSpec
---@field name string
---@field desc string
---@field nargs? string
---@field handler fun(command: vim.api.keyset.create_user_command.command_args)

---@return Clodex.CommandSpec[]
--- Builds the complete command list and injects category-specific variants.
--- Keeping this in one place guarantees consistent naming, docs, and handlers.
local function command_specs()
    local specs = {
        {
            name = "ClodexToggle",
            desc = "Toggle Codex terminal",
            --- Toggles the currently tracked terminal target for the active tab.
            --- This is the primary entry point from user command to terminal visibility.
            handler = function()
                require("clodex").toggle()
            end,
        },
        {
            name = "ClodexStateToggle",
            desc = "Toggle Codex state preview panel",
            --- Shows or hides the command/state floating preview panels.
            --- Useful for quickly checking active queues and project state.
            handler = function()
                require("clodex").toggle_state_preview()
            end,
        },
        {
            name = "ClodexProjectAdd",
            desc = "Add current directory as a Clodex project",
            nargs = "?",
            --- Registers a project from current path or provided root/name.
            --- If omitted, existing detection paths are used to infer a good default.
            handler = function(command)
                require("clodex").add_project({ name = command.args ~= "" and command.args or nil })
            end,
        },
        {
            name = "ClodexProjectRename",
            desc = "Rename a Clodex project",
            nargs = "?",
            --- Renames a project using the selected project or supplied identifier.
            --- Validation and registry persistence are delegated to the app layer.
            handler = function(command)
                require("clodex").rename_project(command.args ~= "" and command.args or nil)
            end,
        },
        {
            name = "ClodexProjectRemove",
            desc = "Remove a Clodex project",
            nargs = "?",
            --- Removes a project from registry and clears its sessions/queue data.
            --- If no target is supplied, picker-driven removal is used.
            handler = function(command)
                require("clodex").remove_project(command.args ~= "" and command.args or nil)
            end,
        },
        {
            name = "ClodexTerminalHeaderToggle",
            desc = "Toggle header line in the active Codex terminal buffer",
            --- Toggles terminal header rendering for the active Codex buffer.
            --- Header visibility is stored per session and updated immediately.
            handler = function()
                require("clodex").toggle_terminal_header()
            end,
        },
        {
            name = "ClodexProjectClear",
            desc = "Clear the active Clodex project for the current tab",
            --- Clears any pinned active project for the current tab.
            --- After clearing, automatic target resolution determines what to display.
            handler = function()
                require("clodex").clear_active_project()
            end,
        },
        {
            name = "ClodexQueueWorkspace",
            desc = "Open Clodex project queue workspace",
            --- Opens the queue workspace for project and queue item operations.
            --- It is the canonical UI for viewing and managing queued prompts.
            handler = function()
                require("clodex").open_queue_workspace()
            end,
        },
        {
            name = "ClodexProjectTodo",
            desc = "Open the current project's TODO.md",
            --- Opens or creates the active project's todo file in the current window.
            --- This gives each project a simple persistent scratchpad for queued work.
            handler = function()
                require("clodex").open_project_todo_file()
            end,
        },
        {
            name = "ClodexProjectDictionary",
            desc = "Open the current project's dictionary",
            --- Opens or creates the active project's shared glossary file.
            --- Use it for project-local terms that should stay easy to revisit.
            handler = function()
                require("clodex").open_project_dictionary_file()
            end,
        },
        {
            name = "ClodexProjectCheatsheet",
            desc = "Open the current project's cheatsheet",
            handler = function()
                require("clodex").open_project_cheatsheet_file()
            end,
        },
        {
            name = "ClodexProjectCheatsheetToggle",
            desc = "Toggle the current project's cheatsheet preview",
            handler = function()
                require("clodex").toggle_project_cheatsheet_preview()
            end,
        },
        {
            name = "ClodexProjectCheatsheetAdd",
            desc = "Add a one-line cheatsheet item",
            handler = function()
                require("clodex").add_project_cheatsheet_item()
            end,
        },
        {
            name = "ClodexProjectNotes",
            desc = "Open the current project's notes picker",
            handler = function()
                require("clodex").open_project_notes_picker()
            end,
        },
        {
            name = "ClodexProjectNoteAdd",
            desc = "Create a project note",
            handler = function()
                require("clodex").create_project_note()
            end,
        },
        {
            name = "ClodexProjectBookmarks",
            desc = "Open the current project's bookmarks picker",
            handler = function()
                require("clodex").open_project_bookmarks_picker()
            end,
        },
        {
            name = "ClodexProjectBookmarkAdd",
            desc = "Add a bookmark for the current line",
            handler = function()
                require("clodex").add_project_bookmark()
            end,
        },
        {
            name = "ClodexTodoAdd",
            desc = "Add a todo prompt to a project's planned queue",
            nargs = "?",
            --- Adds a todo prompt, optionally resolving target project from argument.
            --- Used as the default command for quick notes-to-queue workflows.
            handler = function(command)
                require("clodex").add_todo({
                    project_value = command.args ~= "" and command.args or nil,
                })
            end,
        },
        {
            name = "ClodexTodoError",
            desc = "Add an error-investigation todo prompt",
            nargs = "?",
            --- Adds an error classification prompt for debugging and fix tasks.
            --- Source details and screenshots can be added during the command flow.
            handler = function(command)
                require("clodex").add_error_todo({
                    project_value = command.args ~= "" and command.args or nil,
                })
            end,
        },
        {
            name = "ClodexTodoImplement",
            desc = "Implement the next queued prompt for a project",
            nargs = "?",
            --- Implements the next queued item for the selected project.
            --- This is the most common quick action after selecting a queue.
            handler = function(command)
                require("clodex").implement_next_queued_item({
                    project_value = command.args ~= "" and command.args or nil,
                })
            end,
        },
        {
            name = "ClodexTodoImplementAll",
            desc = "Implement all queued prompts for a project",
            nargs = "?",
            --- Implements all queued items in sequence for a project.
            --- Useful for batch processing while staying inside one project context.
            handler = function(command)
                require("clodex").implement_all_queued_items({
                    project_value = command.args ~= "" and command.args or nil,
                })
            end,
        },
        {
            name = "ClodexPromptAdd",
            desc = "Add a prompt to the current or detected project",
            --- Launches prompt creation for the current/default project.
            --- Useful when category is already selected later in the flow.
            handler = function()
                require("clodex").add_prompt()
            end,
        },
        {
            name = "ClodexPromptAddFor",
            desc = "Pick a project and prompt category to add",
            --- Opens a picker path requiring explicit project selection first.
            --- This is used when command origin should avoid implicit project inference.
            handler = function()
                require("clodex").add_prompt_for_project()
            end,
        },
        {
            name = "ClodexDebugReload",
            desc = "Reload clodex modules for debugging",
            --- Reloads plugin modules and re-runs setup for development workflows.
            --- Keeps command bindings and module cache aligned during iteration.
            handler = function()
                require("clodex").debug_reload()
            end,
        },
    }

    for _, category in ipairs(Category.list()) do
        local suffix = command_suffix[category.id]
        if suffix then
            specs[#specs + 1] = {
                name = "ClodexPrompt" .. suffix,
                desc = ("Add a %s prompt"):format(category.label:lower()),
                nargs = "?",
                --- Adds a category-specific prompt while allowing optional project override.
                --- Generated command names keep behavior discoverable by prompt type.
                handler = function(command)
                    require("clodex").add_prompt({
                        project_value = command.args ~= "" and command.args or nil,
                        category = category.id,
                    })
                end,
            }
            specs[#specs + 1] = {
                name = "ClodexPrompt" .. suffix .. "For",
                desc = ("Pick a project and add a %s prompt"):format(category.label:lower()),
                --- Opens the category-specific chooser and opens project selection first.
                --- Best used when command input should not infer project implicitly.
                handler = function()
                    require("clodex").add_prompt_for_project({
                        category = category.id,
                    })
                end,
            }
        end
    end

    return specs
end

---@param name string
---@return string?
local function compatibility_alias(name)
    if not vim.startswith(name, PRIMARY_COMMAND_PREFIX) then
        return nil
    end

    return COMPAT_COMMAND_PREFIX .. name:sub(#PRIMARY_COMMAND_PREFIX + 1)
end

---@return Clodex.CommandSpec[]
function M.list()
    return command_specs()
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

        local alias = compatibility_alias(spec.name)
        if alias then
            vim.api.nvim_create_user_command(alias, spec.handler, opts)
        end

        for _, typo_alias in ipairs(LEGACY_TYPO_ALIASES[spec.name] or {}) do
            vim.api.nvim_create_user_command(typo_alias, spec.handler, opts)
        end
    end
end

return M
