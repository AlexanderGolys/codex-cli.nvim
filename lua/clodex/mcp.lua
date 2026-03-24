local fs = require("clodex.util.fs")

---@class Clodex.Mcp
local M = {}

local SOURCE_PATH = fs.normalize(debug.getinfo(1, "S").source:sub(2))
local REPO_ROOT = fs.dirname(fs.dirname(fs.dirname(SOURCE_PATH)))
local BIN_NAME = vim.fn.has("win32") == 1 and "clodex-mcp.exe" or "clodex-mcp"
local SERVER_NAME = "clodex"

---@param values Clodex.Config.Values
---@return string
local function runtime_root(values)
    return fs.normalize(values.mcp.runtime_dir)
end

---@param value string
---@return string
local function toml_string(value)
    return ('"%s"'):format(value:gsub('\\', '\\\\'):gsub('"', '\\"'))
end

---@param values? Clodex.Config.Values
---@return string[]
local function server_args(values)
    local configured = values and values.mcp and values.mcp.cmd or nil
    if type(configured) ~= "table" or #configured <= 1 then
        return {}
    end

    local args = {}
    for index = 2, #configured do
        args[#args + 1] = toml_string(configured[index])
    end
    return args
end

---@param values Clodex.Config.Values
---@return string
function M.codex_home(values)
    return fs.join(runtime_root(values), "codex")
end

---@param values Clodex.Config.Values
---@return string
function M.codex_config_path(values)
    return fs.join(M.codex_home(values), "config.toml")
end

---@param values Clodex.Config.Values
---@return string
function M.opencode_config_path(values)
    return fs.join(runtime_root(values), "opencode.json")
end

---@return string
local function release_binary_path()
    return fs.join(REPO_ROOT, "rust", "clodex-mcp", "target", "release", BIN_NAME)
end

---@return string
local function debug_binary_path()
    return fs.join(REPO_ROOT, "rust", "clodex-mcp", "target", "debug", BIN_NAME)
end

---@param values? Clodex.Config.Values
---@return string[]?
function M.server_cmd(values)
    local configured = values and values.mcp and values.mcp.cmd or nil
    if type(configured) == "table" and #configured > 0 then
        return vim.deepcopy(configured)
    end

    local release = release_binary_path()
    if fs.is_file(release) then
        return { release }
    end

    local debug = debug_binary_path()
    if fs.is_file(debug) then
        return { debug }
    end

    return nil
end

---@param values? Clodex.Config.Values
---@return boolean
function M.is_available(values)
    return M.server_cmd(values) ~= nil
end

---@param values? Clodex.Config.Values
---@return boolean
function M.is_enabled(values)
    return values ~= nil and values.mcp ~= nil and values.mcp.enabled == true and M.is_available(values)
end

---@param values? Clodex.Config.Values
---@return string[]
function M.codex_config_args(values)
    if not M.is_enabled(values) then
        return {}
    end

    local cmd = assert(M.server_cmd(values))
    local args = {
        "-c",
        ("mcp_servers.%s.command=%s"):format(SERVER_NAME, toml_string(cmd[1])),
    }

    local server_cmd_args = server_args(values)
    if #server_cmd_args > 0 then
        args[#args + 1] = "-c"
        args[#args + 1] = ("mcp_servers.%s.args=[%s]"):format(SERVER_NAME, table.concat(server_cmd_args, ", "))
    end

    return args
end

---@param values Clodex.Config.Values
local function write_codex_runtime(values)
    local cmd = assert(M.server_cmd(values))
    local lines = {
        ("[mcp_servers.%s]"):format(SERVER_NAME),
        ("command = %s"):format(toml_string(cmd[1])),
    }

    local server_cmd_args = server_args(values)
    if #server_cmd_args > 0 then
        lines[#lines + 1] = ("args = [%s]"):format(table.concat(server_cmd_args, ", "))
    end

    fs.write_file(M.codex_config_path(values), table.concat(lines, "\n") .. "\n")
end

---@param values Clodex.Config.Values
local function write_opencode_runtime(values)
    local cmd = assert(M.server_cmd(values))
    fs.write_json(M.opencode_config_path(values), {
        mcp = {
            [SERVER_NAME] = {
                type = "local",
                command = cmd,
                enabled = true,
            },
        },
    })
end

---@param values Clodex.Config.Values
function M.sync_runtime(values)
    if not M.is_enabled(values) then
        return
    end

    write_codex_runtime(values)
    write_opencode_runtime(values)
end

return M
