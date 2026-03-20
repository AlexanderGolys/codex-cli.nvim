describe("clodex.commands", function()
    local Commands
    local created
    local fake_clodex
    local notify_calls
    local original_notify

    before_each(function()
        package.loaded["clodex.commands"] = nil
        package.loaded["clodex"] = nil
        package.loaded["clodex.app"] = nil

        created = {}
        notify_calls = {}
        fake_clodex = {
            toggle = function() end,
            open_queue_workspace = function() end,
            open_history = function() end,
            toggle_backend = function() end,
            toggle_terminal_header = function() end,
            toggle_state_preview = function() end,
            toggle_mini_state_preview = function() end,
            debug_reload = function() end,
            add_project = function() end,
            open_project_readme_file = function() end,
            open_project_dictionary_file = function() end,
            open_project_cheatsheet_file = function() end,
            toggle_project_cheatsheet_preview = function() end,
            add_project_cheatsheet_item = function() end,
            open_project_notes_picker = function() end,
            create_project_note = function() end,
            open_project_bookmarks_picker = function() end,
            add_project_bookmark = function() end,
            add_todo = function() end,
            add_bug_todo = function() end,
            implement_next_queued_item = function() end,
            implement_all_queued_items = function() end,
            add_prompt = function() end,
            add_prompt_for_project = function() end,
        }

        package.loaded["clodex"] = fake_clodex
        package.loaded["clodex.app"] = {
            instance = function()
                return {
                    registry = {
                        find_by_name_or_root = function(_, value)
                            if value == "demo" then
                                return {
                                    name = "demo",
                                    root = "/tmp/demo",
                                }
                            end
                        end,
                    },
                }
            end,
        }

        original_notify = vim.notify
        vim.notify = function(message, level)
            notify_calls[#notify_calls + 1] = {
                message = message,
                level = level,
            }
        end

        _G._orig_create_user_command = vim.api.nvim_create_user_command
        vim.api.nvim_create_user_command = function(name, handler, opts)
            created[name] = {
                handler = handler,
                opts = opts,
            }
        end

        Commands = require("clodex.commands")
    end)

    after_each(function()
        vim.api.nvim_create_user_command = _G._orig_create_user_command
        _G._orig_create_user_command = nil
        vim.notify = original_notify
    end)

    it("registers the consolidated command families", function()
        Commands.register()

        assert.is_not_nil(created.Clodex)
        assert.is_not_nil(created.ClodexDebug)
        assert.is_not_nil(created.ClodexProject)
        assert.is_not_nil(created.ClodexTodo)
        assert.is_not_nil(created.ClodexPrompt)
    end)

    it("dispatches prompt kind aliases through the base prompt command", function()
        Commands.register()

        local called
        fake_clodex.add_prompt = function(opts)
            called = opts
        end

        created.ClodexPrompt.handler({ args = "explain", fargs = { "explain" } })

        assert.is_not_nil(called)
        assert.are.equal("ask", called.category)
    end)

    it("uses the explicit project when provided to todo commands", function()
        Commands.register()

        local called
        fake_clodex.implement_next_queued_item = function(opts)
            called = opts
        end

        created.ClodexTodo.handler({ args = "implement demo", fargs = { "implement", "demo" } })

        assert.is_not_nil(called)
        assert.are.equal("demo", called.project.name)
    end)

    it("reports invalid enum arguments instead of dispatching", function()
        Commands.register()

        local called = false
        fake_clodex.toggle_backend = function()
            called = true
        end

        created.Clodex.handler({ args = "bogus", fargs = { "bogus" } })

        assert.is_false(called)
        assert.is_true(#notify_calls > 0)
        assert.matches("invalid action 'bogus'", notify_calls[#notify_calls].message)
    end)
end)
