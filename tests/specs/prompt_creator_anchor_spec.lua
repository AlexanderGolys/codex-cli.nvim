describe("clodex.ui.prompt_creator split anchoring", function()
    local Creator
    local creator
    local opened_windows
    local original_ui_win
    local original_notify
    local original_snacks

    before_each(function()
        package.loaded["clodex.ui.prompt_creator"] = nil
        package.loaded["clodex.ui.prompt_creator.layouts.composer"] = nil
        package.loaded["clodex.ui.prompt_creator.layouts.clipboard_preview"] = nil
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
        opened_windows = {}

        package.loaded["clodex.ui.win"] = {
            create_buffer = function(opts)
                local buf = vim.api.nvim_create_buf(false, true)
                local preset = opts and opts.preset or "scratch"
                if preset == "markdown" or preset == "text" then
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
            is_valid = function(win)
                return type(win) == "number" and win > 0 and vim.api.nvim_win_is_valid(win)
            end,
            close = function(win)
                if type(win) == "number" and win > 0 and vim.api.nvim_win_is_valid(win) then
                    vim.api.nvim_win_close(win, true)
                end
            end,
            apply_theme = function() end,
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

                function object:valid()
                    return type(self.win) == "number" and self.win > 0 and vim.api.nvim_win_is_valid(self.win)
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
                        self.win = nil
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

        vim.cmd.only()
        package.loaded["clodex.ui.prompt_creator"] = nil
        package.loaded["clodex.ui.prompt_creator.layouts.composer"] = nil
        package.loaded["clodex.ui.prompt_creator.layouts.clipboard_preview"] = nil
        package.loaded["snacks.input"] = nil
        package.loaded["snacks.picker.select"] = nil
        package.loaded["snacks"] = original_snacks
        package.loaded["clodex.ui.win"] = original_ui_win
        package.loaded["clodex.util.notify"] = original_notify
    end)

    it("keeps the prompt inside the source split when an image is attached", function()
        vim.cmd.vsplit()
        vim.cmd("vertical resize 60")

        local anchor_win = vim.api.nvim_get_current_win()
        local anchor_pos = vim.api.nvim_win_get_position(anchor_win)
        local anchor_width = vim.api.nvim_win_get_width(anchor_win)
        local anchor_height = vim.api.nvim_win_get_height(anchor_win)

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
            initial_draft = {
                image_path = "/tmp/demo.png",
            },
            on_submit = function() end,
        })

        local title_config = vim.api.nvim_win_get_config(creator.layout.title_win.win)
        local body_config = vim.api.nvim_win_get_config(creator.layout.body_win.win)
        local footer_config = vim.api.nvim_win_get_config(creator.footer_win.win)

        assert.are.equal(anchor_win, creator.anchor_win)
        assert.are.equal(anchor_width, creator:editor_size())
        assert.are.equal(anchor_height, select(2, creator:editor_size()))
        assert.is_true(title_config.col >= anchor_pos[2])
        assert.is_true(body_config.col >= anchor_pos[2])
        assert.is_true(footer_config.col >= anchor_pos[2])
        assert.is_true(title_config.col + title_config.width <= anchor_pos[2] + anchor_width)
        assert.is_true(body_config.col + body_config.width <= anchor_pos[2] + anchor_width)
        assert.is_true(footer_config.col + footer_config.width <= anchor_pos[2] + anchor_width)
    end)
end)
