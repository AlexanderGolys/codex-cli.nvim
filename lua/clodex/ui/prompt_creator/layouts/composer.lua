local ui_win = require("clodex.ui.win")

---@class Clodex.PromptCreator.LayoutComposer
---@field creator Clodex.PromptCreator
---@field title_buf integer
---@field body_buf integer
---@field title_win snacks.win?
---@field body_win snacks.win?
local Composer = {}
Composer.__index = Composer

---@param creator Clodex.PromptCreator
---@return Clodex.PromptCreator.LayoutComposer
function Composer.new(creator)
    return setmetatable({
        creator = creator,
        title_buf = ui_win.create_buffer({ preset = "text" }),
        body_buf = ui_win.create_buffer({ preset = "markdown" }),
    }, Composer)
end

function Composer:open()
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
        vim.keymap.set({ "n", "i" }, "<Tab>", function()
            self:focus_body()
        end, { buffer = self.title_buf, silent = true })
        vim.keymap.set({ "n", "i" }, "<Down>", function()
            self:focus_body()
        end, { buffer = self.title_buf, silent = true })
    end
    if not self.body_win then
        self.body_win = ui_win.open({
            buf = self.body_buf,
            enter = false,
            border = "rounded",
            title = " Details ",
            title_pos = "center",
            width = function()
                return self.creator:left_width()
            end,
            height = function()
                return self.creator:body_height()
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
        self.creator:watch_window(self.body_win)
        self.creator:apply_common_keymaps(self.body_buf)
        vim.keymap.set({ "n", "i" }, "<Tab>", function()
            self:focus_title()
        end, { buffer = self.body_buf, silent = true })
        vim.keymap.set({ "n", "i" }, "<S-Tab>", function()
            self:focus_title()
        end, { buffer = self.body_buf, silent = true })
        vim.keymap.set({ "n", "i" }, "<Up>", function()
            if vim.api.nvim_win_get_cursor(self.body_win.win)[1] <= 1 then
                vim.schedule(function()
                    self:focus_title()
                end)
                return vim.keycode("<Ignore>")
            end
            return vim.keycode("<Up>")
        end, { buffer = self.body_buf, silent = true, expr = true })
    end
    self:update()
end

function Composer:update()
    if self.title_win and self.title_win:valid() then
        self.title_win:update()
    end
    if self.body_win and self.body_win:valid() then
        self.body_win:update()
    end
end

---@param draft table
function Composer:set_draft(draft)
    vim.api.nvim_buf_set_lines(self.title_buf, 0, -1, false, { draft.title or "" })
    local lines = vim.split(draft.details or "", "\n", { plain = true })
    vim.api.nvim_buf_set_lines(self.body_buf, 0, -1, false, #lines > 0 and lines or { "" })
end

---@return table
function Composer:get_draft()
    return {
        title = vim.trim(vim.api.nvim_buf_get_lines(self.title_buf, 0, 1, false)[1] or ""),
        details = vim.trim(table.concat(vim.api.nvim_buf_get_lines(self.body_buf, 0, -1, false), "\n")),
    }
end

---@return integer[]
function Composer:buffers()
    return { self.title_buf, self.body_buf }
end

function Composer:focus_title()
    if self.title_win and self.title_win:valid() then
        vim.api.nvim_set_current_win(self.title_win.win)
        vim.cmd.startinsert()
    end
end

function Composer:focus_body()
    if self.body_win and self.body_win:valid() then
        vim.api.nvim_set_current_win(self.body_win.win)
        vim.cmd.startinsert()
    end
end

function Composer:focus_default()
    self:focus_title()
end

---@param winid? integer
---@return string?
function Composer:focused_slot(winid)
    winid = winid or vim.api.nvim_get_current_win()
    if self.title_win and self.title_win:valid() and winid == self.title_win.win then
        return "title"
    end
    if self.body_win and self.body_win:valid() and winid == self.body_win.win then
        return "body"
    end
end

---@param slot? string
---@param insert_mode? boolean
---@return boolean
function Composer:focus_slot(slot, insert_mode)
    if slot == "body" and self.body_win and self.body_win:valid() then
        vim.api.nvim_set_current_win(self.body_win.win)
        if insert_mode then
            vim.cmd.startinsert()
        end
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

function Composer:close()
    if self.title_win and self.title_win:valid() then
        self.title_win:close()
    end
    if self.body_win and self.body_win:valid() then
        self.body_win:close()
    end
    self.title_win = nil
    self.body_win = nil
end

return Composer
