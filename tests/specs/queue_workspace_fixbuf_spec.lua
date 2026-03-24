describe("clodex.ui.queue_workspace fixbuf", function()
    local Workspace
    local original_select
    local original_ui_win

    before_each(function()
        package.loaded["clodex.ui.queue_workspace"] = nil
        original_select = package.loaded["clodex.ui.select"]
        original_ui_win = package.loaded["clodex.ui.win"]

        package.loaded["clodex.ui.select"] = {
            input = function() end,
            confirm = function() end,
            close_active_input = function() end,
            has_active_input = function()
                return false
            end,
        }
    end)

    after_each(function()
        package.loaded["clodex.ui.queue_workspace"] = nil
        package.loaded["clodex.ui.select"] = original_select
        package.loaded["clodex.ui.win"] = original_ui_win
    end)

    it("keeps workspace panel buffers fixed while opening modal editors", function()
        local captured = {}

        package.loaded["clodex.ui.win"] = {
            create_buffer = function()
                return #captured + 10
            end,
            open = function(opts)
                captured[#captured + 1] = vim.deepcopy(opts)
                return {
                    win = #captured,
                }
            end,
        }

        Workspace = require("clodex.ui.queue_workspace")

        local workspace = Workspace.new({
            projects_for_queue_workspace = function()
                return {}
            end,
        }, {
            queue_workspace = {
                width = 1,
                height = 1,
                footer_height = 3,
            },
            time = {
                relative = true,
            },
        })

        workspace.configure_windows = function() end
        workspace.attach_keymaps = function() end
        workspace.attach_focus_tracking = function() end
        workspace.refresh = function() end

        workspace:open()

        assert.are.equal(3, #captured)
        assert.is_true(captured[1].fixbuf)
        assert.is_true(captured[2].fixbuf)
        assert.is_true(captured[3].fixbuf)
    end)
end)
