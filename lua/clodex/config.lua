local HighlightConfig = require("clodex.config.highlights")
local fs = require("clodex.util.fs")

--- Persistent plugin settings used to resolve workspace and project registry files.
---@class Clodex.Config.Storage
---@field projects_file string
---@field workspaces_dir string
---@field session_state_dir string
---@field history_file string

--- Terminal UI/runtime options for Codex subprocess windows.
---@class Clodex.Config.Terminal
---@field win snacks.win.Config|{}
---@field start_insert boolean
---@field prefer_native_statusline boolean

--- Project autodetection behavior configured by the active buffer resolver.
---@class Clodex.Config.ProjectDetection
---@field auto_suggest_git_root boolean

--- Floating preview window sizing and placement options.
---@class Clodex.Config.StatePreview
---@field min_width integer
---@field max_width integer
---@field max_height integer # Non-positive values mean "use full available height".
---@field row integer
---@field col integer
---@field winblend integer

--- Queue workspace layout and presentation defaults for queue/project panes.
---@class Clodex.Config.QueueWorkspace
---@field width number
---@field height number
---@field project_width number
---@field footer_height integer
---@field preview_max_lines integer
---@field fold_preview boolean
---@field date_format string

--- Error prompt behavior and optional screenshot directory hints.
---@class Clodex.Config.ErrorPrompt
---@field screenshot_dir? string

--- Highlight group catalog consumed by setup when applying plugin colors.
---@class Clodex.Config.Highlights
---@field groups table<string, Clodex.Config.HighlightSpec>

--- Settings driving prompt dispatch and external workspace-sync polling.
---@class Clodex.Config.PromptExecution
---@field receipts_dir string # Backward-compatible base directory for project-local execution artifacts.
---@field relative_dir? string # Legacy field retained only for config compatibility.
---@field poll_ms integer
---@field skills_dir? string # Project-local path under each project root; empty string disables generated skill mode.
---@field skill_name string

--- Session integration toggles for tab-scoped Clodex state.
---@class Clodex.Config.Session
---@field persist_current_project boolean

--- Manual project-history tracking for direct CLI conversations outside queued prompts.
---@class Clodex.Config.ManualHistory
---@field model_instructions_file string # Project-local file passed to Codex via `model_instructions_file`; empty disables generation.

--- Runtime-config data structure consumed across managers and UI modules.
---@class Clodex.Config.Values
---@field codex_cmd string[]
---@field storage Clodex.Config.Storage
---@field terminal Clodex.Config.Terminal
---@field project_detection Clodex.Config.ProjectDetection
---@field state_preview Clodex.Config.StatePreview
---@field queue_workspace Clodex.Config.QueueWorkspace
---@field error_prompt Clodex.Config.ErrorPrompt
---@field highlights Clodex.Config.Highlights
---@field prompt_execution Clodex.Config.PromptExecution
---@field session Clodex.Config.Session
---@field manual_history Clodex.Config.ManualHistory

--- Root config object exported by `require("clodex.config")`.
---@class Clodex.Config
---@field values Clodex.Config.Values
local Config = {}
Config.__index = Config

local function default_storage_root()
    return fs.join(vim.fn.stdpath("data"), "clodex")
end

local function defaults()
    local storage_root = default_storage_root()
    return {
        codex_cmd = { "codex" },
        storage = {
            projects_file = fs.join(storage_root, "projects.json"),
            workspaces_dir = fs.join(".clodex", "workspaces"),
            session_state_dir = fs.join(storage_root, "session-state"),
            history_file = fs.join(storage_root, "history.md"),
        },
        terminal = {
            win = {
                position = "right",
                width = 0.4,
            },
            start_insert = true,
            prefer_native_statusline = true,
        },
        project_detection = {
            auto_suggest_git_root = false,
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
            width = 1,
            height = 1,
            project_width = 0.3,
            footer_height = 3,
            preview_max_lines = 5,
            fold_preview = true,
            date_format = "%H:%M %d.%m.%Y",
        },

        error_prompt = {
            screenshot_dir = nil,
        },

        highlights = vim.deepcopy(HighlightConfig),
        prompt_execution = {
            receipts_dir = fs.join(".clodex", "prompt-executions"),
            relative_dir = "",
            poll_ms = 5000,
            skills_dir = fs.join(".codex", "skills"),
            skill_name = "prompt-nvim-clodex",
        },
        session = {
            persist_current_project = true,
        },
        manual_history = {
            model_instructions_file = "",
        },
    }
end

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


--- Resolves a highlight source into a concrete color based on fallback attributes.
---@param value Clodex.Config.HighlightColor?
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


--- Normalizes one configured highlight description into `vim.api.nvim_set_hl` shape.
---@param spec Clodex.Config.HighlightSpec
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

---@return Clodex.Config
function Config.new()
    local self = setmetatable({}, Config)
    self.values = defaults()
    return self
end

--- Applies setup values, maps legacy highlight keys, and caches active values.
---@param opts? Clodex.Config.Values|{}
---@return Clodex.Config.Values
function Config:setup(opts)
    self.values = Config.merge(defaults(), opts or {})
    return self.values
end

--- Writes configured highlight groups to Neovim whenever setup is called or reloaded.
---@param values Clodex.Config.Values
function Config.apply_highlights(values)
    local groups = values and values.highlights and values.highlights.groups or nil
    if type(groups) ~= "table" then
        return
    end

    for name, spec in pairs(groups) do
        vim.api.nvim_set_hl(0, name, resolve_highlight_spec(spec))
    end
end

--- Returns the currently active merged config values.
---@return Clodex.Config.Values
function Config:get()
    return self.values
end

return Config
