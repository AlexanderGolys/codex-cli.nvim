local Config = require("clodex.config")
local Preview = require("clodex.ui.state_preview")
local fs = require("clodex.util.fs")

local function temp_dir()
    local dir = vim.fn.tempname()
    fs.ensure_dir(dir)
    return dir
end

describe("clodex.ui.state_preview", function()
    after_each(function()
        for _, name in ipairs({ "clodex-state-preview-state", "clodex-state-preview-commands" }) do
            local bufnr = vim.fn.bufnr(name)
            if bufnr > 0 and vim.api.nvim_buf_is_valid(bufnr) then
                pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
            end
        end
    end)

    it("shows prompt skill details in the state panel", function()
        local root = temp_dir()
        local skill_file = fs.join(root, "skills", "prompt-nvim-clodex", "SKILL.md")
        fs.write_file(skill_file, "---\nname: prompt-nvim-clodex\n---\nSkill body\n")

        local preview = Preview.new(Config.new():setup())
        preview:ensure_buffers()
        preview.app = {
            execution = {
                uses_prompt_skill = function()
                    return true
                end,
                skill_file = function()
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
        assert.is_true(vim.tbl_contains(lines, "status:              synced"))
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
