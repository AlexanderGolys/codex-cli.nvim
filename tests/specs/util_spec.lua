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

    describe("safe_edit", function()
        local original_edit

        before_each(function()
            original_edit = vim.cmd.edit
            vim.cmd.enew({ bang = true })
            vim.bo[0].modified = false
        end)

        after_each(function()
            vim.cmd.edit = original_edit
            vim.bo[0].modified = false
        end)

        it("keeps modified buffers open when opening another file", function()
            local path = vim.fn.tempname()
            vim.fn.writefile({ "demo" }, path)
            vim.api.nvim_buf_set_lines(0, 0, -1, false, { "unsaved" })
            vim.bo[0].modified = true

            local result = util.safe_edit(path)

            assert.is_false(result.ok)
            assert.are.equal("modified", result.reason)
            assert.are.equal(
                "Current buffer has unsaved changes; keeping it open instead of replacing it.",
                result.message
            )

            vim.fn.delete(path)
        end)

        it("reports swapfile conflicts without throwing", function()
            local path = vim.fn.tempname()
            local edit_calls = 0
            vim.fn.writefile({ "demo" }, path)
            vim.cmd.edit = function()
                edit_calls = edit_calls + 1
                error("vim/_editor.lua:0: nvim_exec2(), line 1: Vim(edit):E325: ATTENTION")
            end

            local result = util.safe_edit(path)

            assert.is_false(result.ok)
            assert.are.equal("swapfile", result.reason)
            assert.are.equal(1, edit_calls)
            assert.are.equal(
                ("Swap file already exists for %s; keeping the current buffer unchanged."):format(path),
                result.message
            )

            vim.fn.delete(path)
        end)

        it("wraps other edit failures as errors", function()
            local path = vim.fn.tempname()
            vim.fn.writefile({ "demo" }, path)
            vim.cmd.edit = function()
                error("boom")
            end

            local result = util.safe_edit(path)

            assert.is_false(result.ok)
            assert.are.equal("error", result.reason)
            assert.matches("Failed to open ", result.message)
            assert.matches("boom", result.message)

            vim.fn.delete(path)
        end)
    end)
end)
