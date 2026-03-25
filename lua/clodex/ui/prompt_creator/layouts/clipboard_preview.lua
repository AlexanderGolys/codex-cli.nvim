local ui_win = require("clodex.ui.win")

---@param win? snacks.win
---@return boolean
local function prompt_win_valid(win)
    return win ~= nil and ui_win.is_valid(win.win)
end

---@class Clodex.PromptCreator.LayoutClipboardPreview
---@field creator Clodex.PromptCreator
---@field title_buf integer
---@field preview_buf integer
---@field title_win snacks.win?
---@field preview_win snacks.win?
local ClipboardPreview = {}
ClipboardPreview.__index = ClipboardPreview

---@param creator Clodex.PromptCreator
---@return Clodex.PromptCreator.LayoutClipboardPreview
function ClipboardPreview.new(creator)
    return setmetatable({
        creator = creator,
        title_buf = ui_win.create_buffer({ preset = "text", bo = { bufhidden = "hide" } }),
        preview_buf = ui_win.create_buffer({ preset = "markdown", bo = { bufhidden = "hide" } }),
    }, ClipboardPreview)
end

function ClipboardPreview:open()
    if not self.title_win then
        self.title_win = ui_win.open({
            buf = self.title_buf,
            enter = true,
            border = "rounded",
            title = " Comment ",
            title_pos = "center",
            width = function()
                return self.creator:content_width()
            end,
            height = 1,
            row = function()
                return self.creator:title_row()
            end,
            col = function()
                return self.creator:content_col()
            end,
            view = "text",
            theme = "prompt_editor",
            bo = { modifiable = true },
        })
        self.creator:watch_window(self.title_win)
        self.creator:apply_first_slot_keymaps(self.title_buf)
        vim.keymap.set({ "n", "i" }, "<Tab>", function()
            self:focus_preview()
        end, { buffer = self.title_buf, silent = true })
    end
    if not self.preview_win then
        self.preview_win = ui_win.open({
            buf = self.preview_buf,
            enter = false,
            border = "rounded",
            title = " Clipboard Preview ",
            title_pos = "center",
            width = function()
                return self.creator:content_width()
            end,
            height = function()
                return self.creator:body_height()
            end,
            row = function()
                return self.creator:body_row()
            end,
            col = function()
                return self.creator:content_col()
            end,
            view = "markdown",
            theme = "prompt_footer",
            bo = { modifiable = false },
        })
        self.creator:watch_window(self.preview_win)
        self.creator:apply_common_keymaps(self.preview_buf)
        vim.keymap.set("n", "<Tab>", function()
            self.creator:focus_project_list()
        end, { buffer = self.preview_buf, silent = true })
        vim.keymap.set("n", "<S-Tab>", function()
            self:focus_title()
        end, { buffer = self.preview_buf, silent = true })
    end
    self:update()
end

function ClipboardPreview:update()
    if self.title_win and self.title_win:valid() then
        self.title_win:update()
    end
    if self.preview_win and self.preview_win:valid() then
        self.preview_win:update()
    end
end

---@param draft table
function ClipboardPreview:set_draft(draft)
    vim.api.nvim_buf_set_lines(self.title_buf, 0, -1, false, { draft.title or "" })
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
        preview_text = vim.trim(self.creator.state.preview_text or ""),
    }
end

---@return string[]
function ClipboardPreview:draft_fields()
    return { "title" }
end

---@return integer[]
function ClipboardPreview:buffers()
    return { self.title_buf, self.preview_buf }
end

function ClipboardPreview:focus_default()
    if self.title_win and self.title_win:valid() then
        vim.api.nvim_set_current_win(self.title_win.win)
        vim.cmd.startinsert()
    end
end

function ClipboardPreview:focus_preview()
    if self.preview_win and self.preview_win:valid() then
        vim.api.nvim_set_current_win(self.preview_win.win)
    end
end

function ClipboardPreview:focus_last()
    self:focus_preview()
end

---@param winid? integer
---@return string?
function ClipboardPreview:focused_slot(winid)
    winid = winid or vim.api.nvim_get_current_win()
    if self.title_win and self.title_win:valid() and winid == self.title_win.win then
        return "title"
    end
    if self.preview_win and self.preview_win:valid() and winid == self.preview_win.win then
        return "preview"
    end
end

---@param slot? string
---@param insert_mode? boolean
---@return boolean
function ClipboardPreview:focus_slot(slot, insert_mode)
    if slot == "preview" and self.preview_win and self.preview_win:valid() then
        vim.api.nvim_set_current_win(self.preview_win.win)
        return true
    end
    if self.title_win and self.title_win:valid() then
        vim.api.nvim_set_current_win(self.title_win.win)
        if insert_mode then
            vim.cmd.startinsert()
        end
        return true
    end
    return false
end

function ClipboardPreview:close()
    for _, win in ipairs({ self.title_win, self.preview_win }) do
        if prompt_win_valid(win) then
            win:close()
        end
    end
    self.title_win = nil
    self.preview_win = nil
end

return ClipboardPreview
