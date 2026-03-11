local M = {}
local ACTIVE_BORDER = "CodexCliQueueActiveBorder"
local INACTIVE_BORDER = "CodexCliQueueInactiveBorder"

--- Opens or activates the selected ui win target in the workspace.
--- This is used by navigation flows that need to display the most recent selection.
---@param opts snacks.win.Config|{}
---@return snacks.win
function M.open(opts)
  local Snacks = require("snacks")
  opts = opts or {}
  local style = opts.style or "float"
  local resolved = Snacks.win.resolve(style, opts, {
    position = "float",
    show = true,
    fixbuf = true,
  })
  return Snacks.win(resolved)
end

--- Checks a valid condition for ui win.
--- This gate keeps callers safe before continuing higher-level state transitions.
---@param win? integer
---@return boolean
function M.is_valid(win)
  return win ~= nil and vim.api.nvim_win_is_valid(win)
end

--- Closes or deactivates ui win behavior for the current context.
--- This is used by command flows when a view or session should stop being active.
---@param win? integer
function M.close(win)
  if not M.is_valid(win) then
    return
  end
  pcall(vim.api.nvim_win_close, win, true)
end

---@param win integer
---@param active boolean
function M.set_focus_border(win, active)
  if not M.is_valid(win) then
    return
  end
  local border = active and ACTIVE_BORDER or INACTIVE_BORDER
  vim.wo[win].winhl = ("NormalFloat:NormalFloat,FloatBorder:%s,CursorLine:CodexCliQueueSelection"):format(border)
end

return M
