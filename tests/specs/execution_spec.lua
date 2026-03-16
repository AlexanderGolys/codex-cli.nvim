local Config = require("clodex.config")
local Execution = require("clodex.workspace.execution")
local fs = require("clodex.util.fs")

local function temp_dir()
    local dir = vim.fn.tempname()
    fs.ensure_dir(dir)
    return dir
end

describe("clodex.workspace.execution", function()
    it("generates the project-local prompt skill from the repo-local template", function()
        local root = temp_dir()
        local project = {
            name = "Demo",
            root = root,
        }
        fs.ensure_dir(fs.join(root, ".git"))
        local execution = Execution.new(Config.new():setup())

        execution:ensure_prompt_skill(project)

        local file = assert(io.open(execution:skill_file(project), "rb"))
        local content = file:read("*a")
        file:close()

        assert.matches("Create a focused git commit", content)
        assert.matches("queues%.implemented", content)
        assert.matches("%$prompt%-nvim%-clodex", content)

        fs.remove(root)
    end)

    it("skips the commit requirement in generated skills for non-git project roots", function()
        local root = temp_dir()
        local project = {
            name = "Demo",
            root = root,
        }
        local execution = Execution.new(Config.new():setup())

        execution:ensure_prompt_skill(project)

        local file = assert(io.open(execution:skill_file(project), "rb"))
        local content = file:read("*a")
        file:close()

        assert.matches("skip the commit step", content)
        assert.matches("history_commit` when a commit exists", content)

        fs.remove(root)
    end)
end)
