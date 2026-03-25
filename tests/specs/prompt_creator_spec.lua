local function wait_for(predicate)
    assert(vim.wait(1000, predicate, 10), "timed out waiting for prompt creator state")
end

describe("clodex.ui.prompt_creator", function()
    local Creator
    local creator
    local opened_windows
    local original_ui_win
    local original_notify

    before_each(function()
        package.loaded["clodex.ui.prompt_creator"] = nil
        package.loaded["clodex.ui.prompt_creator.layouts.composer"] = nil
        package.loaded["clodex.ui.prompt_creator.layouts.clipboard_preview"] = nil
        package.loaded["clodex.ui.prompt_creator.layouts.template_picker"] = nil

        original_ui_win = package.loaded["clodex.ui.win"]
        original_notify = package.loaded["clodex.util.notify"]
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
end)
