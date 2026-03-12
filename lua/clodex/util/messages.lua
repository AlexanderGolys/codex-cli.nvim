local M = {}

local TRACEBACK_MARKERS = {
    "^stack traceback:$",
    "^# stacktrace:$",
}

local ERROR_HEADER_PATTERNS = {
    "^Error detected while processing",
    "^Error executing callback:",
}

local ERROR_LINE_PATTERNS = {
    "^E%d+:",
    "^%S+:%d+:",
    "^Failed to ",
}

---@param line string
---@param patterns string[]
---@return boolean
local function matches_any(line, patterns)
    for _, pattern in ipairs(patterns) do
        if line:match(pattern) then
            return true
        end
    end
    return false
end

---@param output string
---@return string[]
local function split_lines(output)
    if output == "" then
        return {}
    end
    return vim.split(output, "\n", { plain = true })
end

---@param lines string[]
---@param start_idx integer
---@param end_idx integer
---@return string
local function slice_text(lines, start_idx, end_idx)
    local chunk = {} ---@type string[]
    for index = start_idx, end_idx do
        chunk[#chunk + 1] = lines[index]
    end
    return vim.trim(table.concat(chunk, "\n"))
end

---@return string
local function messages_output()
    local ok, result = pcall(vim.api.nvim_exec2, "messages", { output = true })
    if not ok or type(result) ~= "table" then
        return ""
    end
    return result.output or ""
end

---@param lines string[]
---@param traceback_idx integer
---@return integer
local function traceback_start(lines, traceback_idx)
    local start_idx = traceback_idx
    while start_idx > 1 do
        local previous = lines[start_idx - 1]
        if vim.trim(previous) == "" then
            break
        end
        start_idx = start_idx - 1
        if matches_any(previous, ERROR_HEADER_PATTERNS) or matches_any(previous, ERROR_LINE_PATTERNS) then
            break
        end
    end
    return start_idx
end

---@param lines string[]
---@param start_idx integer
---@return integer
local function traceback_end(lines, start_idx)
    local seen_traceback = false
    local end_idx = #lines
    for index = start_idx, #lines do
        local line = lines[index]
        if matches_any(line, TRACEBACK_MARKERS) then
            seen_traceback = true
        elseif seen_traceback and vim.trim(line) == "" then
            end_idx = index - 1
            break
        end
    end
    return end_idx
end

---@param text string
---@return string?
local function normalized_result(text)
    text = vim.trim(text)
    return text ~= "" and text or nil
end

--- Returns the newest traceback/error body from Neovim's message history.
--- Generic error headers are dropped so the returned text is ready for prompt input.
---@return string?
function M.last_error_traceback()
    local lines = split_lines(messages_output())

    for index = #lines, 1, -1 do
        if matches_any(lines[index], TRACEBACK_MARKERS) then
            local start_idx = traceback_start(lines, index)
            local end_idx = traceback_end(lines, start_idx)
            local first_line = lines[start_idx]
            if matches_any(first_line, ERROR_HEADER_PATTERNS) then
                start_idx = math.min(start_idx + 1, end_idx)
            end
            return normalized_result(slice_text(lines, start_idx, end_idx))
        end
    end

    for index = #lines, 1, -1 do
        if matches_any(lines[index], ERROR_LINE_PATTERNS) then
            return normalized_result(lines[index])
        end
    end

    return normalized_result(vim.v.errmsg or "")
end

return M
