describe("clodex.ui.queue_workspace language details", function()
    local Workspace

    before_each(function()
        package.loaded["clodex.ui.queue_workspace"] = nil
        package.loaded["snacks.input"] = {
            input = function() end,
        }
        package.loaded["snacks.picker.select"] = {
            select = function(_items, _opts, on_choice)
                on_choice(nil)
            end,
        }
        Workspace = require("clodex.ui.queue_workspace")
    end)

    after_each(function()
        package.loaded["clodex.ui.queue_workspace"] = nil
        package.loaded["snacks.input"] = nil
        package.loaded["snacks.picker.select"] = nil
    end)

    it("keeps multiple language icons visible on one detail line", function()
        local project = {
            name = "Test Project",
            root = "/tmp/test-project",
        }
        local workspace = Workspace.new({
            current_tab = function()
                return {}
            end,
            projects_for_queue_workspace = function()
                return { project }
            end,
            project_details_store = {
                get = function()
                    return nil
                end,
                get_cached = function()
                    return {
                        file_count = 12,
                        remote_name = "origin",
                        languages = {
                            { name = "lua" },
                            { name = "rs" },
                        },
                        last_file_modified_at = os.time(),
                    }
                end,
            },
            queue_summary = function()
                return {
                    project = project,
                    counts = {
                        planned = 0,
                        queued = 0,
                        implemented = 0,
                        history = 0,
                    },
                    queues = {
                        planned = {},
                        queued = {},
                        implemented = {},
                        history = {},
                    },
                }
            end,
        }, {
            queue_workspace = {
                preview_max_lines = 3,
                fold_preview = true,
            },
        })

        workspace.project_buf = vim.api.nvim_create_buf(false, true)
        workspace.queue_buf = vim.api.nvim_create_buf(false, true)
        workspace.footer_buf = vim.api.nvim_create_buf(false, true)
        workspace.project_win = vim.api.nvim_open_win(workspace.project_buf, false, {
            relative = "editor",
            row = 1,
            col = 1,
            width = 22,
            height = 8,
            style = "minimal",
        })
        workspace.queue_win = vim.api.nvim_open_win(workspace.queue_buf, false, {
            relative = "editor",
            row = 1,
            col = 42,
            width = 40,
            height = 8,
            style = "minimal",
        })
        workspace.footer_win = vim.api.nvim_open_win(workspace.footer_buf, false, {
            relative = "editor",
            row = 10,
            col = 1,
            width = 81,
            height = 3,
            style = "minimal",
        })

        workspace:refresh()

        local lines = vim.api.nvim_buf_get_lines(workspace.project_buf, 0, -1, false)
        assert.is_not_nil(lines[2]:find(" ", 1, true))
        assert.is_nil(lines[2]:find("Lang:", 1, true))
        assert.is_nil(lines[2]:find("Files:", 1, true))

        vim.api.nvim_win_close(workspace.footer_win, true)
        vim.api.nvim_win_close(workspace.queue_win, true)
        vim.api.nvim_win_close(workspace.project_win, true)
    end)
end)
