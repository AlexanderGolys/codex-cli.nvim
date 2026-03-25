local TITLE_HEIGHT_WITH_BORDER = 3

local function wait_for(predicate)
    vim.wait(1000, predicate, 10)
end

describe("clodex.ui.select", function()
    local select
    local opened_windows
    local input_windows
    local input_opts_calls
    local original_ui_win
    local original_completeopt
    local picker_select_calls
    local picker_select_opts

    before_each(function()
        package.loaded["clodex.ui.select"] = nil
        original_ui_win = package.loaded["clodex.ui.win"]
        original_completeopt = vim.o.completeopt
        opened_windows = {}
        input_windows = {}
        input_opts_calls = {}
        picker_select_calls = {}
        picker_select_opts = {}
        package.loaded["snacks.input"] = {
            input = function(opts, _on_confirm)
                input_opts_calls[#input_opts_calls + 1] = vim.deepcopy(opts)
                local buf = vim.api.nvim_create_buf(false, true)
                vim.bo[buf].buftype = "prompt"
                local win = vim.api.nvim_open_win(buf, true, {
                    relative = "editor",
                    style = "minimal",
                    row = 1,
                    col = 1,
                    width = 40,
                    height = 1,
                    border = "rounded",
                })
                local object = {
                    buf = buf,
                    win = win,
                }

                function object:valid()
                    return vim.api.nvim_win_is_valid(self.win)
                end

                function object:focus()
                    vim.api.nvim_set_current_win(self.win)
                end

                function object:close()
                    if self:valid() then
                        vim.api.nvim_win_close(self.win, true)
                    end
                end

                input_windows[#input_windows + 1] = object
                return object
            end,
        }
        package.loaded["snacks.picker.select"] = {
            select = function(_items, opts, on_choice)
                local picker = {
                    closed = false,
                    opts = {
                        focus = "list",
                        enter = true,
                    },
                    focused = {},
                }

                function picker:focus(target, opts)
                    self.focused[#self.focused + 1] = {
                        target = target,
                        opts = opts,
                    }
                end

                picker_select_calls[#picker_select_calls + 1] = picker
                picker_select_opts[#picker_select_opts + 1] = vim.deepcopy(opts)
                on_choice(nil)
                return picker
            end,
        }

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
                for key, value in pairs(opts and opts.bo or {}) do
                    vim.bo[buf][key] = value
                end
                return buf
            end,
            apply_theme = function() end,
            open = function(opts)
                local row = type(opts.row) == "function" and opts.row() or opts.row or 0
                local col = type(opts.col) == "function" and opts.col() or opts.col or 0
                local width = type(opts.width) == "function" and opts.width() or opts.width or 1
                local height = type(opts.height) == "function" and opts.height() or opts.height or 1
                local win = vim.api.nvim_open_win(opts.buf, opts.enter or false, {
                    relative = "editor",
                    style = "minimal",
                    border = opts.border or "none",
                    title = opts.title,
                    title_pos = opts.title_pos,
                    row = row,
                    col = col,
                    width = width,
                    height = height,
                    zindex = opts.zindex,
                })

                for key, value in pairs(opts.wo or {}) do
                    vim.wo[win][key] = value
                end
                for key, value in pairs(opts.bo or {}) do
                    vim.bo[opts.buf][key] = value
                end

                local object = {
                    win = win,
                    buf = opts.buf,
                    opts = opts,
                }

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

        select = require("clodex.ui.select")
    end)

    after_each(function()
        for _, window in ipairs(opened_windows or {}) do
            if window:valid() then
                window:close()
            end
        end
        for _, window in ipairs(input_windows or {}) do
            if window:valid() then
                window:close()
            end
        end
        package.loaded["clodex.ui.select"] = nil
        package.loaded["clodex.ui.win"] = original_ui_win
        package.loaded["snacks.input"] = nil
        package.loaded["snacks.picker.select"] = nil
        vim.o.completeopt = original_completeopt
    end)

    it("switches focus between title and details with Tab and Up, and keeps fields visually stacked", function()
        select.multiline_input({
            prompt = "Test prompt",
            default = "Test title\n\nfirst line\nsecond line",
        }, function() end)

        wait_for(function()
            return #opened_windows == 3 and vim.api.nvim_get_current_win() == opened_windows[1].win
        end)

        local title_window = opened_windows[1]
        local body_window = opened_windows[2]
        local title_config = vim.api.nvim_win_get_config(title_window.win)
        local body_config = vim.api.nvim_win_get_config(body_window.win)

        assert.are.equal(title_config.row + TITLE_HEIGHT_WITH_BORDER, body_config.row)

        vim.api.nvim_input(vim.keycode("<Tab>"))
        wait_for(function()
            return vim.api.nvim_get_current_win() == body_window.win
        end)

        vim.api.nvim_input(vim.keycode("<Tab>"))
        wait_for(function()
            return vim.api.nvim_get_current_win() == title_window.win
        end)

        vim.api.nvim_input(vim.keycode("<Tab>"))
        wait_for(function()
            return vim.api.nvim_get_current_win() == body_window.win
        end)

        vim.api.nvim_win_set_cursor(body_window.win, { 1, 0 })
        vim.api.nvim_input(vim.keycode("<Up>"))
        wait_for(function()
            return vim.api.nvim_get_current_win() == title_window.win
        end)

        vim.api.nvim_input(vim.keycode("<Tab>"))
        wait_for(function()
            return vim.api.nvim_get_current_win() == body_window.win
        end)

        vim.api.nvim_win_set_cursor(body_window.win, { 2, 0 })
        vim.api.nvim_input(vim.keycode("<Up>"))
        wait_for(function()
            local cursor = vim.api.nvim_win_get_cursor(body_window.win)
            return vim.api.nvim_get_current_win() == body_window.win and cursor[1] == 1
        end)
    end)

    it("renders arrow icons in multiline footer hints", function()
        select.multiline_input({
            prompt = "Test prompt",
            default = "Test title\n\nfirst line",
        }, function() end)

        wait_for(function()
            return #opened_windows == 3
        end)

        local hint_lines = vim.api.nvim_buf_get_lines(opened_windows[3].buf, 0, -1, false)

        assert.are.equal(
            "  <CR>/↓ details   <Tab> switch fields   ↑/<S-Tab> title   <C-s> save   <C-q> queue",
            hint_lines[1]
        )
    end)

    it("re-focuses select pickers on the list window after creation", function()
        local chosen

        local picker = select.select({
            { label = "Yes", value = true },
            { label = "No", value = false },
        }, {
            prompt = "Confirm deletion",
            format_item = function(item)
                return item.label
            end,
        }, function(item)
            chosen = item
        end)

        wait_for(function()
            return chosen == nil and #picker.focused > 0
        end)

        assert.are.same(picker_select_calls[1], picker)
        assert.are.same({
            target = "list",
            opts = {
                show = true,
            },
        }, picker.focused[1])
    end)

    it("focuses the confirmation picker list when it opens", function()
        local confirm_picker = select.confirm("Delete prompt?", function() end)

        wait_for(function()
            return confirm_picker and #confirm_picker.focused > 0
        end)

        assert.are.same({
            target = "list",
            opts = {
                show = true,
            },
        }, confirm_picker.focused[1])
        assert.is_false(picker_select_opts[1].snacks.preview)
        assert.are.same({ "input", "preview" }, picker_select_opts[1].snacks.layout.hidden)
        assert.are.equal(100, picker_select_opts[1].snacks.layout.layout.zindex)
        assert.is_true(picker_select_opts[1].snacks.win.list.enter)
    end)

    it("re-focuses one-line inputs after delayed focus changes", function()
        local parent_buf = vim.api.nvim_create_buf(false, true)
        local parent_win = vim.api.nvim_open_win(parent_buf, true, {
            relative = "editor",
            style = "minimal",
            row = 3,
            col = 3,
            width = 40,
            height = 4,
            border = "rounded",
        })

        select.input({
            prompt = "Optional note",
        }, function() end)

        wait_for(function()
            return #input_windows == 1
        end)

        vim.schedule(function()
            if vim.api.nvim_win_is_valid(parent_win) then
                vim.api.nvim_set_current_win(parent_win)
            end
        end)

        wait_for(function()
            return vim.api.nvim_get_current_win() == input_windows[1].win
        end)

        if vim.api.nvim_win_is_valid(parent_win) then
            vim.api.nvim_win_close(parent_win, true)
        end
    end)

    it("opens one-line inputs above workspace-level floats", function()
        select.input({
            prompt = "Optional note",
        }, function() end)

        wait_for(function()
            return #input_opts_calls == 1
        end)

        assert.are.equal(101, input_opts_calls[1].win.zindex)
    end)

    it("uses built-in completion items for prompt context insertion", function()
        vim.o.completeopt = "menuone,noinsert,noselect"
        local source_buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_name(source_buf, "/tmp/example.lua")
        vim.bo[source_buf].buftype = ""
        vim.bo[source_buf].filetype = "lua"
        vim.api.nvim_buf_set_lines(source_buf, 0, -1, false, {
            "local value = 1",
            "return value",
        })
        vim.api.nvim_win_set_buf(0, source_buf)
        vim.api.nvim_win_set_cursor(0, { 1, 0 })

        select.multiline_input({
            prompt = "Test prompt",
            default = "Test title",
        }, function() end)

        wait_for(function()
            return #opened_windows == 3 and vim.api.nvim_get_current_win() == opened_windows[1].win
        end)

        local body_window = opened_windows[2]
        vim.api.nvim_set_current_win(body_window.win)

        assert.are.equal(
            "v:lua.require'clodex.ui.select'.prompt_context_complete",
            vim.bo[body_window.buf].completefunc
        )
        assert.are.equal("menuone,noselect,longest", vim.bo[body_window.buf].completeopt)

        local start_col = select.prompt_context_complete(1, "")
        local items = select.prompt_context_complete(0, "&f")

        assert.are.equal(0, start_col)
        assert.is_true(#items > 0)
        assert.are.equal("&file", items[1].abbr)
        assert.are.equal("&file", items[1].word)
        assert.matches("^@.+$", items[1].info)
    end)

    it("expands prompt context tokens only when the prompt is submitted", function()
        local submitted

        select.multiline_input({
            prompt = "Test prompt",
            default = "Title",
            context = {
                relative_path = "example.lua",
                file_path = "/tmp/example.lua",
                project_root = "/tmp",
                cursor_row = 3,
                current_word = "value",
            },
        }, function(value)
            submitted = value
        end)

        wait_for(function()
            return #opened_windows == 3
        end)

        local body_window = opened_windows[2]
        vim.api.nvim_buf_set_lines(body_window.buf, 0, -1, false, { "&file", "", "&word" })
        vim.api.nvim_set_current_win(body_window.win)
        vim.cmd.stopinsert()
        wait_for(function()
            return vim.fn.mode() == "n"
        end)
        vim.fn.feedkeys(vim.keycode("<CR>"), "xt")

        wait_for(function()
            return submitted ~= nil
        end)

        assert.are.equal('Title\n\n@example.lua\n\n"value" under the cursor in @example.lua: line 3', submitted)
    end)

    it("highlights only valid prompt context tokens in the details buffer", function()
        select.multiline_input({
            prompt = "Test prompt",
            default = table.concat({
                "Title",
                "",
                "&file and &line",
                "&missing should stay plain",
                "&filex should stay plain too",
            }, "\n"),
            context = {
                relative_path = "example.lua",
                file_path = "/tmp/example.lua",
                project_root = "/tmp",
                cursor_row = 3,
            },
        }, function() end)

        wait_for(function()
            return #opened_windows == 3
        end)

        local body_window = opened_windows[2]
        local ns = vim.api.nvim_get_namespaces().clodex_prompt_context_highlight
        local marks = vim.api.nvim_buf_get_extmarks(body_window.buf, ns, 0, -1, { details = true })

        assert.are.same({
            { row = 0, col = 0, end_col = 5, hl_group = "ClodexPromptEditorContext" },
            { row = 0, col = 10, end_col = 15, hl_group = "ClodexPromptEditorContext" },
        }, vim.tbl_map(function(mark)
            return {
                row = mark[2],
                col = mark[3],
                end_col = mark[4].end_col,
                hl_group = mark[4].hl_group,
            }
        end, marks))
    end)

    it("disables bracket-pair highlighting helpers in prompt editors", function()
        select.multiline_input({
            prompt = "Test prompt",
            default = "Title\n\n(body)",
        }, function() end)

        wait_for(function()
            return #opened_windows == 3
        end)

        local title_window = opened_windows[1]
        local body_window = opened_windows[2]

        assert.are.equal("off", vim.bo[title_window.buf].syntax)
        assert.are.equal("off", vim.bo[body_window.buf].syntax)
        assert.are.equal(0, vim.b[title_window.buf].matchup_matchparen_enabled)
        assert.are.equal(0, vim.b[body_window.buf].matchup_matchparen_enabled)
    end)
end)
