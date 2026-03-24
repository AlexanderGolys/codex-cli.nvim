local HighlightConfig = require("clodex.config.highlights")
local Backend = require("clodex.backend")
local fs = require("clodex.util.fs")

--- Persistent plugin settings used to resolve workspace and project registry files.
---@class Clodex.Config.Storage
---@field projects_file string
---@field workspaces_dir string
---@field session_state_dir string
---@field history_file string

--- Terminal UI/runtime options for interactive backend subprocess windows.
---@class Clodex.Config.BlockedInput
---@field enabled boolean
---@field poll_ms integer
---@field win snacks.win.Config|{}

---@class Clodex.Config.Terminal
---@field provider "snacks"|"term"
---@field win snacks.win.Config|{}
---@field start_insert boolean
---@field prefer_native_statusline boolean
---@field blocked_input Clodex.Config.BlockedInput

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
---@field mini { width: integer, height: integer, col: integer, winblend: integer }

--- Queue workspace layout and presentation defaults for queue/project panes.
---@class Clodex.Config.QueueWorkspace
---@field width number
---@field height number
---@field project_width number
---@field footer_height integer
---@field preview_max_lines integer
---@field fold_preview boolean
---@field date_format string # Either "ago" for relative timestamps or an `os.date`-compatible format string.

--- Bug prompt behavior and optional screenshot directory hints.
---@class Clodex.Config.BugPrompt
---@field screenshot_dir? string

--- Highlight group catalog consumed by setup when applying plugin colors.
---@class Clodex.Config.Highlights
---@field groups table<string, Clodex.Config.HighlightSpec>

--- Settings driving prompt dispatch and external workspace-sync polling.
---@alias Clodex.Config.GitWorkflowMode "commit"|"branch_pr"
---
---@class Clodex.Config.PromptExecution
---@field receipts_dir string # Backward-compatible base directory for project-local execution artifacts.
---@field poll_ms integer
---@field skills_dir? string # Project-local skill root relative to the project root unless absolute.
---@field skill_name string
---@field git_workflow Clodex.Config.GitWorkflowMode

--- Session integration toggles for tab-scoped Clodex state.
---@class Clodex.Config.Session
---@field persist_current_project boolean
---@field free_root string # Root/cwd used by the single shared free terminal target.

--- Minimal MCP companion settings used to discover and launch the local helper.
---@class Clodex.Config.Mcp
---@field enabled boolean # Default-on when the helper binary exists; set false to opt out explicitly.
---@field cmd string[]
---@field runtime_dir string

---@class Clodex.Config.KeymapConfig
---@field lhs? string|false
---@field enabled? boolean
---@field enable? boolean
---@field mode? string|string[]
---@field desc? string
---@field silent? boolean
---@field noremap? boolean
---@field expr? boolean
---@field nowait? boolean
---@field script? boolean
---@field unique? boolean
---@field replace_keycodes? boolean

--- Global keymaps created by clodex during setup.
--- Set a value to `false` to disable it.
---@class Clodex.Config.Keymaps
---@field toggle string|Clodex.Config.KeymapConfig|false
---@field queue_workspace string|Clodex.Config.KeymapConfig|false
---@field state_preview string|Clodex.Config.KeymapConfig|false
---@field mini_state_preview string|Clodex.Config.KeymapConfig|false
---@field backend_toggle string|Clodex.Config.KeymapConfig|false

--- Legacy manual-history settings kept for compatibility.
---@class Clodex.Config.ManualHistory
---@field model_instructions_file string # Deprecated and ignored.

