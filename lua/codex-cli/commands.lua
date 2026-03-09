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

---@class CodexCli.CommandSpec
---@field name string
---@field desc string
---@field nargs? string
---@field handler fun(command: vim.api.keyset.create_user_command.command_args)

---@return CodexCli.CommandSpec[]
local function command_specs()
  local specs = {
    {
      name = "CodexToggle",
      desc = "Toggle Codex terminal",
      handler = function()
        require("codex-cli").toggle()
      end,
    },
    {
      name = "CodexStateToggle",
      desc = "Toggle Codex state preview panel",
      handler = function()
        require("codex-cli").toggle_state_preview()
      end,
    },
    {
      name = "CodexProjectSelect",
      desc = "Select active Codex project",
      handler = function()
        require("codex-cli").select_project()
      end,
    },
    {
      name = "CodexProjectAdd",
      desc = "Add current directory as a Codex project",
      nargs = "?",
      handler = function(command)
        require("codex-cli").add_project({ name = command.args ~= "" and command.args or nil })
      end,
    },
    {
      name = "CodexProjectRename",
      desc = "Rename a Codex project",
      nargs = "?",
      handler = function(command)
        require("codex-cli").rename_project(command.args ~= "" and command.args or nil)
      end,
    },
    {
      name = "CodexProjectRemove",
      desc = "Remove a Codex project",
      nargs = "?",
      handler = function(command)
        require("codex-cli").remove_project(command.args ~= "" and command.args or nil)
      end,
    },
    {
      name = "CodexTerminalHeaderToggle",
      desc = "Toggle header line in the active Codex terminal buffer",
      handler = function()
        require("codex-cli").toggle_terminal_header()
      end,
    },
    {
      name = "CodexProjectClear",
      desc = "Clear the active Codex project for the current tab",
      handler = function()
        require("codex-cli").clear_active_project()
      end,
    },
    {
      name = "CodexQueueWorkspace",
      desc = "Open Codex project queue workspace",
      handler = function()
        require("codex-cli").open_queue_workspace()
      end,
    },
    {
      name = "CodexTodoAdd",
      desc = "Add a todo prompt to a project's planned queue",
      nargs = "?",
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
      handler = function(command)
        require("codex-cli").implement_all_queued_items({
          project_value = command.args ~= "" and command.args or nil,
        })
      end,
    },
    {
      name = "CodexPromptAdd",
      desc = "Add a prompt to the current or detected project",
      handler = function()
        require("codex-cli").add_prompt()
      end,
    },
    {
      name = "CodexPromptAddFor",
      desc = "Pick a project and prompt category to add",
      handler = function()
        require("codex-cli").add_prompt_for_project()
      end,
    },
    {
      name = "CodexDebugReload",
      desc = "Reload codex-cli modules for debugging",
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
