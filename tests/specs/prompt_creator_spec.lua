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

local function trigger_buffer_mapping(buf, lhs, mode)
    local map = vim.fn.maparg(lhs, mode or "n", false, true)
    assert.is_table(map)
    assert.is_function(map.callback)
    return map.callback()
end

describe("clodex.ui.prompt_creator", function()
    local Creator
    local creator
    local opened_windows
    local original_ui_win
    local original_notify
    local original_pumvisible
    local original_snacks

    before_each(function()
        package.loaded["clodex.ui.prompt_creator"] = nil
        package.loaded["clodex.ui.prompt_creator.layouts.composer"] = nil
        package.loaded["clodex.ui.prompt_creator.layouts.clipboard_preview"] = nil
        package.loaded["clodex.ui.prompt_creator.layouts.template_picker"] = nil
        package.loaded["snacks.input"] = {
            input = function() end,
        }
        package.loaded["snacks.picker.select"] = {
            select = function(_items, _opts, on_choice)
                on_choice(nil)
            end,
        }

        original_ui_win = package.loaded["clodex.ui.win"]
        original_notify = package.loaded["clodex.util.notify"]
        original_snacks = package.loaded["snacks"]
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
        package.loaded["snacks.input"] = nil
        package.loaded["snacks.picker.select"] = nil
        package.loaded["snacks"] = original_snacks
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

    it("centers tab rows and removes tab borders", function()
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

        local kind_line = vim.api.nvim_buf_get_lines(creator.kind_buf, 0, 1, false)[1]

        assert.are.equal("none", creator.kind_win.opts.border)
        assert.are.equal("none", creator.variant_win.opts.border)
        assert.is_truthy(kind_line:match("^%s+"))
        assert.is_truthy(kind_line:match("%s+$"))
    end)

    it("starts new prompts with a blank title field", function()
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

        local title = vim.api.nvim_buf_get_lines(creator.layout.title_buf, 0, 1, false)[1]

        assert.are.equal("", title)
    end)

    it("highlights footer keymaps", function()
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

        local groups = extmark_groups(creator.footer_buf)

        assert.is_true(vim.tbl_contains(groups, "ClodexPromptTodoTitle"))
    end)

    it("renders arrow icons in footer hints", function()
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

        local lines = vim.api.nvim_buf_get_lines(creator.footer_buf, 0, -1, false)

        assert.is_truthy(lines[1]:find("←/→", 1, true))
        assert.is_truthy(lines[1]:find("↑/↓", 1, true))
        assert.is_truthy(lines[2]:find("Ctrl-←/→", 1, true))
        assert.is_nil(lines[1]:find("Left/Right", 1, true))
        assert.is_nil(lines[1]:find("Up/Down", 1, true))
    end)

    it("hides normal-mode navigation hints while editing in insert mode", function()
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

        creator.in_insert_mode = function()
            return true
        end
        creator:render_footer()

        local lines = vim.api.nvim_buf_get_lines(creator.footer_buf, 0, -1, false)

        assert.is_truthy(lines[1]:find("Tab/Shift%-Tab", 1))
        assert.is_truthy(lines[2]:find("Ctrl-←/→", 1, true))
        assert.is_nil(lines[1]:find("←/→", 1, true))
        assert.is_nil(lines[1]:find("↑/↓", 1, true))
    end)

    it("matches prompt border and footer keymap colors to the active kind", function()
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

        assert.is_truthy(vim.wo[creator.footer_win.win].winhl:find("FloatBorder:ClodexPromptTodoTitle", 1, true))
        assert.is_truthy(vim.tbl_contains(extmark_groups(creator.footer_buf), "ClodexPromptTodoTitle"))

        creator:switch_kind(1)

        wait_for(function()
            return creator.state.kind == "bug"
        end)

        assert.is_truthy(vim.wo[creator.footer_win.win].winhl:find("FloatBorder:ClodexPromptBugTitle", 1, true))
        assert.is_truthy(vim.tbl_contains(extmark_groups(creator.footer_buf), "ClodexPromptBugTitle"))
    end)

    it("supports context token highlighting and completion in the composer body", function()
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
            context = {
                file_path = "/tmp/demo/lua/demo.lua",
                project_root = "/tmp/demo",
                relative_path = "lua/demo.lua",
                cursor_row = 7,
                current_word = "token",
            },
            initial_kind = "todo",
            initial_draft = {
                title = "",
                details = "Explain &file",
            },
            on_submit = function() end,
        })

        local body_buf = creator.layout.body_buf
        local groups = extmark_groups(body_buf)

        assert.is_true(vim.tbl_contains(groups, "ClodexPromptEditorContext"))

        vim.api.nvim_set_current_win(creator.layout.body_win.win)
        vim.api.nvim_win_set_cursor(creator.layout.body_win.win, { 1, 13 })

        local items = require("clodex.ui.select").prompt_context_complete(0, "&f")
        assert.is_true(#items > 0)
        assert.are.equal("&file", items[1].word)
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
        local footer_insert_maps = vim.api.nvim_buf_get_keymap(creator.footer_buf, "i")
        local has_right_switch = false
        local has_left_switch = false
        local has_h_switch = false
        local has_l_switch = false
        local has_old_left_switch = false
        local has_old_right_switch = false
        local has_insert_left_switch = false
        local has_insert_right_switch = false

        for _, map in ipairs(footer_maps) do
            if map.lhs == "<Right>" then
                has_right_switch = true
            elseif map.lhs == "<Left>" then
                has_left_switch = true
            elseif map.lhs == "h" then
                has_h_switch = true
            elseif map.lhs == "l" then
                has_l_switch = true
            elseif map.lhs == ">" then
                has_old_right_switch = true
            elseif map.lhs == "<" then
                has_old_left_switch = true
            end
        end
        for _, map in ipairs(footer_insert_maps) do
            if map.lhs == "<C-Left>" then
                has_insert_left_switch = true
            elseif map.lhs == "<C-Right>" then
                has_insert_right_switch = true
            end
        end

        assert.is_true(has_right_switch)
        assert.is_true(has_left_switch)
        assert.is_true(has_h_switch)
        assert.is_true(has_l_switch)
        assert.is_true(has_insert_left_switch)
        assert.is_true(has_insert_right_switch)
        assert.is_false(has_old_left_switch)
        assert.is_false(has_old_right_switch)

        vim.api.nvim_set_current_win(creator.footer_win.win)
        creator:switch_kind(1)

        wait_for(function()
            return creator.state.kind == "freeform"
                and vim.api.nvim_get_current_win() == creator.footer_win.win
        end)
    end)

    it("does not bind insert-mode letters or arrows to project switching", function()
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

        local title_insert_maps = vim.api.nvim_buf_get_keymap(creator.layout.title_buf, "i")
        local body_insert_maps = vim.api.nvim_buf_get_keymap(creator.layout.body_buf, "i")

        for _, map in ipairs(title_insert_maps) do
            assert.are_not.equal("<Left>", map.lhs)
            assert.are_not.equal("h", map.lhs)
            assert.are_not.equal("<Down>", map.lhs)
        end
        for _, map in ipairs(body_insert_maps) do
            assert.are_not.equal("<Up>", map.lhs)
        end
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

        assert.is_nil(creator.layout.note_win)
        assert.are.equal(" Comment ", creator.layout.title_win.opts.title)
        assert.are.same({ creator.layout.title_buf, creator.layout.preview_buf }, creator.layout:buffers())
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

    it("removes the image preview when switching to a draft without an image", function()
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
                title = "Todo with image",
                details = "Preview should disappear on another kind",
                image_path = "/tmp/demo.png",
            },
            on_submit = function() end,
        })

        assert.is_not_nil(creator.preview_win)
        assert.is_true(creator.preview_win:valid())

        creator:switch_kind(1)

        wait_for(function()
            return creator.preview_win == nil and creator.state.image_path == nil
        end)
    end)

    it("defaults the target project picker to the active project", function()
        local alpha = { name = "Alpha", root = "/tmp/alpha" }
        local beta = { name = "Beta", root = "/tmp/beta" }

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
            project = alpha,
            projects = { alpha, beta },
            active_project_root = beta.root,
            context = {
                file_path = "/tmp/alpha/lua/demo.lua",
                relative_path = "lua/demo.lua",
            },
            initial_kind = "todo",
            on_submit = function() end,
        })

        assert.are.equal(beta.root, creator.project.root)
        assert.are.equal(beta.root, creator.state.project.root)
        assert.are.equal(beta.root, creator.state.context.project_root)
        assert.are.equal(2, creator.project_index)
        assert.are.equal(creator.layout.title_win.win, vim.api.nvim_get_current_win())
    end)

    it("extends title and project-list navigation to switch focus and target project", function()
        local submitted_project
        local alpha = { name = "Alpha", root = "/tmp/alpha" }
        local beta = { name = "Beta", root = "/tmp/beta" }

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
            project = alpha,
            projects = { alpha, beta },
            active_project_root = alpha.root,
            context = {
                file_path = "/tmp/alpha/lua/demo.lua",
                relative_path = "lua/demo.lua",
            },
            initial_kind = "todo",
            initial_draft = {
                title = "Route prompt",
                details = "Send it to another project",
            },
            on_submit = function(_, _, project)
                submitted_project = project
                return false
            end,
        })

        vim.api.nvim_set_current_win(creator.layout.title_win.win)
        vim.cmd.stopinsert()
        trigger_buffer_mapping(creator.layout.title_buf, "<Left>")

        wait_for(function()
            return vim.api.nvim_get_current_win() == creator.project_win.win
        end)

        trigger_buffer_mapping(creator.project_buf, "<Down>")

        wait_for(function()
            return creator.project.root == beta.root and creator.state.context.project_root == beta.root
        end)

        trigger_buffer_mapping(creator.project_buf, "<Right>")

        wait_for(function()
            return vim.api.nvim_get_current_win() == creator.layout.title_win.win
        end)

        creator:submit("queue")

        wait_for(function()
            return submitted_project ~= nil
        end)

        assert.are.equal(beta.root, submitted_project.root)
    end)

    it("includes the project list in the tab cycle", function()
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

        trigger_buffer_mapping(creator.layout.title_buf, "<Tab>")

        wait_for(function()
            return vim.api.nvim_get_current_win() == creator.layout.body_win.win
        end)

        trigger_buffer_mapping(creator.layout.body_buf, "<Tab>")

        wait_for(function()
            return vim.api.nvim_get_current_win() == creator.project_win.win
        end)

        trigger_buffer_mapping(creator.project_buf, "<Tab>")

        wait_for(function()
            return vim.api.nvim_get_current_win() == creator.layout.title_win.win
        end)
    end)

    it("renders stored project icons in the project picker", function()
        creator = Creator.open({
            app = {
                config = {
                    get = function()
                        return {
                            storage = { workspaces_dir = "/tmp" },
                        }
                    end,
                },
                project_details_store = {
                    get_cached = function(_, project)
                        if project.root == "/tmp/alpha" then
                            return { project_icon = "★" }
                        end
                    end,
                },
            },
            project = { name = "Alpha", root = "/tmp/alpha" },
            projects = {
                { name = "Alpha", root = "/tmp/alpha" },
                { name = "Beta", root = "/tmp/beta" },
            },
            active_project_root = "/tmp/alpha",
            initial_kind = "todo",
            on_submit = function() end,
        })

        local lines = vim.api.nvim_buf_get_lines(creator.project_buf, 0, -1, false)

        assert.are.equal(" ★ Alpha", lines[1])
        assert.are.equal(" Beta", lines[2])
    end)

    it("limits clipboard image previews to the preview pane size", function()
        local attached_opts
        package.loaded["snacks"] = {
            input = { input = function() end },
            picker = {
                select = function(_items, _opts, on_choice)
                    on_choice(nil)
                end,
            },
            image = {
                buf = {
                    attach = function(_buf, opts)
                        attached_opts = opts
                    end,
                },
            },
        }

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
                title = "Todo with image",
                image_path = "/tmp/demo.png",
            },
            on_submit = function() end,
        })

        assert.is_not_nil(attached_opts)
        assert.are.equal("/tmp/demo.png", attached_opts.src)
        assert.are.equal(creator:preview_width() - 2, attached_opts.max_width)
        assert.are.equal(creator:preview_height() - 2, attached_opts.max_height)

        package.loaded["snacks"] = nil
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
