--- Defines the codex-cli type for this module.
--- This annotation documents structured state so modules can pass data with consistent expectations.
---@class codex-cli
local M = {}
M.lualine = require("codex-cli.lualine")

local function app()
  return require("codex-cli.app").instance()
end

local function call(method)
  return function(...)
    local instance = app()
    return instance[method](instance, ...)
  end
end

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

---@param opts? CodexCli.Config.Values|{}
function M.setup(opts)
  app():setup(opts)
end

function M.register()
  require("codex-cli.commands").register()
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
M.add_todo = call("add_todo")
M.implement_next_queued_item = call("implement_next_queued_item")
M.implement_all_queued_items = call("implement_all_queued_items")
M.add_prompt = call("add_prompt")
M.add_prompt_for_project = call("add_prompt_for_project")
M.add_error_todo = call("add_error_todo")

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
