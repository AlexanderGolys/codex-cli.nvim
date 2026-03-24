--- Shared prompt definitions and formatting helpers used across prompt actions and UI.
---@alias Clodex.PromptCategory
---| "todo"
---| "bug"
---| "visual"
---| "freeform"
---| "adjustment"
---| "refactor"
---| "idea"
---| "ask"
---| "explain"
---| "library"
---| "notworking"

---@class Clodex.PromptCategoryDef
---@field id Clodex.PromptCategory
---@field label string
---@field title_prefix? string
---@field highlight string
---@field default_title string
---@field picker_detail? string
---@field commit_policy? "required"|"skip"|"optional"

---@class Clodex.PromptComposer.Spec
---@field title string
---@field details? string

---@class Clodex.PromptLibrary.Template
---@field id string
---@field label string
---@field title string
---@field details string
---@field kind Clodex.PromptCategory
---@field language_aware? boolean

---@class Clodex.PromptLibrary.ResolveOpts
---@field language? string

---@class Clodex.Prompt.NormalizeResult
---@field title string
---@field details? string
---@field broken boolean

---@class Clodex.Prompt
---@field categories { list: fun(): Clodex.PromptCategoryDef[], get: fun(id?: string): Clodex.PromptCategoryDef, is_valid: fun(id?: string): boolean, requires_commit: fun(id?: string): boolean, commit_policy: fun(id?: string): "required"|"skip"|"optional" }
---@field library { list: fun(opts?: Clodex.PromptLibrary.ResolveOpts): Clodex.PromptLibrary.Template[], get: fun(id: string, opts?: Clodex.PromptLibrary.ResolveOpts): Clodex.PromptLibrary.Template? }
local M = {}

local WHITESPACE_SUFFIX = " [...]"
local MIDWORD_SUFFIX = "-[...]"
local LANGUAGE_LABELS = {
    c = "C",
    cpp = "C++",
    css = "CSS",
    docker = "Docker",
    go = "Go",
    html = "HTML",
    java = "Java",
    js = "JavaScript",
    jsx = "React/JSX",
    lua = "Lua",
    make = "Make",
    php = "PHP",
    py = "Python",
    rb = "Ruby",
    rs = "Rust",
    sh = "shell",
    sql = "SQL",
    ts = "TypeScript",
    tsx = "React/TSX",
    vim = "Vimscript",
    zig = "Zig",
}
local TITLE_GROUP_SUFFIX = {
    todo = "TodoTitle",
    bug = "BugTitle",
    visual = "VisualTitle",
    freeform = "FreeformTitle",
    adjustment = "FreeformTitle",
    refactor = "RefactorTitle",
    idea = "IdeaTitle",
    ask = "ExplainTitle",
    explain = "ExplainTitle",
    library = "IdeaTitle",
    notworking = "NotWorkingTitle",
}

---@type Clodex.PromptCategoryDef[]
local categories = {
    {
        id = "todo",
        label = "TODO",
        highlight = "todo_title",
        default_title = "New todo",
    },
    {
        id = "bug",
        label = "Bug",
        highlight = "bug_title",
        default_title = "Investigate runtime error",
        title_prefix = "Investigate runtime error",
    },
    {
        id = "visual",
        label = "Visual",
        highlight = "visual_title",
        default_title = "Review image and implement requested changes",
    },
    {
        id = "freeform",
        label = "Freeform",
        highlight = "freeform_title",
        default_title = "",
        picker_detail = "Send any message to the agent",
        commit_policy = "optional",
    },
    {
        id = "refactor",
        label = "Refactor",
        highlight = "refactor_title",
        default_title = "Refactor implementation",
    },
    {
        id = "idea",
        label = "Idea",
        highlight = "idea_title",
        default_title = "Explore an idea",
    },
    {
        id = "ask",
        label = "Ask",
        highlight = "explain_title",
        default_title = "Ask about the current behavior",
        commit_policy = "skip",
    },
    {
        id = "library",
        label = "Library",
        highlight = "idea_title",
        default_title = "Use a saved prompt template",
    },
    {
        id = "notworking",
        label = "Not Working",
        highlight = "notworking_title",
        default_title = "Fix a previously implemented feature that is not working",
    },
}

