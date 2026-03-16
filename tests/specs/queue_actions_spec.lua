local Queue = require("clodex.workspace.queue")
local QueueActions = require("clodex.app.queue_actions")
local fs = require("clodex.util.fs")

local function temp_dir()
    local dir = vim.fn.tempname()
    fs.ensure_dir(dir)
    return dir
end

local function new_project(root, name)
    return {
        name = name or "Test Project",
        root = fs.join(root, name or "project"),
    }
end

describe("clodex.app.queue_actions", function()
    local workspace_root
    local project
    local target_project
    local queue
    local actions
    local refresh_count

    before_each(function()
        workspace_root = temp_dir()
        project = new_project(workspace_root, "project-a")
        target_project = new_project(workspace_root, "project-b")
        fs.ensure_dir(project.root)
        fs.ensure_dir(target_project.root)
        queue = Queue.new(".clodex-test")
        refresh_count = 0
        actions = QueueActions.new({
            queue = queue,
            refresh_views = function()
                refresh_count = refresh_count + 1
            end,
        })
    end)

    after_each(function()
        actions = nil
        queue = nil
        if target_project then
            fs.remove(target_project.root)
        end
        if project then
            fs.remove(project.root)
        end
        if workspace_root then
            fs.remove(workspace_root)
        end
    end)

    it("moves a history item back to queued when the source queue is specified", function()
        local item = queue:add_todo(project, {
            title = "fix prompt flow",
            details = "return to queued",
            queue = "queued",
            kind = "todo",
        })
        queue:complete_queued_item(project, item.id, {
            summary = "implemented",
            completed_at = "2026-01-01T00:00:00Z",
        })

        actions:rewind_queue_item(project, item.id, { queue = "history" })

        local queue_name, _, moved = queue:find_item(project, item.id)
        assert.are.equal("queued", queue_name)
        assert.are.equal(nil, moved.history_summary)
        assert.are.equal(nil, moved.history_completed_at)
        assert.are.equal(1, refresh_count)
    end)

    it("moves a history item back to queued marked as not working", function()
        local item = queue:add_todo(project, {
            title = "fix prompt flow",
            details = "return to queued",
            queue = "queued",
            kind = "todo",
        })
        queue:complete_queued_item(project, item.id, {
            summary = "implemented",
            completed_at = "2026-01-01T00:00:00Z",
        })

        actions:rewind_queue_item(project, item.id, {
            queue = "history",
            mark_not_working = true,
        })

        local queue_name, _, moved = queue:find_item(project, item.id)
        assert.are.equal("queued", queue_name)
        assert.are.equal("error", moved.kind)
        assert.are.equal(
            "The previously implemented behavior is not working as expected. Investigate the regression and fix it.\n\nreturn to queued",
            moved.details
        )
        assert.are.equal(
            "fix prompt flow\n\nThe previously implemented behavior is not working as expected. Investigate the regression and fix it.\n\nreturn to queued",
            moved.prompt
        )
        assert.are.equal(nil, moved.history_summary)
        assert.are.equal(nil, moved.history_completed_at)
        assert.are.equal(1, refresh_count)
    end)

    it("moves a history item to another project when the source queue is specified", function()
        local item = queue:add_todo(project, {
            title = "share prompt",
            queue = "queued",
            kind = "todo",
        })
        queue:complete_queued_item(project, item.id, {
            summary = "done",
        })

        actions:move_queue_item_to_project(project, item.id, target_project, {
            source_queue = "history",
            target_queue = "queued",
        })

        local source_queue_name = queue:find_item(project, item.id)
        local target_queues = queue:queues(target_project)

        assert.are.equal(nil, source_queue_name)
        assert.are.equal(1, #target_queues.queued)
        assert.are.equal("share prompt", target_queues.queued[1].title)
        assert.are.equal(nil, target_queues.queued[1].history_summary)
        assert.are.equal(0, #target_queues.history)
        assert.are.equal(1, refresh_count)
    end)
end)
