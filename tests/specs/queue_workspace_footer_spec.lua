describe("clodex.ui.queue_workspace footer", function()
    local Workspace
    local original_select

    before_each(function()
        package.loaded["clodex.ui.queue_workspace"] = nil
        original_select = package.loaded["clodex.ui.select"]
        package.loaded["clodex.ui.select"] = {
            input = function() end,
            confirm = function() end,
            close_active_input = function() end,
            has_active_input = function()
                return false
            end,
        }
        Workspace = require("clodex.ui.queue_workspace")
    end)

    after_each(function()
        package.loaded["clodex.ui.queue_workspace"] = nil
        package.loaded["clodex.ui.select"] = original_select
    end)

    it("keeps footer action labels concise and hides clear-filter until needed", function()
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
                    return nil
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

        workspace.footer_buf = vim.api.nvim_create_buf(false, true)

        workspace.focus = "projects"
        workspace:render_footer()
        local project_lines = vim.api.nvim_buf_get_lines(workspace.footer_buf, 0, -1, false)
        assert.are.equal("/: filter by project text", project_lines[2])
        assert.are.equal(2, #project_lines)
        assert.is_truthy(project_lines[1]:find("I: set icon", 1, true))

        workspace.project_search = "lua"
        workspace:render_footer()
        project_lines = vim.api.nvim_buf_get_lines(workspace.footer_buf, 0, -1, false)
        assert.are.equal("/: filter by project text   Backspace: clear filter", project_lines[2])

        workspace.focus = "queue"
        workspace.queue_search = "bug"
        workspace:render_footer()
        local queue_lines = vim.api.nvim_buf_get_lines(workspace.footer_buf, 0, -1, false)
        assert.are.equal("/: filter by prompt text   Backspace: clear filter", queue_lines[2])
        assert.is_nil(queue_lines[3]:find("x:", 1, true))
    end)
end)
