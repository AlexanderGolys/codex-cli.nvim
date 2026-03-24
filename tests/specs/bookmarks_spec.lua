local Bookmarks = require("clodex.project.bookmarks")

describe("clodex.project.bookmarks", function()
    describe("jump", function()
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

        it("returns a swapfile result instead of throwing", function()
            local root = vim.fn.tempname()
            local project = {
                root = root,
            }
            local bookmark = {
                path = "notes.md",
                line = 3,
            }
            local edit_calls = 0
            vim.fn.mkdir(root, "p")
            vim.fn.writefile({ "one", "two", "three" }, root .. "/notes.md")
            vim.cmd.edit = function()
                edit_calls = edit_calls + 1
                error("vim/_editor.lua:0: nvim_exec2(), line 1: Vim(edit):E325: ATTENTION")
            end

            local result = Bookmarks.new():jump(project, bookmark)

            assert.is_false(result.ok)
            assert.are.equal("swapfile", result.reason)
            assert.are.equal(1, edit_calls)
            assert.are.equal(
                ("Swap file already exists for %s; keeping the current buffer unchanged."):format(root .. "/notes.md"),
                result.message
            )

            vim.fn.delete(root, "rf")
        end)
    end)
end)
