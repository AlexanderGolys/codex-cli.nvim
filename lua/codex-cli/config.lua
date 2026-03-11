local HighlightConfig = require("codex-cli.config.highlights")

--- Persistent plugin settings used to resolve workspace and project registry files.
---@class CodexCli.Config.Storage
---@field projects_file string
---@field workspaces_dir string

--- Terminal UI/runtime options for Codex subprocess windows.
---@class CodexCli.Config.Terminal
---@field win snacks.win.Config|{}
---@field start_insert boolean

--- Project autodetection behavior configured by the active buffer resolver.
---@class CodexCli.Config.ProjectDetection
---@field auto_suggest_git_root boolean

--- Floating preview window sizing and placement options.
---@class CodexCli.Config.StatePreview
---@field min_width integer
---@field max_width integer
---@field max_height integer # Non-positive values mean "use full available height".
---@field row integer
---@field col integer
---@field winblend integer

--- Queue workspace layout and presentation defaults for queue/project panes.
---@class CodexCli.Config.QueueWorkspace
---@field width number
---@field height number
---@field project_width number
---@field footer_height integer
---@field preview_max_lines integer
---@field fold_preview boolean

--- Error prompt behavior and optional screenshot directory hints.
---@class CodexCli.Config.ErrorPrompt
---@field screenshot_dir? string

--- Highlight group catalog consumed by setup when applying plugin colors.
---@class CodexCli.Config.Highlights
---@field groups table<string, CodexCli.Config.HighlightSpec>

--- Settings driving prompt dispatch and external completion polling.
---@class CodexCli.Config.PromptExecution
---@field receipts_dir string
---@field relative_dir? string # Legacy project-local receipt path retained only for migration/cleanup.
---@field poll_ms integer
---@field skills_dir? string
---@field skill_name string

--- Runtime-config data structure consumed across managers and UI modules.
---@class CodexCli.Config.Values
---@field codex_cmd string[]
---@field storage CodexCli.Config.Storage
---@field terminal CodexCli.Config.Terminal
---@field project_detection CodexCli.Config.ProjectDetection
---@field state_preview CodexCli.Config.StatePreview
---@field queue_workspace CodexCli.Config.QueueWorkspace
---@field error_prompt CodexCli.Config.ErrorPrompt
---@field highlights CodexCli.Config.Highlights
---@field prompt_execution CodexCli.Config.PromptExecution

--- Root config object exported by `require("codex-cli.config")`.
---@class CodexCli.Config
---@field values CodexCli.Config.Values
local Config = {}
Config.__index = Config

local defaults = {
  codex_cmd = { "codex" },
  storage = {
    projects_file = vim.fn.stdpath("data") .. "/codex-cli/projects.json",
    workspaces_dir = vim.fn.stdpath("data") .. "/codex-cli/workspaces",
  },
  terminal = {
    win = {
      position = "right",
      width = 0.45,
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
    width = 0.98,
    height = 0.98,
    project_width = 0.32,
    footer_height = 4,
    preview_max_lines = 5,
    fold_preview = true,
  },

  error_prompt = {
    screenshot_dir = nil,
  },

  highlights = vim.deepcopy(HighlightConfig),
  prompt_execution = {
    receipts_dir = vim.fn.stdpath("data") .. "/codex-cli/prompt-executions",
    relative_dir = ".codex-cli/prompt-executions",
    poll_ms = 5000,
    skills_dir = nil,
    skill_name = "prompt-nvim-codex-cli",
  },
}

--- Checks whether a value is a dictionary-like table for merge operations.
--- This helper distinguishes keyed tables from list-like tables before deep merge.
---@param value any
---@return boolean
local function is_dict_like(value)
  return type(value) == "table" and (vim.tbl_isempty(value) or not vim.islist(value))
end

--- Checks whether a value is a keyed table compatible with config overwrite paths.
--- It treats non-list tables and empty tables as dictionary-shaped data.
---@param value any
---@return boolean
local function is_dict(value)
  return type(value) == "table" and (vim.tbl_isempty(value) or not value[1])
end

--- Loads a named highlight safely from Neovim and returns an empty spec on failure.
---@param name string
---@return vim.api.keyset.highlight
local function get_hl(name)
  if type(name) ~= "string" or name == "" then
    return {}
  end

  local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = name, link = false })
  return ok and hl or {}
end

---@param value CodexCli.Config.HighlightColor?
---@param attr "fg"|"bg"|"sp"
---@return string|integer?
--- Resolves a highlight source into a concrete color based on fallback attributes.
---@param value CodexCli.Config.HighlightColor?
---@param attr "fg"|"bg"|"sp"
---@return string|integer?
local function resolve_color(value, attr)
  if type(value) == "string" or type(value) == "number" then
    return value
  end
  if type(value) ~= "table" then
    return nil
  end

  local source_attr = value.attr or attr
  local sources = type(value.from) == "table" and value.from or { value.from }
  for _, source in ipairs(sources) do
    local resolved = get_hl(source)[source_attr]
    if resolved ~= nil then
      return resolved
    end
  end
end

---@param spec CodexCli.Config.HighlightSpec
---@return vim.api.keyset.highlight
--- Normalizes one configured highlight description into `vim.api.nvim_set_hl` shape.
---@param spec CodexCli.Config.HighlightSpec
---@return vim.api.keyset.highlight
local function resolve_highlight_spec(spec)
  local resolved = {} ---@type vim.api.keyset.highlight
  if type(spec) ~= "table" then
    return resolved
  end

  if spec.link then
    resolved.link = spec.link
  end

  resolved.fg = resolve_color(spec.fg, "fg")
  resolved.bg = resolve_color(spec.bg, "bg")
  resolved.sp = resolve_color(spec.sp, "sp")

  for _, key in ipairs({
    "blend",
    "bold",
    "italic",
    "underline",
    "undercurl",
    "reverse",
    "strikethrough",
    "default",
    "force",
    "ctermfg",
    "ctermbg",
    "cterm",
  }) do
    if spec[key] ~= nil then
      resolved[key] = spec[key]
    end
  end

  return resolved
end

---@generic T
---@param ... T
---@return T
--- Merges nested dictionaries and scalar values while preserving explicit overrides.
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
---@return CodexCli.Config
function Config.new()
  local self = setmetatable({}, Config)
  self.values = vim.deepcopy(defaults)
  return self
end

---@param opts? CodexCli.Config.Values|{}
---@return CodexCli.Config.Values
--- Applies setup values, maps legacy highlight keys, and caches active values.
---@param opts? CodexCli.Config.Values|{}
---@return CodexCli.Config.Values
function Config:setup(opts)
  self.values = Config.merge(vim.deepcopy(defaults), opts or {})
  return self.values
end

---@param values CodexCli.Config.Values
--- Writes configured highlight groups to Neovim whenever setup is called or reloaded.
---@param values CodexCli.Config.Values
function Config.apply_highlights(values)
  local groups = values and values.highlights and values.highlights.groups or nil
  if type(groups) ~= "table" then
    return
  end

  for name, spec in pairs(groups) do
    vim.api.nvim_set_hl(0, name, resolve_highlight_spec(spec))
  end
end

---@return CodexCli.Config.Values
--- Returns the currently active merged config values.
---@return CodexCli.Config.Values
function Config:get()
  return self.values
end

return Config
