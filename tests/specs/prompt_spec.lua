local Prompt = require("clodex.prompt")

describe("clodex.prompt", function()
    it("resolves language-aware prompt library templates", function()
        local template = Prompt.library.get("review-current-file", { language = "lua" })

        assert.is_not_nil(template)
        assert.are.equal("Review current file (Lua)", template.label)
        assert.matches("idiomatic Lua conventions", template.details)
        assert.matches("`&file`", template.details)
    end)

    it("keeps generic prompt library templates unchanged without a language hint", function()
        local template = Prompt.library.get("review-current-file")

        assert.is_not_nil(template)
        assert.are.equal("Review current file", template.label)
        assert.is_nil(template.details:match("idiomatic .* conventions"))
    end)

    it("lists the expanded prompt library toolset", function()
        local ids = vim.tbl_map(function(template)
            return template.id
        end, Prompt.library.list({ language = "rs" }))

        assert.is_true(vim.tbl_contains(ids, "review-current-file"))
        assert.is_true(vim.tbl_contains(ids, "simplify-selection"))
        assert.is_true(vim.tbl_contains(ids, "improve-documentation"))
        assert.is_true(vim.tbl_contains(ids, "map-project-architecture"))
        assert.is_true(vim.tbl_contains(ids, "plan-project-work"))
        assert.is_true(vim.tbl_contains(ids, "review-plan-against-code"))
    end)
end)
