describe("clodex.ui.queue_workspace cursor highlights", function()
    local Workspace
    local original_select

    before_each(function()
        package.loaded["clodex.ui.queue_workspace"] = nil
        original_select = package.loaded["clodex.ui.select"]
        package.loaded["snacks.input"] = {
            input = function() end,
        }
        package.loaded["snacks.picker.select"] = {
            select = function(_items, _opts, on_choice)
                on_choice(nil)
            end,
        }
        package.loaded["clodex.ui.select"] = {
            confirm = function() end,
            input = function() end,
            close_active_input = function() end,
            has_active_input = function()
                return false
            end,
        }
        Workspace = require("clodex.ui.queue_workspace")
    end)

    after_each(function()
        package.loaded["clodex.ui.queue_workspace"] = nil
        package.loaded["snacks.input"] = nil
        package.loaded["snacks.picker.select"] = nil
        package.loaded["clodex.ui.select"] = original_select
    end)

    it("maps focused and unfocused picker cursors to muted cursor highlights", function()
        local project = {
            name = "Test Project",
            root = "/tmp/test-project",
        }
        local workspace = Workspace.new({
            current_tab = function()
                return {
                    active_project_root = project.root,
                }
            end,
            queue_summary = function()
                return {
                    project = project,
                    counts = {
                        planned = 1,
                        queued = 0,
                        implemented = 0,
                        history = 0,
                    },
                    queues = {
                        planned = {
                            {
                                id = "item-1",
                                title = "First prompt",
                                kind = "todo",
                                prompt = "First prompt\n\nPreview line",
                            },
                        },
                        queued = {},
                        implemented = {},
                        history = {},
                    },
                }
            end,
            project_details_store = {
                get = function()
                    return nil
                end,
                get_cached = function()
                    return nil
                end,
            },
        }, {
            queue_workspace = {
                preview_max_lines = 3,
                fold_preview = true,
            },
        })
        workspace.projects = { project }
        workspace.project_index = 1
        workspace.focus = "queue"
        workspace.project_buf = vim.api.nvim_create_buf(false, true)
        workspace.queue_buf = vim.api.nvim_create_buf(false, true)
        workspace.project_win = vim.api.nvim_open_win(workspace.project_buf, false, {
            relative = "editor",
            row = 1,
            col = 1,
            width = 40,
            height = 12,
            style = "minimal",
        })
        workspace.queue_win = vim.api.nvim_open_win(workspace.queue_buf, false, {
            relative = "editor",
            row = 1,
            col = 42,
            width = 40,
            height = 12,
            style = "minimal",
        })

        workspace:render_projects()
        workspace:render_queue()
        workspace:update_window_highlights()

        assert.is_truthy(vim.wo[workspace.project_win].winhl:find("Cursor:ClodexQueueCursorInactive", 1, true))
        assert.is_truthy(vim.wo[workspace.queue_win].winhl:find("Cursor:ClodexQueueCursorActive", 1, true))

        vim.api.nvim_win_close(workspace.project_win, true)
        vim.api.nvim_win_close(workspace.queue_win, true)
    end)
end)
