local M = {}

local uv = vim.uv or vim.loop

local function is_windows_drive_path(path)
    return type(path) == "string" and path:match("^%a:[/\\]") ~= nil
end

--- Returns true when a path is a virtual buffer URI rather than a disk path.
---@param path string
---@return boolean
function M.is_virtual_path(path)
    path = vim.trim(path or "")
    if path == "" or is_windows_drive_path(path) then
        return false
    end
    return path:match("^[%w_.-]+:") ~= nil
end

--- Normalizes an input path with Vim's path normalizer.
---@param path string
---@return string
function M.normalize(path)
    return vim.fs.normalize(path)
end

--- Gets filesystem stat metadata or returns nil when the path is missing.
---@param path string
---@return uv.aliases.fs_stat_table?
function M.stat(path)
    return uv.fs_stat(path)
end

--- Checks whether a path exists on disk.
---@param path string
---@return boolean
function M.exists(path)
    return M.stat(path) ~= nil
end

--- Returns true when a path points to an existing directory.
---@param path string
---@return boolean
function M.is_dir(path)
    local stat = M.stat(path)
    return stat ~= nil and stat.type == "directory"
end

--- Returns true when a path points to a regular file.
---@param path string
---@return boolean
function M.is_file(path)
    local stat = M.stat(path)
    return stat ~= nil and stat.type == "file"
end

--- Returns the directory portion of a path, treating files as parents.
---@param path string
---@return string
function M.dirname(path)
    return vim.fs.dirname(M.normalize(path))
end

--- Returns the file name component of a path.
---@param path string
---@return string
function M.basename(path)
    return vim.fs.basename(M.normalize(path))
end

--- Joins path segments and normalizes separators.
---@param ...
---@return string
function M.join(...)
    return M.normalize(table.concat({ ... }, "/"))
end

--- Resolves a path to a directory path, using current working directory as fallback.
---@param path string
---@return string
function M.cwd_for_path(path)
    if path == "" or M.is_virtual_path(path) then
        return M.cwd()
    end
    path = M.normalize(path)
    return M.is_dir(path) and path or M.dirname(path)
end

--- Resolves the current working directory from Neovim/UV APIs.
---@return string
function M.cwd()
    return M.normalize(uv.cwd() or vim.fn.getcwd())
end

--- Returns the path associated with a buffer, or current cwd when unnamed.
---@param buf? number
---@return string
function M.current_path(buf)
    buf = buf or 0
    local name = vim.api.nvim_buf_get_name(buf)
    if name == "" or M.is_virtual_path(name) then
        return M.cwd()
    end
    return M.normalize(name)
end

--- Returns true when `path` is under `root` or the root itself.
---@param path string
---@param root string
---@return boolean
function M.is_relative_to(path, root)
    path = M.normalize(path)
    root = M.normalize(root)
    return path == root or vim.startswith(path, root .. "/")
end

--- Ensures a directory path exists via Vim's mkdir utility.
---@param path string
function M.ensure_dir(path)
    vim.fn.mkdir(path, "p")
end

--- Adds entry to gitignore if gitignore exists and entry not already present.
---@param dir_path string
---@param entry string
local function add_to_gitignore(dir_path, entry)
    local gitignore_path = M.join(dir_path, ".gitignore")
    if not M.is_file(gitignore_path) then
        return
    end

    local file = io.open(gitignore_path, "r")
    if not file then
        return
    end

    local content = file:read("*a")
    file:close()

    if content:find(entry, 1, true) then
        return
    end

    file = io.open(gitignore_path, "a")
    if file then
        if content:sub(-1) ~= "\n" then
            file:write("\n")
        end
        file:write(entry .. "\n")
        file:close()
    end
end

--- Ensures a directory exists and adds it to .gitignore if applicable.
--- Checks if the path contains a .clodex directory at the project root level.
---@param path string
function M.ensure_dir_with_gitignore(path)
    M.ensure_dir(path)

    local normalized = M.normalize(path)
    if not vim.startswith(normalized, "/") then
        normalized = M.join(M.cwd(), normalized)
    end

    local clodex_idx = normalized:find("/.clodex/", 1, true)
    if clodex_idx then
        local project_root = normalized:sub(1, clodex_idx)
        local gitignore_path = M.join(project_root, ".gitignore")
        if M.is_file(gitignore_path) then
            add_to_gitignore(project_root, ".clodex/")
        end
    end
end

--- Reads JSON from disk and returns a default value on any failure.
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

--- Encodes and writes JSON with directory creation.
---@param path string
---@param value any
function M.write_json(path, value)
    M.ensure_dir_with_gitignore(M.dirname(path))

    local file = assert(io.open(path, "w"))
    file:write(vim.json.encode(value))
    file:close()
end

--- Writes raw string data to a path using binary mode.
---@param path string
---@param content string
function M.write_file(path, content)
    M.ensure_dir_with_gitignore(M.dirname(path))
    local file = assert(io.open(path, "wb"))
    file:write(content)
    file:close()
end

--- Appends raw string data to a path using binary mode.
---@param path string
---@param content string
function M.append_file(path, content)
    M.ensure_dir_with_gitignore(M.dirname(path))
    local file = assert(io.open(path, "ab"))
    file:write(content)
    file:close()
end

--- Copies a file by reading and writing its entire content.
---@param source string
---@param destination string
---@return boolean
function M.copy_file(source, destination)
    if not M.is_file(source) then
        return false
    end

    local input = io.open(source, "rb")
    if not input then
        return false
    end

    local content = input:read("*a")
    input:close()
    M.write_file(destination, content)
    return true
end

--- Removes a file or directory path recursively.
---@param path string
function M.remove(path)
    vim.fn.delete(M.normalize(path), "rf")
end

--- Tries common README filenames and returns the first match.
---@param root string
---@return string?
function M.find_readme(root)
    root = M.normalize(root)
    local candidate = M.join(root, "README.md")
    if M.is_file(candidate) then
        return candidate
    end
end

--- Finds the newest regular file in a directory and returns its path.
---@param dir string
---@return string?
function M.latest_file(dir)
    dir = M.normalize(dir)
    if not M.is_dir(dir) then
        return
    end

    local entries = vim.fn.readdir(dir)
    local newest_path ---@type string?
    local newest_time = -1
    for _, entry in ipairs(entries) do
        local path = M.join(dir, entry)
        local stat = M.stat(path)
        if stat and stat.type == "file" and stat.mtime and stat.mtime.sec then
            if stat.mtime.sec > newest_time then
                newest_time = stat.mtime.sec
                newest_path = path
            end
        end
    end
    return newest_path
end

return M
