describe("clodex.ui.queue_workspace", function()
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
            confirm = function(_prompt, on_choice)
                on_choice(true)
            end,
            close_active_input = function() end,
        }
        Workspace = require("clodex.ui.queue_workspace")
    end)

    after_each(function()
        package.loaded["clodex.ui.queue_workspace"] = nil
        package.loaded["snacks.input"] = nil
        package.loaded["snacks.picker.select"] = nil
        package.loaded["clodex.ui.select"] = original_select
    end)

    it("closes the panel and shows the project terminal after implementing a queued item", function()
        local project = {
            name = "Test Project",
            root = "/tmp/test-project",
        }
        local item = {
            id = "item-1",
            title = "Implement prompt",
        }
        local close_count = 0
        local activated_root
        local shown_state
        local shown_target
        local current_state = {
            tabpage = 1,
        }

        local workspace = {
            app = {
                queue_actions = {
                    implement_queue_item = function(_, queued_project, item_id)
                        assert.are.same(project, queued_project)
                        assert.are.equal(item.id, item_id)
                        return true
                    end,
                },
                project_actions = {
                    activate_project = function(_, root)
                        activated_root = root
                    end,
                    show_target = function(_, state, target)
                        shown_state = state
                        shown_target = target
                        return true
                    end,
                },
                current_tab = function()
                    return current_state
                end,
                refresh_views = function() end,
            },
            selected_project = function()
                return project
            end,
            selected_queue_item = function()
                return item, "queued"
            end,
            close = function()
                close_count = close_count + 1
            end,
            refresh = function() end,
        }

        Workspace.implement_queue_item(workspace)

        vim.wait(100, function()
            return shown_target ~= nil
        end)

        assert.are.equal(1, close_count)
        assert.are.equal(project.root, activated_root)
        assert.are.same(current_state, shown_state)
        assert.are.same({
            kind = "project",
            project = project,
        }, shown_target)
    end)

    it("keeps delete bound to queue-side buffers and still deletes the selected prompt", function()
        local project = {
            name = "Test Project",
            root = "/tmp/test-project",
        }
        local item = {
            id = "item-1",
            title = "Delete prompt",
        }
        local deleted_project
        local deleted_item_id

        local workspace = {
            project_buf = vim.api.nvim_create_buf(false, true),
            queue_buf = vim.api.nvim_create_buf(false, true),
            footer_buf = vim.api.nvim_create_buf(false, true),
            app = {
                queue_actions = {
                    delete_queue_item = function(_, queued_project, item_id)
                        deleted_project = queued_project
                        deleted_item_id = item_id
                    end,
                },
            },
            selected_project = function()
                return project
            end,
            selected_queue_item = function()
                return item, "queued"
            end,
            refresh = function() end,
        }

        Workspace.attach_keymaps(workspace)

        vim.api.nvim_win_set_buf(0, workspace.project_buf)
        assert.are.equal("", vim.fn.maparg("d", "n"))

        vim.api.nvim_win_set_buf(0, workspace.footer_buf)
        assert.is_not.equal("", vim.fn.maparg("d", "n"))

        Workspace.delete_queue_item(workspace)
        vim.wait(100, function()
            return deleted_item_id ~= nil
        end)

        assert.are.equal(project, deleted_project)
        assert.are.equal(item.id, deleted_item_id)
    end)
end)
