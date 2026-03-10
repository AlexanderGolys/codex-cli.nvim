local State = require("codex-cli.tab.state")

--- Defines the CodexCli.TabManager type for this module.
--- This annotation documents structured state so modules can pass data with consistent expectations.
---@class CodexCli.TabManager
---@field states table<number, CodexCli.TabState>
local Manager = {}
Manager.__index = Manager

--- Creates a new tab manager instance from this module.
--- It is used by callers to bootstrap module state before running higher-level plugin actions.
---@return CodexCli.TabManager
function Manager.new()
  local self = setmetatable({}, Manager)
  self.states = {}
  return self
end

--- Removes stale entries for tabs that no longer exist.
--- Called before most operations to keep in-memory state compact and current.
function Manager:cleanup()
  for tabpage, state in pairs(self.states) do
    if not state:is_valid() then
      self.states[tabpage] = nil
    end
  end
end

--- Implements the get path for tab manager.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param tabpage? number
---@return CodexCli.TabState
function Manager:get(tabpage)
  self:cleanup()
  tabpage = tabpage or vim.api.nvim_get_current_tabpage()
  self.states[tabpage] = self.states[tabpage] or State.new(tabpage)
  return self.states[tabpage]
end

--- Implements the list path for tab manager.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@return CodexCli.TabState[]
function Manager:list()
  self:cleanup()
  local ret = {} ---@type CodexCli.TabState[]
  for _, state in pairs(self.states) do
    ret[#ret + 1] = state
  end
  return ret
end

--- Implements the clear_project path for tab manager.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param root string
function Manager:clear_project(root)
  for _, state in ipairs(self:list()) do
    if state.active_project_root == root then
      state:clear_active_project()
    end
  end
end

--- Implements the snapshot path for tab manager.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@return CodexCli.TabState.Snapshot[]
function Manager:snapshot()
  local states = self:list()
  table.sort(states, function(left, right)
    return left.tabpage < right.tabpage
  end)

  local ret = {} ---@type CodexCli.TabState.Snapshot[]
  for _, state in ipairs(states) do
    ret[#ret + 1] = state:snapshot()
  end
  return ret
end

--- Persists or restores tab manager data for this workflow.
--- It is used by session restoration and command surfaces so behavior remains repeatable.
---@param snapshots { active_project_root?: string, prompted_project?: boolean, session_key?: string, has_visible_window?: boolean }[]
function Manager:restore(snapshots)
  self:cleanup()
  snapshots = snapshots or {}

  local tabpages = vim.api.nvim_list_tabpages()
  table.sort(tabpages, function(left, right)
    return left < right
  end)

  for index, tabpage in ipairs(tabpages) do
    local snapshot = snapshots[index] or {}
    self:get(tabpage):restore(snapshot)
  end
end

return Manager
