local LanguageProfile = require("clodex.project.language")

describe("clodex.project.language", function()
    local profile

    before_each(function()
        profile = LanguageProfile.new()
    end)

    it("detects languages from known code paths and ignores non-code files", function()
        assert.are.equal("lua", profile:language_for_path("lua/clodex/init.lua"))
        assert.are.equal("sh", profile:language_for_path("scripts/setup.zsh"))
        assert.are.equal("docker", profile:language_for_path("Dockerfile"))
        assert.is_nil(profile:language_for_path("README.md"))
        assert.is_nil(profile:language_for_path("package.json"))
        assert.is_nil(profile:language_for_path(nil))
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

    it("keeps all recognized languages instead of dropping smaller code buckets", function()
        local language_totals = {
            sh = 8,
            lua = 1,
            ts = 1,
        }

        local languages = profile:dominant_languages(language_totals)

        assert.are.same({
            "sh",
            "lua",
            "ts",
        }, vim.tbl_map(function(language)
            return language.name
        end, languages))
        assert.are.same({
            80,
            10,
            10,
        }, vim.tbl_map(function(language)
            return language.percent
        end, languages))
    end)

    it("returns no languages for config-only repos", function()
        local language_totals = {
        }

        local languages = profile:dominant_languages(language_totals)

        assert.are.same({}, languages)
    end)

    it("formats known language icons and keeps unknown languages as plain text", function()
        assert.are.equal(" sh", profile:format_label("sh"))
        assert.are.equal(" zig", profile:format_label("zig"))
        assert.are.equal("ocaml", profile:format_label("ocaml"))
    end)
end)
