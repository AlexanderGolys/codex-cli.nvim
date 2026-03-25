describe("clodex.prompt.submit", function()
    local Submit

    before_each(function()
        package.loaded["clodex.prompt.submit"] = nil
        Submit = require("clodex.prompt.submit")
    end)

    after_each(function()
        package.loaded["clodex.prompt.submit"] = nil
    end)

    it("expands context tokens for standard creator fields", function()
        local spec = Submit.build_spec({
            kind = "todo",
            title = "Fix &file",
            details = "Inspect &word",
            context = {
                relative_path = "lua/demo.lua",
                file_path = "/tmp/lua/demo.lua",
                project_root = "/tmp",
                cursor_row = 7,
                current_word = "value",
            },
        })

        assert.are.equal("Fix @lua/demo.lua", spec.title)
        assert.are.equal('Inspect "value" under the cursor in @lua/demo.lua: line 7', spec.details)
    end)

    it("builds clipboard-error bug prompts from preview text and uses the comment as the title", function()
        local spec = Submit.build_spec({
            kind = "bug",
            variant = "clipboard_error",
            title = "Investigate save crash",
            details = "It happens after pressing save.",
            preview_text = "Traceback: boom",
        })

        assert.are.equal("Investigate save crash", spec.title)
        assert.matches("Traceback: boom", spec.details)
        assert.not_matches("It happens after pressing save", spec.details)
    end)

    it("adds clipboard image references to any prompt kind", function()
        local spec = Submit.build_spec({
            kind = "ask",
            title = "Explain the issue",
            details = "Look at this screenshot.",
            image_path = "/tmp/demo/image.png",
        })

        assert.are.equal("Explain the issue", spec.title)
        assert.matches("attached clipboard image", spec.details)
        assert.matches("image%.png", spec.details)
        assert.matches("Look at this screenshot", spec.details)
    end)
end)
