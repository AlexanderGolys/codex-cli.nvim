local M = {}

--- Sends a plugin-scoped notification at a chosen severity level.
---@param message string
---@param level? integer
function M.notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO, { title = "clodex.nvim" })
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
