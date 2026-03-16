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

local PROJECT_LANGUAGE_FILETYPES = {
  c = "c",
  cpp = "cpp",
  css = "css",
  dockerfile = "docker",
  go = "go",
  html = "html",
  java = "java",
  javascript = "js",
  javascriptreact = "jsx",
  json = "json",
  jsonc = "jsonc",
  lua = "lua",
  make = "make",
  python = "py",
  ruby = "rb",
  rust = "rs",
  sh = "sh",
  sql = "sql",
  toml = "toml",
  typescript = "ts",
  typescriptreact = "tsx",
  vim = "vim",
  xml = "xml",
  yaml = "yaml",
}

local CORE_LANGUAGE_FILETYPES = {
  c = true,
  cpp = true,
  css = true,
  dockerfile = true,
  go = true,
  html = true,
  java = true,
  javascript = true,
  javascriptreact = true,
  lua = true,
  make = true,
  python = true,
  ruby = true,
  rust = true,
  sh = true,
  sql = true,
  typescript = true,
  typescriptreact = true,
  vim = true,
}

local LANGUAGE_ICONS = {
  c = "",
  cpp = "",
  css = "",
  docker = "",
  go = "",
  html = "",
  java = "",
  js = "",
  jsx = "",
  json = "",
  lua = "",
  make = "",
  py = "",
  rb = "",
  rs = "",
  sh = "",
  sql = "",
  toml = "",
  ts = "",
  tsx = "",
  vim = "",
  xml = "󰗀",
  yaml = "",
}

---@return Clodex.ProjectLanguage
function LanguageProfile.new()
  return setmetatable({}, LanguageProfile)
end

---@param language_totals table<string, integer>
---@param filtered boolean
---@return table<string, integer>, integer
local function filter_primary_language_totals(language_totals, filtered)
  local selected = {} ---@type table<string, integer>
  local selected_file_count = 0

  for language, count in pairs(language_totals) do
    if not filtered or CORE_LANGUAGE_FILETYPES[language] then
      selected[language] = count
      selected_file_count = selected_file_count + count
    end
  end

  if filtered and selected_file_count == 0 then
    return language_totals, 0
  end

  return selected, selected_file_count
end

---@param filetype string?
---@return string?
function LanguageProfile:normalize_filetype(filetype)
  if not filetype or filetype == "" then
    return nil
  end
  return PROJECT_LANGUAGE_FILETYPES[filetype]
end

---@param language_totals table<string, integer>
---@return Clodex.ProjectLanguageStat[]
function LanguageProfile:dominant_languages(language_totals)
  local selected_totals = language_totals
  local selected_file_count = 0

  selected_totals, selected_file_count = filter_primary_language_totals(language_totals, true)
  if selected_file_count == 0 then
    selected_totals, selected_file_count = filter_primary_language_totals(language_totals, false)
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

return LanguageProfile
