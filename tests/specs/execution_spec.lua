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

        assert.matches("prompt kind is `ask`, do not create a commit", content)
        assert.matches("create a focused git commit", content)
        assert.matches("branch%-and%-PR flow", content)
        assert.matches("use its queue tools instead of ad%-hoc JSON editing", content)
        assert.matches("queue_complete_current", content)
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
        local bug_prompt = execution:dispatch_prompt(project, {
            id = "bug-1",
            kind = "bug",
            prompt = "Fix the traceback",
            completion_target = "history",
        })
        local freeform_prompt = execution:dispatch_prompt(project, {
            id = "freeform-1",
            kind = "freeform",
            prompt = "Talk to the agent about the current state",
        })

        assert.matches("Current queue item id: `ask%-1`", ask_prompt)
        assert.matches("Current prompt kind: `ask`", ask_prompt)
        assert.matches("Commit policy for this prompt: `skip`", ask_prompt)
        assert.matches("Git workflow mode for this prompt: `commit`", ask_prompt)
        assert.matches("%$prompt%-nvim%-clodex", ask_prompt)

        assert.matches("Current queue item id: `todo%-1`", todo_prompt)
        assert.matches("Current prompt kind: `todo`", todo_prompt)
        assert.matches("Commit policy for this prompt: `required`", todo_prompt)
        assert.matches("Git workflow mode for this prompt: `commit`", todo_prompt)
        assert.matches("%$prompt%-nvim%-clodex", todo_prompt)

        assert.matches("Completion destination for this prompt: `history`", bug_prompt)
        assert.matches("Current prompt kind: `freeform`", freeform_prompt)
        assert.matches("Commit policy for this prompt: `optional`", freeform_prompt)
        assert.matches("Completion destination for this prompt: `agent_decides`", freeform_prompt)

        fs.remove(root)
    end)

    it("renders the branch-pr workflow mode into queue prompts", function()
        local root = temp_dir()
        local project = {
            name = "Demo",
            root = fs.join(root, "project"),
        }
        fs.ensure_dir(project.root)
        local execution = new_execution(fs.join(root, "skills"), {
            git_workflow = "branch_pr",
        })

        local prompt = execution:dispatch_prompt(project, {
            id = "todo-branch-1",
            kind = "todo",
            prompt = "Implement the feature",
        })

        assert.matches("Git workflow mode for this prompt: `branch_pr`", prompt)

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
