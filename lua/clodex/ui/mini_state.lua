local Backend = require("clodex.backend")
local Extmark = require("clodex.ui.extmark")
local TextBlock = require("clodex.ui.text_block")
local ui_win = require("clodex.ui.win")

---@class Clodex.MiniStatePreview
---@field config Clodex.Config.Values
---@field buf? integer
---@field win? integer
---@field ns integer
---@field app? Clodex.App
local Preview = {}
Preview.__index = Preview

local FIELD_LABEL_WIDTH = 10

---@param win? integer
---@return boolean
local function win_valid(win)
    return win ~= nil and vim.api.nvim_win_is_valid(win)
end

---@param buf? integer
---@return boolean
local function buf_valid(buf)
    return buf ~= nil and vim.api.nvim_buf_is_valid(buf)
end

---@param value any
---@return string
local function format_value(value)
    if value == nil then
        return "none"
    end
    if type(value) == "boolean" then
        return value and "yes" or "no"
    end
    return tostring(value)
end

---@param snapshot Clodex.App.StateSnapshot
---@return string
local function local_session_status(snapshot)
    local tab = snapshot.current_tab
    if not tab.session_key then
        return "hidden"
    end

    for _, session in ipairs(snapshot.sessions) do
        if session.key == tab.session_key then
            if session.waiting_state == "permission" then
                return "perm"
            end
            if session.waiting_state == "question" then
                return "input"
            end
            if session.running then
                return "alive"
            end
            return session.buffer_valid and "stopped" or "offline"
        end
    end

    return "unknown"
end

---@param title string
---@return Clodex.Extmark[]
local function section_marks(title)
    return {
        Extmark.inline(0, 0, #title, "ClodexStateSection"),
    }
end

---@param block Clodex.TextBlock
---@param label string
---@param value any
local function append_field(block, label, value)
    local rendered = format_value(value)
    local prefix = string.format("%-" .. FIELD_LABEL_WIDTH .. "s ", label .. ":")
    block:append_line(prefix .. rendered, {
        Extmark.inline(0, 0, #prefix, "ClodexStateFieldLabel"),
    })
end

---@param config Clodex.Config.Values
---@return Clodex.MiniStatePreview
function Preview.new(config)
    local self = setmetatable({}, Preview)
    self.config = config
    self.ns = vim.api.nvim_create_namespace("clodex-mini-state")
    return self
end

---@param config Clodex.Config.Values
function Preview:update_config(config)
    self.config = config
end

---@return boolean
function Preview:is_open()
    return win_valid(self.win)
end

function Preview:ensure_buffer()
    if buf_valid(self.buf) then
        return
    end

    self.buf = ui_win.create_buffer({
        preset = "scratch",
        name = "clodex-mini-state",
        bo = {
            filetype = "clodex_state",
        },
    })

    for _, lhs in ipairs({ "q", "<Esc>" }) do
        vim.keymap.set("n", lhs, function()
            self:hide()
        end, { buffer = self.buf, nowait = true, silent = true })
    end
end

function Preview:apply_window_style()
    if not win_valid(self.win) then
        return
    end
    ui_win.configure(self.win, {
        view = "panel",
        wo = {
            winblend = self.config.state_preview.mini.winblend,
        },
        theme = "default_float",
    })
end

---@param snapshot Clodex.App.StateSnapshot
function Preview:render(snapshot)
    self:ensure_buffer()

    local project = snapshot.active_project or snapshot.detected_project
    local block = TextBlock.new()
    block:append_line("Mini State", section_marks("Mini State"))
    append_field(block, "backend", Backend.display_name(snapshot.backend or self.config.backend))
    append_field(block, "project", project and project.name or "none")
    append_field(block, "target", snapshot.resolved_target.kind)
    append_field(block, "tab", snapshot.current_tab.tabpage)
    append_field(block, "session", local_session_status(snapshot))
    append_field(block, "visible", snapshot.current_tab.has_visible_window)
    append_field(block, "window", snapshot.current_tab.window_id)
    append_field(block, "buffer", vim.api.nvim_get_current_buf())
    append_field(block, "path", snapshot.current_path)
    block:render(self.buf, self.ns)

    local width = math.max(28, math.min(self.config.state_preview.mini.width, vim.o.columns - 2))
    local height = math.max(6, math.min(self.config.state_preview.mini.height, vim.o.lines - 2))
    local row = math.max(vim.o.lines - height - 2, 0)
    local col = math.max((self.config.state_preview.mini.col or 1) - 1, 0)
    local opts = {
        relative = "editor",
        anchor = "NW",
        row = row,
        col = col,
        width = width,
        height = height,
        style = "minimal",
        border = "rounded",
        title = " State ",
        title_pos = "center",
        zindex = 61,
    }

    if win_valid(self.win) then
        vim.api.nvim_win_set_config(self.win, opts)
    else
        self.win = ui_win.open(vim.tbl_extend("force", opts, {
            buf = self.buf,
            enter = false,
            view = "panel",
            theme = "default_float",
        })).win
    end

    self:apply_window_style()
end

function Preview:hide()
    ui_win.close(self.win)
    self.win = nil
end

---@param app Clodex.App
function Preview:refresh(app)
    if not self:is_open() then
        return
    end
    self.app = app
    self:render(app:state_snapshot())
end

---@param app Clodex.App
function Preview:toggle(app)
    if self:is_open() then
        self:hide()
        return
    end
    self.app = app
    self:render(app:state_snapshot())
end

return Preview
