local TITLE_HEIGHT_WITH_BORDER = 3

local function wait_for(predicate)
    vim.wait(1000, predicate, 10)
end

describe("clodex.ui.select", function()
    local select
    local opened_windows
    local original_ui_win
    local picker_select_calls

    before_each(function()
        package.loaded["clodex.ui.select"] = nil
        original_ui_win = package.loaded["clodex.ui.win"]
        opened_windows = {}
        picker_select_calls = {}
        package.loaded["snacks.input"] = {
            input = function() end,
        }
        package.loaded["snacks.picker.select"] = {
            select = function(_items, _opts, on_choice)
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
                on_choice(nil)
                return picker
            end,
        }

        package.loaded["clodex.ui.win"] = {
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
        package.loaded["clodex.ui.select"] = nil
        package.loaded["clodex.ui.win"] = original_ui_win
        package.loaded["snacks.input"] = nil
        package.loaded["snacks.picker.select"] = nil
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
end)
