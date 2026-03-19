local Config = require("clodex.config")
local Preview = require("clodex.ui.mini_state")

describe("clodex.ui.mini_state", function()
    it("renders the focused local state summary", function()
        local preview = Preview.new(Config.new():setup())

        preview:render({
            backend = "opencode",
            current_path = "/tmp/demo/file.lua",
            active_project = { name = "Demo", root = "/tmp/demo" },
            detected_project = nil,
            resolved_target = {
                kind = "project",
                project = { name = "Demo" },
            },
            current_tab = {
                tabpage = 3,
                has_visible_window = true,
                session_key = "project:/tmp/demo",
                window_id = 19,
            },
            sessions = {
                {
                    key = "project:/tmp/demo",
                    running = true,
                    buffer_valid = true,
                },
            },
            tabs = {},
            projects = {},
            project_states = {},
        })

        local lines = vim.api.nvim_buf_get_lines(preview.buf, 0, -1, false)
        assert.is_true(vim.tbl_contains(lines, "Mini State"))
        assert.is_true(vim.tbl_contains(lines, "backend:   OpenCode"))
        assert.is_true(vim.tbl_contains(lines, "project:   Demo"))
        assert.is_true(vim.tbl_contains(lines, "target:    project"))
        assert.is_true(vim.tbl_contains(lines, "session:   alive"))
        assert.is_true(vim.tbl_contains(lines, "visible:   yes"))
    end)
end)
