local Config = require("clodex.config")

describe("clodex.config", function()
    describe("Config.merge", function()
        it("merges nested dictionary values", function()
            local merged = Config.merge({
                terminal = {
                    win = {
                        position = "right",
                        width = 0.4,
                    },
                    start_insert = true,
                },
                project_detection = {
                    auto_suggest_git_root = false,
                },
            }, {
                terminal = {
                    start_insert = false,
                },
                project_detection = {
                    auto_suggest_git_root = true,
                },
            })

            assert.are.equal("right", merged.terminal.win.position)
            assert.are.equal(0.4, merged.terminal.win.width)
            assert.are.equal(false, merged.terminal.start_insert)
            assert.are.equal(true, merged.project_detection.auto_suggest_git_root)
        end)

        it("replaces list values instead of attempting deep merge", function()
            local merged = Config.merge({
                hooks = { "start", "stop" },
            }, {
                hooks = { "override" },
            })

            assert.are.same({ "override" }, merged.hooks)
        end)
    end)

    describe("setup", function()
        it("keeps defaults and applies option overrides", function()
            local cfg = Config.new()
            local values = cfg:setup({
                terminal = {
                    start_insert = false,
                },
                project_detection = {
                    auto_suggest_git_root = true,
                },
            })

            assert.are.equal(false, values.terminal.start_insert)
            assert.are.equal("right", values.terminal.win.position)
            assert.are.equal(true, values.project_detection.auto_suggest_git_root)
            assert.are.equal("codex", values.codex_cmd[1])
            assert.are.equal("<leader>pt", values.keymaps.toggle.lhs)
            assert.are.equal("<leader>pq", values.keymaps.queue_workspace.lhs)
            assert.are.equal("<leader>ps", values.keymaps.state_preview.lhs)
        end)

        it("darkens adjusted highlight colors relative to their source background", function()
            vim.api.nvim_set_hl(0, "ConfigSpecBase", { bg = "#808080" })

            Config.apply_highlights({
                highlights = {
                    groups = {
                        ConfigSpecAdjusted = {
                            bg = {
                                from = "ConfigSpecBase",
                                attr = "bg",
                                adjust = -0.25,
                            },
                        },
                    },
                },
            })

            local adjusted = vim.api.nvim_get_hl(0, { name = "ConfigSpecAdjusted", link = false })
            assert.are.equal(0x606060, adjusted.bg)
        end)
    end)
end)
