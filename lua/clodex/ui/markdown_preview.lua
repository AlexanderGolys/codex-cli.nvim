local ui_win = require("clodex.ui.win")

---@class Clodex.MarkdownPreview
---@field win? snacks.win
---@field buf? integer
---@field key string
local Preview = {}
Preview.__index = Preview

local DEFAULT_WIDTH = 72
local DEFAULT_HEIGHT = 18

---@param key string
---@return Clodex.MarkdownPreview
function Preview.new(key)
    local self = setmetatable({}, Preview)
    self.key = key
    return self
end

---@return boolean
function Preview:is_open()
    return self.win ~= nil and self.win:valid()
end

---@param buf integer
---@param filetype string
local function configure_buffer(buf, filetype)
    vim.bo[buf].buftype = "nofile"
    vim.bo[buf].bufhidden = "wipe"
    vim.bo[buf].swapfile = false
    vim.bo[buf].modifiable = false
    vim.bo[buf].filetype = filetype
end

---@param lines string[]
---@return integer
local function longest_width(lines)
    local width = 1
    for _, line in ipairs(lines) do
        width = math.max(width, vim.fn.strdisplaywidth(line))
    end
    return width
end

---@param opts { title: string, lines: string[], filetype?: string, width?: integer, height?: integer }
function Preview:show(opts)
    local lines = #opts.lines > 0 and opts.lines or { "" }
    local filetype = opts.filetype or "markdown"

    if self.buf == nil or not vim.api.nvim_buf_is_valid(self.buf) then
        self.buf = ui_win.create_buffer({
            preset = "scratch",
            name = self.key,
        })
    end
    configure_buffer(self.buf, filetype)

    vim.bo[self.buf].modifiable = true
    vim.api.nvim_buf_set_lines(self.buf, 0, -1, false, lines)
    vim.bo[self.buf].modifiable = false

    local ui = vim.api.nvim_list_uis()[1]
    local editor_width = ui and ui.width or vim.o.columns
    local editor_height = ui and ui.height or vim.o.lines
    local width = math.min(math.max(longest_width(lines) + 4, 42), opts.width or DEFAULT_WIDTH, editor_width - 6)
    local height = math.min(math.max(#lines, 6), opts.height or DEFAULT_HEIGHT, editor_height - 4)

    if self:is_open() then
        self.win:update({
            title = (" %s "):format(opts.title),
            width = width,
            height = height,
        })
        return
    end

    self.win = ui_win.open({
        buf = self.buf,
        enter = true,
        backdrop = false,
        border = "rounded",
        title = (" %s "):format(opts.title),
        title_pos = "center",
        width = width,
        height = height,
        row = function()
            return math.max(math.floor((editor_height - height) / 2), 1)
        end,
        col = function()
            return math.max(math.floor((editor_width - width) / 2), 1)
        end,
        view = "markdown",
        bo = {
            buftype = "nofile",
            modifiable = false,
            filetype = filetype,
        },
        theme = "prompt_editor",
    })

    if self.win and self.win:valid() then
        vim.keymap.set("n", "q", function()
            self:close()
        end, { buffer = self.buf, silent = true })
        vim.keymap.set("n", "<Esc>", function()
            self:close()
        end, { buffer = self.buf, silent = true })
    end
end

function Preview:close()
    if self.win and self.win:valid() then
        self.win:close()
    end
    self.win = nil
end

function Preview:toggle(opts)
    if self:is_open() then
        self:close()
        return
    end
    self:show(opts)
end

return Preview
