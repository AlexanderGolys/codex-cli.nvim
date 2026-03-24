describe("clodex.app.prompt_actions", function()
    local PromptActions
    local original_ui
    local original_assets
    local original_notify
    local multiline_calls

    before_each(function()
        package.loaded["clodex.app.prompt_actions"] = nil
        original_ui = package.loaded["clodex.ui.select"]
        original_assets = package.loaded["clodex.prompt.assets"]
        original_notify = package.loaded["clodex.util.notify"]
        multiline_calls = {}

        package.loaded["clodex.ui.select"] = {
            multiline_input = function(opts, on_confirm)
                multiline_calls[#multiline_calls + 1] = {
                    opts = vim.deepcopy(opts),
                    on_confirm = on_confirm,
                }
            end,
            input = function() end,
            pick_project = function() end,
            pick_text = function() end,
        }
        package.loaded["clodex.prompt.assets"] = {
            save_clipboard_image = function()
                return nil
            end,
        }
        package.loaded["clodex.util.notify"] = {
            notify = function() end,
        }

        PromptActions = require("clodex.app.prompt_actions")
    end)

    after_each(function()
        package.loaded["clodex.app.prompt_actions"] = nil
        package.loaded["clodex.ui.select"] = original_ui
        package.loaded["clodex.prompt.assets"] = original_assets
        package.loaded["clodex.util.notify"] = original_notify
    end)

    it("seeds prompt editors with the selected range when invoked from visual context", function()
        local actions = PromptActions.new({
            queue_actions = {
                add_project_todo = function() end,
            },
            queue_workspace = {
                prompt_title_width = function()
                    return 80
                end,
            },
        })
        local project = {
            name = "Demo",
            root = "/tmp/demo",
        }
        local context = {
            selection_text = "local value = 1",
            selection_start_row = 4,
            selection_end_row = 4,
            relative_path = "lua/demo.lua",
        }

        actions:prompt_for_category_kind(project, "refactor", {
            context = context,
        })

        assert.are.equal(1, #multiline_calls)
        assert.are.equal("Refactor prompt for Demo", multiline_calls[1].opts.prompt)
        assert.are.equal("Refactor implementation\n\n&selection", multiline_calls[1].opts.default)
        assert.are.same(context, multiline_calls[1].opts.context)
    end)
end)
