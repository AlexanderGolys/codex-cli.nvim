local M = {}

local did_register = false

function M.register()
  if did_register then
    return
  end
  did_register = true

  vim.api.nvim_create_user_command("CodexToggle", function()
    require("codex-cli").toggle()
  end, { desc = "Toggle Codex terminal" })

  vim.api.nvim_create_user_command("CodexStateToggle", function()
    require("codex-cli").toggle_state_preview()
  end, { desc = "Toggle Codex state preview panel" })

  vim.api.nvim_create_user_command("CodexProjectSelect", function()
    require("codex-cli").select_project()
  end, { desc = "Select active Codex project" })

  vim.api.nvim_create_user_command("CodexProjectAdd", function(command)
    require("codex-cli").add_project({ name = command.args ~= "" and command.args or nil })
  end, {
    desc = "Add current directory as a Codex project",
    nargs = "?",
  })

  vim.api.nvim_create_user_command("CodexProjectRename", function(command)
    require("codex-cli").rename_project(command.args ~= "" and command.args or nil)
  end, {
    desc = "Rename a Codex project",
    nargs = "?",
  })

  vim.api.nvim_create_user_command("CodexProjectRemove", function(command)
    require("codex-cli").remove_project(command.args ~= "" and command.args or nil)
  end, {
    desc = "Remove a Codex project",
    nargs = "?",
  })

  vim.api.nvim_create_user_command("CodexTerminalHeaderToggle", function()
    require("codex-cli").toggle_terminal_header()
  end, { desc = "Toggle header line in the active Codex terminal buffer" })

  vim.api.nvim_create_user_command("CodexProjectClear", function()
    require("codex-cli").clear_active_project()
  end, { desc = "Clear the active Codex project for the current tab" })

  vim.api.nvim_create_user_command("CodexQueueWorkspace", function()
    require("codex-cli").open_queue_workspace()
  end, { desc = "Open Codex project queue workspace" })

  vim.api.nvim_create_user_command("CodexTodoAdd", function(command)
    require("codex-cli").add_todo({
      project_value = command.args ~= "" and command.args or nil,
    })
  end, {
    desc = "Add a todo prompt to a project's planned queue",
    nargs = "?",
  })

  vim.api.nvim_create_user_command("CodexTodoError", function(command)
    require("codex-cli").add_error_todo({
      project_value = command.args ~= "" and command.args or nil,
    })
  end, {
    desc = "Add an error-investigation todo prompt",
    nargs = "?",
  })
end

return M
