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

    it("does not expose the removed library prompt category", function()
        assert.is_false(KindRegistry.is_valid("library"))

        local ids = vim.tbl_map(function(category)
            return category.id
        end, KindRegistry.list())

        assert.is_false(vim.tbl_contains(ids, "library"))
    end)

    it("maps renamed prompt kind aliases to their canonical categories", function()
        assert.are.equal("todo", KindRegistry.get("improvement").id)
        assert.are.equal("freeform", KindRegistry.get("fix").id)
        assert.are.equal("refactor", KindRegistry.get("restructure").id)
        assert.are.equal("idea", KindRegistry.get("vision").id)
        assert.are.equal("cleanup", KindRegistry.get("clean-up").id)
        assert.are.equal("docs", KindRegistry.get("missing-docs").id)
        assert.are.equal("ask", KindRegistry.get("explain").id)
    end)
end)
