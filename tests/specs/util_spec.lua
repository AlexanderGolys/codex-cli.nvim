local util = require("clodex.util")

describe("clodex.util", function()
    describe("uuid_v4", function()
        it("generates v4-formatted IDs", function()
            local id = util.uuid_v4()

            assert.equal(36, #id)
            assert.matches("^[0-9a-f%-]+$", id)
            assert.equal("4", id:sub(15, 15))
            local variant = tonumber(id:sub(20, 20), 16)
            assert.is_true(variant >= 8 and variant <= 11)
        end)

        it("generates unique IDs", function()
            local seen = {}
            for _ = 1, 50 do
                local id = util.uuid_v4()
                assert.is_nil(seen[id])
                seen[id] = true
            end
        end)

        it("is resilient when unpack helpers are missing", function()
            local original_util = package.loaded["clodex.util"]
            local original_global_table_unpack = table.unpack
            local original_global_unpack = unpack

            table.unpack = nil
            unpack = nil
            package.loaded["clodex.util"] = nil

            local ok, err = pcall(function()
                local legacy_util = require("clodex.util")
                local id = legacy_util.uuid_v4()
                assert.equal(36, #id)
                assert.matches("^[0-9a-f%-]+$", id)
            end)

            package.loaded["clodex.util"] = original_util
            table.unpack = original_global_table_unpack
            unpack = original_global_unpack
            if not ok then
                error(err)
            end
        end)
    end)
end)
