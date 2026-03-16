local Session = require("clodex.terminal.session")

describe("clodex.terminal.session", function()
    it("keeps the active-window statusline behavior unchanged when the last line is visible", function()
        local buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
            "older output",
            "Codex ready",
        })

        local session = Session.new({
            key = "project:/tmp/demo",
            kind = "project",
            cwd = "/tmp/demo",
            title = "Clodex: Demo",
            cmd = { "codex" },
        })
        session.buf = buf

        vim.api.nvim_set_current_buf(buf)

        assert.are.equal("", session:statusline_text(vim.api.nvim_get_current_win()))
    end)

    it("keeps the inactive-window statusline text identical to the active line text", function()
        local current_win = vim.api.nvim_get_current_win()
        local inactive_buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_lines(inactive_buf, 0, -1, false, {
            "older output",
            "Codex ready",
        })

        local session = Session.new({
            key = "project:/tmp/demo",
            kind = "project",
            cwd = "/tmp/demo",
            title = "Clodex: Demo",
            cmd = { "codex" },
        })
        session.buf = inactive_buf

        vim.cmd("vsplit")
        local inactive_win = vim.api.nvim_get_current_win()
        vim.api.nvim_win_set_buf(inactive_win, inactive_buf)
        vim.api.nvim_set_current_win(current_win)

        assert.are.equal(" Codex ready ", session:statusline_text(inactive_win))
        assert.are.equal(session:statusline_line_text(), session:statusline_text(inactive_win))

        vim.api.nvim_win_close(inactive_win, true)
    end)
end)
