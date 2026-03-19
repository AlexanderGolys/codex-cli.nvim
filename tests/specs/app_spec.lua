package.loaded["snacks.input"] = {
    input = function() end,
}
package.loaded["snacks.picker.select"] = {
    select = function() end,
}
package.loaded["snacks.terminal"] = {
    open = function()
        return {
            hide = function() end,
        }
    end,
}

local App = require("clodex.app")
local Commands = require("clodex.commands")

describe("clodex.app", function()
    it("sorts queue workspace projects by active state, running sessions, and project update timestamps", function()
        local alpha = { name = "Alpha", root = "/tmp/alpha" }
        local beta = { name = "Beta", root = "/tmp/beta" }
        local gamma = { name = "Gamma", root = "/tmp/gamma" }
        local delta = { name = "Delta", root = "/tmp/delta" }
        local epsilon = { name = "Epsilon", root = "/tmp/epsilon" }

        local timestamps = {
            [alpha.root] = { last_file_modified_at = 100 },
            [beta.root] = { last_file_modified_at = 300 },
            [gamma.root] = { last_file_modified_at = 50 },
            [delta.root] = { last_file_modified_at = 450 },
            [epsilon.root] = { last_codex_activity_at = 75 },
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
            project_details_store = {
                get_cached = function(_, project)
                    return timestamps[project.root]
                end,
            },
            terminals = {
                is_project_session_working = function()
                    return false
                end,
            },
            is_project_session_running = function(_, project)
                return running[project.root] == true
            end,
            queue = {
                summary = function(_, project, session_running)
                    return {
                        project = project,
                        session_running = session_running,
                        last_updated_at = "",
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

    it("captures the selected backend in state snapshots", function()
        local app = setmetatable({
            config = {
                get = function()
                    return { backend = "opencode" }
                end,
            },
            terminals = {
                snapshot = function()
                    return {}
                end,
            },
            registry = {
                list = function()
                    return {}
                end,
                find_for_path = function()
                    return nil
                end,
            },
            current_tab = function()
                return {
                    snapshot = function()
                        return { tabpage = 1, has_visible_window = false }
                    end,
                }
            end,
            tabs = {
                snapshot = function()
                    return {}
                end,
            },
            project_bookmarks = { count = function() return 0 end },
            project_notes = { count = function() return 0 end },
            project_cheatsheet = { count = function() return 0 end, items = function() return {} end },
            is_project_working = function()
                return false
            end,
            is_project_session_running = function()
                return false
            end,
            resolve_target_from_path = function()
                return { kind = "free", cwd = vim.loop.cwd() }
            end,
        }, App)

        local snapshot = app:state_snapshot()

        assert.are.equal("opencode", snapshot.backend)
    end)

    it("lists the backend toggle command and keymap", function()
        local commands = Commands.list()
        local command_names = vim.tbl_map(function(item)
            return item.name
        end, commands)
        local keymaps = Commands.list_keymaps({
            keymaps = {
                toggle = { lhs = "<leader>pt" },
                queue_workspace = { lhs = "<leader>pq" },
                state_preview = { lhs = "<leader>ps" },
                backend_toggle = { lhs = "<leader>pb" },
            },
        })

        assert.is_true(vim.tbl_contains(command_names, "ClodexBackendToggle"))
        assert.is_true(vim.tbl_contains(vim.tbl_map(function(item)
            return item.lhs
        end, keymaps), "<leader>pb"))
    end)
end)
