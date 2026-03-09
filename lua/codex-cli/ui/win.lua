local M = {}

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

return M
