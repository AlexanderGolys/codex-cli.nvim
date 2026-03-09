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

  vim.api.nvim_create_user_command("CodexProjectSelect", function()
    require("codex-cli").select_project()
  end, { desc = "Select active Codex project" })

  vim.api.nvim_create_user_command("CodexProjectAdd", function(command)
    require("codex-cli").add_project({ name = command.args ~= "" and command.args or nil })
  end, {
    desc = "Add current directory as a Codex project",
    nargs = "?",
  })

  vim.api.nvim_create_user_command("CodexProjectRemove", function(command)
    require("codex-cli").remove_project(command.args ~= "" and command.args or nil)
  end, {
    desc = "Remove a Codex project",
    nargs = "?",
  })

  vim.api.nvim_create_user_command("CodexProjectClear", function()
    require("codex-cli").clear_active_project()
  end, { desc = "Clear the active Codex project for the current tab" })
end

return M
