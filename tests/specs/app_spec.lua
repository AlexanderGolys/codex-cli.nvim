local App = require("clodex.app")

describe("clodex.app", function()
    it("sorts queue workspace projects by active state, running sessions, and workspace updates", function()
        local alpha = { name = "Alpha", root = "/tmp/alpha" }
        local beta = { name = "Beta", root = "/tmp/beta" }
        local gamma = { name = "Gamma", root = "/tmp/gamma" }
        local delta = { name = "Delta", root = "/tmp/delta" }
        local epsilon = { name = "Epsilon", root = "/tmp/epsilon" }

        local timestamps = {
            [alpha.root] = "2026-03-16T19:00:00Z",
            [beta.root] = "2026-03-16T19:30:00Z",
            [gamma.root] = "2026-03-16T18:00:00Z",
            [delta.root] = "2026-03-16T19:45:00Z",
        }
        local running = {
            [beta.root] = true,
            [delta.root] = true,
        }

        local app = setmetatable({
            registry = {
                list = function()
                    return { alpha, beta, gamma, delta, epsilon }
                end,
            },
            current_tab = function()
                return { active_project_root = gamma.root }
            end,
            is_project_session_running = function(_, project)
                return running[project.root] == true
            end,
            queue = {
                summary = function(_, project, session_running)
                    return {
                        project = project,
                        session_running = session_running,
                        last_updated_at = timestamps[project.root] or "",
                        counts = {
                            planned = 0,
                            queued = 0,
                            implemented = 0,
                            history = 0,
                        },
                        queues = {
                            planned = {},
                            queued = {},
                            implemented = {},
                            history = {},
                        },
                    }
                end,
            },
        }, App)

        local projects = app:projects_for_queue_workspace()

        assert.are.same({ gamma, delta, beta, alpha, epsilon }, projects)
    end)
end)
