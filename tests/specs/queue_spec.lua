local Queue = require("clodex.workspace.queue")
local fs = require("clodex.util.fs")

local function temp_dir()
    local dir = vim.fn.tempname()
    fs.ensure_dir(dir)
    return dir
end

local function new_project(root)
    return {
        name = "Test Project",
        root = fs.join(root, "project"),
    }
end

describe("clodex.workspace.queue", function()
    local workspace_root
    local project
    local queue

    before_each(function()
        workspace_root = temp_dir()
        project = new_project(workspace_root)
        fs.ensure_dir(project.root)
        queue = Queue.new(workspace_root)
    end)

    after_each(function()
        queue = nil
        if project then
            fs.remove(project.root)
        end
        if workspace_root then
            fs.remove(workspace_root)
        end
    end)

    it("adds todos to planned with stable prompt text", function()
        local item = queue:add_todo(project, {
            title = "  implement retry logic  ",
            details = "should include backoff\nand jitter",
            kind = "todo",
        })

        assert.are.equal("implement retry logic", item.title)
        assert.are.equal("todo", item.kind)
        assert.are.equal("implement retry logic\n\nshould include backoff\nand jitter", item.prompt)
        assert.matches("^[0-9a-f%-]+$", item.id)
    end)

    it("stores ask prompts as a first-class queue kind", function()
        local item = queue:add_todo(project, {
            title = "ask about the parser",
            queue = "queued",
            kind = "ask",
        })

        assert.are.equal("ask", item.kind)
        assert.are.equal("queued", queue:find_item(project, item.id))
    end)

    it("keeps legacy explain prompts mapped to the ask behavior", function()
        local item = queue:add_todo(project, {
            title = "explain the parser",
            kind = "explain",
        })

        assert.are.equal("explain", item.kind)
    end)

    it("moves a queued item to implemented", function()
        local item = queue:add_todo(project, {
            title = "queued item",
            details = "run after config fix",
            queue = "queued",
            kind = "bug",
        })

        assert.are.equal("queued", queue:find_item(project, item.id))
        local advanced = queue:advance(project, item.id)
        assert.are.equal("implemented", advanced)
        local summary = queue:summary(project, false)
        assert.are.equal(1, summary.counts.implemented)
        assert.are.equal(0, summary.counts.queued)
    end)

    it("stores internal completion targets for queue items", function()
        local item = queue:add_todo(project, {
            title = "runtime traceback",
            queue = "queued",
            kind = "bug",
            completion_target = "history",
        })

        local _, _, stored = queue:find_item(project, item.id)

        assert.are.equal("history", stored.completion_target)
    end)

    it("updates details, kind, and prompt together", function()
        local item = queue:add_todo(project, {
            title = "old title",
            details = "old details",
            queue = "planned",
            kind = "todo",
        })
        local updated = queue:update_item(project, item.id, {
            title = "new title",
            details = "new details",
            kind = "freeform",
        })

        assert.are.equal("new title", updated.title)
        assert.are.equal("new details", updated.details)
        assert.are.equal("freeform", updated.kind)
        assert.are.equal("new title\n\nnew details", updated.prompt)
    end)

    it("keeps legacy adjustment items valid", function()
        local item = queue:add_todo(project, {
            title = "legacy adjustment",
            kind = "adjustment",
        })

        assert.are.equal("adjustment", item.kind)
    end)

    it("updates an implemented item with execution metadata", function()
        local item = queue:add_todo(project, {
            title = "fix line",
            details = "use focused edit",
            queue = "queued",
            kind = "todo",
        })
        queue:advance(project, item.id)

        local completed = queue:update_implemented_item(project, item.id, {
            summary = "implemented",
            commit = "abc123",
            completed_at = "2026-01-01T00:00:00Z",
        })

        assert.are.equal(item.id, completed.id)
        assert.are.equal("implemented", completed.history_summary)
        assert.are.same({ "abc123" }, completed.history_commits)
        assert.are.equal("2026-01-01T00:00:00Z", completed.history_completed_at)

        local summary = queue:summary(project, false)
        assert.are.equal(1, summary.counts.implemented)
        assert.are.equal(0, summary.counts.history)
    end)

    it("normalizes malformed history metadata when loading queue items", function()
        local item = queue:add_todo(project, {
            title = "history cleanup",
            queue = "queued",
            kind = "todo",
        })
        queue:advance(project, item.id)
        queue:update_item(project, item.id, {
            history_summary = vim.NIL,
            history_commits = { vim.NIL, "  abc12345  ", "" },
        })

        local _, _, stored = queue:find_item(project, item.id)

        assert.is_nil(stored.history_summary)
        assert.are.same({ "abc12345" }, stored.history_commits)
    end)

    it("reports the most recent workspace update in queue summaries", function()
        local first = queue:add_todo(project, {
            title = "older item",
            queue = "planned",
            kind = "todo",
        })
        local second = queue:add_todo(project, {
            title = "newer item",
            queue = "queued",
            kind = "todo",
        })

        local summary = queue:summary(project, false)

        assert.are.equal(second.updated_at, summary.last_updated_at)
        assert.are_not.equal("", summary.last_updated_at)
        assert.are_not.equal(first.updated_at, "")
    end)

    it("keeps queued items in insertion order", function()
        local first = queue:add_todo(project, {
            title = "first queued",
            queue = "queued",
            kind = "todo",
        })
        local second = queue:add_todo(project, {
            title = "second queued",
            queue = "queued",
            kind = "todo",
        })

        local queued = queue:queue(project, "queued")

        assert.are.equal(first.id, queued[1].id)
        assert.are.equal(second.id, queued[2].id)
    end)
end)
