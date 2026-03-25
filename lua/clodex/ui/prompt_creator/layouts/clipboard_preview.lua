local ui_win = require("clodex.ui.win")

---@class Clodex.PromptCreator.LayoutClipboardPreview
---@field creator Clodex.PromptCreator
---@field title_buf integer
---@field note_buf integer
---@field preview_buf integer
---@field title_win snacks.win?
---@field note_win snacks.win?
---@field preview_win snacks.win?
local ClipboardPreview = {}
ClipboardPreview.__index = ClipboardPreview

---@param creator Clodex.PromptCreator
---@return Clodex.PromptCreator.LayoutClipboardPreview
function ClipboardPreview.new(creator)
    return setmetatable({
        creator = creator,
        title_buf = ui_win.create_buffer({ preset = "text" }),
        note_buf = ui_win.create_buffer({ preset = "markdown" }),
        preview_buf = ui_win.create_buffer({ preset = "markdown" }),
    }, ClipboardPreview)
end

function ClipboardPreview:open()
    if not self.title_win then
        self.title_win = ui_win.open({
            buf = self.title_buf,
            enter = true,
            border = "rounded",
            title = " Title ",
            title_pos = "center",
            width = function()
                return self.creator:left_width()
            end,
            height = 1,
            row = function()
                return self.creator:title_row()
            end,
            col = function()
                return self.creator:left_col()
            end,
            view = "text",
            theme = "prompt_editor",
            bo = { modifiable = true },
        })
        self.creator:watch_window(self.title_win)
        self.creator:apply_common_keymaps(self.title_buf)
    end
    if not self.note_win then
        self.note_win = ui_win.open({
            buf = self.note_buf,
            enter = false,
            border = "rounded",
            title = " Comment ",
            title_pos = "center",
            width = function()
                return self.creator:left_width()
            end,
            height = function()
                return self.creator:clipboard_note_height()
            end,
            row = function()
                return self.creator:body_row()
            end,
            col = function()
                return self.creator:left_col()
            end,
            view = "markdown",
            theme = "prompt_editor",
            bo = { modifiable = true },
        })
        self.creator:watch_window(self.note_win)
        self.creator:apply_common_keymaps(self.note_buf)
    end
    if not self.preview_win then
        self.preview_win = ui_win.open({
            buf = self.preview_buf,
            enter = false,
            border = "rounded",
            title = " Clipboard Preview ",
            title_pos = "center",
            width = function()
                return self.creator:left_width()
            end,
            height = function()
                return self.creator:clipboard_preview_height()
            end,
            row = function()
                return self.creator:clipboard_preview_row()
            end,
            col = function()
                return self.creator:left_col()
            end,
            view = "markdown",
            theme = "prompt_footer",
            bo = { modifiable = false },
        })
        self.creator:watch_window(self.preview_win)
        self.creator:apply_common_keymaps(self.preview_buf)
    end
    self:update()
end

function ClipboardPreview:update()
    if self.title_win and self.title_win:valid() then
        self.title_win:update()
    end
    if self.note_win and self.note_win:valid() then
        self.note_win:update()
    end
    if self.preview_win and self.preview_win:valid() then
        self.preview_win:update()
    end
end

---@param draft table
function ClipboardPreview:set_draft(draft)
    vim.api.nvim_buf_set_lines(self.title_buf, 0, -1, false, { draft.title or "" })
    local note_lines = vim.split(draft.details or "", "\n", { plain = true })
    vim.api.nvim_buf_set_lines(self.note_buf, 0, -1, false, #note_lines > 0 and note_lines or { "" })
    local preview_text = draft.preview_text and vim.trim(draft.preview_text) or ""
    if preview_text == "" then
        preview_text = "No clipboard text found. Copy an error message and switch back to this tab."
    end
    vim.bo[self.preview_buf].modifiable = true
    vim.api.nvim_buf_set_lines(self.preview_buf, 0, -1, false, vim.split(preview_text, "\n", { plain = true }))
    vim.bo[self.preview_buf].modifiable = false
end

---@return table
function ClipboardPreview:get_draft()
    return {
        title = vim.trim(vim.api.nvim_buf_get_lines(self.title_buf, 0, 1, false)[1] or ""),
        details = vim.trim(table.concat(vim.api.nvim_buf_get_lines(self.note_buf, 0, -1, false), "\n")),
        preview_text = vim.trim(self.creator.state.preview_text or ""),
    }
end

---@return integer[]
function ClipboardPreview:buffers()
    return { self.title_buf, self.note_buf, self.preview_buf }
end

function ClipboardPreview:focus_default()
    if self.title_win and self.title_win:valid() then
        vim.api.nvim_set_current_win(self.title_win.win)
        vim.cmd.startinsert()
    end
end

function ClipboardPreview:close()
    for _, win in ipairs({ self.title_win, self.note_win, self.preview_win }) do
        if win and win:valid() then
            win:close()
        end
    end
    self.title_win = nil
    self.note_win = nil
    self.preview_win = nil
end

return ClipboardPreview
