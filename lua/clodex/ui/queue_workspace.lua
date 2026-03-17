local ui = require("clodex.ui.select")
local Extmark = require("clodex.ui.extmark")
local PromptAssets = require("clodex.prompt.assets")
local Prompt = require("clodex.prompt")
local PromptContext = require("clodex.prompt.context")
local TextBlock = require("clodex.ui.text_block")
local ui_win = require("clodex.ui.win")
local notify = require("clodex.util.notify")

--- Defines the Clodex.QueueWorkspace.QueueRow type for this module.
--- This annotation documents structured state so modules can pass data with consistent expectations.
---@class Clodex.QueueWorkspace.QueueRow
---@field kind "header"|"item"|"preview"
---@field text string
---@field queue? Clodex.QueueName
---@field item? Clodex.QueueItem

--- Defines the Clodex.QueueWorkspace.ActionSet type for this module.
--- This annotation documents structured state so modules can pass data with consistent expectations.
---@class Clodex.QueueWorkspace.ActionSet
---@field title string
---@field lines string[]

--- Defines the Clodex.QueueWorkspace.ProjectRow type for this module.
--- This annotation documents structured state so modules can pass data with consistent expectations.
---@class Clodex.QueueWorkspace.ProjectRow
---@field kind "item"|"detail"
---@field text string
---@field project? Clodex.Project

--- Defines the Clodex.QueueWorkspace type for this module.
--- This annotation documents structured state so modules can pass data with consistent expectations.
---@class Clodex.QueueWorkspace
---@field app Clodex.App
---@field config Clodex.Config.Values
---@field project_buf? integer
---@field queue_buf? integer
---@field footer_buf? integer
---@field project_win? integer
---@field queue_win? integer
---@field footer_win? integer
---@field focus "projects"|"queue"
---@field project_index integer
---@field queue_index integer
---@field project_search string
---@field queue_search string
---@field projects Clodex.Project[]
---@field project_rows Clodex.QueueWorkspace.ProjectRow[]
---@field project_item_rows integer[]
---@field queue_rows Clodex.QueueWorkspace.QueueRow[]
---@field queue_item_rows integer[]
---@field suppress_open_until? integer
---@field focus_augroup? integer
local Workspace = {}
Workspace.__index = Workspace

local MAIN_ZINDEX = 55
local FOOTER_ZINDEX = 56
local PROJECT_NS = vim.api.nvim_create_namespace("clodex-queue-projects")
local QUEUE_NS = vim.api.nvim_create_namespace("clodex-queue-items")
local FOOTER_NS = vim.api.nvim_create_namespace("clodex-queue-footer")
local QUEUE_LABELS = {
    planned = "Planned",
    queued = "Queued",
    implemented = "Implemented",
    history = "History",
}
local PROJECT_SEARCH_FIELDS = {
    "name",
    "root",
}
local ITEM_TITLE_PREFIX_WIDTH = 2
local PROJECT_DETAIL_LABELS = {
    "Files:",
    "Lang:",
}
local GITHUB_ICON = ""
local ELLIPSIS = "..."
local PANEL_BORDER_COLS = 2
local PANEL_GAP_COLS = 1
local PROJECT_INSERT_MODE_KEYS = {
    "i",
    "I",
    "o",
    "O",
    "R",
}
local QUEUE_INSERT_MODE_KEYS = {
    "I",
    "o",
    "O",
    "R",
}

local function win_valid(win)
    return win ~= nil and vim.api.nvim_win_is_valid(win)
end

local function buf_valid(buf)
    return buf ~= nil and vim.api.nvim_buf_is_valid(buf)
end

---@param win? integer
---@return integer
local function window_buffer_line_count(win)
    if not win_valid(win) then
        return 0
    end
    local ok, buf = pcall(vim.api.nvim_win_get_buf, win)
    if not ok or not buf_valid(buf) then
        return 0
    end
    return vim.api.nvim_buf_line_count(buf)
end

local function clamp(index, max_value)
    if max_value <= 0 then
        return 1
    end
    return math.min(math.max(index, 1), max_value)
end

---@return integer
local function now_ms()
    return vim.uv.now()
end

---@param self Clodex.QueueWorkspace
---@param delay_ms? integer
local function clear_open_suppression_later(self, delay_ms)
    vim.defer_fn(function()
        self.suppress_open_until = nil
    end, delay_ms or 250)
end

