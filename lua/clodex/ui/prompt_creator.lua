local PromptAssets = require("clodex.prompt.assets")
local DraftStore = require("clodex.prompt.draft_store")
local KindRegistry = require("clodex.prompt.kind_registry")
local Prompt = require("clodex.prompt")
local PromptSubmit = require("clodex.prompt.submit")
local Extmark = require("clodex.ui.extmark")
local ui_select = require("clodex.ui.select")
local notify = require("clodex.util.notify")
local ui_win = require("clodex.ui.win")

local layout_modules = {
    composer = require("clodex.ui.prompt_creator.layouts.composer"),
    clipboard_preview = require("clodex.ui.prompt_creator.layouts.clipboard_preview"),
}

---@class Clodex.PromptCreator.OpenOpts
---@field app Clodex.App
---@field project Clodex.Project
---@field context? Clodex.PromptContext.Capture
---@field projects? Clodex.Project[]
---@field active_project_root? string
---@field initial_kind? Clodex.PromptCategory
---@field submit_actions? Clodex.UiSelect.MultilineAction[]
---@field mode? "new"|"edit"
---@field lock_kind? boolean
---@field initial_draft? table
---@field on_submit fun(spec: Clodex.AppPromptActions.AddTodoSpec, action?: string, project?: Clodex.Project)

---@class Clodex.PromptCreator
---@field app Clodex.App
---@field projects Clodex.Project[]
---@field project Clodex.Project
---@field project_index integer
---@field context? Clodex.PromptContext.Capture
---@field submit_actions Clodex.UiSelect.MultilineAction[]
---@field mode "new"|"edit"
---@field lock_kind boolean
---@field on_submit fun(spec: Clodex.AppPromptActions.AddTodoSpec, action?: string, project?: Clodex.Project)
---@field kinds Clodex.PromptCategoryDef[]
---@field kind_index integer
---@field variant_index integer
---@field state table
---@field drafts Clodex.PromptDraftStore
---@field field_cache table<string, any>
---@field field_history table<string, any[]>
---@field layout any
---@field project_bg_buf integer
---@field project_buf integer
---@field kind_buf integer
---@field footer_buf integer
---@field variant_buf? integer
---@field preview_buf? integer
---@field project_bg_win? snacks.win
---@field project_win? snacks.win
---@field kind_win? snacks.win
---@field footer_win? snacks.win
---@field variant_win? snacks.win
---@field preview_win? snacks.win
---@field preview_placement? any
---@field anchor_win? integer
---@field close_watchers table<integer, integer>
---@field is_closing boolean
---@field suppress_close_events boolean
---@field project_line_map integer[]
---@field kind_tab_spans { start_col: integer, end_col: integer, index: integer }[]
---@field variant_tab_spans { start_col: integer, end_col: integer, index: integer }[]
local Creator = {}
Creator.__index = Creator

local DEFAULT_SUBMIT_ACTIONS = {
    { value = "save", label = "plan", key = "<C-s>" },
    { value = "queue", label = "queue", key = "<C-q>" },
    { value = "exec", label = "run now", key = "<C-e>" },
    { value = "chat", label = "chat", key = "<C-l>" },
}

local TAB_NS = vim.api.nvim_create_namespace("clodex-prompt-creator-tabs")
local FOOTER_NS = vim.api.nvim_create_namespace("clodex-prompt-creator-footer")

---@class Clodex.PromptCreatorLayoutConfig
---@field tab_padding integer
---@field min_window_offset integer
---@field project_picker_margin_rows integer
---@field project_picker_margin_cols integer
---@field creator_background_margin_rows integer
---@field creator_background_margin_cols integer
---@field prompt_background_zindex integer
---@field prompt_content_zindex integer
---@field prompt_background_margin integer
---@field creator_max_height integer
---@field creator_screen_margin_cols integer
---@field creator_screen_margin_rows integer
---@field creator_panel_gap_cols integer
---@field tab_row_height integer
---@field title_gap_rows integer
---@field body_gap_rows integer
---@field footer_gap_rows integer
---@field preview_width_ratio number
---@field preview_min_width integer
---@field preview_max_width integer
---@field preview_min_height integer
---@field preview_image_inset integer
---@field project_list_min_width integer
---@field project_list_max_width integer
---@field project_name_padding integer
---@field content_min_width integer
---@field body_min_height integer
---@field clipboard_note_min_height integer
---@field clipboard_note_max_height integer
---@field clipboard_note_reserved_rows integer
---@field clipboard_preview_gap_rows integer
---@field clipboard_preview_min_height integer
---@field base_width_with_image integer
---@field base_width_without_image integer
---@type Clodex.PromptCreatorLayoutConfig
local LAYOUT = {
    tab_padding = 1,
    min_window_offset = 1,
    project_picker_margin_rows = 1,
    project_picker_margin_cols = 2,
    creator_background_margin_rows = 1,
    creator_background_margin_cols = 1,
    prompt_background_zindex = 1,
    prompt_content_zindex = 20,
    prompt_background_margin = 1,
    creator_max_height = 32,
    creator_screen_margin_cols = 6,
    creator_screen_margin_rows = 4,
    creator_panel_gap_cols = 2,
    tab_row_height = 2,
    title_gap_rows = 2,
    body_gap_rows = 3,
    footer_gap_rows = 2,
    preview_width_ratio = 0.3,
    preview_min_width = 28,
    preview_max_width = 42,
    preview_min_height = 8,
    preview_image_inset = 2,
    project_list_min_width = 18,
    project_list_max_width = 28,
    project_name_padding = 2,
    content_min_width = 36,
    body_min_height = 8,
    clipboard_note_min_height = 4,
    clipboard_note_max_height = 6,
    clipboard_note_reserved_rows = 5,
    clipboard_preview_gap_rows = 3,
    clipboard_preview_min_height = 4,
    base_width_with_image = 156,
    base_width_without_image = 118,
}

---@param value integer
---@param minimum integer
---@param maximum integer
---@return integer
local function clamp(value, minimum, maximum)
    return math.min(math.max(value, minimum), maximum)
end

---@param win? snacks.win
---@return integer
local function window_border_padding(win)
    if not win or not win.opts then
        return 0
    end

    local border = win.opts.border
    if border == nil or border == "none" then
        return 0
    end

    return 1
end

---@param win? snacks.win
---@return boolean
local function prompt_win_valid(win)
    return win ~= nil and ui_win.is_valid(win.win)
end

---@param win? snacks.win
local function close_prompt_win(win)
    if not win then
        return
    end

    local winid = win.win
    if win.close then
        pcall(function()
            win:close()
        end)
    else
        ui_win.close(winid)
    end
    if ui_win.is_valid(winid) then
        ui_win.close(winid)
    end
    if win.close then
        win.win = nil
    end
end

---@param win? integer
---@return boolean
local function is_layout_anchor_win(win)
    if type(win) ~= "number" or win <= 0 or not vim.api.nvim_win_is_valid(win) then
        return false
    end

    return vim.api.nvim_win_get_config(win).relative == ""
end

---@param buf integer
---@return string?
local function prompt_context_base_at_cursor(buf)
    if not vim.api.nvim_buf_is_valid(buf) or vim.api.nvim_get_current_buf() ~= buf then
        return nil
    end

    local cursor_col = vim.api.nvim_win_get_cursor(0)[2]
    local line = vim.api.nvim_get_current_line()
    local start_col = cursor_col
    while start_col > 0 do
        local char = line:sub(start_col, start_col)
        if char:match("[%w_&]") == nil then
            break
        end
        start_col = start_col - 1
    end

    local base = line:sub(start_col + 1, cursor_col)
    if base == "" or not vim.startswith(base, "&") then
        return nil
    end
    return base
