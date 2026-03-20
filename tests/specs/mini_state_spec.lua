local Config = require("clodex.config")
local Preview = require("clodex.ui.mini_state")
local ui_win = require("clodex.ui.win")

describe("clodex.ui.mini_state", function()
    it("renders the focused local state summary", function()
        local original_open = ui_win.open
        ui_win.open = function(opts)
            return {
                win = vim.api.nvim_open_win(opts.buf, false, {
                    relative = "editor",
                    row = 0,
                    col = 0,
                    width = math.max(opts.width or 20, 1),
                    height = math.max(opts.height or 6, 1),
                    style = "minimal",
                }),
            }
        end

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
                    terminal_provider = "term",
                    active_queue_item_title = "Implement parser retry flow",
                },
            },
            tabs = {},
            runtime_projects = {},
            runtime_project_states = {},
        })

        local lines = vim.api.nvim_buf_get_lines(preview.buf, 0, -1, false)
        assert.is_true(vim.tbl_contains(lines, "Mini State"))
        assert.is_true(vim.tbl_contains(lines, "backend:   OpenCode"))
        assert.is_true(vim.tbl_contains(lines, "project:   Demo"))
        assert.is_true(vim.tbl_contains(lines, "target:    project"))
        assert.is_true(vim.tbl_contains(lines, "session:   alive"))
        assert.is_true(vim.tbl_contains(lines, "provider:  term"))
        assert.is_true(vim.tbl_contains(lines, "item:      Implement parser retry flow"))
        assert.is_true(vim.tbl_contains(lines, "visible:   yes"))
        assert.is_true(vim.tbl_contains(lines, "prompted:  no"))
    end)
end)