---@param text string
---@param max_width integer
---@return string
local function truncate_display(text, max_width)
    text = tostring(text or "")
    if max_width <= 0 then
        return ""
    end
    if vim.fn.strdisplaywidth(text) <= max_width then
        return text
    end
    if max_width <= #ELLIPSIS then
        return ELLIPSIS:sub(1, max_width)
    end

    local target_width = max_width - #ELLIPSIS
    local parts = {} ---@type string[]
    local width = 0
    local chars = vim.fn.strchars(text)
    for index = 0, chars - 1 do
        local char = vim.fn.strcharpart(text, index, 1)
        local char_width = vim.fn.strdisplaywidth(char)
        if width + char_width > target_width then
            break
        end
        parts[#parts + 1] = char
        width = width + char_width
    end

    return table.concat(parts) .. ELLIPSIS
end

---@param self Clodex.QueueWorkspace
---@return integer
local function project_panel_width(self)
    if win_valid(self.project_win) then
        return math.max(vim.api.nvim_win_get_width(self.project_win) - 2, 1)
    end

    return math.max(select(3, self:layout()) - 2, 1)
end

---@param summary Clodex.ProjectQueueSummary
---@return string, { start_col: integer, end_col: integer, hl_group: string }[]
local function project_count_suffix(summary)
    local entries = {
        { text = tostring(summary.counts.planned), hl_group = "ClodexQueueTodoCount" },
        { text = tostring(summary.counts.queued), hl_group = "ClodexQueueQueuedCount" },
        { text = tostring(summary.counts.implemented), hl_group = "ClodexQueueImplementedCount" },
        { text = tostring(summary.counts.history), hl_group = "ClodexQueueHistoryCount" },
    }
    local parts = { "  " }
    local spans = {} ---@type { start_col: integer, end_col: integer, hl_group: string }[]
    local offset = #parts[1]

    for index, entry in ipairs(entries) do
        parts[#parts + 1] = entry.text
        spans[#spans + 1] = {
            start_col = offset,
            end_col = offset + #entry.text,
            hl_group = entry.hl_group,
        }
        offset = offset + #entry.text
        if index < #entries then
            parts[#parts + 1] = "/"
            offset = offset + 1
        end
    end

    return table.concat(parts), spans
end

-- @@@clodex.panel.project.title
---@param project Clodex.Project
---@param summary Clodex.ProjectQueueSummary
---@param max_width integer
---@return string, { start_col: integer, end_col: integer, hl_group: string }[]
local function project_title_text(project, summary, max_width)
    local prefix = summary.session_running and "󰚩 " or "󱙻 "
    local suffix, spans = project_count_suffix(summary)
    local name_width = math.max(max_width - vim.fn.strdisplaywidth(prefix) - vim.fn.strdisplaywidth(suffix), 1)
    return truncate_display(prefix .. truncate_display(project.name, name_width) .. suffix, max_width), spans
end

---@param projects Clodex.Project[]
---@param root? string
---@return integer?
local function project_index_for_root(projects, root)
    if not root or root == "" then
        return nil
    end
    for index, project in ipairs(projects) do
        if project.root == root then
            return index
        end
    end
end

---@param line integer
---@param rows integer[]
---@return integer?
local function row_index(line, rows)
    for index, first_row in ipairs(rows) do
        local next_row = rows[index + 1] or math.huge
        if line >= first_row and line < next_row then
            return index
        end
    end
    return nil
end

local function resolve_size(total, value, minimum)
    if value <= 1 then
        return math.max(math.floor(total * value), minimum)
    end
    return math.max(math.floor(value), minimum)
end

---@param first_row integer
---@param last_row integer
---@param hl_group string
---@return Clodex.Extmark[]
local function selection_marks(first_row, last_row, hl_group)
    local marks = {} ---@type Clodex.Extmark[]
    for row = first_row, last_row do
        marks[#marks + 1] = Extmark.line(row - 1, hl_group)
    end
    return marks
end

---@param focused boolean
---@return string
local function selection_highlight(focused)
    if focused then
        return "ClodexQueueSelectionActive"
    end
    return "ClodexQueueSelectionInactive"
end

local function prompt_queue_label(queue_name)
    return QUEUE_LABELS[queue_name] or queue_name
end

---@param item Clodex.QueueItem
---@param queue_name Clodex.QueueName
---@param query string
---@return boolean
local function queue_item_matches_search(item, queue_name, query)
    if query == "" then
        return true
    end

    local text = table
        .concat({
            item.title or "",
            item.details or "",
            item.prompt or "",
            prompt_queue_label(queue_name),
        }, "\n")
        :lower()
    return text:find(query, 1, true) ~= nil
end

---@param item Clodex.QueueItem
---@return Clodex.PromptCategory
local function prompt_item_kind(item)
    return Prompt.categories.get(item.kind).id
end

---@param item Clodex.QueueItem
---@param opts? { max_lines?: integer, fold?: boolean }
---@return string[]
local function prompt_preview_lines(item, opts)
    opts = opts or {}
    local preview = {} ---@type string[]
    local lines = vim.split(item.prompt or "", "\n", { plain = true })
    local max_lines = math.max(tonumber(opts.max_lines) or 3, 1)
    local folded = opts.fold ~= false
    local remaining = 0
    local skipped_title = false
    for _, line in ipairs(lines) do
        line = vim.trim(line)
        if line ~= "" then
            if not skipped_title then
                skipped_title = true
            elseif #preview >= max_lines then
                remaining = remaining + 1
            else
                preview[#preview + 1] = "    " .. line
            end
        end
    end

    if folded and remaining > 0 then
        if #preview >= max_lines then
            preview[#preview] = ("    ... (+%d more lines)"):format(remaining + 1)
        else
            preview[#preview + 1] = ("    ... (+%d more line%s)"):format(remaining, remaining == 1 and "" or "s")
        end
    else
        while #preview > max_lines do
            preview[#preview] = nil
        end
    end

    return preview
end

---@param item Clodex.QueueItem
---@param project_root? string
---@return string[]
local function item_metadata_preview_lines(item, project_root)
    local preview = {} ---@type string[]
    if item.history_commit and item.history_commit ~= "" then
        local short = project_root and git.short_commit(project_root, item.history_commit) or item.history_commit
        preview[#preview + 1] = ("    Commit: %s%s"):format(COMMIT_ICON, short or item.history_commit)
    end
    return preview
end

---@param queue_name Clodex.QueueName
---@return string, string, string
local function queue_header_groups(queue_name)
    local map = {
        planned = {
            "ClodexQueueTodoName",
            "ClodexQueueTodoBracket",
            "ClodexQueueTodoCount",
        },
        queued = {
            "ClodexQueueQueuedName",
            "ClodexQueueQueuedBracket",
            "ClodexQueueQueuedCount",
        },
        implemented = {
            "ClodexQueueImplementedName",
            "ClodexQueueImplementedBracket",
            "ClodexQueueImplementedCount",
        },
        history = {
            "ClodexQueueHistoryName",
            "ClodexQueueHistoryBracket",
            "ClodexQueueHistoryCount",
        },
    }
    local groups = map[queue_name] or map.planned
    return groups[1], groups[2], groups[3]
end

---@param queue_name Clodex.QueueName
---@param count integer
---@return string, Clodex.Extmark[]
local function queue_header_line(queue_name, count)
    local label = prompt_queue_label(queue_name)
    local text = ("%s (%d)"):format(label, count)
    local name_hl, bracket_hl, count_hl = queue_header_groups(queue_name)
    local marks = {
        Extmark.inline(0, 0, #label, name_hl),
        Extmark.inline(0, #label, #label + 2, bracket_hl),
        Extmark.inline(0, #label + 2, #label + 2 + #tostring(count), count_hl),
        Extmark.inline(0, #label + 2 + #tostring(count), #text, bracket_hl),
    }
    return text, marks
end

---@param focus "projects"|"queue"
---@return Clodex.QueueWorkspace.ActionSet
local function footer_actions(focus)
    if focus == "projects" then
        return {
            title = " Project Actions ",
            lines = {
                "s: set current project   A: start session   X: stop session   a: add prompt/project   D: delete project",
                "/: filter projects by name/root/activity   Backspace: clear filter",
                "&: insert editor context in prompt editor   x: canned prompt in prompt editor",
            },
        }
    end

    return {
        title = " Queue Actions ",
        lines = {
            "a: add prompt   e: edit prompt   i: implement queued item   m/M: move forward/back",
            "/: search prompt list by title/details/body   Backspace: clear filter",
            "p: move project   H/L: prev/next project   d: delete item   &: context   x: canned prompt   !: mark not working   Ctrl-S: save",
        },
    }
end

---@param _queue_name Clodex.QueueName
---@param items Clodex.QueueItem[]
---@return boolean
local function should_render_queue(_queue_name, items)
    return #items > 0
end

---@param text string
---@return string
local function footer_text(text)
    return text:gsub("Left/Right", "←/→"):gsub("Up/Down", "↑/↓")
end

local git = require("clodex.util.git")

local COMMIT_ICON = "󰜘 "

---@param item Clodex.QueueItem
---@param project_root? string
---@return string
local function history_suffix(item, project_root)
    local parts = {} ---@type string[]
    if item.history_summary and item.history_summary ~= "" then
        parts[#parts + 1] = item.history_summary
    end
    if item.history_commit and item.history_commit ~= "" then
        local short = project_root and git.short_commit(project_root, item.history_commit) or item.history_commit
        parts[#parts + 1] = COMMIT_ICON .. (short or item.history_commit)
    end
    return #parts > 0 and ("  [" .. table.concat(parts, " | ") .. "]") or ""
end

---@param timestamp? integer
---@param config Clodex.Config.Values
---@return string
local function format_timestamp(timestamp, config)
    if not timestamp or timestamp <= 0 then
        return "-"
    end

    local date_format = config and config.queue_workspace and config.queue_workspace.date_format or nil
    if date_format ~= "ago" then
        return os.date(date_format or "%H:%M %d.%m.%Y", timestamp)
    end

    local now = os.time()
    local delta = now - timestamp
    if delta <= 0 then
        return "just now"
    end

    local units = {
        { name = "y", seconds = 31536000 },
        { name = "mo", seconds = 2592000 },
        { name = "d", seconds = 86400 },
        { name = "h", seconds = 3600 },
        { name = "m", seconds = 60 },
        { name = "s", seconds = 1 },
    }

    for _, unit in ipairs(units) do
        local count = math.floor(delta / unit.seconds)
        if count >= 1 then
            return ("%d%s ago"):format(count, unit.name)
        end
    end

    return "just now"
end

local LanguageProfile = require("clodex.project.language")
local language_profile = LanguageProfile.new()

---@param languages Clodex.ProjectDetails.LanguageStat[]
---@return string
local function format_languages(languages)
    if #languages == 0 then
        return "-"
    end

    local parts = {} ---@type string[]
    local max_items = 3
    for index, language in ipairs(languages) do
        if index > max_items then
            break
        end
        parts[#parts + 1] = ("%s %d%%"):format(language_profile:format_label(language.name), language.percent)
    end
    if #languages > max_items then
        parts[#parts + 1] = ("+%d"):format(#languages - max_items)
    end
    return table.concat(parts, ", ")
end

---@param detail string
---@return Clodex.Extmark[]
---@param has_remote boolean
---@return Clodex.Extmark[]
local function project_detail_extmarks(detail, has_remote)
    local marks = {
        Extmark.inline(0, 0, #detail, "ClodexQueueItemMuted"),
    }
    local search_from = 1

    for _, label in ipairs(PROJECT_DETAIL_LABELS) do
        local start_col = detail:find(label, search_from, true)
        if start_col then
            local label_start = start_col - 1
            marks[#marks + 1] = Extmark.inline(0, label_start, label_start + #label, "ClodexStateFieldLabel")
            search_from = start_col + #label
        end
    end

    local icon_pos = detail:find(GITHUB_ICON, 1, true)
    if icon_pos then
        local icon_start = icon_pos - 1
        local icon_end = icon_start + #GITHUB_ICON
        local remote_icon_hl = has_remote and "ClodexProjectRemoteAttached" or "ClodexProjectRemoteDetached"
        marks[#marks + 1] = Extmark.inline(0, icon_start, icon_end, remote_icon_hl)
    end

    return marks
end

---@param value string
---@return string
local function normalize_search(value)
    return vim.trim(value):lower()
end

---@param config Clodex.Config.Values
---@param details? Clodex.ProjectDetails
---@return string
local function summary_search_text(config, details)
    if not details then
        return ""
    end
    return table.concat({
        details.remote_name or "",
        format_languages(details.languages),
        format_timestamp(details.last_codex_activity_at, config),
        format_timestamp(details.last_file_modified_at, config),
        tostring(details.file_count or ""),
    }, " ")
end

---@param project Clodex.Project
---@param details? Clodex.ProjectDetails
---@param query string
---@return boolean
local function project_matches_search(project, details, query, config)
    if query == "" then
        return true
    end

    for _, field in ipairs(PROJECT_SEARCH_FIELDS) do
        local value = project[field]
        if type(value) == "string" and value:lower():find(query, 1, true) then
            return true
        end
    end

    return summary_search_text(config, details):lower():find(query, 1, true) ~= nil
end

---@param config Clodex.Config.Values
---@param summary Clodex.ProjectQueueSummary
---@param details? Clodex.ProjectDetails
---@return string[]
local function project_detail_lines(config, app, summary, details)
    details = details or app.project_details_store:get_cached(summary.project)
    if not details then
        return {
            "    Files:-  " .. GITHUB_ICON,
            "    Lang:-  -",
        }
    end
    return {
        ("    Files:%d  %s"):format(details.file_count, " " .. GITHUB_ICON),
        ("    Lang:%s  %s"):format(
            format_languages(details.languages),
            format_timestamp(details.last_file_modified_at, config)
        ),
    }
end

---@param app Clodex.App
---@param config Clodex.Config.Values
---@return Clodex.QueueWorkspace
function Workspace.new(app, config)
    local self = setmetatable({}, Workspace)
    self.app = app
    self.config = config
    self.focus = "projects"
    self.project_index = 1
    self.queue_index = 1
    self.project_search = ""
    self.queue_search = ""
    self.projects = {}
    self.project_rows = {}
    self.project_item_rows = {}
    self.queue_rows = {}
    self.queue_item_rows = {}
    return self
end

---@param config Clodex.Config.Values
function Workspace:update_config(config)
    self.config = config
end

--- Focuses a project row by root so selection commands can land on the right entry.
---@param root? string
function Workspace:focus_project(root)
    self.projects = self:filtered_projects()
    self.project_index = 1
    if root and root ~= "" then
        for index, project in ipairs(self.projects) do
            if project.root == root then
                self.project_index = index
                break
            end
        end
    end
    self.queue_index = 1
    self.focus = "projects"
end

---@return Clodex.Project[]
function Workspace:filtered_projects()
    local projects = self.app:projects_for_queue_workspace()
    local query = normalize_search(self.project_search)
    if query == "" then
        return projects
    end

    local filtered = {} ---@type Clodex.Project[]
    for _, project in ipairs(projects) do
        local details = self.app.project_details_store:get_cached(project)
        if project_matches_search(project, details, query, self.config) then
            filtered[#filtered + 1] = project
        end
    end
    return filtered
end

--- Checks a open condition for ui queue workspace.
--- This gate keeps callers safe before continuing higher-level state transitions.
---@return boolean
function Workspace:is_open()
    return win_valid(self.project_win) and win_valid(self.queue_win) and win_valid(self.footer_win)
end

function Workspace:ensure_buffers()
    local function make_buffer(name)
        local buf = vim.api.nvim_create_buf(false, true)
        vim.bo[buf].buftype = "nofile"
        vim.bo[buf].bufhidden = "wipe"
        vim.bo[buf].swapfile = false
        vim.bo[buf].modifiable = false
        vim.bo[buf].filetype = "clodex_queue_workspace"
        vim.api.nvim_buf_set_name(buf, name)
        return buf
    end

    self.project_buf = buf_valid(self.project_buf) and self.project_buf or make_buffer("clodex-queue-projects")
    self.queue_buf = buf_valid(self.queue_buf) and self.queue_buf or make_buffer("clodex-queue-items")
    self.footer_buf = buf_valid(self.footer_buf) and self.footer_buf or make_buffer("clodex-queue-footer")
end

---@return integer, integer, integer, integer, integer, integer
function Workspace:layout()
    local ui_state = vim.api.nvim_list_uis()[1]
    local columns = ui_state and ui_state.width or vim.o.columns
    local lines = ui_state and ui_state.height or vim.o.lines
    local cfg = self.config.queue_workspace
    local footer_height = math.max(cfg.footer_height, 2)
    local max_width = math.max(columns, 1)
    local max_height = math.max(lines - footer_height - 3, 1)
    local width = math.min(resolve_size(max_width, cfg.width, 72), max_width)
    local height = math.min(resolve_size(max_height, cfg.height, 18), max_height)
    local chrome_width = PANEL_BORDER_COLS * 2 + PANEL_GAP_COLS
    local content_width = math.max(width - chrome_width, 56)
    local row = math.max(math.floor((lines - height - footer_height - 3) / 2), 0)
    local col = math.max(math.floor((columns - width) / 2), 0)
    local project_width = math.max(math.floor(content_width * cfg.project_width), 24)
    local queue_width = math.max(content_width - project_width, 32)
    return row, col, project_width, queue_width, height, footer_height
end

---@return integer
function Workspace:prompt_title_width()
    local queue_width = win_valid(self.queue_win) and vim.api.nvim_win_get_width(self.queue_win)
        or select(4, self:layout())
    return math.max(queue_width - ITEM_TITLE_PREFIX_WIDTH, 1)
end

--- Opens or activates the selected ui queue workspace target in the workspace.
--- This is used by navigation flows that need to display the most recent selection.
function Workspace:open()
    if self:is_open() then
        self:refresh()
        return
    end

    self:ensure_buffers()

    local row, col, project_width, queue_width, height, footer_height = self:layout()
    self.project_win = ui_win.open({
        buf = self.project_buf,
        enter = true,
        row = row,
        col = col,
        width = project_width,
        height = height,
        style = "minimal",
        border = "rounded",
        title = " Projects ",
        zindex = MAIN_ZINDEX,
    }).win
    self.queue_win = ui_win.open({
        buf = self.queue_buf,
        enter = false,
        row = row,
        col = col + project_width + PANEL_BORDER_COLS + PANEL_GAP_COLS,
        width = queue_width,
        height = height,
        style = "minimal",
        border = "rounded",
        title = " Queue ",
        zindex = MAIN_ZINDEX,
    }).win
    self.footer_win = ui_win.open({
        buf = self.footer_buf,
        enter = false,
        row = row + height + 1,
        col = col,
        width = project_width + queue_width + PANEL_BORDER_COLS + PANEL_GAP_COLS,
        height = footer_height,
        style = "minimal",
        border = "rounded",
        title = footer_actions(self.focus).title,
        zindex = FOOTER_ZINDEX,
    }).win

    self:configure_windows()
    self:attach_keymaps()
    self:attach_focus_tracking()
    self:refresh(true)
end

function Workspace:configure_windows()
    for _, win in ipairs({ self.project_win, self.queue_win, self.footer_win }) do
        if win_valid(win) then
            vim.wo[win].number = false
            vim.wo[win].relativenumber = false
            vim.wo[win].signcolumn = "no"
            vim.wo[win].foldcolumn = "0"
            vim.wo[win].wrap = false
            vim.wo[win].spell = false
        end
    end

    for _, win in ipairs({ self.project_win, self.queue_win }) do
        if win_valid(win) then
            vim.wo[win].cursorline = false
        end
    end

    if win_valid(self.footer_win) then
        vim.wo[self.footer_win].cursorline = false
    end
    self:update_window_highlights()
end

--- Closes or deactivates ui queue workspace behavior for the current context.
--- This is used by command flows when a view or session should stop being active.
function Workspace:close()
    require("clodex.ui.select").close_active_input()
    self:clear_focus_tracking()
    local wins = {
        self.project_win,
        self.queue_win,
        self.footer_win,
    }

    -- Clear workspace window handles before closing any floats so autocommand-driven
    -- refreshes during teardown do not try to render into windows that are mid-close.
    self.project_win = nil
    self.queue_win = nil
    self.footer_win = nil

    for _, win in ipairs(wins) do
        ui_win.close(win)
    end
end

function Workspace:clear_focus_tracking()
    if not self.focus_augroup then
        return
    end
    pcall(vim.api.nvim_del_augroup_by_id, self.focus_augroup)
    self.focus_augroup = nil
end

function Workspace:sync_focus_to_current_win()
    if not self:is_open() then
        return
    end

    local current_win = vim.api.nvim_get_current_win()
    if current_win == self.project_win then
        self:set_focus("projects")
        return
    end
    if current_win == self.queue_win then
        self:set_focus("queue")
    end
end

function Workspace:attach_focus_tracking()
    self:clear_focus_tracking()

    local group = vim.api.nvim_create_augroup(("clodex_queue_workspace_focus_%d"):format(self.project_buf or 0), {
        clear = true,
    })
    self.focus_augroup = group

    local function watch(buf)
        vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter" }, {
            group = group,
            buffer = buf,
            callback = function()
                self:sync_focus_to_current_win()
            end,
        })
    end

    if buf_valid(self.project_buf) then
        watch(self.project_buf)
    end
    if buf_valid(self.queue_buf) then
        watch(self.queue_buf)
    end
end

function Workspace:attach_keymaps()
    local function map(buf, lhs, rhs)
        vim.keymap.set("n", lhs, rhs, { buffer = buf, nowait = true, silent = true })
    end

    local function when_focused(target, action)
        return function()
            if self.focus ~= target then
                return
            end
            action()
        end
    end

    local function footer_by_focus(project_action, queue_action)
        return function()
            if self.focus == "projects" then
                project_action()
                return
            end
            if self.focus == "queue" then
                queue_action()
            end
        end
    end

    local function block_insert_keys(buf, keys)
        for _, lhs in ipairs(keys) do
            map(buf, lhs, function() end)
        end
    end

    local function project_click(confirm)
        local mouse = vim.fn.getmousepos()
        if mouse.winid ~= self.project_win then
            return
        end
        local index = row_index(mouse.line, self.project_item_rows)
        if not index then
            return
        end
        self.project_index = index
        self.queue_index = 1
        self:set_focus("projects")
        self:refresh()
        if confirm then
            self:open_selected_project()
        end
    end

    local function queue_click(confirm)
        local mouse = vim.fn.getmousepos()
        if mouse.winid ~= self.queue_win then
            return
        end
        local index = row_index(mouse.line, self.queue_item_rows)
        if not index then
            return
        end
        self.queue_index = index
        self:set_focus("queue")
        self:refresh()
        if confirm then
            self:open_selected_project()
        end
    end

    block_insert_keys(self.project_buf, PROJECT_INSERT_MODE_KEYS)
    for _, buf in ipairs({ self.queue_buf, self.footer_buf }) do
        block_insert_keys(buf, QUEUE_INSERT_MODE_KEYS)
    end

    for _, buf in ipairs({ self.project_buf, self.queue_buf, self.footer_buf }) do
        map(buf, "q", function()
            self:close()
        end)
        map(buf, "<Esc>", function()
            self:close()
        end)
        map(buf, "h", function()
            self:set_focus("projects")
        end)
        map(buf, "<Left>", function()
            self:set_focus("projects")
        end)
        map(buf, "l", function()
            self:set_focus("queue")
        end)
        map(buf, "<Right>", function()
            self:set_focus("queue")
        end)
        map(buf, "k", function()
            self:move_selection(-1)
        end)
        map(buf, "<Up>", function()
            self:move_selection(-1)
        end)
        map(buf, "j", function()
            self:move_selection(1)
        end)
        map(buf, "<Down>", function()
            self:move_selection(1)
        end)
        map(buf, "<CR>", function()
            self:open_selected_project()
        end)
    end

    map(self.project_buf, "s", function()
        self:set_current_project()
    end)
    map(self.project_buf, "A", function()
        self:activate_selected_project()
    end)
    map(self.project_buf, "X", function()
        self:deactivate_selected_project()
    end)
    map(self.project_buf, "a", function()
        self:add_todo()
    end)
    map(self.project_buf, "D", function()
        self:delete_project()
    end)
    map(self.project_buf, "/", function()
        self:prompt_project_search()
    end)
    map(self.project_buf, "<BS>", function()
        self:clear_project_search()
    end)

    map(self.queue_buf, "a", function()
        self:add_todo()
    end)
    map(self.queue_buf, "/", function()
        self:prompt_queue_search()
    end)
    map(self.queue_buf, "<BS>", function()
        self:clear_queue_search()
    end)
    for _, buf in ipairs({ self.queue_buf, self.footer_buf }) do
        map(
            buf,
            "e",
            when_focused("queue", function()
                self:edit_queue_item()
            end)
        )
        map(
            buf,
            "i",
            when_focused("queue", function()
                self:implement_queue_item()
            end)
        )
        map(
            buf,
            "m",
            when_focused("queue", function()
                self:move_queue_item()
            end)
        )
        map(
            buf,
            "M",
            when_focused("queue", function()
                self:move_queue_item_back()
            end)
        )
        map(
            buf,
            "!",
            when_focused("queue", function()
                self:mark_queue_item_not_working()
            end)
        )
        map(
            buf,
            "p",
            when_focused("queue", function()
                self:move_queue_item_to_project()
            end)
        )
        map(
            buf,
            "H",
            when_focused("queue", function()
                self:move_queue_item_to_adjacent_project(-1)
            end)
        )
        map(
            buf,
            "L",
            when_focused("queue", function()
                self:move_queue_item_to_adjacent_project(1)
            end)
        )
        map(
            buf,
            "d",
            when_focused("queue", function()
                self:set_focus("queue")
                self:delete_queue_item()
            end)
        )
    end

    map(
        self.footer_buf,
        "s",
        when_focused("projects", function()
            self:set_current_project()
        end)
    )
    map(
        self.footer_buf,
        "A",
        when_focused("projects", function()
            self:activate_selected_project()
        end)
    )
    map(
        self.footer_buf,
        "X",
        when_focused("projects", function()
            self:deactivate_selected_project()
        end)
    )
    map(
        self.footer_buf,
        "a",
        footer_by_focus(function()
            self:add_todo()
        end, function()
            self:add_todo()
        end)
    )
    map(
        self.footer_buf,
        "D",
        when_focused("projects", function()
            self:delete_project()
        end)
    )
    map(
        self.footer_buf,
        "/",
        footer_by_focus(function()
            self:prompt_project_search()
        end, function()
            self:prompt_queue_search()
        end)
    )
    map(
        self.footer_buf,
        "<BS>",
        footer_by_focus(function()
            self:clear_project_search()
        end, function()
            self:clear_queue_search()
        end)
    )

    map(self.project_buf, "<LeftMouse>", function()
        project_click(false)
    end)
    map(self.project_buf, "<2-LeftMouse>", function()
        project_click(true)
    end)
    map(self.queue_buf, "<LeftMouse>", function()
        queue_click(false)
    end)
    map(self.queue_buf, "<2-LeftMouse>", function()
        queue_click(true)
    end)
end

---@param focus "projects"|"queue"
function Workspace:set_focus(focus)
    if focus == "queue" and not self:selected_project() then
        return
    end
    if self.focus == focus then
        self:apply_focus()
        return
    end
    self.focus = focus
    if self:is_open() then
        self:render_projects()
        self:render_queue()
        self:render_footer()
        if win_valid(self.footer_win) then
            vim.api.nvim_win_set_config(self.footer_win, {
                title = footer_actions(self.focus).title,
                title_pos = "center",
            })
        end
    end
    self:apply_focus()
end

function Workspace:update_window_highlights()
    local function apply(win, active)
        ui_win.set_focus_border(win, active)
    end

    apply(self.project_win, self.focus == "projects")
    apply(self.queue_win, self.focus == "queue")
    apply(self.footer_win, false)
end

function Workspace:apply_focus()
    self:update_window_highlights()
    local win = self.focus == "projects" and self.project_win or self.queue_win
    if not win_valid(win) then
        win = win_valid(self.project_win) and self.project_win or self.queue_win
    end
    if win_valid(win) then
        vim.api.nvim_set_current_win(win)
    end
    self:update_cursor()
end

---@return Clodex.Project?
function Workspace:selected_project()
    return self.projects[self.project_index]
end

function Workspace:update_cursor()
    if win_valid(self.project_win) then
        local row = self.project_item_rows[self.project_index] or 1
        local max_row = window_buffer_line_count(self.project_win)
        if max_row > 0 then
            pcall(vim.api.nvim_win_set_cursor, self.project_win, { clamp(row, max_row), 0 })
        end
    end
    if win_valid(self.queue_win) then
        local selectable = self.queue_item_rows[self.queue_index] or 1
        local max_row = window_buffer_line_count(self.queue_win)
        if max_row > 0 then
            pcall(vim.api.nvim_win_set_cursor, self.queue_win, { clamp(selectable, max_row), 0 })
        end
    end
end

---@param delta integer
function Workspace:move_selection(delta)
    if self.focus == "projects" then
        if #self.projects == 0 then
            return
        end
        local next_index = clamp(self.project_index + delta, #self.projects)
        if next_index ~= self.project_index then
            self.project_index = next_index
            self.queue_index = 1
            self:refresh()
            return
        end
    else
        if #self.queue_item_rows == 0 then
            return
        end
        local next_index = clamp(self.queue_index + delta, #self.queue_item_rows)
        if next_index == self.queue_index then
            self:update_cursor()
            return
        end
        self.queue_index = next_index
        self:render_queue()
    end
    self:update_cursor()
end

--- Updates ui queue workspace state after local changes.
--- Higher-level callers use this to keep the UI and terminal state consistent.
---@param initial? boolean
function Workspace:refresh(initial)
    if not self:is_open() then
        return
    end

    local selected_project = self:selected_project()
    local selected_root = selected_project and selected_project.root or nil
    self.projects = self:filtered_projects()
    if #self.projects == 0 then
        self.project_index = 1
        self.queue_index = 1
    else
        local preserved_index = project_index_for_root(self.projects, selected_root)
        self.project_index = preserved_index or clamp(self.project_index, #self.projects)
    end

    self:render_projects()
    self:render_queue()
    self:render_footer()
    if initial then
        self.focus = "projects"
    end
    if win_valid(self.footer_win) then
        vim.api.nvim_win_set_config(self.footer_win, {
            title = footer_actions(self.focus).title,
            title_pos = "center",
        })
    end
    self:apply_focus()
end

function Workspace:render_projects()
    self.project_rows = {}
    self.project_item_rows = {}
    local block = TextBlock.new()
    local selected_project = self.projects[self.project_index]
    local selected_root = selected_project and selected_project.root or nil
    local active_root = self.app:current_tab().active_project_root
    local max_width = project_panel_width(self)

    if self.project_search ~= "" then
        local search_text = ("Filter: %s"):format(self.project_search)
        block:append_line(search_text, {
            Extmark.inline(0, 0, #"Filter:", "ClodexStateFieldLabel"),
            Extmark.inline(0, #"Filter: ", #search_text, "ClodexQueueItemMuted"),
        })
        block:append_line("")
        self.project_rows[#self.project_rows + 1] = {
            kind = "detail",
            text = search_text,
        }
        self.project_rows[#self.project_rows + 1] = {
            kind = "detail",
            text = "",
        }
    end

    for _, project in ipairs(self.projects) do
        local summary = self.app:queue_summary(project)
        local details = project.root == selected_root and self.app.project_details_store:get(project)
            or self.app.project_details_store:get_cached(project)
        local title, count_spans = project_title_text(project, summary, max_width)
        local count_suffix = project_count_suffix(summary)
        self.project_rows[#self.project_rows + 1] = {
            kind = "item",
            text = title,
            project = project,
        }
        self.project_item_rows[#self.project_item_rows + 1] = #self.project_rows
        local is_active_project = active_root ~= nil and project.root == active_root
        local item_hl = is_active_project and "ClodexQueueProjectCurrent"
            or summary.session_running and "ClodexQueueProjectActive"
            or "ClodexQueueProjectInactive"
        local item_extmarks = {
            Extmark.inline(0, 0, #title, item_hl),
        }
        local counts_start = title:find(count_suffix, 1, true)
        if counts_start then
            for _, span in ipairs(count_spans) do
                item_extmarks[#item_extmarks + 1] =
                    Extmark.inline(0, counts_start - 1 + span.start_col, counts_start - 1 + span.end_col, span.hl_group)
            end
        end
        block:append_line(title, item_extmarks)

        local has_remote = details ~= nil and details.remote_name ~= nil and details.remote_name ~= ""
        for _, detail in ipairs(project_detail_lines(self.config, self.app, summary, details)) do
            detail = truncate_display(detail, max_width)
            self.project_rows[#self.project_rows + 1] = {
                kind = "detail",
                text = detail,
                project = project,
            }
            block:append_line(detail, project_detail_extmarks(detail, has_remote))
        end
    end

    if block:is_empty() then
        if self.project_search ~= "" then
            block:append_line("No projects match the current filter", {
                Extmark.inline(0, 0, #"No projects match the current filter", "ClodexQueueItemMuted"),
            })
            block:append_line("")
            block:append_line("Press / to change the filter or Backspace to clear it", {
                Extmark.inline(0, 0, #"Press / to change the filter or Backspace to clear it", "ClodexQueueItemMuted"),
            })
        else
            block:append_line("No projects configured")
            block:append_line("")
            block:append_line("Press a to add the current workspace as a Clodex project", {
                Extmark.inline(
                    0,
                    0,
                    #"Press a to add the current workspace as a Clodex project",
                    "ClodexQueueItemMuted"
                ),
            })
        end
    end

    local selected_row = self.project_item_rows[self.project_index]
    if selected_row then
        local selected = self.project_rows[selected_row]
        local last_row = selected_row
        while self.project_rows[last_row + 1] and self.project_rows[last_row + 1].project == selected.project do
            last_row = last_row + 1
        end
        block:add_extmarks(selection_marks(selected_row, last_row, selection_highlight(self.focus == "projects")))
    end

    block:render(self.project_buf, PROJECT_NS)
end

function Workspace:render_queue()
    local project = self:selected_project()
    self.queue_rows = {}
    self.queue_item_rows = {}

    local block = TextBlock.new()
    local query = normalize_search(self.queue_search)
    local rendered_items = false
    if not project then
        block:append_line("No project selected")
    else
        local summary = self.app:queue_summary(project)
        if self.queue_search ~= "" then
            local search_text = ("Filter: %s"):format(self.queue_search)
            block:append_line(search_text, {
                Extmark.inline(0, 0, #"Filter:", "ClodexStateFieldLabel"),
                Extmark.inline(0, #"Filter: ", #search_text, "ClodexQueueItemMuted"),
            })
            block:append_line("")
            self.queue_rows[#self.queue_rows + 1] = {
                kind = "header",
                text = search_text,
            }
            self.queue_rows[#self.queue_rows + 1] = {
                kind = "header",
                text = "",
            }
        end
        for _, queue_name in ipairs({ "planned", "queued", "implemented", "history" }) do
            local items = {} ---@type Clodex.QueueItem[]
            for _, item in ipairs(summary.queues[queue_name]) do
                if queue_item_matches_search(item, queue_name, query) then
                    items[#items + 1] = item
                end
            end
            if should_render_queue(queue_name, items) then
                local header_text, header_marks = queue_header_line(queue_name, #items)
                self.queue_rows[#self.queue_rows + 1] = {
                    kind = "header",
                    text = header_text,
                    queue = queue_name,
                }
                block:append_line(header_text, header_marks)

                for _, item in ipairs(items) do
                    rendered_items = true
                    local suffix = (queue_name == "implemented" or queue_name == "history")
                            and history_suffix(item, project and project.root)
                        or ""
                    local item_text = "  " .. item.title .. suffix
                    local title_text = "  " .. item.title
                    self.queue_rows[#self.queue_rows + 1] = {
                        kind = "item",
                        text = item_text,
                        queue = queue_name,
                        item = item,
                    }
                    self.queue_item_rows[#self.queue_item_rows + 1] = #self.queue_rows
                    local item_extmarks = {
                        Extmark.inline(0, 0, #title_text, Prompt.title_group(prompt_item_kind(item))),
                    }
                    if #item_text > #title_text then
                        item_extmarks[#item_extmarks + 1] =
                            Extmark.inline(0, #title_text, #item_text, "ClodexQueueItemMuted")
                    end
                    block:append_line(item_text, item_extmarks)

                    for _, preview in
                        ipairs(prompt_preview_lines(item, {
                            max_lines = self.config.queue_workspace.preview_max_lines,
                            fold = self.config.queue_workspace.fold_preview,
                        }))
                    do
                        self.queue_rows[#self.queue_rows + 1] = {
                            kind = "preview",
                            text = preview,
                            queue = queue_name,
                            item = item,
                        }
                        block:append_line(preview, {
                            Extmark.inline(0, 0, #preview, Prompt.preview_group()),
                        })
                    end
                    for _, preview in ipairs(item_metadata_preview_lines(item, project and project.root)) do
                        self.queue_rows[#self.queue_rows + 1] = {
                            kind = "preview",
                            text = preview,
                            queue = queue_name,
                            item = item,
                        }
                        block:append_line(preview, {
                            Extmark.inline(0, 0, #preview, "ClodexQueueItemMuted"),
                        })
                    end
                end

                block:append_line("")
                self.queue_rows[#self.queue_rows + 1] = {
                    kind = "header",
                    text = "",
                }
            end
        end

        if not rendered_items then
            if self.queue_search ~= "" then
                block:append_line("No prompts match the current filter", {
                    Extmark.inline(0, 0, #"No prompts match the current filter", "ClodexQueueItemMuted"),
                })
                block:append_line("")
                block:append_line("Press / to change the filter or Backspace to clear it", {
                    Extmark.inline(
                        0,
                        0,
                        #"Press / to change the filter or Backspace to clear it",
                        "ClodexQueueItemMuted"
                    ),
                })
            else
                block:append_line("No prompts queued for this project", {
                    Extmark.inline(0, 0, #"No prompts queued for this project", "ClodexQueueItemMuted"),
                })
            end
        end
    end

    if #self.queue_item_rows == 0 then
        self.queue_index = 1
    else
        self.queue_index = clamp(self.queue_index, #self.queue_item_rows)
    end

    local selected_row = self.queue_item_rows[self.queue_index]
    if selected_row then
        local item = self.queue_rows[selected_row]
        if item and item.item then
            local last_row = selected_row
            while self.queue_rows[last_row + 1] and self.queue_rows[last_row + 1].item == item.item do
                last_row = last_row + 1
            end
            block:add_extmarks(selection_marks(selected_row, last_row, selection_highlight(self.focus == "queue")))
        end
    end

    block:render(self.queue_buf, QUEUE_NS)
end

function Workspace:render_footer()
    local action_set = footer_actions(self.focus)
    local block = TextBlock.new()
    for _, line in ipairs(action_set.lines) do
        line = footer_text(line)
        block:append_line(line, {
            Extmark.inline(0, 0, #line, "ClodexQueueFooter"),
        })
    end
    block:render(self.footer_buf, FOOTER_NS)
end

function Workspace:activate_selected_project()
    local project = self:selected_project()
    if not project then
        return
    end
    self.app.project_actions:activate_project_session(project)
    self:refresh()
end

function Workspace:deactivate_selected_project()
    local project = self:selected_project()
    if not project then
        return
    end
    self.app.project_actions:deactivate_project_session(project)
    self:refresh()
end

function Workspace:open_selected_project()
    if self.suppress_open_until and self.suppress_open_until > now_ms() then
        return
    end

    local project = self:selected_project()
    if not project then
        self:add_project()
        return
    end
    self:close()
    vim.schedule(function()
        self.app.project_actions:open_project_workspace_target(project)
    end)
end

--- Pins the selected project as the current project for the active tab.
--- This reuses the normal project-target routing so terminal and preview state stay in sync.
function Workspace:set_current_project()
    local project = self:selected_project()
    if not project then
        notify.warn("No project selected")
        return
    end
    self.app:set_current_project(project)
    self:refresh()
end

---@return Clodex.QueueItem?, Clodex.QueueName?
function Workspace:selected_queue_item()
    local row_index = self.queue_item_rows[self.queue_index]
    local row = row_index and self.queue_rows[row_index] or nil
    if not row or not row.item then
        return nil, nil
    end
    return row.item, row.queue
end

--- Adds a new ui queue workspace entry and keeps related state aligned.
--- This function feeds the same workflow used by interactive and scripted callers.
function Workspace:add_project()
    self.app:add_project()
end

--- Adds a new ui queue workspace entry and keeps related state aligned.
--- This function feeds the same workflow used by interactive and scripted callers.
function Workspace:add_todo()
    local project = self:selected_project()
    if not project then
        self:add_project()
        return
    end

    ui.multiline_input({
        prompt = ("Todo prompt for %s"):format(project.name),
        context = PromptContext.capture({ project = project }),
        paste_image = function()
            local image_path =
                PromptAssets.save_clipboard_image(self.config.storage.workspaces_dir, project.root, "todo")
            if not image_path then
                return nil
            end
            return ("Use the saved clipboard image at `%s` as an additional visual reference."):format(image_path)
        end,
        submit_actions = {
            { value = "save", label = "plan", key = "<C-s>" },
            { value = "queue", label = "queue", key = "<C-q>" },
            { value = "exec", label = "run now", key = "<C-e>" },
        },
    }, function(body, action)
        local spec = body and Prompt.parse(body) or nil
        if not spec then
            return
        end
        local queue_opts = action == "exec" and { queue = "queued", implement = true, run_mode = "exec" }
            or action == "queue" and { queue = "queued" }
            or nil
        self.app.queue_actions:add_project_todo(project, {
            title = spec.title,
            details = spec.details,
        }, queue_opts)
        self.queue_index = 1
        self:refresh()
    end)
end

function Workspace:edit_queue_item()
    local project = self:selected_project()
    local item = self:selected_queue_item()
    if not project or not item then
        notify.warn("No queue item selected")
        return
    end

    ui.multiline_input({
        prompt = ("Edit prompt for %s"):format(project.name),
        default = Prompt.render(item.title, item.details),
        context = PromptContext.capture({ project = project }),
        paste_image = function()
            local image_path =
                PromptAssets.save_clipboard_image(self.config.storage.workspaces_dir, project.root, item.kind)
            if not image_path then
                return nil
            end
            return ("Use the saved clipboard image at `%s` as an additional visual reference."):format(image_path)
        end,
    }, function(body)
        local spec = body and Prompt.parse(body) or nil
        if not spec then
            return
        end
        self.app.queue_actions:edit_queue_item(project, item.id, {
            title = spec.title,
            details = spec.details,
        })
        self:refresh()
    end)
end

function Workspace:implement_queue_item()
    local project = self:selected_project()
    local item, queue_name = self:selected_queue_item()
    if not project or not item then
        notify.warn("No queue item selected")
        return
    end
    if queue_name ~= "queued" then
        notify.warn("Select an item from the queued section")
        return
    end

    if not self.app.queue_actions:implement_queue_item(project, item.id) then
        self:refresh()
        return
    end

    self:close()
    vim.schedule(function()
        local state = self.app:current_tab()
        self.app.project_actions:activate_project(project.root)
        self.app.project_actions:show_target(state, {
            kind = "project",
            project = project,
        })
    end)
end

function Workspace:move_all_planned_items_to_queued()
    local project = self:selected_project()
    if not project then
        notify.warn("No project selected")
        return
    end

    self.app.queue_actions:move_all_planned_items_to_queued(project)
    self:refresh()
end

function Workspace:move_queue_item()
    local project = self:selected_project()
    local item = self:selected_queue_item()
    if not project or not item then
        notify.warn("No queue item selected")
        return
    end
    self.app.queue_actions:advance_queue_item(project, item.id)
    self.queue_index = 1
    self:refresh()
end

function Workspace:move_queue_item_back()
    local project = self:selected_project()
    local item, queue_name = self:selected_queue_item()
    if not project or not item or not queue_name then
        notify.warn("No queue item selected")
        return
    end

    self.app.queue_actions:rewind_queue_item(project, item.id, { queue = queue_name })
    self.queue_index = 1
    self:refresh()
end

function Workspace:mark_queue_item_not_working()
    local project = self:selected_project()
    local item, queue_name = self:selected_queue_item()
    if not project or not item or not queue_name then
        notify.warn("No queue item selected")
        return
    end

    if queue_name ~= "implemented" then
        notify.warn("Only implemented items can be marked as not working")
        return
    end

    ui.input({
        prompt = "Optional note",
    }, function(note)
        if note == nil then
            return
        end
        self.app.queue_actions:rewind_queue_item(project, item.id, {
            queue = queue_name,
            mark_not_working = true,
            note = note,
        })
        self.queue_index = 1
        self:refresh()
    end)
end

function Workspace:move_queue_item_to_project()
    local project = self:selected_project()
    local item, queue_name = self:selected_queue_item()
    if not project or not item or not queue_name then
        notify.warn("No queue item selected")
        return
    end

    local current_index = self.project_index
    self:close()
    vim.schedule(function()
        ui.pick_project(self.app:projects_for_queue_workspace(), {
            prompt = ("Move '%s' to project"):format(item.title),
        }, function(target_project)
            if not target_project then
                self:open()
                self.project_index = current_index
                self:refresh()
                return
            end

            self:prompt_move_to_project(project, item, queue_name, target_project, function()
                for index, candidate in ipairs(self.app:projects_for_queue_workspace()) do
                    if candidate.root == target_project.root then
                        self.project_index = index
                        break
                    end
                end
                self.queue_index = 1
                self:open()
                self:refresh()
            end)
        end)
    end)
end

---@param project Clodex.Project
---@param item Clodex.QueueItem
---@param queue_name Clodex.QueueName
---@param target_project Clodex.Project
---@param on_complete fun()
function Workspace:prompt_move_to_project(project, item, queue_name, target_project, on_complete)
    local function move_to_project(copy)
        self.app.queue_actions:move_queue_item_to_project(project, item.id, target_project, {
            source_queue = queue_name,
            copy = copy,
        })
        on_complete()
    end

    if queue_name == "history" then
        ui.select({
            { label = "Move history item", copy = false },
            { label = "Duplicate history item", copy = true },
        }, {
            prompt = ("Transfer '%s' to %s"):format(item.title, target_project.name),
            format_item = function(choice)
                return choice.label
            end,
        }, function(choice)
            if not choice then
                on_complete()
                return
            end
            move_to_project(choice.copy)
        end)
        return
    end

    move_to_project(false)
end

---@param delta integer
function Workspace:move_queue_item_to_adjacent_project(delta)
    local project = self:selected_project()
    local item, queue_name = self:selected_queue_item()
    if not project or not item or not queue_name then
        notify.warn("No queue item selected")
        return
    end

    local target_index = self.project_index + delta
    if target_index < 1 or target_index > #self.projects then
        notify.warn("No adjacent project in that direction")
        return
    end

    local target_project = self.projects[target_index]
    if not target_project or target_project.root == project.root then
        notify.warn("No adjacent project in that direction")
        return
    end

    self:prompt_move_to_project(project, item, queue_name, target_project, function()
        self.project_index = target_index
        self.queue_index = 1
        self:refresh()
    end)
end

function Workspace:delete_queue_item()
    local project = self:selected_project()
    local item = self:selected_queue_item()
    if not project or not item then
        notify.warn("No queue item selected")
        return
    end

    -- Guard against the confirmation picker submit key falling through to the
    -- workspace Enter mapping and opening the selected project.
    self.suppress_open_until = now_ms() + 500
    vim.schedule(function()
        ui.confirm(("Delete '%s'?"):format(item.title), function(confirmed)
            if not confirmed then
                clear_open_suppression_later(self)
                return
            end
            self.app.queue_actions:delete_queue_item(project, item.id)
            self.queue_index = 1
            self:refresh()
            clear_open_suppression_later(self)
        end)
    end)
end

function Workspace:delete_project()
    local project = self:selected_project()
    if not project then
        notify.warn("No project selected")
        return
    end

    -- Guard against the confirmation picker submit key falling through to the
    -- workspace Enter mapping and opening the selected project.
    self.suppress_open_until = now_ms() + 500
    vim.schedule(function()
        ui.confirm(("Remove project %s?"):format(project.name), function(confirmed)
            if not confirmed then
                clear_open_suppression_later(self)
                return
            end
            self.app.project_actions:perform_project_removal(project)
            self.projects = self:filtered_projects()
            self.project_index = clamp(self.project_index, #self.projects)
            self.queue_index = 1
            self:refresh()
            clear_open_suppression_later(self)
        end)
    end)
end

function Workspace:prompt_project_search()
    ui.input({
        prompt = "Project filter",
        default = self.project_search,
    }, function(value)
        if value == nil then
            return
        end
        self.project_search = vim.trim(value)
        self.project_index = 1
        self.queue_index = 1
        self.focus = "projects"
        self:refresh()
    end)
end

function Workspace:clear_project_search()
    if self.project_search == "" then
        return
    end
    self.project_search = ""
    self.project_index = 1
    self.queue_index = 1
    self:refresh()
end

function Workspace:prompt_queue_search()
    ui.input({
        prompt = "Prompt filter",
        default = self.queue_search,
    }, function(value)
        if value == nil then
            return
        end
        self.queue_search = vim.trim(value)
        self.queue_index = 1
        self.focus = "queue"
        self:refresh()
    end)
end

function Workspace:clear_queue_search()
    if self.queue_search == "" then
        return
    end
    self.queue_search = ""
    self.queue_index = 1
    self.focus = "queue"
    self:refresh()
end

return Workspace
