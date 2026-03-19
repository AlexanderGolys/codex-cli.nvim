local Config = require("clodex.config")
local Backend = require("clodex.backend")
local Mcp = require("clodex.mcp")

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

    it("builds codex CLI overrides for an enabled MCP server", function()
        local values = Config.new():setup({
            mcp = {
                enabled = true,
                cmd = { "cargo", "run", "--bin", "clodex-mcp" },
            },
        })

        assert.are.same({
            "-c",
            'mcp_servers.clodex.command="cargo"',
            "-c",
            'mcp_servers.clodex.args=["run", "--bin", "clodex-mcp"]',
        }, Mcp.codex_config_args(values))

        assert.are.same({
            "codex",
            "-c",
            'mcp_servers.clodex.command="cargo"',
            "-c",
            'mcp_servers.clodex.args=["run", "--bin", "clodex-mcp"]',
        }, Backend.cli_cmd(values))
    end)
end)
