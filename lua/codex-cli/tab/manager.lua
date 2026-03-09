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

return Manager
