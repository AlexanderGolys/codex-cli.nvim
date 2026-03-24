

---@class Clodex.ProjectLanguageStat
---@field name string
---@field files integer
---@field percent integer

---@class Clodex.ProjectLanguage
local LanguageProfile = {}
LanguageProfile.__index = LanguageProfile

local DOMINANT_LANGUAGE_COVERAGE_PERCENT = 85
local DOMINANT_LANGUAGE_MIN_PERCENT = 10
local OTHER_LANGUAGE_NAME = "other"

local PROJECT_LANGUAGE_EXTENSIONS = {
    c = "c",
    h = "c",
    cc = "cpp",
    cpp = "cpp",
    cxx = "cpp",
    hpp = "cpp",
    tpp = "cpp",
    hxx = "cpp",
    hh = "cpp",
    ipp = "cpp",
    cu = "cpp",
    cuh = "cpp",
    cl = "cpp",
    css = "css",
    htm = "html",
    html = "html",
    java = "java",
    js = "js",
    jsx = "jsx",
    lua = "lua",
    php = "php",
    py = "py",
    rb = "rb",
    rs = "rs",
    sh = "sh",
    bash = "sh",
    zsh = "sh",
    sql = "sql",
    ts = "ts",
    tsx = "jsx",
    vim = "vim",
    zig = "zig",
}

local PROJECT_LANGUAGE_FILENAMES = {
    ["dockerfile"] = "docker",
    ["makefile"] = "make",
}

local LANGUAGE_ICONS = {
    c = " ",
    cpp = " ",
    css = " ",
    docker = " ",
    go = " ",
    html = " ",
    java = " ",
    js = " ",
    jsx = " ",
    lua = " ",
    make = " ",
    php = " ",
    py = " ",
    rb = " ",
    rs = " ",
    sh = " ",
    sql = " ",
    ts = " ",
    vim = " ",
    zig = " ",
}

---@return Clodex.ProjectLanguage
function LanguageProfile.new()
    return setmetatable({}, LanguageProfile)
end

---@param path string?
---@return string?
function LanguageProfile:language_for_path(path)
    path = vim.trim(path or "")
    if path == "" then
        return nil
    end
    local name = vim.fs.basename(path):lower()
    if PROJECT_LANGUAGE_FILENAMES[name] then
        return PROJECT_LANGUAGE_FILENAMES[name]
    end
    local extension = name:match("%.([^.]+)$")
    if not extension then
        return nil
    end
    return PROJECT_LANGUAGE_EXTENSIONS[extension]
end

---@param language_totals table<string, integer>
---@return Clodex.ProjectLanguageStat[]
function LanguageProfile:dominant_languages(language_totals)
    local selected_file_count = 0
    local selected_totals = language_totals
    for _, count in pairs(language_totals) do
        selected_file_count = selected_file_count + count
    end
    if selected_file_count == 0 then
        return {}
    end

    local languages = {} ---@type Clodex.ProjectLanguageStat[]
    for name, count in pairs(selected_totals) do
        languages[#languages + 1] = {
            name = name,
            files = count,
            percent = math.floor((count * 100 / selected_file_count) + 0.5),
        }
    end

    table.sort(languages, function(left, right)
        if left.files ~= right.files then
            return left.files > right.files
        end
        return left.name < right.name
    end)

    if #languages <= 1 then
        return languages
    end

    local dominant = {} ---@type Clodex.ProjectLanguageStat[]
    local omitted_files = 0
    local omitted_percent = 0
    local coverage = 0
    for index, language in ipairs(languages) do
        if index > 1
            and language.percent < DOMINANT_LANGUAGE_MIN_PERCENT
            and coverage >= DOMINANT_LANGUAGE_COVERAGE_PERCENT
        then
            omitted_files = omitted_files + language.files
            omitted_percent = omitted_percent + language.percent
        else
            dominant[#dominant + 1] = language
            coverage = coverage + language.percent
        end
    end

    if omitted_files > 0 and omitted_percent > 0 then
        dominant[#dominant + 1] = {
            name = OTHER_LANGUAGE_NAME,
            files = omitted_files,
            percent = omitted_percent,
        }
    end

    return dominant
end

---@param language string
---@return string
function LanguageProfile:format_label(language)
    local icon = LANGUAGE_ICONS[language]
    if not icon then
        return language
    end
    return ("%s %s"):format(icon, language)
end

LanguageProfile.ICONS = LANGUAGE_ICONS

return LanguageProfile
