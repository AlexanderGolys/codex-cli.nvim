local PromptAssets = require("clodex.prompt.assets")
local CreatorRegistry = require("clodex.prompt.creator_registry")
local DraftStore = require("clodex.prompt.draft_store")
local KindRegistry = require("clodex.prompt.kind_registry")
local Prompt = require("clodex.prompt")
local PromptSubmit = require("clodex.prompt.submit")
local Extmark = require("clodex.ui.extmark")
local notify = require("clodex.util.notify")
local ui_win = require("clodex.ui.win")

local layout_modules = {
    composer = require("clodex.ui.prompt_creator.layouts.composer"),
    clipboard_preview = require("clodex.ui.prompt_creator.layouts.clipboard_preview"),
    template_picker = require("clodex.ui.prompt_creator.layouts.template_picker"),
}

---@class Clodex.PromptCreator.OpenOpts
---@field app Clodex.App
---@field project Clodex.Project
---@field context? Clodex.PromptContext.Capture
---@field initial_kind? Clodex.PromptCategory
---@field submit_actions? Clodex.UiSelect.MultilineAction[]
---@field mode? "new"|"edit"
---@field lock_kind? boolean
---@field initial_draft? table
---@field on_submit fun(spec: Clodex.AppPromptActions.AddTodoSpec, action?: string)

---@class Clodex.PromptCreator
---@field app Clodex.App
---@field project Clodex.Project
---@field context? Clodex.PromptContext.Capture
---@field submit_actions Clodex.UiSelect.MultilineAction[]
---@field mode "new"|"edit"
---@field lock_kind boolean
---@field on_submit fun(spec: Clodex.AppPromptActions.AddTodoSpec, action?: string)
---@field kinds Clodex.PromptCategoryDef[]
---@field kind_index integer
---@field variant_index integer
---@field state table
---@field drafts Clodex.PromptDraftStore
---@field layout any
---@field kind_buf integer
---@field footer_buf integer
---@field variant_buf? integer
---@field preview_buf? integer
---@field kind_win? snacks.win
---@field footer_win? snacks.win
---@field variant_win? snacks.win
---@field preview_win? snacks.win
---@field close_watchers table<integer, integer>
---@field is_closing boolean
---@field suppress_close_events boolean
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
local TAB_PADDING = 1

local function read_bug_message_register()
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
    if kind == "bug" or kind == "library" then
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
    local kind_index = 1
    for index, kind in ipairs(kinds) do
        if kind.id == initial_kind then
            kind_index = index
            break
        end
    end

    local self = setmetatable({
        app = opts.app,
        project = opts.project,
        context = opts.context,
        submit_actions = vim.deepcopy(opts.submit_actions or DEFAULT_SUBMIT_ACTIONS),
        mode = opts.mode or "new",
        lock_kind = opts.lock_kind == true,
        on_submit = opts.on_submit,
        kinds = kinds,
        kind_index = kind_index,
        variant_index = 1,
        state = {
            project = opts.project,
            context = opts.context,
            kind = initial_kind,
            variant = nil,
            title = "",
            details = "",
            image_path = opts.initial_draft and opts.initial_draft.image_path or nil,
            preview_text = "",
        },
        drafts = DraftStore.new(),
        kind_buf = ui_win.create_buffer({ preset = "scratch" }),
        footer_buf = ui_win.create_buffer({ preset = "scratch" }),
        close_watchers = {},
        is_closing = false,
        suppress_close_events = false,
        kind_tab_spans = {},
        variant_tab_spans = {},
    }, Creator)

    self:prime_drafts(opts.initial_draft)
    return self
end

---@param initial_draft? table
function Creator:prime_drafts(initial_draft)
    for _, kind in ipairs(self.kinds) do
        local creator = CreatorRegistry.get(kind.id)
        local base = initial_draft and kind.id == self.state.kind and vim.deepcopy(initial_draft)
            or selection_seed(kind.id, self.context)
            or CreatorRegistry.default_draft(kind.id, creator.default_variant)
        self.drafts:set(kind.id, nil, base)
        for _, variant in ipairs(CreatorRegistry.variants(kind.id)) do
            local draft = kind.id == self.state.kind and initial_draft and variant.id == creator.default_variant and vim.deepcopy(initial_draft)
                or CreatorRegistry.default_draft(kind.id, variant.id)
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
    return CreatorRegistry.variants(self:kind())
end

---@return string?
function Creator:variant()
    local variants = self:variants()
    local current = variants[self.variant_index]
    return current and current.id or nil