local categories_by_id = {} ---@type table<Clodex.PromptCategory, Clodex.PromptCategoryDef>
for _, category in ipairs(categories) do
    categories_by_id[category.id] = category
end
categories_by_id.explain = categories_by_id.ask
categories_by_id.adjustment = categories_by_id.freeform

---@type Clodex.PromptLibrary.Template[]
local templates = {
    {
        id = "fix-diagnostics",
        label = "Fix diagnostics",
        title = "Fix diagnostics from the current project",
        kind = "freeform",
        details = table.concat({
            "Use `&all_diagnostics` as the primary problem list.",
            "Group related issues, fix them in a coherent order, and mention any follow-up validation.",
        }, "\n\n"),
    },
    {
        id = "explain-current-file",
        label = "Ask about current file",
        title = "Ask about the current file",
        kind = "ask",
        details = table.concat({
            "Explain `&file` in terms of its responsibilities, main control flow, and important assumptions.",
            "Call out any non-obvious edge cases or follow-up refactors worth considering.",
        }, "\n\n"),
    },
    {
        id = "refactor-selection",
        label = "Refactor selection",
        title = "Refactor the selected code",
        kind = "refactor",
        details = table.concat({
            "Focus on `&selection` and keep behavior intact while reducing duplication.",
            "Keep behavior intact, reduce duplication, and explain any structural tradeoffs.",
        }, "\n\n"),
    },
    {
        id = "fix-buffer-diagnostics",
        label = "Fix buffer diagnostics",
        title = "Fix diagnostics from the current buffer",
        kind = "idea",
        details = table.concat({
            "Use `&buff_diagnostics` as the main issue list.",
            "Fix what should be fixed and explain clearly why any remaining diagnostics should be ignored.",
        }, "\n\n"),
    },
    {
        id = "review-current-file",
        label = "Review current file",
        title = "Review the current file",
        kind = "ask",
        language_aware = true,
        details = table.concat({
            "Review `&file` for correctness, structure, naming, and maintainability.",
            "Call out the most important problems first, then list concrete improvements and any follow-up refactors worth considering.",
        }, "\n\n"),
    },
    {
        id = "simplify-selection",
        label = "Simplify selection",
        title = "Simplify the selected code",
        kind = "refactor",
        language_aware = true,
        details = table.concat({
            "Focus on `&selection` and simplify it without changing behavior.",
            "Reduce indirection, duplication, and unnecessary branching while preserving the surrounding API and the repository's style.",
        }, "\n\n"),
    },
    {
        id = "improve-documentation",
        label = "Improve documentation",
        title = "Improve documentation for the current file",
        kind = "todo",
        language_aware = true,
        details = table.concat({
            "Use `&file` as the main reference and improve the documentation around the code that matters most.",
            "Prefer concise, high-signal explanations, add missing usage guidance when helpful, and avoid comments that just restate obvious code.",
        }, "\n\n"),
    },
    {
        id = "map-project-architecture",
        label = "Map project architecture",
        title = "Explain the project architecture",
        kind = "ask",
        language_aware = true,
        details = table.concat({
            "Explain the repository in terms of its main modules, boundaries, data flow, and architectural decisions.",
            "Highlight the most important tradeoffs, fragile spots, and places where the structure could be clarified or simplified.",
        }, "\n\n"),
    },
    {
        id = "plan-project-work",
        label = "Plan project work",
        title = "Create an implementation plan for the current project",
        kind = "idea",
        language_aware = true,
        details = table.concat({
            "Study the current codebase and produce a concrete implementation plan before changing code.",
            "Break the work into ordered steps, mention architectural constraints, and call out the validation needed for each stage.",
        }, "\n\n"),
    },
    {
        id = "review-plan-against-code",
        label = "Review plan against code",
        title = "Review a plan against the current codebase",
        kind = "ask",
        language_aware = true,
        details = table.concat({
            "Use the pasted plan as the proposal and compare it against the actual repository structure and constraints.",
            "Point out where the plan matches the codebase, where it conflicts with reality, and what should be changed before implementation starts.",
        }, "\n\n"),
    },
}

