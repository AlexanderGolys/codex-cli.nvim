--- Defines the codex-cli type for this module.
--- This annotation documents structured state so modules can pass data with consistent expectations.
---@class codex-cli
local M = {}
M.lualine = require("codex-cli.lualine")

--- Implements the app path for init.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
local function app()
  return require("codex-cli.app").instance()
end

--- Implements the current_config path for init.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
local function current_config()
  local ok, app_module = pcall(require, "codex-cli.app")
  if not ok or type(app_module.instance) ~= "function" then
    return {}
  end

  local ok_app, instance = pcall(app_module.instance)
  if not ok_app or not instance or not instance.config then
    return {}
  end

  return vim.deepcopy(instance.config:get() or {})
end

--- Implements the setup path for init.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param opts? CodexCli.Config.Values|{}
function M.setup(opts)
  app():setup(opts)
end

--- Implements the register path for init.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
function M.register()
  require("codex-cli.commands").register()
end

--- Toggles the init state for the active context.
--- It is typically invoked from user commands and keeps preview/session state in sync.
function M.toggle()
  app():toggle()
end

--- Implements the toggle_state_preview path for init.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
function M.toggle_state_preview()
  app():toggle_state_preview()
end

--- Implements the open_terminal path for init.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
function M.open_terminal()
  app():toggle()
end

--- Adds a new init entry and keeps related state aligned.
--- This function feeds the same workflow used by interactive and scripted callers.
---@param opts? { name?: string, root?: string }
function M.add_project(opts)
  app():add_project(opts)
end

--- Implements the rename_project path for init.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param name? string
function M.rename_project(name)
  app():rename_project(name)
end

--- Removes a init item and normalizes dependent state.
--- This cleanup keeps persistence and session state consistent with user actions.
---@param value? string
function M.remove_project(value)
  app():remove_project(value)
end

--- Implements the toggle_terminal_header path for init.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
function M.toggle_terminal_header()
  app():toggle_terminal_header()
end

--- Implements the clear_active_project path for init.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
function M.clear_active_project()
  app():clear_active_project()
end

--- Implements the open_queue_workspace path for init.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
function M.open_queue_workspace()
  app():open_queue_workspace()
end

--- Opens the active project's `TODO.md` in the current window.
--- The file is created automatically when it does not already exist.
function M.open_project_todo_file()
  app():open_project_todo_file()
end

--- Adds a new init entry and keeps related state aligned.
--- This function feeds the same workflow used by interactive and scripted callers.
---@param opts? { project_value?: string }
function M.add_todo(opts)
  app():add_todo(opts)
end

--- Implements the implement_next_queued_item path for init.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param opts? { project_value?: string }
function M.implement_next_queued_item(opts)
  app():implement_next_queued_item(opts)
end

--- Implements the implement_all_queued_items path for init.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param opts? { project_value?: string }
function M.implement_all_queued_items(opts)
  app():implement_all_queued_items(opts)
end

--- Adds a new init entry and keeps related state aligned.
--- This function feeds the same workflow used by interactive and scripted callers.
---@param opts? { project_value?: string, category?: CodexCli.PromptCategory }
function M.add_prompt(opts)
  app():add_prompt(opts)
end

--- Adds a new init entry and keeps related state aligned.
--- This function feeds the same workflow used by interactive and scripted callers.
---@param opts? { project_value?: string, category?: CodexCli.PromptCategory }
function M.add_prompt_for_project(opts)
  app():add_prompt_for_project(opts)
end

--- Adds a new init entry and keeps related state aligned.
--- This function feeds the same workflow used by interactive and scripted callers.
---@param opts? { project_value?: string }
function M.add_error_todo(opts)
  app():add_error_todo(opts)
end

--- Implements the debug_reload path for init.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
function M.debug_reload()
  local opts = current_config()

  for key in pairs(package.loaded) do
    if key:match("^codex%-cli") then
      package.loaded[key] = nil
    end
  end

  require("codex-cli").setup(opts)
  vim.notify("codex-cli reloaded", vim.log.levels.INFO)
end

return M
