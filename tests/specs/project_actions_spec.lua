local ProjectActions

describe("clodex.app.project_actions", function()
    local original_select
    local original_markdown_preview
    local picked_opts

    before_each(function()
        package.loaded["clodex.app.project_actions"] = nil
        original_select = package.loaded["clodex.ui.select"]
        original_markdown_preview = package.loaded["clodex.ui.markdown_preview"]
        picked_opts = nil
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
        ProjectActions = require("clodex.app.project_actions")
    end)

    after_each(function()
        package.loaded["clodex.app.project_actions"] = nil
        package.loaded["clodex.ui.select"] = original_select
        package.loaded["clodex.ui.markdown_preview"] = original_markdown_preview
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
end)
