local Queue = require("clodex.workspace.queue")
local fs = require("clodex.util.fs")

local function temp_dir()
    local dir = vim.fn.tempname()
    fs.ensure_dir(dir)
    return dir
end

describe("clodex.execution.runner", function()
    local workspace_root
    local project
    local queue
    local original_history
    local original_git
    local Runner

    before_each(function()
        workspace_root = temp_dir()
        project = {
            name = "Runner Project",
            root = fs.join(workspace_root, "project"),
        }
        fs.ensure_dir(project.root)
        queue = Queue.new(".clodex-test")

        original_history = package.loaded["clodex.history"]
        original_git = package.loaded["clodex.util.git"]
        package.loaded["clodex.history"] = {
            append_prompt_resolved = function() end,
        }
        package.loaded["clodex.util.git"] = {
            head_commit = function()
                return "abc12345"
            end,
        }
        package.loaded["clodex.execution.runner"] = nil
        Runner = require("clodex.execution.runner")
    end)

    after_each(function()
        package.loaded["clodex.execution.runner"] = nil
        package.loaded["clodex.history"] = original_history
        package.loaded["clodex.util.git"] = original_git
        if project then
            fs.remove(project.root)
        end
        if workspace_root then
            fs.remove(workspace_root)
        end
    end)

    it("moves auto-history implemented items directly to history on completion", function()
        local item = queue:add_todo(project, {
            title = "traceback bug",
            queue = "queued",
            kind = "bug",
            completion_target = "history",
        })
        queue:advance(project, item.id)

        local runner = Runner.new({
            queue = queue,
            queue_actions = {
                remember_workspace_revision = function() end,
            },
        }, {})

        runner:complete_item(project, item, "fixed traceback path")

        local queue_name, _, completed = queue:find_item(project, item.id)
        assert.are.equal("history", queue_name)
        assert.are.equal("fixed traceback path", completed.history_summary)
        assert.are.same({ "abc12345" }, completed.history_commits)
    end)
end)
