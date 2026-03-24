local Config = require("clodex.config")
local Backend = require("clodex.backend")
local Mcp = require("clodex.mcp")
local fs = require("clodex.util.fs")

local function temp_dir()
    local dir = vim.fn.tempname()
    fs.ensure_dir(dir)
    return dir
end

describe("clodex.mcp", function()
    it("prefers an explicitly configured command", function()
        local values = Config.new():setup({
            mcp = {
                enabled = true,
                cmd = { "cargo", "run", "--bin", "clodex-mcp" },
            },
        })

        assert.are.same({ "cargo", "run", "--bin", "clodex-mcp" }, Mcp.server_cmd(values))
        assert.is_true(Mcp.is_available(values))
    end)

    it("writes persistent codex runtime config for an enabled MCP server", function()
        local runtime_dir = temp_dir()
        local values = Config.new():setup({
            mcp = {
                enabled = true,
                cmd = { "cargo", "run", "--bin", "clodex-mcp" },
                runtime_dir = runtime_dir,
            },
        })
        local env = Backend.cli_env(values)
        local file = assert(io.open(Mcp.codex_config_path(values), "rb"))
        local content = file:read("*a")
        file:close()

        assert.are.same({ "codex" }, Backend.cli_cmd(values))
        assert.are.equal(Mcp.codex_home(values), env.CODEX_HOME)
        assert.matches("%[mcp_servers%.clodex%]", content)
        assert.matches('command = "cargo"', content)
        assert.matches('args = %[%"run%", %"%-%-bin%", %"clodex%-mcp%"%]', content)

        fs.remove(runtime_dir)
    end)

    it("writes persistent opencode runtime config for an enabled MCP server", function()
        local runtime_dir = temp_dir()
        local values = Config.new():setup({
            backend = "opencode",
            mcp = {
                enabled = true,
                cmd = { "cargo", "run", "--bin", "clodex-mcp" },
                runtime_dir = runtime_dir,
            },
        })
        local env = Backend.cli_env(values)
        local decoded = fs.read_json(Mcp.opencode_config_path(values), {})

        assert.are.equal(Mcp.opencode_config_path(values), env.OPENCODE_CONFIG)
        assert.are.same({
            type = "local",
            command = { "cargo", "run", "--bin", "clodex-mcp" },
            enabled = true,
        }, decoded.mcp.clodex)

        fs.remove(runtime_dir)
    end)

    it("applies the MCP-enabled Codex command to project TUI sessions", function()
        local values = Config.new():setup({
            mcp = {
                enabled = true,
                cmd = { "cargo", "run", "--bin", "clodex-mcp" },
                runtime_dir = temp_dir(),
            },
        })
        package.loaded["snacks.terminal"] = {
            open = function()
            end,
        }
        package.loaded["clodex.terminal.manager"] = nil
        local Manager = require("clodex.terminal.manager")
        local manager = Manager.new(values)
        local spec = manager:session_spec({
            kind = "project",
            project = {
                name = "Demo",
                root = "/tmp/demo",
            },
        })

        assert.are.same(Backend.cli_cmd(values), spec.cmd)
        assert.are.equal(Mcp.codex_home(values), spec.env.CODEX_HOME)
        assert.are.equal("snacks", spec.terminal_provider)

        fs.remove(values.mcp.runtime_dir)
    end)

    it("applies persistent opencode config env to project TUI sessions", function()
        local values = Config.new():setup({
            backend = "opencode",
            mcp = {
                enabled = true,
                cmd = { "cargo", "run", "--bin", "clodex-mcp" },
                runtime_dir = temp_dir(),
            },
        })
        package.loaded["snacks.terminal"] = {
            open = function()
            end,
        }
        package.loaded["clodex.terminal.manager"] = nil
        local Manager = require("clodex.terminal.manager")
        local manager = Manager.new(values)
        local spec = manager:session_spec({
            kind = "project",
            project = {
                name = "Demo",
                root = "/tmp/demo",
            },
        })
        local decoded = fs.read_json(spec.env.OPENCODE_CONFIG, {})

        assert.are.same({ "opencode" }, spec.cmd)
        assert.are.equal(Mcp.opencode_config_path(values), spec.env.OPENCODE_CONFIG)
        assert.are.same({ "cargo", "run", "--bin", "clodex-mcp" }, decoded.mcp.clodex.command)
        assert.are.equal("term", spec.terminal_provider)

        fs.remove(values.mcp.runtime_dir)
    end)

    it("restarts an existing project session when backend MCP env changes", function()
        local original_session = package.loaded["clodex.terminal.session"]
        package.loaded["clodex.terminal.manager"] = nil

        local created = {}
        package.loaded["clodex.terminal.session"] = {
            new = function(spec)
                local session = {
                    key = spec.key,
                    kind = spec.kind,
                    cwd = spec.cwd,
                    title = spec.title,
                    cmd = vim.deepcopy(spec.cmd),
                    env = spec.env and vim.deepcopy(spec.env) or nil,
                    project_root = spec.project_root,
                    destroyed = false,
                    ensure_started = function()
                        return true
                    end,
                    is_running = function(self)
                        return not self.destroyed
                    end,
                    destroy = function(self)
                        self.destroyed = true
                    end,
                    update_identity = function(self, next_spec)
                        self.key = next_spec.key
                        self.kind = next_spec.kind
                        self.cwd = next_spec.cwd
                        self.title = next_spec.title
                        self.cmd = vim.deepcopy(next_spec.cmd)
                        self.env = next_spec.env and vim.deepcopy(next_spec.env) or nil
                        self.project_root = next_spec.project_root
                    end,
                }
                created[#created + 1] = session
                return session
            end,
        }

        local Manager = require("clodex.terminal.manager")
        local codex_values = Config.new():setup({
            mcp = {
                enabled = true,
                cmd = { "cargo", "run", "--bin", "clodex-mcp" },
                runtime_dir = temp_dir(),
            },
        })
        local opencode_values = Config.new():setup({
            backend = "opencode",
            mcp = {
                enabled = true,
                cmd = { "cargo", "run", "--bin", "clodex-mcp" },
                runtime_dir = temp_dir(),
            },
        })
        local manager = Manager.new(codex_values)
        local project = {
            name = "Demo",
            root = "/tmp/demo",
        }

        local first = manager:ensure_project_session(project)
        manager:update_config(opencode_values)
        local second = manager:ensure_project_session(project)

        assert.are_not.same(first, second)
        assert.is_true(first.destroyed)
        assert.are.equal(Mcp.codex_home(codex_values), first.env.CODEX_HOME)
        assert.are.equal(Mcp.opencode_config_path(opencode_values), second.env.OPENCODE_CONFIG)

        fs.remove(codex_values.mcp.runtime_dir)
        fs.remove(opencode_values.mcp.runtime_dir)
        package.loaded["clodex.terminal.manager"] = nil
        package.loaded["clodex.terminal.session"] = original_session
    end)

    it("restarts an opencode session when the MCP runtime config changes at the same path", function()
        local original_session = package.loaded["clodex.terminal.session"]
        package.loaded["clodex.terminal.manager"] = nil

        package.loaded["clodex.terminal.session"] = {
            new = function(spec)
                return {
                    key = spec.key,
                    kind = spec.kind,
                    cwd = spec.cwd,
                    title = spec.title,
                    cmd = vim.deepcopy(spec.cmd),
                    env = spec.env and vim.deepcopy(spec.env) or nil,
                    runtime_key = spec.runtime_key,
                    project_root = spec.project_root,
                    destroyed = false,
                    ensure_started = function()
                        return true
                    end,
                    is_running = function(self)
                        return not self.destroyed
                    end,
                    destroy = function(self)
                        self.destroyed = true
                    end,
                    update_identity = function(self, next_spec)
                        self.key = next_spec.key
                        self.kind = next_spec.kind
                        self.cwd = next_spec.cwd
                        self.title = next_spec.title
                        self.cmd = vim.deepcopy(next_spec.cmd)
                        self.env = next_spec.env and vim.deepcopy(next_spec.env) or nil
                        self.runtime_key = next_spec.runtime_key
                        self.project_root = next_spec.project_root
                    end,
                }
            end,
        }

        local runtime_dir = temp_dir()
        local first_values = Config.new():setup({
            backend = "opencode",
            mcp = {
                enabled = true,
                cmd = { "cargo", "run", "--bin", "clodex-mcp" },
                runtime_dir = runtime_dir,
            },
        })
        local second_values = Config.new():setup({
            backend = "opencode",
            mcp = {
                enabled = true,
                cmd = { "cargo", "run", "--release", "--bin", "clodex-mcp" },
                runtime_dir = runtime_dir,
            },
        })
        local Manager = require("clodex.terminal.manager")
        local manager = Manager.new(first_values)
        local project = {
            name = "Demo",
            root = "/tmp/demo",
        }

        local first = manager:ensure_project_session(project)
        manager:update_config(second_values)
        local second = manager:ensure_project_session(project)

        assert.are_not.same(first, second)
        assert.is_true(first.destroyed)
        assert.are.equal(Mcp.opencode_config_path(first_values), first.env.OPENCODE_CONFIG)
        assert.are.equal(Mcp.opencode_config_path(second_values), second.env.OPENCODE_CONFIG)
        assert.are_not.equal(first.runtime_key, second.runtime_key)

        fs.remove(runtime_dir)
        package.loaded["clodex.terminal.manager"] = nil
        package.loaded["clodex.terminal.session"] = original_session
    end)
end)
