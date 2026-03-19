package.loaded["snacks.terminal"] = {
    open = function()
        return {
            hide = function() end,
        }
    end,
}

local Session = require("clodex.terminal.session")
local TerminalUi = require("clodex.terminal.ui")

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

    it("maps terminal statusline highlights onto terminal windows", function()
        local buf = vim.api.nvim_create_buf(false, true)
        vim.bo[buf].filetype = "clodex_terminal"
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "Codex ready" })

        local session = Session.new({
            key = "project:/tmp/demo",
            kind = "project",
            cwd = "/tmp/demo",
            title = "Clodex: Demo",
            cmd = { "codex" },
        })
        session.buf = buf

        local app_module = package.loaded["clodex.app"]
        package.loaded["clodex.app"] = {
            instance = function()
                return {
                    config = {
                        get = function()
                            return { backend = "codex" }
                        end,
                    },
                    terminals = {
                        session_by_buf = function(_, target_buf)
                            if target_buf == buf then
                                return session
                            end
                        end,
                    },
                }
            end,
        }

        local win = vim.api.nvim_get_current_win()
        local original_buf = vim.api.nvim_win_get_buf(win)
        vim.api.nvim_win_set_buf(win, buf)

        TerminalUi.apply_window(win)

        assert.matches("StatusLine:ClodexTerminalStatuslineActive", vim.wo[win].winhl)
        assert.matches("StatusLineNC:ClodexTerminalStatusline", vim.wo[win].winhl)

        vim.api.nvim_win_set_buf(win, original_buf)
        package.loaded["clodex.app"] = app_module
    end)
end)
