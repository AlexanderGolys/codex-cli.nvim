local M = {}
local ACTIVE_BORDER = "ClodexQueueActiveBorder"
local INACTIVE_BORDER = "ClodexQueueInactiveBorder"
local ACTIVE_NORMAL = "ClodexQueueFocusActive"
local INACTIVE_NORMAL = "ClodexQueueFocusInactive"
local ACTIVE_SELECTION = "ClodexQueueSelectionActive"
local INACTIVE_SELECTION = "ClodexQueueSelectionInactive"

--- Opens or activates the selected ui win target in the workspace.
--- This is used by navigation flows that need to display the most recent selection.
---@param opts snacks.win.Config|{}
---@return snacks.win
function M.open(opts)
  local Snacks = require("snacks")
  opts = opts or {}
  local style = opts.style or "float"
  local resolved = Snacks.win.resolve({
    position = "float",
    show = true,
    -- Clodex uses this helper for dedicated float views whose buffers should not
    -- be "fixed" by Snacks buffer-swapping autocommands.
    fixbuf = false,
  }, style, opts)
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
  local normal = active and ACTIVE_NORMAL or INACTIVE_NORMAL
  local selection = active and ACTIVE_SELECTION or INACTIVE_SELECTION
  vim.wo[win].winhl = (
    "Normal:%s,NormalNC:%s,NormalFloat:%s,FloatBorder:%s,"
        .. "CursorLine:%s,EndOfBuffer:%s,Cursor:%s,lCursor:%s,"
        .. "CursorIM:%s,TermCursor:%s,TermCursorNC:%s"
  ):format(normal, normal, normal, border, selection, normal, normal, normal, normal, normal, normal)
  vim.wo[win].winblend = 0
end

return M
