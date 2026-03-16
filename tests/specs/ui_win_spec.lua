describe("clodex.ui.win", function()
    local original_snacks
    local ui_win
    local captured

    before_each(function()
        package.loaded["clodex.ui.win"] = nil
        original_snacks = package.loaded["snacks"]
        captured = nil
        package.loaded["snacks"] = {
            win = setmetatable({
                resolve = function(defaults, style, opts)
                    captured = {
                        defaults = vim.deepcopy(defaults),
                        style = style,
                        opts = vim.deepcopy(opts),
                    }
                    return vim.tbl_extend("force", defaults, opts or {})
                end,
            }, {
                __call = function(_, resolved)
                    return {
                        win = 0,
                        buf = resolved.buf,
                        opts = resolved,
                    }
                end,
            }),
        }
        ui_win = require("clodex.ui.win")
    end)

    after_each(function()
        package.loaded["clodex.ui.win"] = nil
        package.loaded["snacks"] = original_snacks
    end)

    it("disables Snacks fixbuf for dedicated float views by default", function()
        local win = ui_win.open({
            buf = 23,
            enter = true,
            style = "minimal",
        })

        assert.are.same({
            position = "float",
            show = true,
            fixbuf = false,
        }, captured.defaults)
        assert.are.equal("minimal", captured.style)
        assert.are.equal(23, win.buf)
        assert.is_false(win.opts.fixbuf)
    end)
end)
