local Config = require("clodex.config")
local Preview = require("clodex.ui.state_preview")
local fs = require("clodex.util.fs")

local function temp_dir()
    local dir = vim.fn.tempname()
    fs.ensure_dir(dir)
    return dir
end

describe("clodex.ui.state_preview", function()
    it("shows prompt skill details in the state panel", function()
        local root = temp_dir()
        local skill_file = fs.join(root, ".codex", "skills", "prompt-nvim-clodex", "SKILL.md")
        fs.write_file(skill_file, "---\nname: prompt-nvim-clodex\n---\nSkill body\n")

        local preview = Preview.new(Config.new():setup())
        preview:ensure_buffers()
        preview.app = {
            execution = {
                uses_prompt_skill = function()
                    return true
                end,
                skill_file = function(_, project)
                    assert.are.equal(root, project.root)
                    return skill_file
                end,
            },
        }

        preview:render_state({
            current_tab = {
                tabpage = 1,
                has_visible_window = true,
                session_key = "project:" .. root,
                window_id = 1,
            },
            current_path = root,
            active_project = {
                name = "Demo",
                root = root,
            },
            detected_project = nil,
            resolved_target = {
                kind = "project",
                project = {
                    name = "Demo",
                },
            },
            project_states = {},
            tabs = {},
        })

        local lines = vim.api.nvim_buf_get_lines(preview.state_buf, 0, -1, false)
        assert.is_true(vim.tbl_contains(lines, "Prompt Skill"))
        assert.is_true(vim.tbl_contains(lines, "project:             Demo"))
        assert.is_true(vim.tbl_contains(lines, "status:              created"))
        assert.is_true(vim.tbl_contains(lines, "  ---"))
        assert.is_true(vim.tbl_contains(lines, "  name: prompt-nvim-clodex"))
        assert.is_true(vim.tbl_contains(lines, "  Skill body"))

        fs.remove(root)
    end)

    it("renders the command pane with bare command names only", function()
        local preview = Preview.new(Config.new():setup())
        preview:ensure_buffers()

        preview:render_commands()

        local lines = vim.api.nvim_buf_get_lines(preview.command_buf, 0, -1, false)

        assert.is_true(#lines > 0)
        assert.is_true(vim.startswith(lines[1], "Clodex"))
        assert.is_nil(lines[1]:find(":", 1, true))
        assert.is_nil(lines[1]:find("  ", 1, true))
    end)
end)
