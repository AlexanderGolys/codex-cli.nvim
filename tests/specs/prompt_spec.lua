local Prompt = require("clodex.prompt")
local KindRegistry = require("clodex.prompt.kind_registry")

describe("clodex.prompt", function()
    it("keeps layout-backed modes on every prompt category", function()
        for _, category in ipairs(KindRegistry.list()) do
            if category.id ~= "notworking" then
                local modes = KindRegistry.modes(category.id)

                assert.is_true(#modes > 0)
                assert.is_string(KindRegistry.default_mode(category.id))
                for _, mode in ipairs(modes) do
                    assert.is_string(mode.id)
                    assert.is_true(mode.id ~= "")
                    assert.is_string(mode.layout)
                    assert.is_true(mode.layout ~= "")
                    assert.is_table(KindRegistry.default_draft(category.id, mode.id))
                end
            end
        end
    end)

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
