local function wait_for(predicate)
    vim.wait(1000, predicate, 10)
end

describe("clodex.ui.select picker focus", function()
    local select
    local original_ui_win
    local original_select
    local picker_win

    before_each(function()
        package.loaded["clodex.ui.select"] = nil
        original_ui_win = package.loaded["clodex.ui.win"]
        original_select = package.loaded["snacks.picker.select"]

        package.loaded["clodex.ui.win"] = {
            create_buffer = function()
                return vim.api.nvim_create_buf(false, true)
            end,
            open = function(opts)
                local win = vim.api.nvim_open_win(opts.buf, opts.enter or false, {
                    relative = "editor",
                    style = "minimal",
                    row = 1,
                    col = 1,
                    width = 10,
                    height = 1,
                })
                return {
                    buf = opts.buf,
                    win = win,
                    opts = opts,
                    valid = function(self)
                        return vim.api.nvim_win_is_valid(self.win)
                    end,
                    close = function(self)
                        if self:valid() then
                            vim.api.nvim_win_close(self.win, true)
                        end
                    end,
                    update = function() end,
                }
            end,
            apply_theme = function() end,
        }

        package.loaded["snacks.input"] = {
            input = function() end,
        }

        package.loaded["snacks.picker.select"] = {
            select = function(_items, opts, on_choice)
                local list_buf = vim.api.nvim_create_buf(false, true)
                picker_win = vim.api.nvim_open_win(list_buf, false, {
                    relative = "editor",
                    style = "minimal",
                    row = 2,
                    col = 2,
                    width = 20,
                    height = 4,
                })

                local picker = {
                    closed = false,
                    opts = {
                        focus = "list",
                        enter = true,
                    },
                    list = {
                        win = {
                            win = picker_win,
                        },
                    },
                    focused = {},
                }

                function picker:focus(target, focus_opts)
                    self.focused[#self.focused + 1] = {
                        target = target,
                        opts = focus_opts,
                    }
                end

                on_choice(nil)
                return picker
            end,
        }

        select = require("clodex.ui.select")
    end)

    after_each(function()
        if picker_win and vim.api.nvim_win_is_valid(picker_win) then
            vim.api.nvim_win_close(picker_win, true)
        end
        picker_win = nil
        package.loaded["clodex.ui.select"] = nil
        package.loaded["clodex.ui.win"] = original_ui_win
        package.loaded["snacks.input"] = nil
        package.loaded["snacks.picker.select"] = original_select
    end)

    it("accepts snacks.win picker list handles", function()
        local current_buf = vim.api.nvim_create_buf(false, true)
        local current_win = vim.api.nvim_open_win(current_buf, true, {
            relative = "editor",
            style = "minimal",
            row = 5,
            col = 5,
            width = 20,
            height = 4,
        })

        local picker = select.select({ "one", "two" }, {}, function() end)

        wait_for(function()
            return #picker.focused > 0 and vim.api.nvim_get_current_win() == picker_win
        end)

        assert.are.same({
            target = "list",
            opts = {
                show = true,
            },
        }, picker.focused[1])

        if vim.api.nvim_win_is_valid(current_win) then
            vim.api.nvim_win_close(current_win, true)
        end
    end)
end)
