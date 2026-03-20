describe("clodex.util.notify", function()
    local Notify
    local calls
    local original_notify

    before_each(function()
        package.loaded["clodex.util.notify"] = nil
        calls = {}
        original_notify = vim.notify
        vim.notify = function(message, level, opts)
            calls[#calls + 1] = {
                message = message,
                level = level,
                opts = opts,
            }
        end
        Notify = require("clodex.util.notify")
    end)

    after_each(function()
        vim.notify = original_notify
    end)

    it("keeps single-line messages under the plugin title", function()
        Notify.notify("Saved prompt", vim.log.levels.INFO)

        assert.are.same("Saved prompt", calls[1].message)
        assert.are.same("clodex.nvim", calls[1].opts.title)
        assert.are.same("text", calls[1].opts.ft)
    end)

    it("promotes the first line of multiline messages into the title", function()
        Notify.notify("Queue loop armed\n\nWaiting for the active prompt to finish.", vim.log.levels.INFO)

        assert.are.same("Queue loop armed", calls[1].opts.title)
        assert.are.same("Waiting for the active prompt to finish.", calls[1].message)
        assert.are.same("text", calls[1].opts.ft)
    end)
end)
