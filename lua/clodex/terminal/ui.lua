local M = {}
local STATUSLINE_EXPR = "%!v:lua.require('clodex.terminal.ui').statusline()"
local WINBAR_EXPR = "%!v:lua.require('clodex.terminal.ui').winbar()"

local Backend = require("clodex.backend")

local STATUSLINE_HL_PREFIX = "ClodexTerminalStatuslineDyn"

---@param buf integer
---@param name string
---@return string?
local function buffer_color(buf, name)
    local ok, value = pcall(vim.api.nvim_buf_get_var, buf, name)
    if not ok or type(value) ~= "string" or value == "" then
        return nil
    end
    if value:match("^#%x%x%x%x%x%x$") then
        return value:upper()
    end
end

---@param group string
---@param attr "fg"|"bg"
---@return string?
local function highlight_hex(group, attr)
    local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = group, link = false })
    if not ok or type(hl) ~= "table" or type(hl[attr]) ~= "number" then
        return nil
    end
    return string.format("#%06X", hl[attr])
end

---@param buf integer
---@return string?
local function terminal_statusline_bg(buf)
    return buffer_color(buf, "terminal_color_background")
        or buffer_color(buf, "terminal_color_0")
        or highlight_hex("Normal", "bg")
end

---@param buf integer
---@return string?
local function terminal_statusline_fg(buf)
    return buffer_color(buf, "terminal_color_foreground")
        or highlight_hex("ClodexTerminalStatusline", "fg")
        or highlight_hex("Normal", "fg")
end

---@param value string
---@return string
local function color_key(value)
    return value:gsub("#", "")
end

---@param win integer
---@return string, string
local function ensure_terminal_statusline_highlights(win)
    local buf = vim.api.nvim_win_get_buf(win)
    local bg = terminal_statusline_bg(buf)
    local fg = terminal_statusline_fg(buf)
    if not bg or not fg then
        return "ClodexTerminalStatuslineActive", "ClodexTerminalStatusline"
    end

    local suffix = color_key(bg) .. "_" .. color_key(fg)
    local active = STATUSLINE_HL_PREFIX .. "Active_" .. suffix
    local inactive = STATUSLINE_HL_PREFIX .. "Inactive_" .. suffix
    vim.api.nvim_set_hl(0, inactive, { fg = fg, bg = bg })
    vim.api.nvim_set_hl(0, active, { fg = fg, bg = bg, bold = true })
    return active, inactive
end

---@param win? integer
---@return Clodex.TerminalSession?
local function current_session(win)
    local ok, app = pcall(require, "clodex.app")
    if not ok then
        return nil
    end
    local instance = app.instance and app.instance() or nil
    if not instance or not instance.terminals then
        return nil
    end
    local target = win
    if type(target) ~= "number" or not vim.api.nvim_win_is_valid(target) then
        target = vim.api.nvim_get_current_win()
    end
    return instance.terminals:session_by_buf(vim.api.nvim_win_get_buf(target))
end

---@return boolean
local function is_opencode_backend()
    local ok, app = pcall(require, "clodex.app")
    if not ok then
        return false
    end
    local instance = app.instance and app.instance() or nil
    if not instance or not instance.config then
        return false
    end
    return Backend.normalize(instance.config:get().backend) == "opencode"
end

local function current_window()
    local win = vim.api.nvim_get_current_win()
    return vim.api.nvim_win_is_valid(win) and win or nil
end

local function clodex_terminal_window(win)
    return type(win) == "number"
        and vim.api.nvim_win_is_valid(win)
        and vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "clodex_terminal"
end

---@param win integer
local function apply_terminal_window_highlights(win)
    local active, inactive = ensure_terminal_statusline_highlights(win)
    vim.wo[win].winhl = table.concat({
        "StatusLine:" .. active,
        "StatusLineNC:" .. inactive,
    }, ",")
end

---@param win? integer
function M.apply_window(win)
    local target = win
    if not clodex_terminal_window(target) then
        return
    end
    if is_opencode_backend() then
        return
    end
    vim.wo[target].statusline = STATUSLINE_EXPR
    vim.wo[target].winbar = WINBAR_EXPR
    apply_terminal_window_highlights(target)
end

---@return string
function M.statusline(win)
    local target = type(win) == "number" and win or current_window()
    local session = current_session(target)
    if not session then
        return ""
    end
    return session:statusline_text(target)
end

---@return string
function M.winbar(win)
    local session = current_session(win)
    if not session then
        return ""
    end
    return session:winbar_text()
end

---@param win? integer
function M.refresh_chrome(win)
    local target = win
    if type(target) ~= "number" or not vim.api.nvim_win_is_valid(target) then
        target = current_window()
    end
    if clodex_terminal_window(target) then
        M.apply_window(target)
        pcall(vim.cmd.redrawstatus)
    end
end

function M.refresh_all_chrome()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
        if clodex_terminal_window(win) then
            M.apply_window(win)
        end
    end
end

return M