end

---@param app? Clodex.App
---@param project Clodex.Project
---@return Clodex.ProjectDetails.Snapshot?
local function project_details(app, project)
    local store = app and app.project_details_store or nil
    if not store then
        return nil
    end
    return store:get_cached(project) or (store.get and store:get(project)) or nil
end

---@param bufs integer[]
local function close_prompt_buffer_windows(bufs)
    if not bufs or #bufs == 0 then
        return
    end

    local targets = {}
    for _, buf in ipairs(bufs) do
        if type(buf) == "number" and buf > 0 and vim.api.nvim_buf_is_valid(buf) then
            targets[buf] = true
        end
    end

    if vim.tbl_isempty(targets) then
        return
    end

    for _, winid in ipairs(vim.api.nvim_list_wins()) do
        local ok, buf = pcall(vim.api.nvim_win_get_buf, winid)
        if ok and targets[buf] then
            ui_win.close(winid)
        end
    end
end

local function prompt_buffer(preset)
    return ui_win.create_buffer({
        preset = preset,
        bo = { bufhidden = "hide" },
    })
end

local PROMPT_THEME_WINDOW_FIELDS = {
    { name = "project_win" },
    { name = "kind_win" },
    { name = "footer_win" },
    { name = "variant_win" },
    { name = "preview_win" },
    { name = "layout", slots = { "title_win", "body_win", "preview_win", "footer_win" } }, 
}

---@param parts string[]
---@return string
local function footer_line(parts)
    return table.concat(parts, "   ")
end

---@param image_path string
---@return string[]
local function preview_fallback_lines(image_path)
    return {
        "# Clipboard image",
        "",
        ("`%s`"):format(image_path),
        "",
        "Inline preview unavailable. The prompt still keeps the attached image path.",
    }
end

