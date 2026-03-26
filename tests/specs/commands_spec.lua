describe("clodex.commands", function()
    local Commands
    local created
    local fake_clodex
    local notify_calls
    local original_notify
    local captured_prompt_context

    before_each(function()
        package.loaded["clodex.commands"] = nil
        package.loaded["clodex"] = nil
        package.loaded["clodex.app"] = nil

        created = {}
        notify_calls = {}
        captured_prompt_context = {
            selection_text = "print(value)",
            selection_start_row = 3,
            selection_end_row = 3,
            relative_path = "lua/example.lua",
        }
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
            open_project_todo_file = function() end,
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
            add_prompt_for_current_file_project = function() end,
        }

        package.loaded["clodex"] = fake_clodex
        package.loaded["clodex.app"] = {
            instance = function()
                return {
                    registry = {
                        list = function()
                            return {
                                {
                                    name = "demo",
                                    root = "/tmp/demo",
                                },
                                {
                                    name = "alpha",
                                    root = "/tmp/alpha",
                                },
                            }
                        end,
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
        package.loaded["clodex.prompt.context"] = {
            capture = function(opts)
                if opts and opts.selection_mode then
                    return vim.deepcopy(captured_prompt_context)
                end
                return nil
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
        assert.is_not_nil(created.ClodexPromptFile)
        assert.is_true(created.ClodexPrompt.opts.range)
    end)

    it("offers enum and project completion for todo commands", function()
        Commands.register()

        assert.are.same(
            {
                "/tmp/alpha",
                "/tmp/demo",
                "add",
                "all",
                "alpha",
                "bug",
                "demo",
                "error",
                "for",
                "implement",
                "implement-all",
                "implement_all",
                "pick",
            },
            created.ClodexTodo.opts.complete("", "ClodexTodo ", 11)
        )
        assert.are.same(
            { "/tmp/alpha", "/tmp/demo", "alpha", "demo", "for", "pick" },
            created.ClodexTodo.opts.complete("", "ClodexTodo implement ", 21)
        )
    end)

    it("offers enum and project completion for prompt commands", function()
        Commands.register()

        assert.is_true(vim.tbl_contains(created.ClodexPrompt.opts.complete("", "ClodexPrompt ", 13), "ask"))
        assert.is_true(vim.tbl_contains(created.ClodexPrompt.opts.complete("", "ClodexPrompt ", 13), "improvement"))
        assert.is_true(vim.tbl_contains(created.ClodexPrompt.opts.complete("", "ClodexPrompt ", 13), "fix"))
        assert.is_true(vim.tbl_contains(created.ClodexPrompt.opts.complete("", "ClodexPrompt ", 13), "feature"))
        assert.is_true(vim.tbl_contains(created.ClodexPrompt.opts.complete("", "ClodexPrompt ", 13), "restructure"))
        assert.is_true(vim.tbl_contains(created.ClodexPrompt.opts.complete("", "ClodexPrompt ", 13), "vision"))
        assert.is_true(vim.tbl_contains(created.ClodexPrompt.opts.complete("", "ClodexPrompt ", 13), "clean-up"))
        assert.is_true(vim.tbl_contains(created.ClodexPrompt.opts.complete("", "ClodexPrompt ", 13), "demo"))
        assert.are.same(
            { "/tmp/alpha", "/tmp/demo", "alpha", "demo", "for", "pick" },
            created.ClodexPrompt.opts.complete("", "ClodexPrompt ask ", 17)
        )
    end)

    it("dispatches project todo commands through the project action API", function()
        Commands.register()

        local called = false
        fake_clodex.open_project_todo_file = function()
            called = true
        end

        created.ClodexProject.handler({ args = "todo", fargs = { "todo" } })

        assert.is_true(called)
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

    it("offers explicit backend completion for the top-level command", function()
        Commands.register()

        assert.are.same({ "backend", "chat", "cli", "header", "history", "panel", "term", "term-header", "terminal", "terminal-header", "terminal_header" }, created.Clodex.opts.complete("", "Clodex ", 7))
        assert.are.same({ "codex", "opencode" }, created.Clodex.opts.complete("", "Clodex backend ", 15))
    end)

    it("routes explicit backend selection through the runtime backend setter", function()
        local called
        package.loaded["clodex.app"] = {
            instance = function()
                return {
                    registry = {
                        list = function()
                            return {}
                        end,
                    },
                    set_backend = function(_, backend)
                        called = backend
                    end,
                }
            end,
        }

        package.loaded["clodex.commands"] = nil
        Commands = require("clodex.commands")
        Commands.register()

        created.Clodex.handler({ args = "backend opencode", fargs = { "backend", "opencode" } })

        assert.are.equal("opencode", called)
    end)

    it("passes visual selection context to prompt commands", function()
        Commands.register()

        local called
        fake_clodex.add_prompt = function(opts)
            called = opts
        end

        created.ClodexPrompt.handler({
            args = "restructure",
            fargs = { "restructure" },
            range = 2,
        })

        assert.is_not_nil(called)
        assert.are.equal("restructure", called.category)
        assert.are.same(captured_prompt_context, called.context)
    end)

    it("routes current-file prompt commands through the current file project action", function()
        Commands.register()

        local called
        fake_clodex.add_prompt_for_current_file_project = function(opts)
            called = opts
        end

        created.ClodexPromptFile.handler({
            args = "restructure",
            fargs = { "restructure" },
            range = 2,
        })

        assert.is_not_nil(called)
        assert.are.equal("restructure", called.category)
        assert.are.same(captured_prompt_context, called.context)
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
