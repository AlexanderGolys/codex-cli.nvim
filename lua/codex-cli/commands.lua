local M = {}

local did_register = false
local Category = require("codex-cli.prompt.category")

local command_suffix = {
  todo = "Todo",
  error = "Error",
  visual = "Visual",
  adjustment = "Adjustment",
  refactor = "Refactor",
  idea = "Idea",
  explain = "Explain",
}

--- Describes a Neovim `:Codex*` command and its execution callback.
--- This shape is shared by both static and generated category-specific command registrations.
---@class CodexCli.CommandSpec
---@field name string
---@field desc string
---@field nargs? string
---@field handler fun(command: vim.api.keyset.create_user_command.command_args)

---@return CodexCli.CommandSpec[]
--- Builds the complete command list and injects category-specific variants.
--- Keeping this in one place guarantees consistent naming, docs, and handlers.
local function command_specs()
  local specs = {
    {
      name = "CodexToggle",
      desc = "Toggle Codex terminal",
      --- Toggles the currently tracked terminal target for the active tab.
      --- This is the primary entry point from user command to terminal visibility.
      handler = function()
        require("codex-cli").toggle()
      end,
    },
    {
      name = "CodexStateToggle",
      desc = "Toggle Codex state preview panel",
      --- Shows or hides the command/state floating preview panels.
      --- Useful for quickly checking active queues and project state.
      handler = function()
        require("codex-cli").toggle_state_preview()
      end,
    },
    {
      name = "CodexProjectAdd",
      desc = "Add current directory as a Codex project",
      nargs = "?",
      --- Registers a project from current path or provided root/name.
      --- If omitted, existing detection paths are used to infer a good default.
      handler = function(command)
        require("codex-cli").add_project({ name = command.args ~= "" and command.args or nil })
      end,
    },
    {
      name = "CodexProjectRename",
      desc = "Rename a Codex project",
      nargs = "?",
      --- Renames a project using the selected project or supplied identifier.
      --- Validation and registry persistence are delegated to the app layer.
      handler = function(command)
        require("codex-cli").rename_project(command.args ~= "" and command.args or nil)
      end,
    },
    {
      name = "CodexProjectRemove",
      desc = "Remove a Codex project",
      nargs = "?",
      --- Removes a project from registry and clears its sessions/queue data.
      --- If no target is supplied, picker-driven removal is used.
      handler = function(command)
        require("codex-cli").remove_project(command.args ~= "" and command.args or nil)
      end,
    },
    {
      name = "CodexTerminalHeaderToggle",
      desc = "Toggle header line in the active Codex terminal buffer",
      --- Toggles terminal header rendering for the active Codex buffer.
      --- Header visibility is stored per session and updated immediately.
      handler = function()
        require("codex-cli").toggle_terminal_header()
      end,
    },
    {
      name = "CodexProjectClear",
      desc = "Clear the active Codex project for the current tab",
      --- Clears any pinned active project for the current tab.
      --- After clearing, automatic target resolution determines what to display.
      handler = function()
        require("codex-cli").clear_active_project()
      end,
    },
    {
      name = "CodexQueueWorkspace",
      desc = "Open Codex project queue workspace",
      --- Opens the queue workspace for project and queue item operations.
      --- It is the canonical UI for viewing and managing queued prompts.
      handler = function()
        require("codex-cli").open_queue_workspace()
      end,
    },
    {
      name = "CodexProjectTodo",
      desc = "Open the current project's TODO.md",
      --- Opens or creates the active project's todo file in the current window.
      --- This gives each project a simple persistent scratchpad for queued work.
      handler = function()
        require("codex-cli").open_project_todo_file()
      end,
    },
    {
      name = "CodexTodoAdd",
      desc = "Add a todo prompt to a project's planned queue",
      nargs = "?",
      --- Adds a todo prompt, optionally resolving target project from argument.
      --- Used as the default command for quick notes-to-queue workflows.
      handler = function(command)
        require("codex-cli").add_todo({
          project_value = command.args ~= "" and command.args or nil,
        })
      end,
    },
    {
      name = "CodexTodoError",
      desc = "Add an error-investigation todo prompt",
      nargs = "?",
      --- Adds an error classification prompt for debugging and fix tasks.
      --- Source details and screenshots can be added during the command flow.
      handler = function(command)
        require("codex-cli").add_error_todo({
          project_value = command.args ~= "" and command.args or nil,
        })
      end,
    },
    {
      name = "CodexTodoImplement",
      desc = "Implement the next queued prompt for a project",
      nargs = "?",
      --- Implements the next queued item for the selected project.
      --- This is the most common quick action after selecting a queue.
      handler = function(command)
        require("codex-cli").implement_next_queued_item({
          project_value = command.args ~= "" and command.args or nil,
        })
      end,
    },
    {
      name = "CodexTodoImplementAll",
      desc = "Implement all queued prompts for a project",
      nargs = "?",
      --- Implements all queued items in sequence for a project.
      --- Useful for batch processing while staying inside one project context.
      handler = function(command)
        require("codex-cli").implement_all_queued_items({
          project_value = command.args ~= "" and command.args or nil,
        })
      end,
    },
    {
      name = "CodexPromptAdd",
      desc = "Add a prompt to the current or detected project",
      --- Launches prompt creation for the current/default project.
      --- Useful when category is already selected later in the flow.
      handler = function()
        require("codex-cli").add_prompt()
      end,
    },
    {
      name = "CodexPromptAddFor",
      desc = "Pick a project and prompt category to add",
      --- Opens a picker path requiring explicit project selection first.
      --- This is used when command origin should avoid implicit project inference.
      handler = function()
        require("codex-cli").add_prompt_for_project()
      end,
    },
    {
      name = "CodexDebugReload",
      desc = "Reload codex-cli modules for debugging",
      --- Reloads plugin modules and re-runs setup for development workflows.
      --- Keeps command bindings and module cache aligned during iteration.
      handler = function()
        require("codex-cli").debug_reload()
      end,
    },
  }

  for _, category in ipairs(Category.list()) do
    local suffix = command_suffix[category.id]
        if suffix then
          specs[#specs + 1] = {
            name = "CodexPrompt" .. suffix,
            desc = ("Add a %s prompt"):format(category.label:lower()),
            nargs = "?",
            --- Adds a category-specific prompt while allowing optional project override.
            --- Generated command names keep behavior discoverable by prompt type.
            handler = function(command)
              require("codex-cli").add_prompt({
                project_value = command.args ~= "" and command.args or nil,
            category = category.id,
          })
        end,
      }
          specs[#specs + 1] = {
            name = "CodexPrompt" .. suffix .. "For",
            desc = ("Pick a project and add a %s prompt"):format(category.label:lower()),
            --- Opens the category-specific chooser and opens project selection first.
            --- Best used when command input should not infer project implicitly.
            handler = function()
              require("codex-cli").add_prompt_for_project({
                category = category.id,
          })
        end,
      }
    end
  end

  return specs
end

---@return CodexCli.CommandSpec[]
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
  end
end

return M
