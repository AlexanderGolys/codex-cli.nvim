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

        assert.are.equal("@{src/main.lua}", PromptContext.expand_token("&file", context))
        assert.are.equal("@{src/main.lua}: line 12", PromptContext.expand_token("&line", context))
        assert.are.equal(("\"%s\" under the cursor in @{%s}: line %d"):format("function", "src/main.lua", 12), PromptContext.expand_token("&word", context))
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

        assert.matches("Check line: @{src/main.lua}: line 3", expanded)
        assert.matches("Also: @{src/main.lua}", expanded)
        assert.matches("Word: \"token\" under the cursor in @{src/main.lua}: line 3", expanded)
    end)
end)

