local ui = require("clodex.ui.select")
local notify = require("clodex.util.notify")

--- Defines the Clodex.ProjectPicker.Item type for this module.
--- This annotation documents structured state so modules can pass data with consistent expectations.
---@class Clodex.ProjectPicker.Item
---@field project? Clodex.Project
---@field label string
---@field spacer? string
---@field preview? { text: string, ft?: string, loc?: boolean }
---@field preview_title? string

--- Defines the Clodex.ProjectPicker type for this module.
--- This annotation documents structured state so modules can pass data with consistent expectations.
---@class Clodex.ProjectPicker
---@field registry Clodex.ProjectRegistry
local Picker = {}
Picker.__index = Picker

--- Creates a new project picker instance from this module.
--- It is used by callers to bootstrap module state before running higher-level plugin actions.
---@param registry Clodex.ProjectRegistry
---@return Clodex.ProjectPicker
function Picker.new(registry)
    local self = setmetatable({}, Picker)
    self.registry = registry
    return self
end

--- Implements the preview_text path for project picker.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param project Clodex.Project
---@param active_root? string
---@return string
function Picker:preview_text(project, active_root)
    local exists = vim.uv.fs_stat(project.root) ~= nil and "yes" or "no"
    local active = active_root and active_root == project.root and "yes" or "no"
    return table.concat({
        "# Clodex Project",
        "",
        ("- Name: `%s`"):format(project.name),
        ("- Root: `%s`"):format(project.root),
        ("- Exists on disk: `%s`"):format(exists),
        ("- Active in this tab: `%s`"):format(active),
    }, "\n")
end

--- Implements the format_item path for project picker.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param item Clodex.ProjectPicker.Item
---@param supports_chunks? boolean
---@return string|snacks.picker.Highlight[]
function Picker:format_item(item, supports_chunks)
    if not item.project then
        return item.label
    end
    if not supports_chunks then
        return item.label
    end
    return {
        { item.project.name,  "ClodexPickerProject" },
        { item.spacer or "  " },
        { item.project.root,  "ClodexPickerRoot" },
    }
end

---@param opts? {
---include_none?: boolean,
---prompt?: string,
---active_root?: string,
---on_delete?: fun(project: Clodex.Project),
---on_rename?: fun(project: Clodex.Project),
---snacks?: table,
---}
---@param on_choice fun(project?: Clodex.Project)
function Picker:pick(opts, on_choice)
    opts = opts or {}
    local projects = self.registry:list()
    local items = {} ---@type Clodex.ProjectPicker.Item[]
    local name_width = 0
    local snacks_opts = vim.tbl_deep_extend("force", {
        preview = "preview",
        layout = {
            preset = "select",
            hidden = {},
        },
    }, vim.deepcopy(opts.snacks or {}))
    local action_hints = {} ---@type string[]

    if opts.include_none then
        items[#items + 1] = {
            label = "No active project",
            preview = {
                text = "# Clodex Project\n\n- Active project override is disabled for this tab.",
                ft = "markdown",
                loc = false,
            },
            preview_title = "No active project",
        }
    end

    for _, project in ipairs(projects) do
        name_width = math.max(name_width, vim.fn.strdisplaywidth(project.name))
    end

    for _, project in ipairs(projects) do
        local spacer = (" "):rep(math.max(name_width - vim.fn.strdisplaywidth(project.name), 0) + 2)
        items[#items + 1] = {
            project = project,
            label = project.name .. spacer .. project.root,
            spacer = spacer,
            preview = {
                text = self:preview_text(project, opts.active_root),
                ft = "markdown",
                loc = false,
            },
            preview_title = project.name,
        }
    end

    if #items == 0 then
        notify.warn("No Clodex projects configured")
        return
    end

    if opts.on_delete then
        snacks_opts.actions = snacks_opts.actions or {}
        snacks_opts.actions.codex_project_delete = {
            desc = "Delete project",
            action = function(picker, item)
                item = item and item.item or item
                if not item or not item.project then
                    notify.warn("No project selected")
                    return
                end
                local project = item.project
                if picker and picker.close then
                    picker:close()
                end
                vim.schedule(function()
                    opts.on_delete(project)
                end)
            end,
        }
        action_hints[#action_hints + 1] = "d: Delete project"

        snacks_opts.win = snacks_opts.win or {}
        snacks_opts.win.input = snacks_opts.win.input or {}
        snacks_opts.win.input.keys = snacks_opts.win.input.keys or {}
        snacks_opts.win.input.keys["d"] = { "codex_project_delete", mode = { "n", "i" } }

        snacks_opts.win.list = snacks_opts.win.list or {}
        snacks_opts.win.list.keys = snacks_opts.win.list.keys or {}
        snacks_opts.win.list.keys["d"] = { "codex_project_delete", mode = { "n", "i" } }
    end

    if opts.on_rename then
        snacks_opts.actions = snacks_opts.actions or {}
        snacks_opts.actions.codex_project_rename = {
            desc = "Rename project",
            action = function(picker, item)
                item = item and item.item or item
                if not item or not item.project then
                    notify.warn("No project selected")
                    return
                end
                local project = item.project
                if picker and picker.close then
                    picker:close()
                end
                vim.schedule(function()
                    opts.on_rename(project)
                end)
            end,
        }
        action_hints[#action_hints + 1] = "r: Rename project"

        snacks_opts.win = snacks_opts.win or {}
        snacks_opts.win.input = snacks_opts.win.input or {}
        snacks_opts.win.input.keys = snacks_opts.win.input.keys or {}
        snacks_opts.win.input.keys["r"] = { "codex_project_rename", mode = { "n", "i" } }

        snacks_opts.win.list = snacks_opts.win.list or {}
        snacks_opts.win.list.keys = snacks_opts.win.list.keys or {}
        snacks_opts.win.list.keys["r"] = { "codex_project_rename", mode = { "n", "i" } }
    end

    if #action_hints > 0 then
        snacks_opts.help = snacks_opts.help or true
        notify.notify(("Project actions: %s"):format(table.concat(action_hints, ", ")))
    end

    ui.select(items, {
        prompt = opts.prompt or "Select Clodex project",
        format_item = function(item, supports_chunks)
            return self:format_item(item, supports_chunks)
        end,
        snacks = snacks_opts,
    }, function(item)
        on_choice(item and item.project or nil)
    end)
end

--- Opens a picker path for project picker and handles the chosen result.
--- It is used by user-driven selection flows to continue the action pipeline with valid input.
---@param on_choice fun(project?: Clodex.Project)
function Picker:pick_for_removal(on_choice)
    return self:pick({ prompt = "Remove Clodex project" }, on_choice)
end

--- Opens a picker for project rename flows.
--- Enter accepts the highlighted project and rename remains available as a picker action too.
---@param active_root? string
---@param on_choice fun(project?: Clodex.Project)
function Picker:pick_for_rename(active_root, on_choice)
    return self:pick({
        prompt = "Rename Clodex project",
        active_root = active_root,
        on_rename = on_choice,
    }, on_choice)
end

return Picker
