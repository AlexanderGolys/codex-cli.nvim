---@class CodexCli.Config.Storage
---@field projects_file string
---@field workspaces_dir string

---@class CodexCli.Config.Terminal
---@field win snacks.win.Config|{}
---@field start_insert boolean

---@class CodexCli.Config.ProjectDetection
---@field auto_suggest_git_root boolean

---@class CodexCli.Config.StatePreview
---@field min_width integer
---@field max_width integer
---@field max_height integer # Non-positive values mean "use full available height".
---@field row integer
---@field col integer
---@field winblend integer

---@class CodexCli.Config.QueueWorkspace
---@field width number
---@field height number
---@field project_width number
---@field footer_height integer

---@class CodexCli.Config.ErrorPrompt
---@field screenshot_dir? string

---@class CodexCli.Config.Values
---@field codex_cmd string[]
---@field storage CodexCli.Config.Storage
---@field terminal CodexCli.Config.Terminal
---@field project_detection CodexCli.Config.ProjectDetection
---@field state_preview CodexCli.Config.StatePreview
---@field queue_workspace CodexCli.Config.QueueWorkspace
---@field error_prompt CodexCli.Config.ErrorPrompt

---@class CodexCli.Config
---@field values CodexCli.Config.Values
local Config = {}
Config.__index = Config

local defaults = {
  codex_cmd = { "bash", "-lc", "codex" },
  storage = {
    projects_file = vim.fn.stdpath("data") .. "/codex-cli/projects.json",
    workspaces_dir = vim.fn.stdpath("data") .. "/codex-cli/workspaces",
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
  state_preview = {
    min_width = 36,
    max_width = 72,
    max_height = 0,
    row = 1,
    col = 2,
    winblend = 18,
  },
  queue_workspace = {
    width = 0.8,
    height = 0.7,
    project_width = 0.34,
    footer_height = 3,
  },
  error_prompt = {
    screenshot_dir = nil,
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
