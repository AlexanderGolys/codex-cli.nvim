local Config = require("clodex.config")
local Execution = require("clodex.workspace.execution")
local fs = require("clodex.util.fs")

local function temp_dir()
    local dir = vim.fn.tempname()
    fs.ensure_dir(dir)
    return dir
end

local function new_execution(skills_dir)
    return Execution.new(Config.new():setup({
        prompt_execution = {
            skills_dir = skills_dir,
            skill_name = "prompt-nvim-clodex",
        },
    }))
end

local function new_opencode_execution()
    return Execution.new(Config.new():setup({
        backend = "opencode",
    }))
end

describe("clodex.workspace.execution", function()
    it("syncs the global prompt skill from the repo template", function()
        local root = temp_dir()
        local execution = new_execution(fs.join(root, "skills"))

        execution:sync_prompt_skill()

        local file = assert(io.open(execution:skill_file(), "rb"))
        local content = file:read("*a")
        file:close()

        assert.matches("prompt kind is `ask`, do not create a commit", content)
        assert.matches("create a focused git commit", content)
        assert.matches("%.clodex/implemented%.json", content)
        assert.matches("%$prompt%-nvim%-clodex", content)

        fs.remove(root)
    end)

    it("overwrites stale global skill content during sync", function()
        local root = temp_dir()
        local execution = new_execution(fs.join(root, "skills"))

        fs.write_file(execution:skill_file(), "stale")
        execution:sync_prompt_skill()

        local file = assert(io.open(execution:skill_file(), "rb"))
        local content = file:read("*a")
        file:close()

        assert.are_not.equal("stale", content)
        assert.matches("Repeat until `%.clodex/queued%.json` is empty", content)

        fs.remove(root)
    end)

    it("renders queue prompts with item id and kind-aware commit policy", function()
        local root = temp_dir()
        local project = {
            name = "Demo",
            root = fs.join(root, "project"),
        }
        fs.ensure_dir(project.root)
        local execution = new_execution(fs.join(root, "skills"))

        local ask_prompt = execution:dispatch_prompt(project, {
            id = "ask-1",
            kind = "ask",
            prompt = "Explain the behavior",
        })
        local todo_prompt = execution:dispatch_prompt(project, {
            id = "todo-1",
            kind = "todo",
            prompt = "Implement the fix",
        })

        assert.matches("Current queue item id: `ask%-1`", ask_prompt)
        assert.matches("Current prompt kind: `ask`", ask_prompt)
        assert.matches("Commit policy for this prompt: `skip`", ask_prompt)
        assert.matches("%$prompt%-nvim%-clodex", ask_prompt)

        assert.matches("Current queue item id: `todo%-1`", todo_prompt)
        assert.matches("Current prompt kind: `todo`", todo_prompt)
        assert.matches("Commit policy for this prompt: `required`", todo_prompt)

        fs.remove(root)
    end)

    it("syncs the checked-in skill into the project-local opencode skills dir", function()
        local root = temp_dir()
        local project = {
            name = "Demo",
            root = fs.join(root, "project"),
        }
        fs.ensure_dir(project.root)

        local execution = new_opencode_execution()
        execution:sync_prompt_skill(project)

        local skill_file = execution:skill_file(project)
        local file = assert(io.open(skill_file, "rb"))
        local content = file:read("*a")
        file:close()

        assert.are.equal(
            fs.normalize(vim.fn.expand("~/.config/opencode/skills/prompt-nvim-clodex/SKILL.md")),
            skill_file
        )
        assert.matches("Manual History", content)
        assert.matches("%$prompt%-nvim%-clodex", content)

        fs.remove(root)
    end)
end)
