local M = {}

local uv = vim.uv or vim.loop

---@param path string
---@return string
function M.normalize(path)
  return vim.fs.normalize(path)
end

---@param path string
---@return uv.aliases.fs_stat_table?
function M.stat(path)
  return uv.fs_stat(path)
end

---@param path string
---@return boolean
function M.exists(path)
  return M.stat(path) ~= nil
end

---@param path string
---@return boolean
function M.is_dir(path)
  local stat = M.stat(path)
  return stat ~= nil and stat.type == "directory"
end

---@param path string
---@return boolean
function M.is_file(path)
  local stat = M.stat(path)
  return stat ~= nil and stat.type == "file"
end

---@param path string
---@return string
function M.dirname(path)
  path = M.normalize(path)
  if M.is_dir(path) then
    return path
  end
  return vim.fs.dirname(path)
end

---@param path string
---@return string
function M.basename(path)
  return vim.fs.basename(M.normalize(path))
end

---@param path string
---@return string
function M.cwd_for_path(path)
  path = path ~= "" and M.normalize(path) or M.cwd()
  return M.is_dir(path) and path or M.dirname(path)
end

---@return string
function M.cwd()
  return M.normalize(uv.cwd() or vim.fn.getcwd())
end

---@param buf? number
---@return string
function M.current_path(buf)
  buf = buf or 0
  local name = vim.api.nvim_buf_get_name(buf)
  return name ~= "" and M.normalize(name) or M.cwd()
end

---@param path string
---@param root string
---@return boolean
function M.is_relative_to(path, root)
  path = M.normalize(path)
  root = M.normalize(root)
  return path == root or vim.startswith(path, root .. "/")
end

---@param path string
function M.ensure_dir(path)
  vim.fn.mkdir(path, "p")
end

---@param path string
---@param default any
---@return any
function M.read_json(path, default)
  if not M.is_file(path) then
    return default
  end

  local file = io.open(path, "r")
  if not file then
    return default
  end

  local content = file:read("*a")
  file:close()
  if content == "" then
    return default
  end

  local ok, decoded = pcall(vim.json.decode, content)
  return ok and decoded or default
end

---@param path string
---@param value any
function M.write_json(path, value)
  M.ensure_dir(M.dirname(path))

  local file = assert(io.open(path, "w"))
  file:write(vim.json.encode(value))
  file:close()
end

return M
