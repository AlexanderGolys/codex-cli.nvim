local M = {}

local config = {
  terminal_cmd = "snacks",
  terminal_height = 0.4,
  auto_context = true,
}

function M.setup(opts)
  config = vim.tbl_deep_extend("force", config, opts or {})
end

function M.open_terminal()
  -- TBD: Integrate with snacks terminal
  vim.notify("codex-cli: open_terminal not yet implemented", vim.log.levels.INFO)
end

function M.generate_prompt()
  -- TBD: Generate prompt from buffer, diagnostics, quickfix
  vim.notify("codex-cli: generate_prompt not yet implemented", vim.log.levels.INFO)
end

return M
