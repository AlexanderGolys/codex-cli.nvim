---@class CodexCli.TabState
---@field tabpage number
---@field active_project_root? string
---@field prompted_project? boolean
---@field window? snacks.win
---@field session_key? string

---@class CodexCli.TabState.Snapshot
---@field tabpage number
---@field active_project_root? string
---@field has_visible_window boolean
---@field session_key? string
---@field window_id? integer
local State = {}
State.__index = State

---@param tabpage number
---@return CodexCli.TabState
function State.new(tabpage)
  local self = setmetatable({}, State)
  self.tabpage = tabpage
  self.prompted_project = false
  return self
end

---@return boolean
function State:is_valid()
  return vim.api.nvim_tabpage_is_valid(self.tabpage)
end

---@return boolean
function State:has_visible_window()
  return self.window ~= nil
    and self.window:win_valid()
    and vim.api.nvim_win_get_tabpage(self.window.win) == self.tabpage
end

---@param root? string
function State:set_active_project(root)
  self.active_project_root = root
end

function State:clear_active_project()
  self.active_project_root = nil
end

---@return boolean
function State:has_prompted_project()
  return self.prompted_project == true
end

function State:mark_prompted_project()
  self.prompted_project = true
end

---@param window? snacks.win
---@param session_key? string
function State:set_window(window, session_key)
  self.window = window
  self.session_key = session_key
end

function State:clear_window()
  self.window = nil
  self.session_key = nil
end

function State:hide_window()
  if self:has_visible_window() then
    self.window:hide()
  end
  self:clear_window()
end

---@param session_key string
---@return boolean
function State:is_showing(session_key)
  return self:has_visible_window() and self.session_key == session_key
end

---@return CodexCli.TabState.Snapshot
function State:snapshot()
  return {
    tabpage = self.tabpage,
    active_project_root = self.active_project_root,
    has_visible_window = self:has_visible_window(),
    session_key = self.session_key,
    window_id = self:has_visible_window() and self.window.win or nil,
  }
end

return State
