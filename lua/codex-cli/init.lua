---@class codex-cli
local M = {}
M.lualine = require("codex-cli.lualine")

local function app()
  return require("codex-cli.app").instance()
end

---@param opts? CodexCli.Config.Values|{}
function M.setup(opts)
  app():setup(opts)
end

function M.register()
  require("codex-cli.commands").register()
end

function M.toggle()
  app():toggle()
end

function M.toggle_state_preview()
  app():toggle_state_preview()
end

function M.open_terminal()
  app():toggle()
end

function M.select_project()
  app():select_project()
end

---@param opts? { name?: string, root?: string }
function M.add_project(opts)
  app():add_project(opts)
end

---@param name? string
function M.rename_project(name)
  app():rename_project(name)
end

---@param value? string
function M.remove_project(value)
  app():remove_project(value)
end

function M.toggle_terminal_header()
  app():toggle_terminal_header()
end

function M.clear_active_project()
  app():clear_active_project()
end

function M.open_queue_workspace()
  app():open_queue_workspace()
end

---@param opts? { project_value?: string }
function M.add_todo(opts)
  app():add_todo(opts)
end

---@param opts? { project_value?: string }
function M.add_error_todo(opts)
  app():add_error_todo(opts)
end

return M