---@param insert_mode boolean
---@param has_variants boolean
---@param has_multiple_projects boolean
local function footer_lines(insert_mode, has_variants, has_multiple_projects)
    if insert_mode then
        return {
            "Tab/Shift-Tab: move focus   Ctrl-V: image",
            "Ctrl-←/→: kind   Ctrl-S: plan   Ctrl-Q: queue   Ctrl-E: run now   Ctrl-L: chat   q: close",
        }
    end

    local row_one = {
        "←/→ or h/l: kind",
    }
    if has_multiple_projects then
        row_one[#row_one + 1] = "↑/↓ or j/k: project"
    end
    if has_variants then
        row_one[#row_one + 1] = "[/]: source"
    end
    row_one[#row_one + 1] = "Ctrl-V: image"

    return {
        footer_line(row_one),
        "Ctrl-←/→: kind (insert)   Ctrl-S: plan   Ctrl-Q: queue   Ctrl-E: run now   Ctrl-L: chat   q: close",
    }
end

---@param insert_mode boolean
---@param has_variants boolean
---@param has_multiple_projects boolean
local function footer_key_labels(insert_mode, has_variants, has_multiple_projects)
    if insert_mode then
        return {
            { row = 0, text = "Tab/Shift-Tab" },
            { row = 0, text = "Ctrl-V" },
            { row = 1, text = "Ctrl-←/→" },
            { row = 1, text = "Ctrl-S" },
            { row = 1, text = "Ctrl-Q" },
            { row = 1, text = "Ctrl-E" },
            { row = 1, text = "Ctrl-L" },
        }
    end

    return {
        { row = 0, text = "←/→" },
        { row = 0, text = "h/l" },
        { row = 0, text = "Ctrl-V" },
        { row = 1, text = "Ctrl-S" },
        { row = 1, text = "Ctrl-Q" },
        { row = 1, text = "Ctrl-E" },
        { row = 1, text = "Ctrl-L" },
        { row = 1, text = "q: close" },
    }
end

---@param winid integer
---@param mappings table<string, string>
local function update_winhl(winid, mappings)
    if winid == 0 or not vim.api.nvim_win_is_valid(winid) then
        return
    end

    local winhl = vim.wo[winid].winhl or ""
    local fields = {}
    for part in winhl:gmatch("[^,]+") do
        local source, target = part:match("^([^:]+):(.+)$")
        if source and target then
            fields[source] = target
        end
    end
    for source, target in pairs(mappings) do
        fields[source] = target
    end

    local parts = {}
    for source, target in pairs(fields) do
        parts[#parts + 1] = ("%s:%s"):format(source, target)
    end
    table.sort(parts)
    vim.wo[winid].winhl = table.concat(parts, ",")
end

---@param context? Clodex.PromptContext.Capture
---@param project Clodex.Project
---@return Clodex.PromptContext.Capture?
local function project_context(context, project)
    if not context then
        return nil
    end

    local updated = vim.deepcopy(context)
    updated.project_root = project.root
    if updated.file_path and updated.file_path ~= "" then
        local relative = vim.fs.relpath(project.root, updated.file_path)
        updated.relative_path = relative and relative ~= "" and relative or vim.fs.basename(updated.file_path)
    end
    return updated
end

---@param projects? Clodex.Project[]
---@param project Clodex.Project
---@return Clodex.Project[]
local function normalize_projects(projects, project)
    local items = {} ---@type Clodex.Project[]
    local seen = {} ---@type table<string, boolean>

    for _, item in ipairs(projects or {}) do
        if item and item.root and not seen[item.root] then
            seen[item.root] = true
            items[#items + 1] = item
        end
    end
    if project and project.root and not seen[project.root] then
        items[#items + 1] = project
    end
    return items
end

local function read_clipboard_message_register()
    for _, register in ipairs({ "+", '"', "*" }) do
        local message = vim.trim((vim.fn.getreg(register) or ""):gsub("\r\n", "\n"))
        if message ~= "" then
            return message
        end
    end
end

---@param kind Clodex.PromptCategory
---@param context? Clodex.PromptContext.Capture
---@return table?
local function selection_seed(kind, context)
    if not context or not context.selection_text then
        return nil
    end
    if kind == "bug" then
        return nil
    end
    local spec = require("clodex.prompt").parse(require("clodex.prompt").render(
        KindRegistry.get(kind).default_title,
        "&selection"
    ))
    return spec and {
        title = spec.title,
        details = spec.details or "",
    } or nil
end

---@param opts Clodex.PromptCreator.OpenOpts
---@return Clodex.PromptCreator
function Creator.new(opts)
    local kinds = {} ---@type Clodex.PromptCategoryDef[]
    for _, kind in ipairs(KindRegistry.list()) do
        if kind.id ~= "notworking" then
            kinds[#kinds + 1] = kind
        end
    end

    local initial_kind = KindRegistry.is_valid(opts.initial_kind) and opts.initial_kind or "todo"
    local projects = normalize_projects(opts.projects, opts.project)
    local project = opts.project
    local project_index = 1
    local active_project_root = opts.active_project_root or opts.project.root

    for index, item in ipairs(projects) do
        if item.root == active_project_root then
            project = item
            project_index = index
            break
        end
    end

    local kind_index = 1
    for index, kind in ipairs(kinds) do
        if kind.id == initial_kind then
            kind_index = index
            break
        end
    end

    local self = setmetatable({
        app = opts.app,
        projects = projects,
        project = project,
        project_index = project_index,
        context = project_context(opts.context, project),
        submit_actions = vim.deepcopy(opts.submit_actions or DEFAULT_SUBMIT_ACTIONS),
        mode = opts.mode or "new",
        lock_kind = opts.lock_kind == true,
        on_submit = opts.on_submit,
        kinds = kinds,
        kind_index = kind_index,
        variant_index = 1,
        state = {
            project = project,
            context = project_context(opts.context, project),
            kind = initial_kind,
            variant = nil,
            title = "",
            details = "",
            image_path = opts.initial_draft and opts.initial_draft.image_path or nil,
            preview_text = "",
        },
        drafts = DraftStore.new(),
        field_cache = {},
        field_history = {},
        project_bg_buf = prompt_buffer("scratch"),
        project_buf = prompt_buffer("scratch"),
        kind_buf = prompt_buffer("scratch"),
        footer_buf = prompt_buffer("scratch"),
        anchor_win = is_layout_anchor_win(vim.api.nvim_get_current_win()) and vim.api.nvim_get_current_win() or nil,
        close_watchers = {},
        is_closing = false,
        suppress_close_events = false,
        project_line_map = {},
        kind_tab_spans = {},
        variant_tab_spans = {},
    }, Creator)

    self:prime_drafts(opts.initial_draft)
    return self
end

---@param initial_draft? table
function Creator:prime_drafts(initial_draft)
    for _, kind in ipairs(self.kinds) do
        local default_mode = KindRegistry.default_mode(kind.id)
        for _, variant in ipairs(KindRegistry.modes(kind.id)) do
            local draft = kind.id == self.state.kind and initial_draft and variant.id == default_mode and vim.deepcopy(initial_draft)
                or (variant.id == default_mode and selection_seed(kind.id, self.context))
                or KindRegistry.default_draft(kind.id, variant.id)
            self.drafts:set(kind.id, variant.id, draft)
        end
    end
    self:sync_state_from_draft()
end

---@return Clodex.PromptCategory
function Creator:kind()
    return self.kinds[self.kind_index].id
end

---@return table[]
function Creator:variants()
    local modes = KindRegistry.modes(self:kind())
    if #modes <= 1 then
        return {}
    end
    return modes
end

---@return string?
function Creator:variant()
    local variants = KindRegistry.modes(self:kind())
    local current = variants[self.variant_index]
    return current and current.id or nil
end

function Creator:sync_state_from_draft()
    self.state.kind = self:kind()
    local kind_default_title = KindRegistry.get(self.state.kind).default_title or ""
    local variants = KindRegistry.modes(self.state.kind)
    local max_index = math.min(math.max(self.variant_index, 1), math.max(#variants, 1))
    self.variant_index = max_index
    self.state.variant = variants[self.variant_index] and variants[self.variant_index].id or KindRegistry.default_mode(self.state.kind)

    local default_draft = KindRegistry.default_draft(self.state.kind, self.state.variant)
    local draft = self:merge_cached_fields(
        self.state.kind,
        self.state.variant,
        self.drafts:get(self.state.kind, self.state.variant, default_draft),
        default_draft
    )
    self.state.title = ""
    self.state.details = ""
    self.state.image_path = nil
    self.state.preview_text = ""
    for key, value in pairs(draft) do
        self.state[key] = value
    end
    if self.mode == "new" and self.state.title == kind_default_title then
        self.state.title = ""
    end
    self.state.project = self.project
    self.state.context = self.context
    local variant = KindRegistry.mode(self.state.kind, self.state.variant)
    if variant.on_select then
        variant.on_select(self)
    end
end

---@param kind Clodex.PromptCategory
---@param variant? string
---@return string[]
function Creator:draft_fields_for(kind, variant)
    local layout = layout_modules[KindRegistry.layout_id(kind, variant)]
    if layout and layout.draft_fields then
        return layout.draft_fields(layout) or {}
    end
    return {}
end

---@param fields string[]
---@param draft table
function Creator:update_field_cache(fields, draft)
    for _, field in ipairs(fields) do
        if draft[field] ~= nil then
            local value = vim.deepcopy(draft[field])
            self.field_cache[field] = value
            self.field_history[field] = self.field_history[field] or {}
            local history = self.field_history[field]
            if not vim.deep_equal(history[#history], value) then
                history[#history + 1] = vim.deepcopy(value)
            end
        end
    end
end

---@param kind Clodex.PromptCategory
---@param variant? string
---@param draft table
---@param default_draft table
---@return table
function Creator:merge_cached_fields(kind, variant, draft, default_draft)
    local merged = vim.deepcopy(draft or {})
    for _, field in ipairs(self:draft_fields_for(kind, variant)) do
        local cached = self.field_cache[field]
        local current = merged[field]
        local default_value = default_draft[field]
        if cached ~= nil and (current == nil or current == "" or current == default_value) then
            merged[field] = vim.deepcopy(cached)
        end
    end
    return merged
end

---@return Clodex.PromptContext.Capture?
function Creator:prompt_context()
    return self.state.context or self.context
end

---@param buf integer
function Creator:refresh_prompt_context(buf)
    ui_select.refresh_prompt_context(buf, self:prompt_context())
end

---@param buf integer
function Creator:maybe_trigger_prompt_context_completion(buf)
    local base = prompt_context_base_at_cursor(buf)
    if not base or vim.fn.pumvisible() == 1 then
        return
    end

    if #ui_select.prompt_context_complete(0, base) == 0 then
        return
    end

    vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(buf) or vim.api.nvim_get_current_buf() ~= buf or vim.fn.pumvisible() == 1 then
            return
        end
        vim.api.nvim_feedkeys(vim.keycode("<C-x><C-u>"), "n", false)
    end)
end

function Creator:refresh_layout_prompt_contexts()
    if not self.layout or not self.layout.buffers then
        return
    end

    for _, buf in ipairs(self.layout:buffers()) do
        if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].modifiable then
            self:refresh_prompt_context(buf)
        end
    end
end

---@param buf integer
function Creator:trigger_context_completion(buf)
    self:refresh_prompt_context(buf)
    vim.cmd.startinsert()
    vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(buf) or vim.api.nvim_get_current_buf() ~= buf then
            return
        end
        vim.api.nvim_feedkeys(vim.keycode("&<C-x><C-u>"), "n", false)
    end)
end

---@param buf integer
function Creator:attach_prompt_context(buf)
    if not vim.bo[buf].modifiable then
        return
    end

    self:refresh_prompt_context(buf)
    vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
        buffer = buf,
        callback = function()
            self:refresh_prompt_context(buf)
            if vim.api.nvim_get_current_buf() == buf and vim.api.nvim_get_mode().mode:sub(1, 1) == "i" then
                self:maybe_trigger_prompt_context_completion(buf)
            end
        end,
    })
    vim.api.nvim_create_autocmd("BufWipeout", {
        once = true,
        buffer = buf,
        callback = function()
            ui_select.clear_prompt_context(buf)
        end,
    })
    vim.api.nvim_create_autocmd({ "InsertEnter", "InsertLeave" }, {
        buffer = buf,
        callback = function()
            if self.footer_buf and vim.api.nvim_buf_is_valid(self.footer_buf) then
                self:render_footer()
            end
        end,
    })
    vim.keymap.set("n", "&", function()
        self:trigger_context_completion(buf)
    end, { buffer = buf, silent = true })
    vim.keymap.set("i", "&", function()
        self:refresh_prompt_context(buf)
        return "&"
    end, { buffer = buf, silent = true, expr = true })
end

function Creator:save_current_draft()
    if self.layout and self.layout.get_draft then
        local draft = self.layout:get_draft()
        if draft then
            if self.state.preview_text and draft.preview_text == nil then
                draft.preview_text = self.state.preview_text
            end
            self:update_field_cache(self.layout.draft_fields and self.layout:draft_fields() or {}, draft)
            self.drafts:set(self.state.kind, self.state.variant, vim.tbl_extend("force", draft, {
                image_path = self.state.image_path,
                preview_text = self.state.preview_text,
            }))
        end
    end
end

---@return integer?, integer?, integer?, integer?
-- Uses the source split as the layout frame when the creator is opened from a normal window.
-- This keeps the whole prompt UI centered inside that split instead of the full editor grid.
function Creator:anchor_rect()
    local win = is_layout_anchor_win(self.anchor_win) and self.anchor_win or nil
    if not win then
        local current_win = vim.api.nvim_get_current_win()
        win = is_layout_anchor_win(current_win) and current_win or nil
    end
    if not win then
        return nil, nil, nil, nil
    end

    local position = vim.api.nvim_win_get_position(win)
    return position[2], position[1], vim.api.nvim_win_get_width(win), vim.api.nvim_win_get_height(win)
end

---@return string?
function Creator:read_clipboard_message()
    return read_clipboard_message_register()
end

---@return integer, integer
function Creator:editor_size()
    local _, _, width, height = self:anchor_rect()
    if width and height then
        return width, height
    end

    local ui = vim.api.nvim_list_uis()[1]
    return ui and ui.width or vim.o.columns, ui and ui.height or vim.o.lines
end

---@return integer
-- Total combined width of the creator content before the outer background margin is applied.
function Creator:total_width()
    local width = self:editor_size()
    local base_width = self.state.image_path and LAYOUT.base_width_with_image or LAYOUT.base_width_without_image
    return math.min(width - LAYOUT.creator_screen_margin_cols, base_width + self:project_panel_width() + LAYOUT.creator_panel_gap_cols)
end

---@return integer
-- Total combined height of the creator content before the outer background margin is applied.
function Creator:total_height()
    local _, height = self:editor_size()
    return math.min(height - LAYOUT.creator_screen_margin_rows, LAYOUT.creator_max_height)
end

---@return integer
-- Backdrop width: one extra column on each side so the background only shows in the gaps.
function Creator:project_background_width()
    local left, _, right = self:creator_frame_bounds()
    if left and right then
        return (right - left) + (LAYOUT.prompt_background_margin * 2)
    end
    return self:total_width() + (LAYOUT.creator_background_margin_cols * 2)
end

---@return integer
-- Left-side project column width including its inner padding inside the shared backdrop.
function Creator:project_panel_width()
    return self:project_list_width() + (LAYOUT.project_picker_margin_cols * 2)
end

---@return integer
-- Backdrop height: one extra row on each side so it frames the full creator layout.
function Creator:project_background_height()
    local _, top, _, bottom = self:creator_frame_bounds()
    if top and bottom then
        return (bottom - top) + (LAYOUT.prompt_background_margin * 2)
    end
    return self:total_height() + (LAYOUT.creator_background_margin_rows * 2)
end

---@return integer
function Creator:preview_width()
    if not self.state.image_path then
        return 0
    end
    return clamp(
        math.floor(self:total_width() * LAYOUT.preview_width_ratio),
        LAYOUT.preview_min_width,
        LAYOUT.preview_max_width
    )
end

---@return integer
function Creator:left_width()
    local preview_width = self:preview_width()
    local width = self:total_width() - preview_width
    if preview_width > 0 then
        width = width - LAYOUT.creator_panel_gap_cols
    end
    return width
end

---@return integer
function Creator:project_list_width()
    local width = LAYOUT.project_list_min_width
    for _, project in ipairs(self.projects) do
        local details = project_details(self.app, project)
        local icon = details and details.project_icon and (details.project_icon .. " ") or ""
        width = math.max(width, vim.fn.strdisplaywidth(icon .. project.name) + LAYOUT.project_name_padding)
    end
    return math.min(width, LAYOUT.project_list_max_width)
end

---@return integer
-- The main content area gets whatever remains after reserving project and preview columns.
function Creator:content_width()
    return math.max(self:left_width() - self:project_panel_width() - LAYOUT.creator_panel_gap_cols, LAYOUT.content_min_width)
end

---@return integer
function Creator:left_col()
    local anchor_col, _, width = self:anchor_rect()
    width = width or self:editor_size()
    return math.max((anchor_col or 0) + math.floor((width - self:total_width()) / 2), LAYOUT.min_window_offset)
end

---@return integer
-- Content starts after the project column plus the fixed gap between the two panels.
function Creator:content_col()
    return self:left_col() + self:project_panel_width() + LAYOUT.creator_panel_gap_cols
end

---@return integer
function Creator:top_row()
    local _, anchor_row, _, height = self:anchor_rect()
    local resolved_height = height or select(2, self:editor_size())
    return math.max((anchor_row or 0) + math.floor((resolved_height - self:total_height()) / 2), LAYOUT.min_window_offset)
end

---@return integer
function Creator:kind_row()
    return self:top_row()
end

---@return integer
-- Variant tabs, when present, occupy their own row between kind tabs and the title field.
function Creator:variant_row()
    return self:kind_row() + LAYOUT.tab_row_height
end

---@return integer
-- The title moves down when variant tabs are visible so the stacked tab rows never overlap.
function Creator:title_row()
    if #self:variants() > 0 then
        return self:variant_row() + LAYOUT.title_gap_rows
    end
    return self:kind_row() + LAYOUT.title_gap_rows
end

---@return integer
function Creator:body_row()
    return self:title_row() + LAYOUT.body_gap_rows
end

---@return integer
function Creator:footer_row()
    return self:top_row() + self:total_height()
end

---@return integer
-- Body height is derived from the space left between the title field and footer, not a fixed size.
function Creator:body_height()
    return math.max(self:footer_row() - self:body_row() - LAYOUT.footer_gap_rows, LAYOUT.body_min_height)
end

---@return integer
function Creator:clipboard_note_height()
    return clamp(
        self:body_height() - LAYOUT.clipboard_note_reserved_rows,
        LAYOUT.clipboard_note_min_height,
        LAYOUT.clipboard_note_max_height
    )
end

---@return integer
function Creator:clipboard_preview_row()
    return self:body_row() + self:clipboard_note_height() + LAYOUT.clipboard_preview_gap_rows
end

---@return integer
function Creator:clipboard_preview_height()
    return math.max(
        self:footer_row() - self:clipboard_preview_row() - LAYOUT.footer_gap_rows,
        LAYOUT.clipboard_preview_min_height
    )
end

---@return integer
function Creator:preview_col()
    return self:left_col() + self:left_width() + LAYOUT.creator_panel_gap_cols
end

---@return integer
function Creator:preview_row()
    return self:title_row()
end

---@return integer
-- The preview shares the vertical span from title through footer and uses the same gutter as the main panels.
function Creator:preview_height()
    return math.max(self:footer_row() - self:preview_row() + LAYOUT.creator_panel_gap_cols, LAYOUT.preview_min_height)
end

---@return snacks.image.Opts
function Creator:preview_image_opts()
    local width = self:preview_width()
    local height = self:preview_height()

    -- Constrain image rendering to the real preview window whenever it already
    -- exists. That keeps large screenshots inside the visible pane even if the
    -- floating window was clamped smaller than the ideal layout math.
    if self.preview_win and self.preview_win:valid() then
        width = vim.api.nvim_win_get_width(self.preview_win.win)
        height = vim.api.nvim_win_get_height(self.preview_win.win)
    end

    width = math.max(width - LAYOUT.preview_image_inset, LAYOUT.min_window_offset)
    height = math.max(height - LAYOUT.preview_image_inset, LAYOUT.min_window_offset)
    return {
        src = self.state.image_path,
        width = width,
        max_width = width,
        height = height,
        max_height = height,
    }
end

---@return integer?, integer?, integer?, integer?
-- Tracks the actual outer frame occupied by the visible creator windows so the
-- plain backdrop can wrap the full composed UI instead of approximating it.
function Creator:creator_frame_bounds()
    local windows = {
        self.project_win,
        self.kind_win,
        self.variant_win,
        self.footer_win,
        self.preview_win,
        self.layout and self.layout.title_win or nil,
        self.layout and self.layout.body_win or nil,
    }

    local left, top, right, bottom
    for _, win in ipairs(windows) do
        if win and win:valid() then
            local config = vim.api.nvim_win_get_config(win.win)
            local border = window_border_padding(win)
            local frame_left = config.col - border
            local frame_top = config.row - border
            local frame_right = config.col + config.width + border
            local frame_bottom = config.row + config.height + border

            left = left and math.min(left, frame_left) or frame_left
            top = top and math.min(top, frame_top) or frame_top
            right = right and math.max(right, frame_right) or frame_right
            bottom = bottom and math.max(bottom, frame_bottom) or frame_bottom
        end
    end

    return left, top, right, bottom
end

---@return integer
function Creator:project_row()
    return self:top_row()
end

---@return integer
-- The project picker lives inside the larger backdrop: picker margin plus outer backdrop margin.
function Creator:project_height()
    return math.max(self:total_height() - (LAYOUT.project_picker_margin_rows * 2), LAYOUT.min_window_offset)
end

---@return integer
function Creator:project_col()
    return self:left_col() + (LAYOUT.project_picker_margin_cols - LAYOUT.creator_background_margin_cols)
end

---@return integer
-- The shared backdrop starts one cell above the visible creator to create the intended outer margin.
function Creator:project_background_row()
    local _, top = self:creator_frame_bounds()
    if top then
        return top - LAYOUT.prompt_background_margin
    end
    return self:top_row() - LAYOUT.creator_background_margin_rows
end

---@return integer
-- The shared backdrop starts one cell left of the visible creator to create the intended outer margin.
function Creator:project_background_col()
    local left = self:creator_frame_bounds()
    if left then
        return left - LAYOUT.prompt_background_margin
    end
    return self:left_col() - LAYOUT.creator_background_margin_cols
end

---@param buf integer
---@param labels { label: string, hl_group: string, active_hl_group: string }[]
---@param active_index integer
---@param total_width integer
---@return { start_col: integer, end_col: integer, index: integer }[]
function Creator:render_tab_line(buf, labels, active_index, total_width)
    local parts = {} ---@type string[]
    local marks = {} ---@type Clodex.Extmark[]
    local spans = {} ---@type { start_col: integer, end_col: integer, index: integer }[]
    local col = 0

    for index, entry in ipairs(labels) do
        if index > 1 then
            parts[#parts + 1] = " "
            col = col + 1
        end

            local text = string.rep(" ", LAYOUT.tab_padding) .. entry.label .. string.rep(" ", LAYOUT.tab_padding)
        local start_col = col
        local end_col = start_col + #text
        parts[#parts + 1] = text
        marks[#marks + 1] = Extmark.inline(
            0,
            start_col,
            end_col,
            index == active_index and entry.active_hl_group or entry.hl_group
        )
        spans[#spans + 1] = {
            start_col = start_col,
            end_col = end_col,
            index = index,
        }
        col = end_col
    end

    local line = table.concat(parts)
    local pad = math.max(math.floor((total_width - vim.fn.strdisplaywidth(line)) / 2), 0)
    if pad > 0 then
        line = string.rep(" ", pad) .. line
        for _, span in ipairs(spans) do
            span.start_col = span.start_col + pad
            span.end_col = span.end_col + pad
        end
        for _, mark in ipairs(marks) do
            mark.start_pos[2] = mark.start_pos[2] + pad
            mark.end_pos[2] = mark.end_pos[2] + pad
        end
    end

    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { line })
    vim.bo[buf].modifiable = false
    vim.api.nvim_buf_clear_namespace(buf, TAB_NS, 0, -1)
    for _, mark in ipairs(marks) do
        mark:place(buf, TAB_NS)
    end
    return spans
end

---@param spans { start_col: integer, end_col: integer, index: integer }[]
---@param column integer
---@return integer?
local function tab_index_at_column(spans, column)
    local col = math.max((tonumber(column) or 1) - 1, 0)
    for _, span in ipairs(spans) do
        if col >= span.start_col and col < span.end_col then
            return span.index
        end
    end
end

---@return boolean
function Creator:in_insert_mode()
    return vim.api.nvim_get_mode().mode:sub(1, 1) == "i"
end

---@return { area: string, slot?: string, insert: boolean }?
function Creator:capture_focus_context()
    local current_win = vim.api.nvim_get_current_win()
    if self.layout and self.layout.focused_slot then
        local slot = self.layout:focused_slot(current_win)
        if slot then
            return {
                area = "layout",
                slot = slot,
                insert = self:in_insert_mode(),
            }
        end
    end

    local candidates = {
        project = self.project_win,
        kind = self.kind_win,
        variant = self.variant_win,
        footer = self.footer_win,
        preview = self.preview_win,
    }
    for area, win in pairs(candidates) do
        if win and win:valid() and current_win == win.win then
            return {
                area = area,
                insert = false,
            }
        end
    end
end

---@param context { area: string, slot?: string, insert: boolean }?
---@return boolean
function Creator:restore_focus_context(context)
    if not context then
        return false
    end

    if context.area == "layout" and self.layout and self.layout.focus_slot and self.layout:focus_slot(context.slot, context.insert) then
        return true
    end

    local win = nil ---@type snacks.win?
    if context.area == "project" then
        win = self.project_win
    elseif context.area == "kind" then
        win = self.kind_win
    elseif context.area == "variant" then
        win = self.variant_win
    elseif context.area == "footer" then
        win = self.footer_win
    elseif context.area == "preview" then
        win = self.preview_win
    end

    if not win or not win:valid() then
        return false
    end

    vim.api.nvim_set_current_win(win.win)
    return true
end

function Creator:focus_default()
    if self.layout and self.layout.focus_default then
        self.layout:focus_default()
    end
end

---@param fn fun()
function Creator:without_close_watchers(fn)
    self.suppress_close_events = true
    local ok, result = pcall(fn)
    self.suppress_close_events = false
    if not ok then
        error(result)
    end
    return result
end

function Creator:apply_shell_keymaps(buf)
    self:apply_common_keymaps(buf)
    vim.keymap.set("n", "<LeftMouse>", function()
        self:click_kind_tab()
        self:click_variant_tab()
    end, { buffer = buf, silent = true })
end

function Creator:focus_project_list()
    if not self.project_win or not self.project_win:valid() then
        return
    end

    local focus = function()
        if self.project_win and self.project_win:valid() then
            vim.api.nvim_set_current_win(self.project_win.win)
        end
    end

    if self:in_insert_mode() then
        vim.cmd.stopinsert()
    end

    vim.schedule(focus)
end

function Creator:focus_creator_default()
    if self:in_insert_mode() then
        vim.cmd.stopinsert()
    end
    vim.schedule(function()
        self:focus_default()
    end)
end

function Creator:focus_creator_last_slot()
    if self:in_insert_mode() then
        vim.cmd.stopinsert()
    end
    vim.schedule(function()
        if self.layout and self.layout.focus_last then
            self.layout:focus_last()
            return
        end
        self:focus_default()
    end)
end

---@param index integer
function Creator:set_project_index(index)
    local project = self.projects[index]
    if not project or (self.project and self.project.root == project.root) then
        return
    end

    self.project_index = index
    self.project = project
    self.context = project_context(self.context, project)
    self.state.project = project
    self.state.context = self.context
    self:render_project_list()
    self:refresh_layout_prompt_contexts()
end

---@param delta integer
function Creator:move_project(delta)
    local count = #self.projects
    if count <= 1 then
        return
    end
    self:set_project_index(((self.project_index - 1 + delta) % count) + 1)
end

function Creator:render_project_list()
    local lines = {} ---@type string[]
    local marks = {} ---@type Clodex.Extmark[]

    self.project_line_map = {}
    for index, project in ipairs(self.projects) do
        local details = project_details(self.app, project)
        local icon = details and details.project_icon and (details.project_icon .. " ") or ""
        local line = " " .. icon .. project.name
        lines[#lines + 1] = line
        self.project_line_map[#lines] = index
        marks[#marks + 1] = Extmark.inline(
            #lines - 1,
            0,
            #line,
            index == self.project_index and "ClodexPromptSourceTabActive" or "ClodexPromptSourceTab"
        )
    end

    vim.bo[self.project_buf].modifiable = true
    vim.api.nvim_buf_set_lines(self.project_buf, 0, -1, false, #lines > 0 and lines or { " No projects " })
    vim.bo[self.project_buf].modifiable = false
    vim.api.nvim_buf_clear_namespace(self.project_buf, TAB_NS, 0, -1)
    for _, mark in ipairs(marks) do
        mark:place(self.project_buf, TAB_NS)
    end

    if self.project_win and self.project_win:valid() then
        vim.api.nvim_win_set_cursor(self.project_win.win, { math.max(self.project_index, 1), 0 })
    end
end

function Creator:render_project_background()
    if not self.project_bg_buf or not vim.api.nvim_buf_is_valid(self.project_bg_buf) then
        return
    end

    local lines = {}
    for _ = 1, self:project_background_height() do
        lines[#lines + 1] = ""
    end

    vim.bo[self.project_bg_buf].modifiable = true
    vim.api.nvim_buf_set_lines(self.project_bg_buf, 0, -1, false, lines)
    vim.bo[self.project_bg_buf].modifiable = false
end

function Creator:apply_project_keymaps()
    vim.keymap.set({ "n", "i" }, "<Right>", function()
        self:focus_creator_default()
        return vim.keycode("<Ignore>")
    end, { buffer = self.project_buf, silent = true, expr = true })
    vim.keymap.set("n", "l", function()
        self:focus_creator_default()
        return vim.keycode("<Ignore>")
    end, { buffer = self.project_buf, silent = true, expr = true })
    vim.keymap.set({ "n", "i" }, "<Tab>", function()
        self:focus_creator_default()
        return vim.keycode("<Ignore>")
    end, { buffer = self.project_buf, silent = true, expr = true })
    vim.keymap.set({ "n", "i" }, "<S-Tab>", function()
        self:focus_creator_last_slot()
        return vim.keycode("<Ignore>")
    end, { buffer = self.project_buf, silent = true, expr = true })
    vim.keymap.set("n", "<Down>", function()
        self:move_project(1)
    end, { buffer = self.project_buf, silent = true })
    vim.keymap.set("n", "j", function()
        self:move_project(1)
    end, { buffer = self.project_buf, silent = true })
    vim.keymap.set("n", "<Up>", function()
        self:move_project(-1)
    end, { buffer = self.project_buf, silent = true })
    vim.keymap.set("n", "k", function()
        self:move_project(-1)
    end, { buffer = self.project_buf, silent = true })
    for _, action in ipairs(self.submit_actions) do
        vim.keymap.set("n", action.key, function()
            self:submit(action.value)
        end, { buffer = self.project_buf, silent = true })
    end
    vim.keymap.set("n", "q", function()
        self:close()
    end, { buffer = self.project_buf, silent = true })
    vim.keymap.set("n", "<Esc>", function()
        self:close()
    end, { buffer = self.project_buf, silent = true })
    vim.keymap.set("n", "<LeftMouse>", function()
        local mouse = vim.fn.getmousepos()
        if not self.project_win or not self.project_win:valid() or mouse.winid ~= self.project_win.win then
            return
        end
        self:set_project_index(self.project_line_map[mouse.line] or self.project_index)
    end, { buffer = self.project_buf, silent = true })
end

---@param buf integer
function Creator:apply_first_slot_keymaps(buf)
    self:apply_common_keymaps(buf)
    vim.keymap.set("n", "<Left>", function()
        self:focus_project_list()
        return vim.keycode("<Ignore>")
    end, { buffer = buf, silent = true, expr = true })
    vim.keymap.set("n", "h", function()
        self:focus_project_list()
        return vim.keycode("<Ignore>")
    end, { buffer = buf, silent = true, expr = true })
    vim.keymap.set({ "n", "i" }, "<S-Tab>", function()
        self:focus_project_list()
        return vim.keycode("<Ignore>")
    end, { buffer = buf, silent = true, expr = true })
end

function Creator:render_kind_tabs()
    local labels = {}
    for _, kind in ipairs(self.kinds) do
        labels[#labels + 1] = {
            label = kind.label,
            hl_group = Prompt.title_group(kind.id),
            active_hl_group = Prompt.title_group(kind.id) .. "Active",
        }
    end
    self.kind_tab_spans = self:render_tab_line(self.kind_buf, labels, self.kind_index, self:content_width())
end

function Creator:render_variant_tabs()
    local variants = self:variants()
    if #variants == 0 then
        if self.variant_win and self.variant_win:valid() then
            self:without_close_watchers(function()
                self.variant_win:close()
            end)
        end
        self.variant_win = nil
        self.variant_buf = nil
        self.variant_tab_spans = {}
        return
    end

    self.variant_buf = self.variant_buf or prompt_buffer("scratch")
    if not vim.b[self.variant_buf].clodex_prompt_keymaps_applied then
        self:apply_shell_keymaps(self.variant_buf)
        vim.b[self.variant_buf].clodex_prompt_keymaps_applied = true
    end
    local labels = {}
    for _, variant in ipairs(variants) do
        labels[#labels + 1] = {
            label = variant.label,
            hl_group = "ClodexPromptSourceTab",
            active_hl_group = "ClodexPromptSourceTabActive",
        }
    end
    self.variant_tab_spans = self:render_tab_line(self.variant_buf, labels, self.variant_index, self:content_width())
    if not self.variant_win then
        self.variant_win = ui_win.open({
            buf = self.variant_buf,
            enter = false,
            border = "none",
            zindex = LAYOUT.prompt_content_zindex,
            width = function()
                return self:content_width()
            end,
            height = 1,
            row = function()
                return self:variant_row()
            end,
            col = function()
                return self:content_col()
            end,
            view = "footer",
            theme = "prompt_footer",
        })
        self:watch_window(self.variant_win)
    else
        self.variant_win:update()
    end
end

function Creator:render_footer()
    local insert_mode = self:in_insert_mode()
    local has_variants = #self:variants() > 0
    local has_multiple_projects = #self.projects > 1
    local lines = footer_lines(insert_mode, has_variants, has_multiple_projects)
    local marks = {} ---@type Clodex.Extmark[]
    local key_hl = Prompt.title_group(self.state.kind)

    local key_labels = footer_key_labels(insert_mode, has_variants, has_multiple_projects)
    if not insert_mode and has_multiple_projects then
        key_labels[#key_labels + 1] = { row = 0, text = "↑/↓" }
        key_labels[#key_labels + 1] = { row = 0, text = "j/k" }
    end
    if not insert_mode and has_variants then
        key_labels[#key_labels + 1] = { row = 0, text = "[/]" }
    end

    for _, key in ipairs(key_labels) do
        local start_col = lines[key.row + 1]:find(key.text, 1, true)
        if start_col then
            marks[#marks + 1] = Extmark.inline(key.row, start_col - 1, start_col - 1 + #key.text, key_hl)
        end
    end

    vim.bo[self.footer_buf].modifiable = true
    vim.api.nvim_buf_set_lines(self.footer_buf, 0, -1, false, lines)
    vim.bo[self.footer_buf].modifiable = false
    vim.api.nvim_buf_clear_namespace(self.footer_buf, FOOTER_NS, 0, -1)
    for _, mark in ipairs(marks) do
        mark:place(self.footer_buf, FOOTER_NS)
    end
end

function Creator:apply_prompt_theme()
    local prompt_hl = Prompt.title_group(self.state.kind)

    for _, field in ipairs(PROMPT_THEME_WINDOW_FIELDS) do
        if field.slots then
            local container = self[field.name]
            for _, slot in ipairs(field.slots) do
                local win = container and container[slot]
                if win and win.valid and win:valid() then
                    update_winhl(win.win, {
                        FloatBorder = prompt_hl,
                        FloatTitle = prompt_hl,
                    })
                end
            end
        else
            local win = self[field.name]
            if win and win.valid and win:valid() then
                update_winhl(win.win, {
                    FloatBorder = prompt_hl,
                    FloatTitle = prompt_hl,
                })
            end
        end
    end
end

---@param column integer
function Creator:activate_kind_tab_at(column)
    local index = tab_index_at_column(self.kind_tab_spans, column)
    if not index or index == self.kind_index then
        return
    end
    self:switch_kind(index - self.kind_index)
end

---@param column integer
function Creator:activate_variant_tab_at(column)
    local index = tab_index_at_column(self.variant_tab_spans, column)
    if not index or index == self.variant_index then
        return
    end
    self:switch_variant(index - self.variant_index)
end

function Creator:click_kind_tab()
    local mouse = vim.fn.getmousepos()
    if not self.kind_win or not self.kind_win:valid() or mouse.winid ~= self.kind_win.win then
        return
    end
    self:activate_kind_tab_at(mouse.column)
end

function Creator:click_variant_tab()
    local mouse = vim.fn.getmousepos()
    if not self.variant_win or not self.variant_win:valid() or mouse.winid ~= self.variant_win.win then
        return
    end
    self:activate_variant_tab_at(mouse.column)
end

---@param win? snacks.win
function Creator:watch_window(win)
    if not prompt_win_valid(win) then
        return
    end

    local winid = win.win
    if not winid or winid == 0 or self.close_watchers[winid] then
        return
    end

    self.close_watchers[winid] = vim.api.nvim_create_autocmd("WinClosed", {
        pattern = tostring(winid),
        once = true,
        callback = function()
            self.close_watchers[winid] = nil
            if self.suppress_close_events then
                return
            end
            self:close()
        end,
    })
end

function Creator:clear_window_watchers()
    for winid, autocmd in pairs(self.close_watchers) do
        self.close_watchers[winid] = nil
        pcall(vim.api.nvim_del_autocmd, autocmd)
    end
end

function Creator:ensure_shell_windows()
    self:render_project_background()
    if not self.project_bg_win then
        self.project_bg_win = ui_win.open({
            buf = self.project_bg_buf,
            enter = false,
            border = "none",
            zindex = LAYOUT.prompt_background_zindex,
            width = function()
                return self:project_background_width()
            end,
            height = function()
                return self:project_background_height()
            end,
            row = function()
                return self:project_background_row()
            end,
            col = function()
                return self:project_background_col()
            end,
            view = "footer",
            theme = "prompt_footer",
        })
        self:watch_window(self.project_bg_win)
    else
        self.project_bg_win:update()
    end

    if not self.project_win then
        self.project_win = ui_win.open({
            buf = self.project_buf,
            enter = false,
            border = "rounded",
            zindex = LAYOUT.prompt_content_zindex,
            title = " Target Project ",
            title_pos = "center",
            width = function()
                return self:project_list_width()
            end,
            height = function()
                return self:project_height()
            end,
            row = function()
                return self:project_row()
            end,
            col = function()
                return self:project_col()
            end,
            view = "footer",
            theme = "prompt_footer",
        })
        self:watch_window(self.project_win)
        if not vim.b[self.project_buf].clodex_prompt_keymaps_applied then
            self:apply_project_keymaps()
            vim.b[self.project_buf].clodex_prompt_keymaps_applied = true
        end
        vim.wo[self.project_win.win].cursorline = true
    else
        self.project_win:update()
    end
    if not self.kind_win then
        self.kind_win = ui_win.open({
            buf = self.kind_buf,
            enter = false,
            border = "none",
            zindex = LAYOUT.prompt_content_zindex,
            width = function()
                return self:content_width()
            end,
            height = 2,
            row = function()
                return self:kind_row()
            end,
            col = function()
                return self:content_col()
            end,
            view = "footer",
            theme = "prompt_footer",
        })
        self:watch_window(self.kind_win)
        if not vim.b[self.kind_buf].clodex_prompt_keymaps_applied then
            self:apply_shell_keymaps(self.kind_buf)
            vim.b[self.kind_buf].clodex_prompt_keymaps_applied = true
        end
    else
        self.kind_win:update()
    end
    if not self.footer_win then
        self.footer_win = ui_win.open({
            buf = self.footer_buf,
            enter = false,
            border = "rounded",
            zindex = LAYOUT.prompt_content_zindex,
            title = " Actions ",
            title_pos = "center",
            width = function()
                return self:content_width()
            end,
            height = 2,
            row = function()
                return self:footer_row()
            end,
            col = function()
                return self:content_col()
            end,
            view = "footer",
            theme = "prompt_footer",
        })
        self:watch_window(self.footer_win)
        if not vim.b[self.footer_buf].clodex_prompt_keymaps_applied then
            self:apply_common_keymaps(self.footer_buf)
            vim.b[self.footer_buf].clodex_prompt_keymaps_applied = true
        end
    else
        self.footer_win:update()
    end
end

function Creator:render_preview()
    local function render_preview_fallback()
        if not self.preview_buf or not vim.api.nvim_buf_is_valid(self.preview_buf) then
            return
        end
        vim.bo[self.preview_buf].modifiable = true
        vim.bo[self.preview_buf].filetype = "markdown"
        vim.api.nvim_buf_set_lines(self.preview_buf, 0, -1, false, preview_fallback_lines(self.state.image_path))
        vim.bo[self.preview_buf].modifiable = false
    end

    if not self.state.image_path then
        if self.preview_placement and self.preview_placement.close then
            self.preview_placement:close()
            self.preview_placement = nil
        end
        if self.preview_win and self.preview_win:valid() then
            self:without_close_watchers(function()
                self.preview_win:close()
            end)
        end
        self.preview_win = nil
        self.preview_buf = nil
        return
    end

    self.preview_buf = self.preview_buf or prompt_buffer("scratch")
    if not self.preview_win then
        self.preview_win = ui_win.open({
            buf = self.preview_buf,
            enter = false,
            border = "rounded",
            zindex = LAYOUT.prompt_content_zindex,
            title = " Clipboard Image ",
            title_pos = "center",
            width = function()
                return self:preview_width()
            end,
            height = function()
                return self:preview_height()
            end,
            row = function()
                return self:preview_row()
            end,
            col = function()
                return self:preview_col()
            end,
            view = "markdown",
            theme = "prompt_footer",
        })
        self:watch_window(self.preview_win)
        if not vim.b[self.preview_buf].clodex_prompt_keymaps_applied then
            self:apply_common_keymaps(self.preview_buf)
            vim.b[self.preview_buf].clodex_prompt_keymaps_applied = true
        end
    else
        self.preview_win:update()
    end
    local ok, Snacks = pcall(require, "snacks")
    if self.preview_placement and self.preview_placement.close then
        self.preview_placement:close()
        self.preview_placement = nil
    end
    if ok and Snacks.image and Snacks.image.supports and Snacks.image.supports(self.state.image_path)
        and Snacks.image.placement and Snacks.image.placement.new then
        local placement = Snacks.image.placement.new(self.preview_buf, self.state.image_path, self:preview_image_opts())
        self.preview_placement = placement
        vim.defer_fn(function()
            if self.preview_placement ~= placement or not self.preview_buf or not vim.api.nvim_buf_is_valid(self.preview_buf) then
                return
            end
            if placement.ready and placement:ready() then
                return
            end
            if placement.close then
                placement:close()
            end
            if self.preview_placement == placement then
                self.preview_placement = nil
            end
            render_preview_fallback()
        end, 1500)
        return
    end
    render_preview_fallback()
end

---@param focus_context? { area: string, slot?: string, insert: boolean }
function Creator:activate_layout(focus_context)
    if self.layout and self.layout.close then
        self:without_close_watchers(function()
            self.layout:close()
        end)
    end
    local layout_id = KindRegistry.layout_id(self.state.kind, self.state.variant)
    self.layout = layout_modules[layout_id].new(self)
    self.layout:open()
    self.layout:set_draft(vim.tbl_extend("force", self:merge_cached_fields(
        self.state.kind,
        self.state.variant,
        self.drafts:get(self.state.kind, self.state.variant, self.state),
        KindRegistry.default_draft(self.state.kind, self.state.variant)
    ), {
        title = self.state.title,
        details = self.state.details,
        image_path = self.state.image_path,
        preview_text = self.state.preview_text,
    }))
    self:refresh_layout_prompt_contexts()
    self:render_preview()
    if not self:restore_focus_context(focus_context) then
        self:focus_default()
    end
end

function Creator:refresh()
    self:ensure_shell_windows()
    self:render_project_list()
    self:render_kind_tabs()
    self:render_variant_tabs()
    self:render_footer()
    if self.layout and self.layout.update then
        self.layout:update()
    end
    self:render_preview()
    self:apply_prompt_theme()
end

---@param silent? boolean
function Creator:replace_clipboard_image(silent)
    local image_path = PromptAssets.save_clipboard_image(
        self.app.config:get().storage.workspaces_dir,
        self.project.root,
        self.state.kind
    )
    if not image_path then
        return
    end
    self.state.image_path = image_path
    self:save_current_draft()
    self:render_preview()
    self:refresh()
    if not silent then
        notify.notify(("Updated clipboard image for %s"):format(self.project.name))
    end
end

---@param delta integer
function Creator:switch_kind(delta)
    if self.lock_kind then
        return
    end
    local focus_context = self:capture_focus_context()
    self:save_current_draft()
    local count = #self.kinds
    self.kind_index = ((self.kind_index - 1 + delta) % count) + 1
    self.variant_index = 1
    self:sync_state_from_draft()
    self:activate_layout(focus_context)
    self:refresh()
    self:restore_focus_context(focus_context)
end

---@param delta integer
function Creator:switch_variant(delta)
    local variants = self:variants()
    if #variants == 0 then
        return
    end
    local focus_context = self:capture_focus_context()
    self:save_current_draft()
    self.variant_index = ((self.variant_index - 1 + delta) % #variants) + 1
    self:sync_state_from_draft()
    self:activate_layout(focus_context)
    self:refresh()
    self:restore_focus_context(focus_context)
end

---@param buf integer
function Creator:apply_common_keymaps(buf)
    vim.keymap.set("n", "<Right>", function()
        self:switch_kind(1)
    end, { buffer = buf, silent = true })
    vim.keymap.set("n", "l", function()
        self:switch_kind(1)
    end, { buffer = buf, silent = true })
    vim.keymap.set("n", "<Left>", function()
        self:switch_kind(-1)
    end, { buffer = buf, silent = true })
    vim.keymap.set("n", "h", function()
        self:switch_kind(-1)
    end, { buffer = buf, silent = true })
    vim.keymap.set("i", "<C-Right>", function()
        self:switch_kind(1)
    end, { buffer = buf, silent = true })
    vim.keymap.set("i", "<C-Left>", function()
        self:switch_kind(-1)
    end, { buffer = buf, silent = true })
    vim.keymap.set("n", "]", function()
        self:switch_variant(1)
    end, { buffer = buf, silent = true })
    vim.keymap.set("n", "[", function()
        self:switch_variant(-1)
    end, { buffer = buf, silent = true })
    for _, action in ipairs(self.submit_actions) do
        vim.keymap.set({ "n", "i" }, action.key, function()
            self:submit(action.value)
        end, { buffer = buf, silent = true })
    end
    vim.keymap.set({ "n", "i" }, "<C-v>", function()
        self:replace_clipboard_image(false)
    end, { buffer = buf, silent = true })
    vim.keymap.set("n", "q", function()
        self:close()
    end, { buffer = buf, silent = true })
    vim.keymap.set("n", "<Esc>", function()
        self:close()
    end, { buffer = buf, silent = true })

    self:attach_prompt_context(buf)
end

---@param action string
function Creator:submit(action)
    self:save_current_draft()
    local draft = self.drafts:get(self.state.kind, self.state.variant, self.state)
    local spec = PromptSubmit.build_spec(vim.tbl_extend("force", self.state, draft))
    if not spec then
        notify.warn("Prompt title is required")
        return
    end

    local result = self.on_submit(spec, action, self.project)
    if result == false then
        return
    end

    vim.schedule(function()
        if not self.is_closing then
            self:close()
        end
    end)
end

---@param clear_layout? boolean
function Creator:close(clear_layout)
    if self.is_closing then
        return
    end

    self.is_closing = true
    self:clear_window_watchers()
    local layout_buffers = self.layout and self.layout.buffers and self.layout:buffers() or {}
    local lingering_buffers = {
        self.project_bg_buf,
        self.project_buf,
        self.kind_buf,
        self.variant_buf,
        self.footer_buf,
        self.preview_buf,
    }
    vim.list_extend(lingering_buffers, layout_buffers)
    if self.preview_placement and self.preview_placement.close then
        self.preview_placement:close()
        self.preview_placement = nil
    end
    if clear_layout ~= false and self.layout and self.layout.close then
        self:without_close_watchers(function()
            self.layout:close()
        end)
    end
    self.layout = nil
    self:without_close_watchers(function()
        for _, win in ipairs({ self.project_bg_win, self.project_win, self.kind_win, self.variant_win, self.footer_win, self.preview_win }) do
            close_prompt_win(win)
        end
        close_prompt_buffer_windows(lingering_buffers)
    end)
    self.project_bg_win = nil
    self.project_win = nil
    self.kind_win = nil
    self.variant_win = nil
    self.footer_win = nil
    self.preview_win = nil
    self.is_closing = false
end

---@param opts Clodex.PromptCreator.OpenOpts
function Creator.open(opts)
    local creator = Creator.new(opts)
    creator:ensure_shell_windows()
    creator:render_kind_tabs()
    creator:render_variant_tabs()
    creator:render_footer()
    creator:activate_layout()
    creator:refresh()
    return creator
end

return Creator