--- Runtime-config data structure consumed across managers and UI modules.
---@class Clodex.Config.Values
---@field backend Clodex.Backend.Name
---@field codex_cmd string[]
---@field opencode_cmd string[]
---@field storage Clodex.Config.Storage
---@field terminal Clodex.Config.Terminal
---@field project_detection Clodex.Config.ProjectDetection
---@field state_preview Clodex.Config.StatePreview
---@field queue_workspace Clodex.Config.QueueWorkspace
---@field bug_prompt Clodex.Config.BugPrompt
---@field highlights Clodex.Config.Highlights
---@field prompt_execution Clodex.Config.PromptExecution
---@field session Clodex.Config.Session
---@field mcp Clodex.Config.Mcp
---@field keymaps Clodex.Config.Keymaps
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
        backend = "codex",
        codex_cmd = { "codex" },
        opencode_cmd = { "opencode" },
        storage = {
            projects_file = fs.join(storage_root, "projects.json"),
            workspaces_dir = ".clodex",
            session_state_dir = fs.join(storage_root, "session-state"),
            history_file = fs.join(storage_root, "history.md"),
        },
        terminal = {
            provider = "snacks",
            win = {
                position = "right",
                width = 0.4,
            },
            start_insert = true,
            prefer_native_statusline = true,
            blocked_input = {
                enabled = true,
                poll_ms = 1000,
                win = {
                    position = "float",
                    width = 0.72,
                    height = 0.8,
                    border = "rounded",
                },
            },
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
            mini = {
                width = 42,
                height = 11,
                col = 2,
                winblend = 28,
            },
        },

        queue_workspace = {
            width = 1,
            height = 1,
            project_width = 0.3,
            footer_height = 3,
            preview_max_lines = 5,
            fold_preview = true,
            date_format = "ago",
        },

        bug_prompt = {
            screenshot_dir = nil,
        },

        highlights = vim.deepcopy(HighlightConfig),
        prompt_execution = {
            receipts_dir = fs.join(".clodex", "prompt-executions"),
            poll_ms = 5000,
            skills_dir = fs.join(".clodex", "skills"),
            skill_name = "prompt-nvim-clodex",
            git_workflow = "commit",
        },
        session = {
            persist_current_project = true,
            free_root = vim.fn.expand("~"),
        },
        mcp = {
            enabled = true,
            cmd = {},
            runtime_dir = fs.join(storage_root, "mcp"),
        },
        keymaps = {
            toggle = {
                lhs = "<leader>pt",
            },
            queue_workspace = {
                lhs = "<leader>pq",
            },
            state_preview = {
                lhs = "<leader>ps",
            },
            mini_state_preview = {
                lhs = "<leader>pS",
            },
            backend_toggle = {
                lhs = "<leader>pb",
            },
        },
        manual_history = {
            model_instructions_file = "",
        },
    }
end

---@param values Clodex.Config.Values
---@param opts table
---@return boolean
local function option_provided(values, opts, ...)
    local current = opts
    for index = 1, select("#", ...) do
        local key = select(index, ...)
        if type(current) ~= "table" then
            return false
        end
        current = current[key]
        if current == nil then
            return false
        end
    end
    return true
end

---@param provider string?
---@return "snacks"|"term"
local function normalize_terminal_provider(provider)
    if provider == "term" then
        return "term"
    end
    return "snacks"
end

---@param values Clodex.Config.Values
---@param opts table
local function apply_backend_defaults(values, opts)
    values.backend = Backend.normalize(values.backend)
    values.terminal.provider = normalize_terminal_provider(values.terminal.provider)
end

--- Checks whether a value is a keyed table compatible with config overwrite paths.
--- It treats non-list tables and empty tables as dictionary-shaped data.
---@param value any
---@return boolean
local function is_dict(value)
    return type(value) == "table" and (vim.tbl_isempty(value) or not vim.islist(value))
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

local COLOR_CHANNEL_MAX = 255
local RGB_SHIFT_RED = 16
local RGB_SHIFT_GREEN = 8

---@param value string|integer?
---@return integer?
local function color_number(value)
    if type(value) == "number" then
        return value
    end
    if type(value) ~= "string" or not value:match("^#%x%x%x%x%x%x$") then
        return nil
    end
    return tonumber(value:sub(2), 16)
end

---@param channel integer
---@param adjust number
---@return integer
local function adjust_channel(channel, adjust)
    if adjust < 0 then
        return math.max(math.floor(channel * (1 + adjust) + 0.5), 0)
    end
    return math.min(math.floor(channel + (COLOR_CHANNEL_MAX - channel) * adjust + 0.5), COLOR_CHANNEL_MAX)
end

---@param value string|integer?
---@param adjust? number
---@return string|integer?
local function adjusted_color(value, adjust)
    if type(adjust) ~= "number" or adjust == 0 then
        return value
    end

    local color = color_number(value)
    if not color then
        return value
    end

    local red = math.floor(color / 2 ^ RGB_SHIFT_RED) % (COLOR_CHANNEL_MAX + 1)
    local green = math.floor(color / 2 ^ RGB_SHIFT_GREEN) % (COLOR_CHANNEL_MAX + 1)
    local blue = color % (COLOR_CHANNEL_MAX + 1)
    return adjust_channel(red, adjust) * 2 ^ RGB_SHIFT_RED
        + adjust_channel(green, adjust) * 2 ^ RGB_SHIFT_GREEN
        + adjust_channel(blue, adjust)
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
            return adjusted_color(resolved, value.adjust)
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
        if is_dict(ret) and is_dict(value) then
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
---@param opts? table
---@return Clodex.Config.Values
function Config:setup(opts)
    self.values = Config.merge(defaults(), opts or {})
    apply_backend_defaults(self.values, opts or {})
    return self.values
end

--- Writes configured highlight groups to Neovim whenever setup is called or reloaded.
---@param values Clodex.Config.Values|{ highlights: Clodex.Config.Highlights }
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