local templates_by_id = {} ---@type table<string, Clodex.PromptLibrary.Template>
for _, template in ipairs(templates) do
    templates_by_id[template.id] = template
end

local function prepend_details(title, details)
    local parts = {} ---@type string[]
    local head = vim.trim(title or "")
    local tail = vim.trim(details or "")
    if head ~= "" then
        parts[#parts + 1] = head
    end
    if tail ~= "" then
        parts[#parts + 1] = tail
    end
    return #parts > 0 and table.concat(parts, "\n\n") or nil
end

---@param language? string
---@return string?
local function normalize_language(language)
    language = type(language) == "string" and vim.trim(language):lower() or ""
    if language == "" or language == "other" then
        return nil
    end
    return language
end

---@param language? string
---@return string?
local function language_label(language)
    language = normalize_language(language)
    if not language then
        return nil
    end
    return LANGUAGE_LABELS[language] or language:upper()
end

---@param template Clodex.PromptLibrary.Template
---@param opts? Clodex.PromptLibrary.ResolveOpts
---@return Clodex.PromptLibrary.Template
local function resolve_template(template, opts)
    local resolved = vim.deepcopy(template)
    local language = template.language_aware and language_label(opts and opts.language) or nil
    if not language then
        return resolved
    end

    resolved.label = ("%s (%s)"):format(resolved.label, language)
    resolved.details = table.concat({
        ("Use idiomatic %s conventions for structure, naming, error handling, and documentation whenever that guidance fits the code under review."):format(language),
        resolved.details,
    }, "\n\n")
    return resolved
end

M.categories = {}

---@return Clodex.PromptCategoryDef[]
function M.categories.list()
    return vim.deepcopy(categories)
end

---@param id? string
---@return Clodex.PromptCategoryDef
function M.categories.get(id)
    return categories_by_id[id] or categories_by_id.todo
end

---@param id? string
---@return boolean
function M.categories.is_valid(id)
    return categories_by_id[id] ~= nil
end

---@param id? string
---@return boolean
function M.categories.requires_commit(id)
    return (M.categories.get(id).commit_policy or "required") == "required"
end

---@param id? string
---@return "required"|"skip"|"optional"
function M.categories.commit_policy(id)
    return M.categories.get(id).commit_policy or "required"
end

M.library = {}

---@param opts? Clodex.PromptLibrary.ResolveOpts
---@return Clodex.PromptLibrary.Template[]
function M.library.list(opts)
    local items = {} ---@type Clodex.PromptLibrary.Template[]
    for _, template in ipairs(templates) do
        items[#items + 1] = resolve_template(template, opts)
    end
    return items
end

---@param id string
---@param opts? Clodex.PromptLibrary.ResolveOpts
---@return Clodex.PromptLibrary.Template?
function M.library.get(id, opts)
    local template = templates_by_id[id]
    return template and resolve_template(template, opts) or nil
end

---@param title string
---@param details? string
---@return string
function M.render(title, details)
    local lines = { vim.trim(title or "") }
    local body = details and vim.trim(details) or ""
    if body ~= "" then
        lines[#lines + 1] = ""
        lines[#lines + 1] = body
    end
    return table.concat(lines, "\n")
end

---@param body string
---@return Clodex.PromptComposer.Spec?
function M.parse(body)
    local trimmed = vim.trim(body or "")
    if trimmed == "" then
        return nil
    end

    local lines = vim.split(trimmed, "\n", { plain = true })
    local title_index ---@type integer?
    for index, line in ipairs(lines) do
        if vim.trim(line) ~= "" then
            title_index = index
            break
        end
    end
    if not title_index then
        return nil
    end

    local title = vim.trim(lines[title_index])
    if title == "" then
        return nil
    end

    local detail_lines = {}
    for index = title_index + 1, #lines do
        detail_lines[#detail_lines + 1] = lines[index]
    end

    local details = vim.trim(table.concat(detail_lines, "\n"))
    return {
        title = title,
        details = details ~= "" and details or nil,
    }
end

---@param kind? Clodex.PromptCategory|string
---@return string
function M.title_group(kind)
    local suffix = TITLE_GROUP_SUFFIX[M.categories.get(kind).id] or TITLE_GROUP_SUFFIX.todo
    return "ClodexPrompt" .. suffix
end

---@return string
function M.preview_group()
    return "ClodexPromptPreviewText"
end

---@param kind? Clodex.PromptCategory|string
---@return string
function M.preview_group_for(kind)
    if M.categories.get(kind).id == "freeform" then
        return "ClodexPromptFreeformPreviewText"
    end
    return M.preview_group()
end

---@param opts { title: string, details?: string, max_width?: integer }
---@return Clodex.Prompt.NormalizeResult
function M.normalize_title(opts)
    local title = vim.trim(opts.title or "")
    local details = vim.trim(opts.details or "")
    local max_width = math.max(tonumber(opts.max_width) or 0, 1)
    if title == "" or vim.fn.strdisplaywidth(title) <= max_width then
        return {
            title = title,
            details = details ~= "" and details or nil,
            broken = false,
        }
    end

    for idx = 1, #title do
        local ch = title:sub(idx, idx)
        local next_text = title:sub(idx + 1)
        if ch:match("[%.!?]") and next_text:match("^%s+%S") then
            local prev = idx > 1 and title:sub(idx - 1, idx - 1) or ""
            if prev:match("[%w%]%)\"']") and vim.fn.strdisplaywidth(title:sub(1, idx)) <= max_width then
                return {
                    title = vim.trim(title:sub(1, idx)),
                    details = prepend_details(next_text, details),
                    broken = true,
                }
            end
        end
    end

    for idx = 1, #title do
        if title:sub(idx, idx) == "," then
            local prev = idx > 1 and title:sub(idx - 1, idx - 1) or ""
            local next_text = title:sub(idx + 1)
            if prev ~= "" and not prev:match("%s") and next_text:match("^%s+%S") then
                if vim.fn.strdisplaywidth(title:sub(1, idx)) <= max_width then
                    local tail = vim.trim(next_text)
                    if tail:sub(1, 1):match("%l") then
                        tail = tail:sub(1, 1):upper() .. tail:sub(2)
                    end
                    return {
                        title = vim.trim(title:sub(1, idx)),
                        details = prepend_details(tail, details),
                        broken = true,
                    }
                end
            end
        end
    end

    local whitespace_idx ---@type integer?
    for idx = 1, #title do
        if title:sub(idx, idx):match("%s") then
            local head = title:sub(1, idx - 1):gsub("%s+$", "")
            if head ~= "" and vim.fn.strdisplaywidth(head .. WHITESPACE_SUFFIX) <= max_width then
                whitespace_idx = idx
            end
        end
    end
    if whitespace_idx then
        return {
            title = title:sub(1, whitespace_idx - 1):gsub("%s+$", "") .. WHITESPACE_SUFFIX,
            details = prepend_details(title:sub(whitespace_idx + 1), details),
            broken = true,
        }
    end

    local best = ""
    for idx = 1, #title do
        local head = title:sub(1, idx)
        if vim.fn.strdisplaywidth(head .. MIDWORD_SUFFIX) > max_width then
            break
        end
        best = head
    end

    if best == "" then
        return {
            title = MIDWORD_SUFFIX:sub(1, math.max(max_width, 1)),
            details = prepend_details(title, details),
            broken = true,
        }
    end

    return {
        title = best .. MIDWORD_SUFFIX,
        details = prepend_details(title:sub(#best + 1), details),
        broken = true,
    }
end

return M
