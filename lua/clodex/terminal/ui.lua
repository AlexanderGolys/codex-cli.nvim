local M = {}

local function current_session()
    local ok, app = pcall(require, "clodex.app")
    if not ok then
        return nil
    end
    local instance = app.instance and app.instance() or nil
    if not instance or not instance.terminals then
        return nil
    end
    return instance.terminals:session_by_buf(vim.api.nvim_get_current_buf())
end

---@return string
function M.statusline()
    local session = current_session()
    if not session then
        return ""
    end
    return session:statusline_text(vim.api.nvim_get_current_win())
end

---@return string
function M.winbar()
    local session = current_session()
    if not session then
        return ""
    end
    return session:winbar_text()
end

return M
