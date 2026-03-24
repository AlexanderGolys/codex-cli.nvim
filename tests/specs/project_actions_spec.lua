local ProjectActions

describe("clodex.app.project_actions", function()
    local original_select
    local original_markdown_preview
    local original_notify
    local original_edit
    local picked_opts
    local warned_messages
    local error_messages

    before_each(function()
        package.loaded["clodex.app.project_actions"] = nil
        original_select = package.loaded["clodex.ui.select"]
        original_markdown_preview = package.loaded["clodex.ui.markdown_preview"]
        original_notify = package.loaded["clodex.util.notify"]
        original_edit = vim.cmd.edit
        picked_opts = nil
        warned_messages = {}
        error_messages = {}
        package.loaded["clodex.ui.select"] = {
            pick_project = function(_projects, opts, on_choice)
                picked_opts = opts
                on_choice({
                    name = "Beta",
                    root = "/tmp/beta",
                })
            end,
        }
        package.loaded["clodex.ui.markdown_preview"] = {
            new = function()
                return {}
            end,
        }
        package.loaded["clodex.util.notify"] = {
            warn = function(message)
                warned_messages[#warned_messages + 1] = message
            end,
            error = function(message)
                error_messages[#error_messages + 1] = message
            end,
            notify = function() end,
        }
        ProjectActions = require("clodex.app.project_actions")
    end)

    after_each(function()
        package.loaded["clodex.app.project_actions"] = nil
        package.loaded["clodex.ui.select"] = original_select
        package.loaded["clodex.ui.markdown_preview"] = original_markdown_preview
        package.loaded["clodex.util.notify"] = original_notify
        vim.cmd.edit = original_edit
    end)

    it("asks new tabs to choose an active project instead of keeping the inherited one", function()
        local refresh_count = 0
        local touched_project
        local state = {
            active_project_root = "/tmp/alpha",
            prompted = false,
            has_prompted_project = function(self)
                return self.prompted
            end,
            mark_prompted_project = function(self)
                self.prompted = true
            end,
            clear_active_project = function(self)
                self.active_project_root = nil
            end,
            set_active_project = function(self, root)
                self.active_project_root = root
            end,
            has_visible_window = function()
                return false
            end,
        }
        local actions = ProjectActions.new({
            registry = {
                list = function()
                    return {
                        { name = "Alpha", root = "/tmp/alpha" },
                        { name = "Beta", root = "/tmp/beta" },
                    }
                end,
            },
            project_details_store = {
                touch_activity = function(_, project)
                    touched_project = project
                end,
            },
            refresh_views = function()
                refresh_count = refresh_count + 1
            end,
        })

        actions:prompt_new_tab_active_project(state)

        assert.are.same("Active project for new tab", picked_opts.prompt)
        assert.is_true(picked_opts.include_none)
        assert.are.same("/tmp/alpha", picked_opts.active_root)
        assert.is_true(state.prompted)
        assert.are.same("/tmp/beta", state.active_project_root)
        assert.are.same("/tmp/beta", touched_project.root)
        assert.are.equal(1, refresh_count)
    end)


    it("keeps modified buffers open when opening a project workspace target", function()
        local root = vim.fn.tempname()
        local readme = root .. "/README.md"
        local edit_calls = 0
        local refreshed = 0
        local shown = 0
        local touched = 0
        local activated_root
        local state = {
            set_active_project = function(_, root_value)
                activated_root = root_value
            end,
        }
        vim.fn.mkdir(root, "p")
        vim.fn.writefile({ "# Demo" }, readme)
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { "unsaved" })
        vim.bo[0].modified = true
        vim.cmd.edit = function()
            edit_calls = edit_calls + 1
        end

        local actions = ProjectActions.new({
            current_tab = function()
                return state
            end,
            terminals = {
                ensure_project_session = function()
                    return { key = "project::demo" }
                end,
                get_session = function()
                    return { key = "project::demo" }
                end,
                show_in_tab = function()
                    shown = shown + 1
                end,
            },
            tabs = {
                list = function()
                    return { state }
                end,
            },
            project_details_store = {
                touch_activity = function()
                    touched = touched + 1
                end,
            },
            refresh_views = function()
                refreshed = refreshed + 1
            end,
        })

        actions:open_project_workspace_target({ name = "Demo", root = root })

        assert.are.equal(root, activated_root)
        assert.are.equal(0, edit_calls)
        assert.are.equal(1, shown)
        assert.are.equal(1, touched)
        assert.are.equal(2, refreshed)
        assert.are.same({ "Current buffer has unsaved changes; keeping it open instead of replacing it." }, warned_messages)

        vim.bo[0].modified = false
        vim.fn.delete(root, "rf")
    end)

    it("warns instead of crashing when the project README hits a swapfile conflict", function()
        local root = vim.fn.tempname()
        local readme = root .. "/README.md"
        local edit_calls = 0
        local refreshed = 0
        local shown = 0
        local touched = 0
        local activated_root
        local state = {
            set_active_project = function(_, root_value)
                activated_root = root_value
            end,
        }
        vim.fn.mkdir(root, "p")
        vim.fn.writefile({ "# Demo" }, readme)
        vim.bo[0].modified = false
        vim.cmd.edit = function()
            edit_calls = edit_calls + 1
            error("vim/_editor.lua:0: nvim_exec2(), line 1: Vim(edit):E325: ATTENTION")
        end

        local actions = ProjectActions.new({
            current_tab = function()
                return state
            end,
            terminals = {
                ensure_project_session = function()
                    return { key = "project::demo" }
                end,
                get_session = function()
                    return { key = "project::demo" }
                end,
                show_in_tab = function()
                    shown = shown + 1
                end,
            },
            tabs = {
                list = function()
                    return { state }
                end,
            },
            project_details_store = {
                touch_activity = function()
                    touched = touched + 1
                end,
            },
            refresh_views = function()
                refreshed = refreshed + 1
            end,
        })

        actions:open_project_workspace_target({ name = "Demo", root = root })

        assert.are.equal(root, activated_root)
        assert.are.equal(1, edit_calls)
        assert.are.equal(1, shown)
        assert.are.equal(1, touched)
        assert.are.equal(2, refreshed)
        assert.are.same({
            ("Swap file already exists for %s; keeping the current buffer unchanged."):format(readme),
        }, warned_messages)
        assert.are.same({}, error_messages)

        vim.fn.delete(root, "rf")
    end)

end)
