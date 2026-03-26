local PromptContext = require("clodex.prompt.context")

describe("clodex.prompt.context", function()
    it("expands file and line tokens using captured metadata", function()
        local context = {
            file_path = "/Users/dev/project/src/main.lua",
            project_root = "/Users/dev/project",
            relative_path = "src/main.lua",
            cursor_row = 12,
            cursor_col = 5,
            current_word = "function",
        }

        assert.are.equal("@src/main.lua", PromptContext.expand_token("&file", context))
        assert.are.equal("@src/main.lua: line 12", PromptContext.expand_token("&line", context))
        assert.are.equal(("\"%s\" under the cursor in @%s: line %d"):format("function", "src/main.lua", 12), PromptContext.expand_token("&word", context))
    end)

    it("replaces supported tokens in prompt templates", function()
        local context = {
            relative_path = "src/main.lua",
            file_path = "/Users/dev/project/src/main.lua",
            project_root = "/Users/dev/project",
            cursor_row = 3,
            current_word = "token",
        }

        local text = "Check line: &line\nAlso: &file\nWord: &word"
        local expanded = PromptContext.expand_text(text, context)

        assert.matches("Check line: @src/main.lua: line 3 %(%[Inserted context from &line%]%)", expanded)
        assert.matches("Also: @src/main.lua %(%[Inserted context from &file%]%)", expanded)
        assert.matches("Word: \"token\" under the cursor in @src/main.lua: line 3 %(%[Inserted context from &word%]%)", expanded)
    end)

    it("keeps invalid or unavailable tokens unchanged during expansion", function()
        local context = {
            relative_path = "src/main.lua",
            file_path = "/Users/dev/project/src/main.lua",
            project_root = "/Users/dev/project",
            cursor_row = 3,
            current_word = "token",
        }

        local text = "Keep &selection and &filex as written"
        local expanded = PromptContext.expand_text(text, context)

        assert.are.equal("Keep &selection and &filex as written", expanded)
    end)

    it("filters completion tokens to only currently available context", function()
        local context = {
            buf = vim.api.nvim_create_buf(false, true),
            relative_path = "src/main.lua",
            file_path = "/Users/dev/project/src/main.lua",
            project_root = "/Users/dev/project",
            cursor_row = 3,
            current_word = "token",
        }

        local tokens = PromptContext.tokens(context)
        local labels = vim.tbl_map(function(item)
            return item.token
        end, tokens)

        assert.is_true(vim.tbl_contains(labels, "&file"))
        assert.is_true(vim.tbl_contains(labels, "&line"))
        assert.is_true(vim.tbl_contains(labels, "&word"))
        assert.is_false(vim.tbl_contains(labels, "&selection"))
        assert.is_false(vim.tbl_contains(labels, "&diagnostic"))
        assert.is_false(vim.tbl_contains(labels, "&buff_diagnostics"))
        assert.is_false(vim.tbl_contains(labels, "&all_diagnostics"))
    end)

    it("keeps quick prompts tokenized until prompt submission", function()
        local prompts = PromptContext.quick_prompts({
            relative_path = "src/main.lua",
            file_path = "/Users/dev/project/src/main.lua",
            project_root = "/Users/dev/project",
            cursor_row = 3,
            current_word = "token",
        })

        assert.are.equal(
            "Explain how the current file fits into the project and walk through the important control flow.\n\n&file",
            prompts[2].text
        )
    end)
end)
