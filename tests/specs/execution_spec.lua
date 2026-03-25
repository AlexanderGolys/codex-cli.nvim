local Config = require("clodex.config")
local Execution = require("clodex.workspace.execution")
local fs = require("clodex.util.fs")

local function temp_dir()
    local dir = vim.fn.tempname()
    fs.ensure_dir(dir)
    return dir
end

local function new_execution(skills_dir, prompt_execution)
    prompt_execution = vim.tbl_extend("force", {
        skills_dir = skills_dir,
        skill_name = "prompt-nvim-clodex",
    }, prompt_execution or {})
    return Execution.new(Config.new():setup({
        prompt_execution = prompt_execution,
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

        assert.matches("Use the `clodex` MCP server as the primary queue interface", content)
        assert.matches("Call `get_task`", content)
        assert.matches("Call `close_task`", content)
        assert.matches("fall back to editing `%.clodex/%*%.json` queue files directly", content)
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
        assert.matches("If `close_task` returns `status = done`, stop", content)

        fs.remove(root)
    end)

    it("renders queue prompts with MCP task-loop instructions", function()
        local root = temp_dir()
        local project = {
            name = "Demo",
            root = fs.join(root, "project"),
        }
        fs.ensure_dir(project.root)
        local execution = new_execution(fs.join(root, "skills"))

        local todo_prompt = execution:dispatch_prompt(project, {
            id = "todo-1",
            kind = "todo",
            prompt = "Implement the fix",
        })
        local bug_prompt = execution:dispatch_prompt(project, {
            id = "bug-1",
            kind = "bug",
            prompt = "Fix the traceback",
            completion_target = "history",
        })
        local idea_prompt = execution:dispatch_prompt(project, {
            id = "idea-1",
            kind = "idea",
            prompt = "Plan the feature",
        })

        assert.matches("current queued item id is `todo%-1`", todo_prompt)
        assert.matches("calling `get_task`", todo_prompt)
        assert.matches("call `close_task` with `success`, `comment`, and `commit_id`", todo_prompt)
        assert.matches("%$prompt%-nvim%-clodex", todo_prompt)

        assert.matches("close directly to `history`", bug_prompt)
        assert.matches("generating follow%-up prompts only", idea_prompt)
        assert.matches("Do not change code or create a git commit", idea_prompt)
        assert.matches("commit_id = \"\"", idea_prompt)

        fs.remove(root)
    end)

    it("syncs the checked-in skill into the configured project-local skills dir", function()
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
            fs.normalize(".clodex/skills/prompt-nvim-clodex/SKILL.md"),
            skill_file
        )
        assert.matches("Manual History", content)
        assert.matches("%$prompt%-nvim%-clodex", content)

        fs.remove(root)
    end)
end)
