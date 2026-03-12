local App = require("clodex.app")

--- Defines the Clodex.Lualine.Opts type for this module.
--- This annotation documents structured state so modules can pass data with consistent expectations.
---@class Clodex.Lualine.Opts
---@field tabpage? number
---@field include_detected? boolean
---@field empty_text? string
---@field prefix? string

local M = {}

---@param tabpage? number
---@return number?
local function tabpage_buf(tabpage)
  if not tabpage then
    return vim.api.nvim_get_current_buf()
  end
  if not vim.api.nvim_tabpage_is_valid(tabpage) then
    return
  end
  local win = vim.api.nvim_tabpage_get_win(tabpage)
  if not win or not vim.api.nvim_win_is_valid(win) then
    return
  end
  return vim.api.nvim_win_get_buf(win)
end

---@param opts? Clodex.Lualine.Opts
---@return Clodex.Project?
function M.project(opts)
  opts = opts or {}
  local app = App.instance()
  local state = app.tabs:get(opts.tabpage)
  local project = state.active_project_root and app.registry:get(state.active_project_root) or nil
  if project then
    return project
  end

  if opts.include_detected then
    local path = app.detector:current_path(tabpage_buf(opts.tabpage))
    return app.detector:project_for_path(path)
  end
end

---@param opts? Clodex.Lualine.Opts
---@return string
function M.project_name(opts)
  opts = opts or {}
  local project = M.project(opts)
  if not project then
    return opts.empty_text or ""
  end

  if opts.prefix and opts.prefix ~= "" then
    return opts.prefix .. project.name
  end
  return project.name
end

return M
