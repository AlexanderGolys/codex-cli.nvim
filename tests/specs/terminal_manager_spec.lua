describe("clodex.terminal.manager", function()
    local Manager

    before_each(function()
        package.loaded["clodex.terminal.manager"] = nil
        package.loaded["clodex.terminal.session"] = {
            new = function()
                error("session creation is not expected in this spec")
            end,
        }
        Manager = require("clodex.terminal.manager")
    end)

    after_each(function()
        package.loaded["clodex.terminal.manager"] = nil
        package.loaded["clodex.terminal.session"] = nil
    end)

    it("falls back to the current tab when showing a session for an invalid tab state", function()
        local manager = Manager.new({
            backend = "codex",
            terminal = {
                provider = "term",
                win = {},
            },
        })

        local opened = 0
        local expected_parent = vim.api.nvim_get_current_win()
        manager.open_window = function(_, session, parent_win)
            opened = opened + 1
            assert.are.equal(expected_parent, parent_win)
            return {
                win = vim.api.nvim_get_current_win(),
                on = function() end,
                hide = function() end,
            }
        end

        local archived = 0
        local state = {
            tabpage = 999999,
            window = nil,
            session_key = nil,
            has_visible_window = function()
                return false
            end,
            hide_window = function() end,
            clear_window = function() end,
            set_window = function(self, window, session_key)
                self.window = window
                self.session_key = session_key
            end,
        }
        local session = {
            key = "project:/tmp/demo",
            archive_history_chunk = function()
                archived = archived + 1
            end,
        }

        manager:show_in_tab(state, session)

        assert.are.equal(1, opened)
        assert.are.equal(vim.api.nvim_get_current_tabpage(), state.tabpage)
        assert.are.equal("project:/tmp/demo", state.session_key)
        assert.are.equal(0, archived)
    end)
end)
