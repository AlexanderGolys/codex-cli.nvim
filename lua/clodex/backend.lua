local fs = require("clodex.util.fs")
local Mcp = require("clodex.mcp")

---@alias Clodex.Backend.Name "codex"|"opencode"

local Backend = {}

---@param name string?
---@return Clodex.Backend.Name
function Backend.normalize(name)
    if name == "opencode" then
        return "opencode"
    end
    return "codex"
end

---@param name string?
---@return string
function Backend.display_name(name)
    if Backend.normalize(name) == "opencode" then
        return "OpenCode"
    end
    return "Codex"
end

---@param name string?
---@return boolean
function Backend.uses_project_local_skills(name)
    return false
end

---@param name string?
---@return boolean
function Backend.supports_model_instructions(name)
    return Backend.normalize(name) == "codex"
end

---@param name string?
---@return boolean
function Backend.supports_direct_exec(name)
    return Backend.normalize(name) == "codex"
end

---@return string
local function codex_home()
    local configured = vim.trim(vim.env.CODEX_HOME or "")
    if configured ~= "" then
        return fs.normalize(vim.fn.expand(configured))
    end

    return fs.join(vim.fn.expand("~"), ".codex")
end

---@param name string?
---@return string
function Backend.default_skills_dir(name)
    if Backend.normalize(name) == "opencode" then
        return fs.join(vim.fn.expand("~"), ".config", "opencode", "skills")
    end

    return fs.join(codex_home(), "skills")
end

---@param config Clodex.Config.Values
---@return string[]
function Backend.cli_cmd(config)
    local name = Backend.normalize(config.backend)
    local cmd = nil ---@type string[]
    if name == "opencode" then
        cmd = vim.deepcopy(config.opencode_cmd)
    else
        cmd = vim.deepcopy(config.codex_cmd)
    end

    if name == "codex" then
        vim.list_extend(cmd, Mcp.codex_config_args(config))
    end

    return cmd
end

---@param config Clodex.Config.Values
---@param _target? Clodex.TerminalTarget
---@return table<string, string>?
function Backend.cli_env(config, _target)
    if not Mcp.is_enabled(config) then
        return nil
    end

    Mcp.sync_runtime(config)

    if Backend.normalize(config.backend) == "opencode" then
        return {
            OPENCODE_CONFIG = Mcp.opencode_config_path(config),
        }
    end

    return {
        CODEX_HOME = Mcp.codex_home(config),
    }
end

return Backend
