---@class CodexCli.Config.Storage
---@field projects_file string

---@class CodexCli.Config.Terminal
---@field win snacks.win.Config|{}
---@field start_insert boolean

---@class CodexCli.Config.ProjectDetection
---@field auto_suggest_git_root boolean

---@class CodexCli.Config.Values
---@field codex_cmd string[]
---@field storage CodexCli.Config.Storage
---@field terminal CodexCli.Config.Terminal
---@field project_detection CodexCli.Config.ProjectDetection

---@class CodexCli.Config
---@field values CodexCli.Config.Values
local Config = {}
Config.__index = Config

local defaults = {
  codex_cmd = { "bash", "-lc", "codex" },
  storage = {
    projects_file = vim.fn.stdpath("data") .. "/codex-cli/projects.json",
  },
  terminal = {
    win = {
      position = "right",
      width = 0.35,
    },
    start_insert = true,
  },
  project_detection = {
    auto_suggest_git_root = true,
  },
}

local function is_dict_like(value)
  return type(value) == "table" and (vim.tbl_isempty(value) or not vim.islist(value))
end

local function is_dict(value)
  return type(value) == "table" and (vim.tbl_isempty(value) or not value[1])
end

---@generic T
---@param ... T
---@return T
function Config.merge(...)
  local ret = select(1, ...)
  for index = 2, select("#", ...) do
    local value = select(index, ...)
    if is_dict_like(ret) and is_dict(value) then
      for key, nested in pairs(value) do
        ret[key] = Config.merge(ret[key], nested)
      end
    elseif value ~= nil then
      ret = value
    end
  end
  return ret
end

---@return CodexCli.Config
function Config.new()
  local self = setmetatable({}, Config)
  self.values = vim.deepcopy(defaults)
  return self
end

---@param opts? CodexCli.Config.Values|{}
---@return CodexCli.Config.Values
function Config:setup(opts)
  self.values = Config.merge(vim.deepcopy(defaults), opts or {})
  return self.values
end

---@return CodexCli.Config.Values
function Config:get()
  return self.values
end

return Config
