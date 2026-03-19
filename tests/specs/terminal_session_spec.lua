package.loaded["snacks.terminal"] = {
    open = function()
        return {
            hide = function() end,
        }
    end,
}

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

    it("treats a ready prompt as not working", function()
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
        session.job_id = 123
        session.awaiting_response = true

        local original_jobwait = vim.fn.jobwait
        vim.fn.jobwait = function()
            return { -1 }
        end

        assert.is_false(session:is_working())
        assert.is_false(session.awaiting_response)

        vim.fn.jobwait = original_jobwait
    end)

    it("treats non-ready output after dispatch as working", function()
        local buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
            "Thinking...",
        })

        local session = Session.new({
            key = "project:/tmp/demo",
            kind = "project",
            cwd = "/tmp/demo",
            title = "Clodex: Demo",
            cmd = { "codex" },
        })
        session.buf = buf
        session.job_id = 123
        session.awaiting_response = true

        local original_jobwait = vim.fn.jobwait
        vim.fn.jobwait = function()
            return { -1 }
        end

        assert.is_true(session:is_working())

        vim.fn.jobwait = original_jobwait
    end)

    it("detects when the session is waiting for user input", function()
        local buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
            "Could you confirm which project root I should use?",
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
        session.job_id = 123

        local original_jobwait = vim.fn.jobwait
        vim.fn.jobwait = function()
            return { -1 }
        end

        assert.are.equal("question", session:waiting_state())

        vim.fn.jobwait = original_jobwait
    end)

    it("detects when the session is waiting for permission", function()
        local buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
            "I need your permission to edit tracked files before I continue.",
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
        session.job_id = 123

        local original_jobwait = vim.fn.jobwait
        vim.fn.jobwait = function()
            return { -1 }
        end

        assert.are.equal("permission", session:waiting_state())

        vim.fn.jobwait = original_jobwait
    end)
end)
