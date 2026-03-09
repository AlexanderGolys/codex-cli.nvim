local State = require("codex-cli.tab.state")

---@class CodexCli.TabManager
---@field states table<number, CodexCli.TabState>
local Manager = {}
Manager.__index = Manager

---@return CodexCli.TabManager
function Manager.new()
  local self = setmetatable({}, Manager)
  self.states = {}
  return self
end

function Manager:cleanup()
  for tabpage, state in pairs(self.states) do
    if not state:is_valid() then
      self.states[tabpage] = nil
    end
  end
end

---@param tabpage? number
---@return CodexCli.TabState
function Manager:get(tabpage)
  self:cleanup()
  tabpage = tabpage or vim.api.nvim_get_current_tabpage()
  self.states[tabpage] = self.states[tabpage] or State.new(tabpage)
  return self.states[tabpage]
end

---@return CodexCli.TabState[]
function Manager:list()
  self:cleanup()
  local ret = {} ---@type CodexCli.TabState[]
  for _, state in pairs(self.states) do
    ret[#ret + 1] = state
  end
  return ret
end

---@param root string
function Manager:clear_project(root)
  for _, state in ipairs(self:list()) do
    if state.active_project_root == root then
      state:clear_active_project()
    end
  end
end

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

---@param snapshots { active_project_root?: string, prompted_project?: boolean }[]
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
