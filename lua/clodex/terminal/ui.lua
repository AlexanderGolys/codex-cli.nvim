local M = {}
local STATUSLINE_EXPR = "%!v:lua.require('clodex.terminal.ui').statusline()"
local WINBAR_EXPR = "%!v:lua.require('clodex.terminal.ui').winbar()"

local Backend = require("clodex.backend")

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
    vim.wo[win].winhl = table.concat({
        "StatusLine:ClodexTerminalStatuslineActive",
        "StatusLineNC:ClodexTerminalStatusline",
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
