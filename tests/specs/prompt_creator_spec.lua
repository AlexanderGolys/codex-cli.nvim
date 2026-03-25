local function wait_for(predicate)
    assert(vim.wait(1000, predicate, 10), "timed out waiting for prompt creator state")
end

local function extmark_groups(buf)
    local groups = {}
    for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, -1, 0, -1, { details = true })) do
        groups[#groups + 1] = mark[4].hl_group
    end
    return groups
end

describe("clodex.ui.prompt_creator", function()
    local Creator
    local creator
    local opened_windows
    local original_ui_win
    local original_notify
    local original_pumvisible

    before_each(function()
        package.loaded["clodex.ui.prompt_creator"] = nil
        package.loaded["clodex.ui.prompt_creator.layouts.composer"] = nil
        package.loaded["clodex.ui.prompt_creator.layouts.clipboard_preview"] = nil
        package.loaded["clodex.ui.prompt_creator.layouts.template_picker"] = nil

        original_ui_win = package.loaded["clodex.ui.win"]
        original_notify = package.loaded["clodex.util.notify"]
        original_pumvisible = vim.fn.pumvisible
        opened_windows = {}

        package.loaded["clodex.ui.win"] = {
            create_buffer = function(opts)
                local buf = vim.api.nvim_create_buf(false, true)
                local preset = opts and opts.preset or "scratch"
                if preset == "markdown" then
                    vim.bo[buf].filetype = "markdown"
                    vim.bo[buf].modifiable = true
                elseif preset == "text" then
                    vim.bo[buf].modifiable = true
                else
                    vim.bo[buf].modifiable = false
                end
                vim.bo[buf].buftype = "nofile"
                vim.bo[buf].bufhidden = "wipe"
                vim.bo[buf].swapfile = false
                return buf
            end,
            open = function(opts)
                local object = {
                    buf = opts.buf,
                    opts = opts,
                }
                object.win = vim.api.nvim_open_win(opts.buf, opts.enter or false, {
                    relative = "editor",
                    style = "minimal",
                    border = opts.border or "none",
                    title = opts.title,
                    title_pos = opts.title_pos,
                    row = type(opts.row) == "function" and opts.row() or opts.row or 0,
                    col = type(opts.col) == "function" and opts.col() or opts.col or 0,
                    width = type(opts.width) == "function" and opts.width() or opts.width or 1,
                    height = type(opts.height) == "function" and opts.height() or opts.height or 1,
                })

                for key, value in pairs(opts.bo or {}) do
                    vim.bo[opts.buf][key] = value
                end

                function object:valid()
                    return vim.api.nvim_win_is_valid(self.win)
                end

                function object:update()
                    if not self:valid() then
                        return
                    end
                    vim.api.nvim_win_set_config(self.win, {
                        relative = "editor",
                        row = type(self.opts.row) == "function" and self.opts.row() or self.opts.row or 0,
                        col = type(self.opts.col) == "function" and self.opts.col() or self.opts.col or 0,
                        width = type(self.opts.width) == "function" and self.opts.width() or self.opts.width or 1,
                        height = type(self.opts.height) == "function" and self.opts.height() or self.opts.height or 1,
                    })
                end

                function object:close()
                    if self:valid() then
                        vim.api.nvim_win_close(self.win, true)
                    end
                end

                opened_windows[#opened_windows + 1] = object
                return object
            end,
        }
        package.loaded["clodex.util.notify"] = {
            notify = function() end,
            warn = function() end,
        }

        Creator = require("clodex.ui.prompt_creator")
    end)

    after_each(function()
        if creator then
            pcall(function()
                creator:close()
            end)
        end
        for _, window in ipairs(opened_windows or {}) do
            if window:valid() then
                window:close()
            end
        end

        package.loaded["clodex.ui.prompt_creator"] = nil
        package.loaded["clodex.ui.prompt_creator.layouts.composer"] = nil
        package.loaded["clodex.ui.prompt_creator.layouts.clipboard_preview"] = nil
        package.loaded["clodex.ui.prompt_creator.layouts.template_picker"] = nil
        package.loaded["clodex.ui.win"] = original_ui_win
        package.loaded["clodex.util.notify"] = original_notify
        vim.fn.pumvisible = original_pumvisible
    end)

    it("closes the footer when a prompt editor window is destroyed", function()
        creator = Creator.open({
            app = {
                config = {
                    get = function()
                        return {
                            storage = { workspaces_dir = "/tmp" },
                        }
                    end,
                },
            },
            project = {
                name = "Demo",
                root = "/tmp/demo",
            },
            initial_kind = "todo",
            on_submit = function() end,
        })

        local title_win = creator.layout.title_win
        local footer_win = creator.footer_win

        assert.is_true(title_win:valid())
        assert.is_true(footer_win:valid())

        vim.api.nvim_win_close(title_win.win, true)

        wait_for(function()
            return creator.footer_win == nil and creator.kind_win == nil and creator.layout.title_win == nil
        end)
    end)

    it("renders active and inactive tab highlights", function()
        creator = Creator.open({
            app = {
                config = {
                    get = function()
                        return {
                            storage = { workspaces_dir = "/tmp" },
                        }
                    end,
                },
            },
            project = {
                name = "Demo",
                root = "/tmp/demo",
            },
            initial_kind = "todo",
            on_submit = function() end,
        })

        local groups = extmark_groups(creator.kind_buf)

        assert.is_true(vim.tbl_contains(groups, "ClodexPromptTodoTitleActive"))
        assert.is_true(vim.tbl_contains(groups, "ClodexPromptBugTitle"))
    end)

    it("changes kind tabs from the footer and keeps normal-mode focus in the editor", function()
        creator = Creator.open({
            app = {
                config = {
                    get = function()
                        return {
                            storage = { workspaces_dir = "/tmp" },
                        }
                    end,
                },
            },
            project = {
                name = "Demo",
                root = "/tmp/demo",
            },
            initial_kind = "todo",
            on_submit = function() end,
        })

        vim.api.nvim_set_current_win(creator.layout.body_win.win)
        vim.cmd.stopinsert()
        creator:switch_kind(1)

        wait_for(function()
            return creator.state.kind == "bug"
                and creator.layout.body_win
                and creator.layout.body_win:valid()
                and vim.api.nvim_get_current_win() == creator.layout.body_win.win
                and vim.api.nvim_get_mode().mode == "n"
        end)

        local footer_maps = vim.api.nvim_buf_get_keymap(creator.footer_buf, "n")
        local has_footer_switch = false
        for _, map in ipairs(footer_maps) do
            if map.lhs == ">" then
                has_footer_switch = true
                break
            end
        end
        assert.is_true(has_footer_switch)

        vim.api.nvim_set_current_win(creator.footer_win.win)
        creator:switch_kind(1)

        wait_for(function()
            return creator.state.kind == "freeform"
                and vim.api.nvim_get_current_win() == creator.footer_win.win
        end)
    end)

    it("changes tabs by mouse hit testing", function()
        creator = Creator.open({
            app = {
                config = {
                    get = function()
                        return {
                            storage = { workspaces_dir = "/tmp" },
                        }
                    end,
                },
            },
            project = {
                name = "Demo",
                root = "/tmp/demo",
            },
            initial_kind = "bug",
            on_submit = function() end,
        })

        creator:activate_kind_tab_at(creator.kind_tab_spans[3].start_col + 1)

        wait_for(function()
            return creator.state.kind == "freeform"
        end)

        creator:switch_kind(-1)
        wait_for(function()
            return creator.state.kind == "bug"
        end)

        creator:activate_variant_tab_at(creator.variant_tab_spans[2].start_col + 1)

        wait_for(function()
            return creator.state.variant == "clipboard_error"
        end)
    end)

    it("keeps completion popup navigation in the details field", function()
        creator = Creator.open({
            app = {
                config = {
                    get = function()
                        return {
                            storage = { workspaces_dir = "/tmp" },
                        }
                    end,
                },
            },
            project = {
                name = "Demo",
                root = "/tmp/demo",
            },
            initial_kind = "bug",
            on_submit = function() end,
        })

        local body_win = creator.layout.body_win

        vim.api.nvim_set_current_win(body_win.win)
        vim.api.nvim_win_set_cursor(body_win.win, { 1, 0 })
        vim.cmd.startinsert()
        vim.fn.pumvisible = function()
            return 1
        end

        vim.api.nvim_input(vim.keycode("<Up>"))

        wait_for(function()
            return vim.api.nvim_get_current_win() == body_win.win
        end)

        assert.are.equal(body_win.win, vim.api.nvim_get_current_win())
    end)

    it("keeps the creator open when submit requests it", function()
        local submitted_spec
        local submitted_action

        creator = Creator.open({
            app = {
                config = {
                    get = function()
                        return {
                            storage = { workspaces_dir = "/tmp" },
                        }
                    end,
                },
            },
            project = {
                name = "Demo",
                root = "/tmp/demo",
            },
            initial_kind = "todo",
            initial_draft = {
                title = "Keep prompt",
                details = "Preserve footer",
            },
            on_submit = function(spec, action)
                submitted_spec = spec
                submitted_action = action
                return false
            end,
        })

        creator:submit("exec")

        wait_for(function()
            return submitted_action == "exec"
                and submitted_spec ~= nil
                and creator.footer_win ~= nil
                and creator.footer_win:valid()
                and creator.layout.title_win ~= nil
                and creator.layout.title_win:valid()
        end)

        assert.are.equal("Keep prompt", submitted_spec.title)
        assert.are.equal("Preserve footer", submitted_spec.details)
    end)
end)
