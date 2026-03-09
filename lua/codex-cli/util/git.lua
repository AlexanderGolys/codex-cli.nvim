local M = {}

local fs = require("codex-cli.util.fs")

---@param dir string
---@return boolean
local function has_git(dir)
  return fs.exists(dir .. "/.git")
end

---@param path? string
---@return string?
function M.get_root(path)
  local dir = fs.cwd_for_path(path or fs.current_path())
  if has_git(dir) then
    return dir
  end

  for parent in vim.fs.parents(dir) do
    if has_git(parent) then
      return fs.normalize(parent)
    end
  end
end

return M
