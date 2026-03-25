---@class Clodex.PromptDraftStore
---@field values table<string, table>
local DraftStore = {}
DraftStore.__index = DraftStore

---@return Clodex.PromptDraftStore
function DraftStore.new()
    return setmetatable({ values = {} }, DraftStore)
end

---@param kind string
---@param variant? string
---@return string
function DraftStore:key(kind, variant)
    return variant and (kind .. ":" .. variant) or kind
end

---@param kind string
---@param variant? string
---@param fallback? table
---@return table
function DraftStore:get(kind, variant, fallback)
    local key = self:key(kind, variant)
    local value = self.values[key]
    if value then
        return vim.deepcopy(value)
    end
    return vim.deepcopy(fallback or {})
end

---@param kind string
---@param variant? string
---@param value table
function DraftStore:set(kind, variant, value)
    self.values[self:key(kind, variant)] = vim.deepcopy(value or {})
end

return DraftStore
