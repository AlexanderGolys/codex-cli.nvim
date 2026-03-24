local M = {}

---@param message string
---@return { title: string, body: string, ft: string }
local function split_message(message)
    local text = vim.trim(message or "")
    if text == "" then
        return {
            title = "clodex.nvim",
            body = "",
            ft = "text",
        }
    end

    local lines = vim.split(text, "\n", { plain = true })
    if #lines == 1 then
        return {
            title = "clodex.nvim",
            body = lines[1],
            ft = "text",
        }
    end

    local title = vim.trim(lines[1])
    local body = vim.trim(table.concat(vim.list_slice(lines, 2), "\n"))
    if title == "" then
        title = "clodex.nvim"
    end
    if body == "" then
        body = title
        title = "clodex.nvim"
    end
    return {
        title = title,
        body = body,
        ft = "text",
    }
end

--- Sends a plugin-scoped notification at a chosen severity level.
---@param message string
---@param level? integer
function M.notify(message, level)
    local parts = split_message(message)
    vim.notify(parts.body, level or vim.log.levels.INFO, {
        title = parts.title,
        ft = parts.ft,
    })
end

--- Sends an error-level notification with Codex CLI title.
---@param message string
function M.error(message)
    M.notify(message, vim.log.levels.ERROR)
end

--- Sends a warning-level notification with Codex CLI title.
---@param message string
function M.warn(message)
    M.notify(message, vim.log.levels.WARN)
end

return M
