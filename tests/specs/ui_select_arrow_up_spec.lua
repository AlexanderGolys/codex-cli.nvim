local TITLE_HEIGHT_WITH_BORDER = 3

local function wait_for(predicate)
    vim.wait(1000, predicate, 10)
end

describe("clodex.ui.select arrow-up handling", function()
    local select
    local opened_windows
    local original_ui_win
    local original_completeopt
    local original_input
    local original_picker_select
    local original_pumvisible

    before_each(function()
        package.loaded["clodex.ui.select"] = nil
        original_ui_win = package.loaded["clodex.ui.win"]
        original_completeopt = vim.o.completeopt
        original_input = package.loaded["snacks.input"]
        original_picker_select = package.loaded["snacks.picker.select"]
        original_pumvisible = vim.fn.pumvisible
        opened_windows = {}

        package.loaded["snacks.input"] = {
            input = function() end,
        }
        package.loaded["snacks.picker.select"] = {
            select = function(_items, _opts, on_choice)
                on_choice(nil)
            end,
        }

        package.loaded["clodex.ui.win"] = {
            create_buffer = function(opts)
                return vim.api.nvim_create_buf(false, (opts and opts.preset) == "scratch")
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
        package.loaded["clodex.ui.select"] = nil
        package.loaded["clodex.ui.win"] = original_ui_win
        package.loaded["snacks.input"] = original_input
        package.loaded["snacks.picker.select"] = original_picker_select
        vim.fn.pumvisible = original_pumvisible
        vim.o.completeopt = original_completeopt
    end)

    it("keeps completion popup navigation in the details field", function()
        select.multiline_input({
            prompt = "Bug prompt",
            default = "Title",
            context = {
                relative_path = "example.lua",
                file_path = "/tmp/example.lua",
                project_root = "/tmp",
                cursor_row = 3,
                current_word = "value",
            },
        }, function() end)

        wait_for(function()
            return #opened_windows == 3 and vim.api.nvim_get_current_win() == opened_windows[1].win
        end)

        local title_window = opened_windows[1]
        local body_window = opened_windows[2]
        local title_config = vim.api.nvim_win_get_config(title_window.win)
        local body_config = vim.api.nvim_win_get_config(body_window.win)

        assert.are.equal(title_config.row + TITLE_HEIGHT_WITH_BORDER, body_config.row)

        vim.api.nvim_set_current_win(body_window.win)
        vim.api.nvim_win_set_cursor(body_window.win, { 1, 0 })
        vim.cmd.startinsert()
        vim.fn.pumvisible = function()
            return 1
        end

        vim.api.nvim_input(vim.keycode("<Up>"))

        wait_for(function()
            return vim.api.nvim_get_current_win() == body_window.win
        end)

        assert.are.equal(body_window.win, vim.api.nvim_get_current_win())
    end)
end)
