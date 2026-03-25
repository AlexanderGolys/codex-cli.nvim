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


    it("can start sessions with the native Neovim terminal provider", function()
        local root = vim.fn.tempname()
        vim.fn.mkdir(root, "p")

        local termopen_calls = {}
        local original_termopen = vim.fn.termopen
        vim.fn.termopen = function(cmd, opts)
            termopen_calls[#termopen_calls + 1] = {
                cmd = vim.deepcopy(cmd),
                opts = vim.deepcopy(opts),
            }
            return 456
        end

        local session = Session.new({
            key = root,
            kind = "project",
            cwd = root,
            title = "Clodex: Demo",
            cmd = { "codex" },
            env = { DEMO = "1" },
            terminal_provider = "term",
        })

        assert.is_true(session:ensure_started())
        assert.are.equal(456, session.job_id)
        assert.are.equal("clodex_terminal", vim.bo[session.buf].filetype)
        assert.are.same({ "codex" }, termopen_calls[1].cmd)
        assert.are.equal(root, termopen_calls[1].opts.cwd)
        assert.are.same({ DEMO = "1" }, termopen_calls[1].opts.env)

        vim.fn.termopen = original_termopen
        session:destroy()
        vim.fn.delete(root, "rf")
    end)

    it("maps terminal statusline highlights onto terminal windows", function()
        local buf = vim.api.nvim_create_buf(false, true)
        vim.bo[buf].filetype = "clodex_terminal"
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "Codex ready" })
        vim.api.nvim_buf_set_var(buf, "terminal_color_background", "#112233")
        vim.api.nvim_buf_set_var(buf, "terminal_color_foreground", "#ddeeff")

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

        local active_name = vim.wo[win].winhl:match("StatusLine:([^,]+)")
        local inactive_name = vim.wo[win].winhl:match("StatusLineNC:([^,]+)")

        assert.matches("ClodexTerminalStatuslineDynActive_112233_DDEEFF", active_name)
        assert.matches("ClodexTerminalStatuslineDynInactive_112233_DDEEFF", inactive_name)

        local active = vim.api.nvim_get_hl(0, { name = active_name, link = false })
        local inactive = vim.api.nvim_get_hl(0, { name = inactive_name, link = false })

        assert.are.equal(0x112233, active.bg)
        assert.are.equal(0xDDEEFF, active.fg)
        assert.is_true(active.bold)
        assert.are.equal(0x112233, inactive.bg)
        assert.are.equal(0xDDEEFF, inactive.fg)

        vim.api.nvim_win_set_buf(win, original_buf)
        package.loaded["clodex.app"] = app_module
    end)

    it("clears terminal chrome after leaving a terminal buffer", function()
        local terminal_buf = vim.api.nvim_create_buf(false, true)
        vim.bo[terminal_buf].filetype = "clodex_terminal"
        vim.api.nvim_buf_set_lines(terminal_buf, 0, -1, false, { "Codex ready" })

        local normal_buf = vim.api.nvim_create_buf(false, true)
        vim.bo[normal_buf].filetype = "markdown"

        local session = Session.new({
            key = "project:/tmp/demo",
            kind = "project",
            cwd = "/tmp/demo",
            title = "Clodex: Demo",
            cmd = { "codex" },
        })
        session.buf = terminal_buf

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
                            if target_buf == terminal_buf then
                                return session
                            end
                        end,
                    },
                }
            end,
        }

        local win = vim.api.nvim_get_current_win()
        local original_buf = vim.api.nvim_win_get_buf(win)
        vim.api.nvim_win_set_buf(win, terminal_buf)
        TerminalUi.apply_window(win)

        assert.are.equal("%!v:lua.require('clodex.terminal.ui').statusline()", vim.api.nvim_get_option_value("statusline", { scope = "local", win = win }))
        assert.are.equal("%!v:lua.require('clodex.terminal.ui').winbar()", vim.api.nvim_get_option_value("winbar", { scope = "local", win = win }))

        vim.api.nvim_win_set_buf(win, normal_buf)
        TerminalUi.refresh_chrome(win)

        assert.are.equal("", vim.api.nvim_get_option_value("statusline", { scope = "local", win = win }))
        assert.are.equal("", vim.api.nvim_get_option_value("winbar", { scope = "local", win = win }))
        assert.are.equal("", vim.api.nvim_get_option_value("winhl", { scope = "local", win = win }))

        vim.api.nvim_win_set_buf(win, original_buf)
        package.loaded["clodex.app"] = app_module
    end)
end)
