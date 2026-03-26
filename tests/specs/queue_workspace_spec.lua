describe("clodex.ui.queue_workspace", function()
    local Workspace
    local original_select
    local confirm_callbacks
    local active_input_open
    local input_callbacks
    local open_creator_calls
    local close_active_input_calls

    local function extmark_rows(buf, hl_group)
        local marks = vim.api.nvim_buf_get_extmarks(buf, -1, 0, -1, { details = true })
        local rows = {}
        for _, mark in ipairs(marks) do
            if mark[4].line_hl_group == hl_group then
                rows[#rows + 1] = mark[2]
            end
        end
        return rows
    end

    before_each(function()
        package.loaded["clodex.ui.queue_workspace"] = nil
        original_select = package.loaded["clodex.ui.select"]
        confirm_callbacks = {}
        input_callbacks = {}
        open_creator_calls = {}
        close_active_input_calls = 0
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
                confirm_callbacks[#confirm_callbacks + 1] = on_choice
            end,
            input = function(opts, on_confirm)
                input_callbacks[#input_callbacks + 1] = {
                    opts = opts,
                    on_confirm = on_confirm,
                }
            end,
            close_active_input = function()
                close_active_input_calls = close_active_input_calls + 1
                active_input_open = false
            end,
            has_active_input = function()
                return active_input_open
            end,
        }
        active_input_open = false
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
                        return true, "started"
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

    it("opens the selected project in a new tab", function()
        local project = {
            name = "Test Project",
            root = "/tmp/test-project",
        }
        local close_count = 0
        local opened_project
        local tabnew_count = 0
        local original_tabnew = vim.cmd.tabnew

        vim.cmd.tabnew = function()
            tabnew_count = tabnew_count + 1
        end

        local workspace = {
            app = {
                project_actions = {
                    open_project_workspace_target = function(_, opened)
                        opened_project = opened
                    end,
                },
            },
            selected_project = function()
                return project
            end,
            close = function()
                close_count = close_count + 1
            end,
        }

        Workspace.open_selected_project_in_new_tab(workspace)

        vim.wait(100, function()
            return opened_project ~= nil
        end)

        vim.cmd.tabnew = original_tabnew

        assert.are.equal(1, close_count)
        assert.are.equal(1, tabnew_count)
        assert.are.same(project, opened_project)
    end)

    it("allows implementing a planned item through the same action", function()
        local project = {
            name = "Test Project",
            root = "/tmp/test-project",
        }
        local item = {
            id = "item-1",
            title = "Implement from planned",
        }
        local implemented_item_id
        local close_count = 0

        local workspace = {
            app = {
                queue_actions = {
                    implement_queue_item = function(_, queued_project, item_id)
                        assert.are.same(project, queued_project)
                        implemented_item_id = item_id
                        return true, "started"
                    end,
                },
                project_actions = {
                    activate_project = function() end,
                    show_target = function()
                        return true
                    end,
                },
                current_tab = function()
                    return {}
                end,
            },
            selected_project = function()
                return project
            end,
            selected_queue_item = function()
                return item, "planned"
            end,
            close = function()
                close_count = close_count + 1
            end,
            refresh = function() end,
        }

        Workspace.implement_queue_item(workspace)

        assert.are.equal(item.id, implemented_item_id)
        assert.are.equal(1, close_count)
    end)

    it("keeps the workspace open when a planned item only moves forward because the project is busy", function()
        local project = {
            name = "Test Project",
            root = "/tmp/test-project",
        }
        local item = {
            id = "item-1",
            title = "Move forward from planned",
        }
        local close_count = 0
        local refresh_count = 0

        local workspace = {
            app = {
                queue_actions = {
                    implement_queue_item = function(_, queued_project, item_id)
                        assert.are.same(project, queued_project)
                        assert.are.equal(item.id, item_id)
                        return true, "queued"
                    end,
                },
            },
            selected_project = function()
                return project
            end,
            selected_queue_item = function()
                return item, "planned"
            end,
            close = function()
                close_count = close_count + 1
            end,
            refresh = function()
                refresh_count = refresh_count + 1
            end,
            queue_index = 3,
        }

        Workspace.implement_queue_item(workspace)

        assert.are.equal(0, close_count)
        assert.are.equal(1, refresh_count)
        assert.are.equal(1, workspace.queue_index)
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
            projects = { project },
            queue_index = 1,
            focus = "queue",
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
            close = function() end,
            open = function() end,
            refresh = function() end,
        }

        Workspace.attach_keymaps(workspace)

        vim.api.nvim_win_set_buf(0, workspace.project_buf)
        assert.are.equal("", vim.fn.maparg("d", "n"))

        vim.api.nvim_win_set_buf(0, workspace.footer_buf)
        assert.is_not.equal("", vim.fn.maparg("d", "n"))

        Workspace.delete_queue_item(workspace)
        vim.wait(100, function()
            return #confirm_callbacks == 1
        end)
        confirm_callbacks[1](true)
        vim.wait(100, function()
            return deleted_item_id ~= nil
        end)

        assert.are.equal(project, deleted_project)
        assert.are.equal(item.id, deleted_item_id)
    end)

    it("blocks insert-mode entry keys without shadowing queue actions", function()
        local workspace = {
            project_buf = vim.api.nvim_create_buf(false, true),
            queue_buf = vim.api.nvim_create_buf(false, true),
            footer_buf = vim.api.nvim_create_buf(false, true),
            projects = {},
            queue_index = 1,
            focus = "projects",
            app = {},
            selected_project = function()
                return nil
            end,
            selected_queue_item = function()
                return nil
            end,
            close = function() end,
            open = function() end,
            refresh = function() end,
            set_focus = function() end,
            move_selection = function() end,
            open_selected_project = function() end,
            set_current_project = function() end,
            activate_selected_project = function() end,
            deactivate_selected_project = function() end,
            add_todo = function() end,
            delete_project = function() end,
            prompt_project_search = function() end,
            clear_project_search = function() end,
            prompt_queue_search = function() end,
            clear_queue_search = function() end,
            edit_queue_item = function() end,
            implement_queue_item = function() end,
            move_queue_item = function() end,
            move_queue_item_back = function() end,
            mark_queue_item_not_working = function() end,
            move_queue_item_to_project = function() end,
            move_queue_item_to_adjacent_project = function() end,
            delete_queue_item = function() end,
        }

        Workspace.attach_keymaps(workspace)

        vim.api.nvim_win_set_buf(0, workspace.project_buf)
        for _, lhs in ipairs({ "i", "I", "o", "O", "R" }) do
            assert.is_not.equal("", vim.fn.maparg(lhs, "n", false, true).lhs)
        end

        vim.api.nvim_win_set_buf(0, workspace.queue_buf)
        assert.are.equal("i", vim.fn.maparg("i", "n", false, true).lhs)
        assert.are.equal("/", vim.fn.maparg("/", "n", false, true).lhs)
        assert.is_not.equal("", vim.fn.maparg("<BS>", "n", false, true).lhs)
        for _, lhs in ipairs({ "I", "o", "O", "R" }) do
            assert.is_not.equal("", vim.fn.maparg(lhs, "n", false, true).lhs)
        end

        vim.api.nvim_win_set_buf(0, workspace.footer_buf)
        assert.are.equal("i", vim.fn.maparg("i", "n", false, true).lhs)
        assert.are.equal("/", vim.fn.maparg("/", "n", false, true).lhs)
        assert.is_not.equal("", vim.fn.maparg("<BS>", "n", false, true).lhs)
        for _, lhs in ipairs({ "I", "o", "O", "R" }) do
            assert.is_not.equal("", vim.fn.maparg(lhs, "n", false, true).lhs)
        end
    end)

    it("keeps the workspace open while queue deletion confirmation is shown", function()
        local project = {
            name = "Test Project",
            root = "/tmp/test-project",
        }
        local item = {
            id = "item-1",
            title = "Delete prompt",
        }
        local close_count = 0
        local deleted_item_id
        local workspace = {
            queue_index = 2,
            focus = "queue",
            projects = { project },
            app = {
                queue_actions = {
                    delete_queue_item = function(_, queued_project, item_id)
                        assert.are.same(project, queued_project)
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
            close = function()
                close_count = close_count + 1
            end,
            refresh = function() end,
        }

        Workspace.delete_queue_item(workspace)

        vim.wait(100, function()
            return #confirm_callbacks == 1
        end)

        assert.are.equal(0, close_count)

        confirm_callbacks[1](true)

        vim.wait(100, function()
            return deleted_item_id ~= nil
        end)

        assert.are.equal(0, close_count)
        assert.are.equal(item.id, deleted_item_id)
        assert.are.equal(1, workspace.queue_index)
        assert.are.equal("queue", workspace.focus)
    end)

    it("treats queue deletion confirmation as a modal picker and closes active inputs first", function()
        local project = {
            name = "Test Project",
            root = "/tmp/test-project",
        }
        local item = {
            id = "item-1",
            title = "Delete prompt",
        }
        active_input_open = true

        local workspace = {
            queue_index = 1,
            focus = "queue",
            projects = { project },
            app = {
                queue_actions = {
                    delete_queue_item = function() end,
                },
            },
            selected_project = function()
                return project
            end,
            selected_queue_item = function()
                return item, "queued"
            end,
            close = function() end,
            refresh = function() end,
        }

        Workspace.delete_queue_item(workspace)

        vim.wait(100, function()
            return #confirm_callbacks == 1
        end)

        assert.are.equal(1, close_active_input_calls)
        assert.is_true(workspace.modal_input_open)

        confirm_callbacks[1](false)

        vim.wait(100, function()
            return workspace.modal_input_open == false
        end)
    end)

    it("keeps confirmation modal even when closing the previous input clears the modal flag", function()
        local project = {
            name = "Test Project",
            root = "/tmp/test-project",
        }
        local item = {
            id = "item-1",
            title = "Delete prompt",
        }
        local workspace = {
            queue_index = 1,
            focus = "queue",
            projects = { project },
            modal_input_open = true,
            app = {
                queue_actions = {
                    delete_queue_item = function() end,
                },
            },
            selected_project = function()
                return project
            end,
            selected_queue_item = function()
                return item, "queued"
            end,
            close = function() end,
            refresh = function() end,
        }

        package.loaded["clodex.ui.select"].close_active_input = function()
            close_active_input_calls = close_active_input_calls + 1
            workspace.modal_input_open = false
            active_input_open = false
        end

        active_input_open = true
        Workspace.delete_queue_item(workspace)

        vim.wait(100, function()
            return #confirm_callbacks == 1
        end)

        assert.are.equal(1, close_active_input_calls)
        assert.is_true(workspace.modal_input_open)
    end)

    it("clears project and queue filters when the workspace closes", function()
        local workspace = Workspace.new({}, {
            queue_workspace = {},
        })
        workspace.project_search = "demo"
        workspace.queue_search = "prompt"

        workspace:close()

        assert.are.equal("", workspace.project_search)
        assert.are.equal("", workspace.queue_search)
    end)

    it("offers a chat action when creating todos from the workspace", function()
        local project = {
            name = "Test Project",
            root = "/tmp/test-project",
        }
        local submitted
        local refresh_count = 0
        local workspace = {
            config = {
                storage = {
                    workspaces_dir = ".clodex",
                },
            },
            app = {
                prompt_actions = {
                    open_creator = function(_, queued_project, opts)
                        open_creator_calls[#open_creator_calls + 1] = {
                            project = queued_project,
                            opts = opts,
                        }
                        opts.on_submit({
                            title = "Fix parser",
                            details = "Handle nested tokens",
                        }, "chat")
                    end,
                    submit_prompt = function(_, queued_project, spec, action)
                        submitted = { project = queued_project, spec = spec, action = action }
                    end,
                },
            },
            selected_project = function()
                return project
            end,
            refresh = function()
                refresh_count = refresh_count + 1
            end,
            queue_index = 4,
        }

        Workspace.add_todo(workspace)

        assert.are.equal(1, #open_creator_calls)
        assert.are.equal("todo", open_creator_calls[1].opts.category)
        assert.are.same(project, submitted.project)
        assert.are.equal("Fix parser", submitted.spec.title)
        assert.are.equal("Handle nested tokens", submitted.spec.details)
        assert.are.equal("chat", submitted.action)
        assert.are.equal(1, refresh_count)
        assert.are.equal(1, workspace.queue_index)
    end)

    it("moves the queue selection highlight when keyboard navigation changes the selected item", function()
        local project = {
            name = "Test Project",
            root = "/tmp/test-project",
        }
        local items = {
            {
                id = "item-1",
                title = "First prompt",
                kind = "todo",
                prompt = "First prompt\n\nPreview line",
            },
            {
                id = "item-2",
                title = "Second prompt",
                kind = "todo",
                prompt = "Second prompt\n\nAnother preview",
            },
        }
        local workspace = Workspace.new({
            queue_summary = function()
                return {
                    project = project,
                    counts = {
                        planned = #items,
                        queued = 0,
                        implemented = 0,
                        history = 0,
                    },
                    queues = {
                        planned = items,
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
        workspace.projects = { project }
        workspace.project_index = 1
        workspace.focus = "queue"
        workspace.queue_buf = vim.api.nvim_create_buf(false, true)
        workspace.queue_win = vim.api.nvim_open_win(workspace.queue_buf, false, {
            relative = "editor",
            row = 1,
            col = 1,
            width = 80,
            height = 20,
            style = "minimal",
        })

        workspace:render_queue()

        local initial_rows = extmark_rows(workspace.queue_buf, "ClodexQueueSelectionActive")

        workspace:move_selection(1)

        local moved_rows = extmark_rows(workspace.queue_buf, "ClodexQueueSelectionActive")

        assert.are.same({ 1, 2, 3 }, initial_rows)
        assert.are.same({ 4, 5, 6 }, moved_rows)

        vim.api.nvim_win_close(workspace.queue_win, true)
    end)

    it("uses darker selection highlights for the focused picker", function()
        local project = {
            name = "Test Project",
            root = "/tmp/test-project",
        }
        local items = {
            {
                id = "item-1",
                title = "First prompt",
                kind = "todo",
                prompt = "First prompt\n\nPreview line",
            },
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
                        planned = #items,
                        queued = 0,
                        implemented = 0,
                        history = 0,
                    },
                    queues = {
                        planned = items,
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

        assert.are.same({ 0, 1 }, extmark_rows(workspace.project_buf, "ClodexQueueSelectionInactive"))
        assert.are.same({ 1, 2, 3 }, extmark_rows(workspace.queue_buf, "ClodexQueueSelectionActive"))
        assert.is_truthy(vim.wo[workspace.project_win].winhl:find("Normal:ClodexQueueFocusInactive", 1, true))
        assert.is_truthy(vim.wo[workspace.project_win].winhl:find("NormalFloat:ClodexQueueFocusInactive", 1, true))
        assert.is_truthy(vim.wo[workspace.project_win].winhl:find("FloatTitle:ClodexQueueInactiveBorder", 1, true))
        assert.is_truthy(vim.wo[workspace.queue_win].winhl:find("Normal:ClodexQueueFocusActive", 1, true))
        assert.is_truthy(vim.wo[workspace.queue_win].winhl:find("NormalFloat:ClodexQueueFocusActive", 1, true))
        assert.is_truthy(vim.wo[workspace.queue_win].winhl:find("FloatTitle:ClodexQueueActiveBorder", 1, true))

        vim.api.nvim_win_close(workspace.project_win, true)
        vim.api.nvim_win_close(workspace.queue_win, true)
    end)

    it("renders stored project icons in the project list", function()
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
            project_details_store = {
                get = function()
                    return { project_icon = "★", languages = {}, file_count = 0 }
                end,
                get_cached = function()
                    return { project_icon = "★", languages = {}, file_count = 0 }
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
        workspace.project_buf = vim.api.nvim_create_buf(false, true)

        workspace:render_projects()

        local lines = vim.api.nvim_buf_get_lines(workspace.project_buf, 0, 1, false)
        assert.is_truthy(lines[1]:find("★ Test Project", 1, true))
    end)

    it("loads stored project icons for the project list when the cache is cold", function()
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
            project_details_store = {
                get = function()
                    return { project_icon = "★", languages = {}, file_count = 0 }
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
        workspace.project_buf = vim.api.nvim_create_buf(false, true)

        workspace:render_projects()

        local lines = vim.api.nvim_buf_get_lines(workspace.project_buf, 0, 1, false)
        assert.is_truthy(lines[1]:find("★ Test Project", 1, true))
    end)

    it("filters queue items by prompt search text", function()
        local project = {
            name = "Test Project",
            root = "/tmp/test-project",
        }
        local items = {
            {
                id = "item-1",
                title = "Fix parser",
                details = "Adjust token handling",
                kind = "todo",
                prompt = "Fix parser\n\nAdjust token handling",
            },
            {
                id = "item-2",
                title = "Update docs",
                details = "Document queue search",
                kind = "todo",
                prompt = "Update docs\n\nDocument queue search",
            },
        }
        local workspace = Workspace.new({
            queue_summary = function()
                return {
                    project = project,
                    counts = {
                        planned = #items,
                        queued = 0,
                        implemented = 0,
                        history = 0,
                    },
                    queues = {
                        planned = items,
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
        workspace.projects = { project }
        workspace.project_index = 1
        workspace.queue_search = "token"
        workspace.queue_buf = vim.api.nvim_create_buf(false, true)
        workspace.queue_win = vim.api.nvim_open_win(workspace.queue_buf, false, {
            relative = "editor",
            row = 1,
            col = 1,
            width = 80,
            height = 20,
            style = "minimal",
        })

        workspace:render_queue()

        local lines = vim.api.nvim_buf_get_lines(workspace.queue_buf, 0, -1, false)
        assert.are.same({
            "Filter: token",
            "",
            "Planned (1)",
            "  Fix parser",
            "    Adjust token handling",
            "    Type: Improvement",
            "",
        }, lines)

        vim.api.nvim_win_close(workspace.queue_win, true)
    end)

    it("shows the filtered empty state when no prompts match", function()
        local project = {
            name = "Test Project",
            root = "/tmp/test-project",
        }
        local workspace = Workspace.new({
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
                                title = "Fix parser",
                                details = "Adjust token handling",
                                kind = "todo",
                                prompt = "Fix parser\n\nAdjust token handling",
                            },
                        },
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
        workspace.projects = { project }
        workspace.project_index = 1
        workspace.queue_search = "missing"
        workspace.queue_buf = vim.api.nvim_create_buf(false, true)
        workspace.queue_win = vim.api.nvim_open_win(workspace.queue_buf, false, {
            relative = "editor",
            row = 1,
            col = 1,
            width = 80,
            height = 20,
            style = "minimal",
        })

        workspace:render_queue()

        local lines = vim.api.nvim_buf_get_lines(workspace.queue_buf, 0, -1, false)
        assert.are.same({
            "Filter: missing",
            "",
            "No prompts match the current filter",
            "",
            "Press / to change the filter or Backspace to clear it",
        }, lines)

        vim.api.nvim_win_close(workspace.queue_win, true)
    end)

    it("shows implemented commit ids in the prompt preview", function()
        local project = {
            name = "Test Project",
            root = "/tmp/test-project",
        }
        local workspace = Workspace.new({
            queue_summary = function()
                return {
                    project = project,
                    counts = {
                        planned = 0,
                        queued = 0,
                        implemented = 1,
                        history = 0,
                    },
                    queues = {
                        planned = {},
                        queued = {},
                        implemented = {
                            {
                                id = "item-1",
                                title = "Fix parser",
                                details = "Adjust token handling",
                                prompt = "Fix parser\n\nAdjust token handling",
                                kind = "todo",
                                history_commits = { "abc1234" },
                            },
                        },
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
        workspace.projects = { project }
        workspace.project_index = 1
        workspace.queue_buf = vim.api.nvim_create_buf(false, true)
        workspace.queue_win = vim.api.nvim_open_win(workspace.queue_buf, false, {
            relative = "editor",
            row = 1,
            col = 1,
            width = 80,
            height = 20,
            style = "minimal",
        })

        workspace:render_queue()

        local lines = vim.api.nvim_buf_get_lines(workspace.queue_buf, 0, -1, false)
        assert.are.same({
            "Implemented (1)",
            "  Fix parser  [󰜘 abc1234]",
            "    Adjust token handling",
            "    Type: Improvement",
            "    󰜘 abc1234",
            "",
        }, lines)

        vim.api.nvim_win_close(workspace.queue_win, true)
    end)

    it("ignores malformed history metadata while rendering implemented items", function()
        local project = {
            name = "Test Project",
            root = "/tmp/test-project",
        }
        local workspace = Workspace.new({
            queue_summary = function()
                return {
                    project = project,
                    counts = {
                        planned = 0,
                        queued = 0,
                        implemented = 1,
                        history = 0,
                    },
                    queues = {
                        planned = {},
                        queued = {},
                        implemented = {
                            {
                                id = "item-1",
                                title = "Fix parser",
                                details = "Adjust token handling",
                                prompt = "Fix parser\n\nAdjust token handling",
                                kind = "todo",
                                history_summary = vim.NIL,
                                history_commits = { vim.NIL, "abc1234" },
                            },
                        },
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
        workspace.projects = { project }
        workspace.project_index = 1
        workspace.queue_buf = vim.api.nvim_create_buf(false, true)
        workspace.queue_win = vim.api.nvim_open_win(workspace.queue_buf, false, {
            relative = "editor",
            row = 1,
            col = 1,
            width = 80,
            height = 20,
            style = "minimal",
        })

        workspace:render_queue()

        local lines = vim.api.nvim_buf_get_lines(workspace.queue_buf, 0, -1, false)
        assert.are.same({
            "Implemented (1)",
            "  Fix parser  [󰜘 abc1234]",
            "    Adjust token handling",
            "    Type: Improvement",
            "    󰜘 abc1234",
            "",
        }, lines)

        vim.api.nvim_win_close(workspace.queue_win, true)
    end)

    it("uses the full editor footprint when the workspace is configured fullscreen", function()
        local original_list_uis = vim.api.nvim_list_uis
        vim.api.nvim_list_uis = function()
            return {
                {
                    width = 120,
                    height = 40,
                },
            }
        end

        local workspace = Workspace.new({}, {
            queue_workspace = {
                width = 1,
                height = 1,
                project_width = 0.3,
                footer_height = 3,
                preview_max_lines = 3,
                fold_preview = true,
                date_format = "ago",
            },
        })

        local row, col, project_width, queue_width, height, footer_height = workspace:layout()

        vim.api.nvim_list_uis = original_list_uis

        assert.are.equal(0, row)
        assert.are.equal(0, col)
        assert.are.equal(120, project_width + queue_width + 4)
        assert.are.equal(40, height + footer_height + 3)
    end)

    it("sizes the project list to fit the rendered project content", function()
        local original_list_uis = vim.api.nvim_list_uis
        vim.api.nvim_list_uis = function()
            return {
                {
                    width = 140,
                    height = 40,
                },
            }
        end

        local project = {
            name = "Project with a much longer display name than usual",
            root = "/tmp/project-with-a-much-longer-display-name-than-usual",
        }
        local workspace = Workspace.new({
            queue_summary = function()
                return {
                    project = project,
                    session_running = false,
                    counts = {
                        planned = 12,
                        queued = 3,
                        implemented = 5,
                        history = 7,
                    },
                    queues = {
                        planned = {},
                        queued = {},
                        implemented = {},
                        history = {},
                    },
                }
            end,
            project_details_store = {
                get_cached = function()
                    return {
                        file_count = 182,
                        remote_name = "origin",
                        languages = {
                            { name = "lua" },
                        },
                        last_file_modified_at = os.time(),
                    }
                end,
            },
        }, {
            queue_workspace = {
                width = 1,
                height = 1,
                project_width = 0.3,
                footer_height = 3,
                preview_max_lines = 3,
                fold_preview = true,
                date_format = "ago",
            },
        })
        workspace.projects = { project }

        local _, _, project_width, queue_width = workspace:layout()

        vim.api.nvim_list_uis = original_list_uis

        assert.is_true(project_width > 24)
        assert.is_true(queue_width >= 32)
        assert.is_true(project_width >= vim.fn.strdisplaywidth(project.name))
    end)

    it("renders a running prefix for active project sessions", function()
        local project = {
            name = "Busy Project",
            root = "/tmp/busy-project",
        }
        local workspace = Workspace.new({
            current_tab = function()
                return {}
            end,
            queue_summary = function()
                return {
                    project = project,
                    session_running = true,
                    counts = {
                        planned = 0,
                        queued = 1,
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
                width = 1,
                height = 1,
                project_width = 0.3,
                footer_height = 3,
                preview_max_lines = 3,
                fold_preview = true,
                date_format = "ago",
            },
        })
        workspace.projects = { project }
        workspace.project_index = 1
        workspace.project_buf = vim.api.nvim_create_buf(false, true)

        workspace:render_projects()

        local first_line = vim.api.nvim_buf_get_lines(workspace.project_buf, 0, 1, false)[1]
        assert.are.equal("󰚩 ", first_line:sub(1, #"󰚩 "))
    end)

    it("reflows the open workspace when the project content width changes", function()
        local original_list_uis = vim.api.nvim_list_uis
        vim.api.nvim_list_uis = function()
            return {
                {
                    width = 140,
                    height = 40,
                },
            }
        end

        local project = {
            name = "Short name",
            root = "/tmp/test-project",
        }
        local workspace = Workspace.new({
            current_tab = function()
                return {}
            end,
            projects_for_queue_workspace = function()
                return { project }
            end,
            queue_summary = function()
                return {
                    project = project,
                    session_running = false,
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
                width = 1,
                height = 1,
                project_width = 0.3,
                footer_height = 3,
                preview_max_lines = 3,
                fold_preview = true,
                date_format = "ago",
            },
        })
        workspace.projects = { project }
        workspace.project_index = 1
        workspace.project_buf = vim.api.nvim_create_buf(false, true)
        workspace.queue_buf = vim.api.nvim_create_buf(false, true)
        workspace.footer_buf = vim.api.nvim_create_buf(false, true)
        workspace.project_win = vim.api.nvim_open_win(workspace.project_buf, false, {
            relative = "editor",
            row = 1,
            col = 1,
            width = 24,
            height = 12,
            style = "minimal",
        })
        workspace.queue_win = vim.api.nvim_open_win(workspace.queue_buf, false, {
            relative = "editor",
            row = 1,
            col = 26,
            width = 60,
            height = 12,
            style = "minimal",
        })
        workspace.footer_win = vim.api.nvim_open_win(workspace.footer_buf, false, {
            relative = "editor",
            row = 14,
            col = 1,
            width = 85,
            height = 3,
            style = "minimal",
        })
        workspace:refresh(true)

        local initial_width = vim.api.nvim_win_get_width(workspace.project_win)

        workspace.project_search = "project filter that should force a wider project pane"
        workspace:refresh()
        local widened_width = vim.api.nvim_win_get_width(workspace.project_win)

        vim.api.nvim_list_uis = original_list_uis

        assert.is_true(widened_width > initial_width)

        vim.api.nvim_win_close(workspace.footer_win, true)
        vim.api.nvim_win_close(workspace.queue_win, true)
        vim.api.nvim_win_close(workspace.project_win, true)
    end)

    it("renders footer actions only for the focused picker", function()
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
        workspace.projects = { project }
        workspace.project_index = 1
        workspace.footer_buf = vim.api.nvim_create_buf(false, true)

        workspace.focus = "projects"
        workspace:render_footer()
        local project_lines = vim.api.nvim_buf_get_lines(workspace.footer_buf, 0, -1, false)
        assert.is_truthy(vim.startswith(project_lines[1], "s: set current project"))
        assert.is_nil(project_lines[1]:find("edit prompt", 1, true))

        workspace.focus = "queue"
        workspace:render_footer()
        local queue_lines = vim.api.nvim_buf_get_lines(workspace.footer_buf, 0, -1, false)
        assert.is_truthy(vim.startswith(queue_lines[1], "a: add prompt"))
        assert.is_nil(queue_lines[1]:find("start session", 1, true))
        assert.are.equal("/: filter by prompt text", queue_lines[2])
    end)

    it("updates footer actions when window focus moves between pickers", function()
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
        workspace.projects = { project }
        workspace.project_index = 1
        workspace.project_buf = vim.api.nvim_create_buf(false, true)
        workspace.queue_buf = vim.api.nvim_create_buf(false, true)
        workspace.footer_buf = vim.api.nvim_create_buf(false, true)
        workspace.project_win = vim.api.nvim_open_win(workspace.project_buf, true, {
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
        workspace.footer_win = vim.api.nvim_open_win(workspace.footer_buf, false, {
            relative = "editor",
            row = 14,
            col = 1,
            width = 81,
            height = 3,
            style = "minimal",
        })

        workspace:render_footer()
        workspace:attach_focus_tracking()

        local project_lines = vim.api.nvim_buf_get_lines(workspace.footer_buf, 0, -1, false)
        assert.is_truthy(vim.startswith(project_lines[1], "s: set current project"))

        vim.api.nvim_set_current_win(workspace.queue_win)
        vim.wait(100, function()
            local queue_lines = vim.api.nvim_buf_get_lines(workspace.footer_buf, 0, -1, false)
            return vim.startswith(queue_lines[1], "a: add prompt")
        end)

        local queue_lines = vim.api.nvim_buf_get_lines(workspace.footer_buf, 0, -1, false)
        assert.is_nil(queue_lines[1]:find("start session", 1, true))
        assert.is_truthy(queue_lines[1]:find("edit prompt", 1, true))
        assert.are.equal("/: filter by prompt text", queue_lines[2])

        workspace:clear_focus_tracking()
        vim.api.nvim_win_close(workspace.footer_win, true)
        vim.api.nvim_win_close(workspace.queue_win, true)
        vim.api.nvim_win_close(workspace.project_win, true)
    end)

    it("does not steal focus back from an active one-line input", function()
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
        workspace.projects = { project }
        workspace.project_index = 1
        workspace.focus = "queue"
        workspace.project_buf = vim.api.nvim_create_buf(false, true)
        workspace.queue_buf = vim.api.nvim_create_buf(false, true)
        workspace.footer_buf = vim.api.nvim_create_buf(false, true)
        workspace.project_win = vim.api.nvim_open_win(workspace.project_buf, false, {
            relative = "editor",
            row = 1,
            col = 1,
            width = 40,
            height = 12,
            style = "minimal",
        })
        workspace.queue_win = vim.api.nvim_open_win(workspace.queue_buf, true, {
            relative = "editor",
            row = 1,
            col = 42,
            width = 40,
            height = 12,
            style = "minimal",
        })
        workspace.footer_win = vim.api.nvim_open_win(workspace.footer_buf, false, {
            relative = "editor",
            row = 14,
            col = 1,
            width = 81,
            height = 3,
            style = "minimal",
        })

        local input_buf = vim.api.nvim_create_buf(false, true)
        local input_win = vim.api.nvim_open_win(input_buf, true, {
            relative = "editor",
            row = 3,
            col = 8,
            width = 30,
            height = 1,
            style = "minimal",
            border = "rounded",
        })
        active_input_open = true

        workspace:apply_focus()

        assert.are.equal(input_win, vim.api.nvim_get_current_win())

        active_input_open = false
        vim.api.nvim_win_close(input_win, true)
        vim.api.nvim_win_close(workspace.footer_win, true)
        vim.api.nvim_win_close(workspace.queue_win, true)
        vim.api.nvim_win_close(workspace.project_win, true)
    end)

    it("marks modal input as open before spawning the not-working note prompt", function()
        local project = {
            name = "Test Project",
            root = "/tmp/test-project",
        }
        local item = {
            id = "item-1",
            title = "Broken feature",
        }
        local rewind_called = false

        local workspace = {
            app = {
                queue_actions = {
                    rewind_queue_item = function()
                        rewind_called = true
                    end,
                },
            },
            selected_project = function()
                return project
            end,
            selected_queue_item = function()
                return item, "implemented"
            end,
            refresh = function() end,
            queue_index = 1,
            modal_input_open = false,
        }

        Workspace.mark_queue_item_not_working(workspace)

        assert.is_true(workspace.modal_input_open)
        assert.are.equal(1, #input_callbacks)
        assert.are.equal("Optional note", input_callbacks[1].opts.prompt)
        assert.is_false(rewind_called)

        input_callbacks[1].opts.win.on_close()

        assert.is_false(workspace.modal_input_open)
    end)

    it("updates the project filter while the input is being typed", function()
        local refresh_count = 0
        local workspace = {
            project_search = "",
            project_index = 3,
            queue_index = 4,
            focus = "queue",
            modal_input_open = false,
            refresh = function()
                refresh_count = refresh_count + 1
            end,
        }

        setmetatable(workspace, { __index = Workspace })

        workspace:prompt_project_search()

        assert.are.equal(1, #input_callbacks)
        assert.is_function(input_callbacks[1].opts.changed)

        input_callbacks[1].opts.changed("demo")

        assert.are.equal("demo", workspace.project_search)
        assert.are.equal(1, workspace.project_index)
        assert.are.equal(1, workspace.queue_index)
        assert.are.equal("projects", workspace.focus)
        assert.are.equal(1, refresh_count)
    end)

    it("re-renders footer actions when focus changes", function()
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
        workspace.projects = { project }
        workspace.project_index = 1
        workspace.project_buf = vim.api.nvim_create_buf(false, true)
        workspace.queue_buf = vim.api.nvim_create_buf(false, true)
        workspace.footer_buf = vim.api.nvim_create_buf(false, true)
        workspace.project_win = vim.api.nvim_open_win(workspace.project_buf, false, {
            relative = "editor",
            row = 1,
            col = 1,
            width = 30,
            height = 8,
            style = "minimal",
        })
        workspace.queue_win = vim.api.nvim_open_win(workspace.queue_buf, false, {
            relative = "editor",
            row = 1,
            col = 32,
            width = 50,
            height = 8,
            style = "minimal",
        })
        workspace.footer_win = vim.api.nvim_open_win(workspace.footer_buf, false, {
            relative = "editor",
            row = 10,
            col = 1,
            width = 81,
            height = 3,
            style = "minimal",
            title = " Project Actions ",
        })
        workspace:refresh()
        local initial_lines = vim.api.nvim_buf_get_lines(workspace.footer_buf, 0, -1, false)
        assert.is_truthy(vim.startswith(initial_lines[1], "s: set current project"))

        workspace:set_focus("queue")
        local queue_lines = vim.api.nvim_buf_get_lines(workspace.footer_buf, 0, -1, false)
        assert.is_truthy(vim.startswith(queue_lines[1], "a: add prompt"))
        assert.is_nil(queue_lines[1]:find("start session", 1, true))
        assert.is_truthy(queue_lines[1]:find("edit prompt", 1, true))
        assert.are.equal("/: filter by prompt text", queue_lines[2])

        vim.api.nvim_win_close(workspace.project_win, true)
        vim.api.nvim_win_close(workspace.queue_win, true)
        vim.api.nvim_win_close(workspace.footer_win, true)
    end)

    it("keeps the cursor out of the footer actions window", function()
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
        workspace.projects = { project }
        workspace.project_index = 1
        workspace.project_buf = vim.api.nvim_create_buf(false, true)
        workspace.queue_buf = vim.api.nvim_create_buf(false, true)
        workspace.footer_buf = vim.api.nvim_create_buf(false, true)
        workspace.project_win = vim.api.nvim_open_win(workspace.project_buf, false, {
            relative = "editor",
            row = 1,
            col = 1,
            width = 30,
            height = 8,
            style = "minimal",
        })
        workspace.queue_win = vim.api.nvim_open_win(workspace.queue_buf, false, {
            relative = "editor",
            row = 1,
            col = 32,
            width = 50,
            height = 8,
            style = "minimal",
        })
        workspace.footer_win = vim.api.nvim_open_win(workspace.footer_buf, false, {
            relative = "editor",
            row = 10,
            col = 1,
            width = 81,
            height = 3,
            style = "minimal",
        })

        workspace:refresh()
        assert.are.equal(workspace.project_win, vim.api.nvim_get_current_win())

        workspace:set_focus("queue")
        assert.are.equal(workspace.queue_win, vim.api.nvim_get_current_win())

        vim.api.nvim_win_close(workspace.project_win, true)
        vim.api.nvim_win_close(workspace.queue_win, true)
        vim.api.nvim_win_close(workspace.footer_win, true)
    end)

    it("shows implemented prompts from oldest to newest", function()
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
                        implemented = 2,
                        history = 0,
                    },
                    queues = {
                        planned = {},
                        queued = {},
                        implemented = {
                            {
                                id = "newer",
                                kind = "todo",
                                title = "Newer implemented prompt",
                                created_at = "2026-03-25T16:00:00Z",
                            },
                            {
                                id = "older",
                                kind = "todo",
                                title = "Older implemented prompt",
                                created_at = "2026-03-25T15:00:00Z",
                            },
                        },
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
        workspace.projects = { project }
        workspace.project_index = 1
        workspace.project_buf = vim.api.nvim_create_buf(false, true)
        workspace.queue_buf = vim.api.nvim_create_buf(false, true)
        workspace.footer_buf = vim.api.nvim_create_buf(false, true)
        workspace.project_win = vim.api.nvim_open_win(workspace.project_buf, false, {
            relative = "editor",
            row = 1,
            col = 1,
            width = 30,
            height = 8,
            style = "minimal",
        })
        workspace.queue_win = vim.api.nvim_open_win(workspace.queue_buf, false, {
            relative = "editor",
            row = 1,
            col = 32,
            width = 50,
            height = 12,
            style = "minimal",
        })
        workspace.footer_win = vim.api.nvim_open_win(workspace.footer_buf, false, {
            relative = "editor",
            row = 14,
            col = 1,
            width = 81,
            height = 3,
            style = "minimal",
        })

        workspace:refresh()

        local queue_lines = vim.api.nvim_buf_get_lines(workspace.queue_buf, 0, -1, false)
        local older_index = 0
        local newer_index = 0
        for index, line in ipairs(queue_lines) do
            if line == "  Older implemented prompt" then
                older_index = index
            elseif line == "  Newer implemented prompt" then
                newer_index = index
            end
        end

        assert.is_true(older_index > 0)
        assert.is_true(newer_index > 0)
        assert.is_true(older_index < newer_index)

        vim.api.nvim_win_close(workspace.project_win, true)
        vim.api.nvim_win_close(workspace.queue_win, true)
        vim.api.nvim_win_close(workspace.footer_win, true)
    end)

end)
