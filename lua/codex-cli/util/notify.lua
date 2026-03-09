local M = {}

---@param message string
---@param level? integer
function M.notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO, { title = "codex-cli.nvim" })
end

---@param message string
function M.error(message)
  M.notify(message, vim.log.levels.ERROR)
end

---@param message string
function M.warn(message)
  M.notify(message, vim.log.levels.WARN)
end

return M
