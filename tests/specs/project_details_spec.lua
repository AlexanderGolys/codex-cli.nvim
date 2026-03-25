local Details = require("clodex.project.details")
local Config = require("clodex.config")
local fs = require("clodex.util.fs")

describe("clodex.project.details", function()
    it("persists custom project icons across refreshes", function()
        local root = vim.fn.tempname()
        fs.ensure_dir(root)
        local details = Details.new(Config.new():setup({}))
        local project = {
            name = "Demo",
            root = root,
        }

        details:set_icon(project, "★")

        assert.are.equal("★", details:get_icon(project))
        assert.are.equal("★", details:get(project).project_icon)

        details:set_icon(project, nil)

        assert.is_nil(details:get_icon(project))
        assert.is_nil(details:get(project).project_icon)

        fs.remove(root)
    end)
end)
