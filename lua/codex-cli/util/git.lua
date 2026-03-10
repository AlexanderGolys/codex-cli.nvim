local M = {}

local fs = require("codex-cli.util.fs")

--- Checks whether a directory contains a `.git` marker.
---@param dir string
---@return boolean
local function has_git(dir)
  return fs.exists(dir .. "/.git")
end

--- Resolves the nearest Git root for the given path or current buffer path.
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

--- Reads the current commit hash for a repository, optionally short form.
---@param root string
---@param short? boolean
---@return string?
function M.head_commit(root, short)
  if not root or root == "" then
    return
  end

  local args = { "git", "-C", root, "rev-parse" }
  if short then
    args[#args + 1] = "--short"
  end
  args[#args + 1] = "HEAD"

  local result = vim.system(args, { text = true }):wait()
  if result.code ~= 0 then
    return
  end

  local output = vim.trim(result.stdout or "")
  return output ~= "" and output or nil
end

--- Parses a Git remote URL into a repository name for display.
---@param url string
---@return string?
local function repo_name_from_url(url)
  url = vim.trim(url or "")
  if url == "" then
    return
  end

  url = url:gsub("/+$", "")
  local name = url:match("([^/:]+)%.git$") or url:match("([^/:]+)$")
  if not name or name == "" then
    return
  end
  return name
end

--- Resolves the current remote `origin` name for project metadata.
---@param root string
---@return string?
function M.remote_name(root)
  if not root or root == "" then
    return
  end

  local commands = {
    { "git", "-C", root, "config", "--get", "remote.origin.url" },
    { "git", "-C", root, "remote", "get-url", "origin" },
  }

  for _, args in ipairs(commands) do
    local result = vim.system(args, { text = true }):wait()
    if result.code == 0 then
      local name = repo_name_from_url(result.stdout or "")
      if name then
        return name
      end
    end
  end
end

return M