end

function Creator:sync_state_from_draft()
    self.state.kind = self:kind()
    local creator = CreatorRegistry.get(self.state.kind)
    local variants = self:variants()
    if #variants == 0 then
        self.variant_index = 1
        self.state.variant = nil
    else
        local max_index = math.min(math.max(self.variant_index, 1), #variants)
        self.variant_index = max_index
        self.state.variant = variants[self.variant_index].id
    end

    local draft = self.drafts:get(self.state.kind, self.state.variant, CreatorRegistry.default_draft(self.state.kind, self.state.variant))
    for key, value in pairs(draft) do
        self.state[key] = value
    end
    self.state.project = self.project
    self.state.context = self.context
    if self.state.variant == "clipboard_error" then
        self.state.preview_text = read_bug_message_register() or self.state.preview_text or ""
    end
    if self.state.variant == "clipboard_screenshot" and not self.state.image_path then
        self:replace_clipboard_image(true)
    end
end

function Creator:save_current_draft()
    if self.layout and self.layout.get_draft then
        local draft = self.layout:get_draft()
        if draft then
            if self.state.preview_text and draft.preview_text == nil then
                draft.preview_text = self.state.preview_text
            end
            self.drafts:set(self.state.kind, self.state.variant, vim.tbl_extend("force", draft, {
                image_path = self.state.image_path,
                preview_text = self.state.preview_text,
            }))
        end
    end
end

function Creator:editor_size()
    local ui = vim.api.nvim_list_uis()[1]
    return ui and ui.width or vim.o.columns, ui and ui.height or vim.o.lines
end

function Creator:total_width()
    local width = self:editor_size()
    return math.min(width - 6, self.state.image_path and 150 or 108)
end

function Creator:total_height()
    local _, height = self:editor_size()
    return math.min(height - 4, 30)
end

function Creator:preview_width()
    if not self.state.image_path then
        return 0
    end
    return math.min(42, math.max(28, math.floor(self:total_width() * 0.3)))
end

function Creator:left_width()
    local preview_width = self:preview_width()
    local width = self:total_width() - preview_width
    if preview_width > 0 then
        width = width - 2
    end
    return width
end

function Creator:left_col()
    local width = self:editor_size()
    return math.max(math.floor((width - self:total_width()) / 2), 1)
end

function Creator:top_row()
    local _, height = self:editor_size()
    return math.max(math.floor((height - self:total_height()) / 2), 1)
end

function Creator:kind_row()
    return self:top_row()
end

function Creator:variant_row()
    return self:kind_row() + 3
end

function Creator:title_row()
    return self:variant_row() + (#self:variants() > 0 and 3 or 0)
end

function Creator:body_row()
    return self:title_row() + 3
end

function Creator:footer_row()
    return self:top_row() + self:total_height() - 4
end

function Creator:body_height()
    return math.max(self:footer_row() - self:body_row() - 1, 8)
end

function Creator:clipboard_note_height()
    return math.max(math.min(6, self:body_height() - 5), 4)
end

function Creator:clipboard_preview_row()
    return self:body_row() + self:clipboard_note_height() + 3
end

function Creator:clipboard_preview_height()
    return math.max(self:footer_row() - self:clipboard_preview_row() - 1, 4)
end

function Creator:preview_col()
    return self:left_col() + self:left_width() + 2
end

function Creator:preview_row()
    return self:title_row()
end

function Creator:preview_height()
    return math.max(self:footer_row() - self:preview_row() + 3, 8)
end

---@param buf integer
---@param labels { label: string, hl_group: string, active_hl_group: string }[]
---@param active_index integer
---@return { start_col: integer, end_col: integer, index: integer }[]
function Creator:render_tab_line(buf, labels, active_index)
    local parts = {} ---@type string[]
    local marks = {} ---@type Clodex.Extmark[]
    local spans = {} ---@type { start_col: integer, end_col: integer, index: integer }[]
    local col = 0

    for index, entry in ipairs(labels) do
        if index > 1 then
            parts[#parts + 1] = " "
            col = col + 1
        end

        local text = string.rep(" ", TAB_PADDING) .. entry.label .. string.rep(" ", TAB_PADDING)
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

    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { table.concat(parts) })
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
    if context.area == "kind" then
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

function Creator:render_kind_tabs()
    local labels = {}
    for _, kind in ipairs(self.kinds) do
        labels[#labels + 1] = {
            label = kind.label,
            hl_group = Prompt.title_group(kind.id),
            active_hl_group = Prompt.title_group(kind.id) .. "Active",
        }
    end
    self.kind_tab_spans = self:render_tab_line(self.kind_buf, labels, self.kind_index)
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

    self.variant_buf = self.variant_buf or ui_win.create_buffer({ preset = "scratch" })
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
    self.variant_tab_spans = self:render_tab_line(self.variant_buf, labels, self.variant_index)
    if not self.variant_win then
        self.variant_win = ui_win.open({
            buf = self.variant_buf,
            enter = false,
            border = "rounded",
            title = " Source ",
            title_pos = "center",
            width = function()
                return self:left_width()
            end,
            height = 1,
            row = function()
                return self:variant_row()
            end,
            col = function()
                return self:left_col()
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
    local lines = {
        "</>: prev/next kind   [/]: prev/next source   Ctrl-V: replace clipboard image",
        "Ctrl-S: plan   Ctrl-Q: queue   Ctrl-E: run now   Ctrl-L: chat   q: close",
    }
    vim.bo[self.footer_buf].modifiable = true
    vim.api.nvim_buf_set_lines(self.footer_buf, 0, -1, false, lines)
    vim.bo[self.footer_buf].modifiable = false
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
    if not win or not win.valid or not win:valid() then
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
    if not self.kind_win then
        self.kind_win = ui_win.open({
            buf = self.kind_buf,
            enter = false,
            border = "rounded",
            title = (" Prompt Creator - %s "):format(self.project.name),
            title_pos = "center",
            width = function()
                return self:left_width()
            end,
            height = 1,
            row = function()
                return self:kind_row()
            end,
            col = function()
                return self:left_col()
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
            title = " Actions ",
            title_pos = "center",
            width = function()
                return self:left_width()
            end,
            height = 2,
            row = function()
                return self:footer_row()
            end,
            col = function()
                return self:left_col()
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
    if not self.state.image_path then
        if self.preview_win and self.preview_win:valid() then
            self:without_close_watchers(function()
                self.preview_win:close()
            end)
        end
        self.preview_win = nil
        self.preview_buf = nil
        return
    end

    self.preview_buf = self.preview_buf or ui_win.create_buffer({ preset = "scratch" })
    if not self.preview_win then
        self.preview_win = ui_win.open({
            buf = self.preview_buf,
            enter = false,
            border = "rounded",
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
    if ok and Snacks.image and Snacks.image.buf then
        Snacks.image.buf.attach(self.preview_buf, { src = self.state.image_path })
        return
    end
    vim.bo[self.preview_buf].modifiable = true
    vim.api.nvim_buf_set_lines(self.preview_buf, 0, -1, false, {
        "# Clipboard image",
        "",
        ("`%s`"):format(self.state.image_path),
    })
    vim.bo[self.preview_buf].modifiable = false
end

---@param focus_context? { area: string, slot?: string, insert: boolean }
function Creator:activate_layout(focus_context)
    if self.layout and self.layout.close then
        self:without_close_watchers(function()
            self.layout:close()
        end)
    end
    local creator = CreatorRegistry.get(self.state.kind)
    local layout_id = creator.layout
    for _, variant in ipairs(self:variants()) do
        if variant.id == self.state.variant then
            layout_id = variant.layout
            break
        end
    end
    self.layout = layout_modules[layout_id].new(self)
    self.layout:open()
    self.layout:set_draft(self.drafts:get(self.state.kind, self.state.variant, self.state))
    self:render_preview()
    if not self:restore_focus_context(focus_context) then
        self:focus_default()
    end
end

function Creator:refresh()
    self:ensure_shell_windows()
    self:render_kind_tabs()
    self:render_variant_tabs()
    self:render_footer()
    if self.layout and self.layout.update then
        self.layout:update()
    end
    self:render_preview()
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
    vim.keymap.set("n", ">", function()
        self:switch_kind(1)
    end, { buffer = buf, silent = true })
    vim.keymap.set("n", "<", function()
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
    self:close()
    self.on_submit(spec, action)
end

---@param clear_layout? boolean
function Creator:close(clear_layout)
    if self.is_closing then
        return
    end

    self.is_closing = true
    self:clear_window_watchers()
    if clear_layout ~= false and self.layout and self.layout.close then
        self.layout:close()
    end
    for _, win in ipairs({ self.kind_win, self.variant_win, self.footer_win, self.preview_win }) do
        if win and win.valid and win:valid() then
            win:close()
        end
    end
    self.kind_win = nil
    self.variant_win = nil
    self.footer_win = nil
    self.preview_win = nil
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
