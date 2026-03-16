local LanguageProfile = require("clodex.project.language")

describe("clodex.project.language", function()
    local profile

    before_each(function()
        profile = LanguageProfile.new()
    end)

    it("normalizes allowed filetypes and skips unsupported types", function()
        assert.are.equal("lua", profile:normalize_filetype("lua"))
        assert.are.equal("sh", profile:normalize_filetype("sh"))
        assert.are.equal("json", profile:normalize_filetype("json"))
        assert.is_nil(profile:normalize_filetype("markdown"))
        assert.is_nil(profile:normalize_filetype("text"))
        assert.is_nil(profile:normalize_filetype(nil))
    end)

    it("adds an other bucket for omitted low-share languages", function()
        local language_totals = {
            lua = 12,
            sh = 1,
            py = 1,
        }
        local languages = profile:dominant_languages(language_totals)

        assert.are.same({
            "lua",
            "other",
        }, vim.tbl_map(function(language)
            return language.name
        end, languages))
        assert.are.same({
            92,
            8,
        }, vim.tbl_map(function(language)
            return language.percent
        end, languages))
    end)

    it("prefers primary languages and falls back to config filetypes", function()
        local language_totals = {
            sh = 8,
            yaml = 1,
            toml = 1,
        }

        local languages = profile:dominant_languages(language_totals)

        assert.are.same({
            "sh",
        }, vim.tbl_map(function(language)
            return language.name
        end, languages))
        assert.are.same({
            100,
        }, vim.tbl_map(function(language)
            return language.percent
        end, languages))
    end)

    it("falls back to non-code filetypes for config-only repos", function()
        local language_totals = {
            yaml = 2,
            json = 1,
            toml = 1,
        }

        local languages = profile:dominant_languages(language_totals)

        assert.are.same({
            "yaml",
            "json",
            "toml",
        }, vim.tbl_map(function(language)
            return language.name
        end, languages))
        assert.are.same({
            50,
            25,
            25,
        }, vim.tbl_map(function(language)
            return language.percent
        end, languages))
    end)

    it("formats known language icons and keeps unknown languages as plain text", function()
        assert.are.equal(" sh", profile:format_label("sh"))
        assert.are.equal("zig", profile:format_label("zig"))
    end)
end)
