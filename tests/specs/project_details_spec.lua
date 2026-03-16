local Config = require("clodex.config")
local Details = require("clodex.project.details")
local fs = require("clodex.util.fs")

local function temp_dir()
    local dir = vim.fn.tempname()
    fs.ensure_dir(dir)
    return dir
end

local function write_file(path, contents)
    local file = assert(io.open(path, "w"))
    file:write(contents)
    file:close()
end

describe("clodex.project.details", function()
    local root
    local details

    before_each(function()
        root = temp_dir()
        details = Details.new(Config.new():setup())
    end)

    after_each(function()
        details = nil
        if root then
            fs.remove(root)
        end
    end)

    it("returns dominant languages and keeps core-language focus", function()
        for index = 1, 10 do
            write_file(fs.join(root, ("module_%d.lua"):format(index)), "local value = 1\nreturn value\n")
        end
        write_file(fs.join(root, "build.sh"), "#!/bin/sh\necho ok\n")
        write_file(fs.join(root, "deploy.sh"), "#!/bin/sh\necho deploy\n")
        write_file(fs.join(root, "tool.py"), "print('ok')\n")
        write_file(fs.join(root, "README.md"), "# Title\n")
        write_file(fs.join(root, "package.json"), "{\n  \"name\": \"demo\"\n}\n")

        local snapshot = details:compute({
            root = root,
        })

        assert.are.same({ "lua", "sh" }, vim.tbl_map(function(language)
            return language.name
        end, snapshot.languages))
        assert.are.same({ 83, 17 }, vim.tbl_map(function(language)
            return language.percent
        end, snapshot.languages))
    end)

    it("still reports config-centric repositories as languages", function()
        write_file(fs.join(root, "chart.yaml"), "apiVersion: v2\nname: demo\n")
        write_file(fs.join(root, "values.yaml"), "replicaCount: 1\n")
        write_file(fs.join(root, "package.json"), "{\n  \"name\": \"demo\"\n}\n")
        write_file(fs.join(root, "schema.toml"), "title = \"demo\"\n")
        write_file(fs.join(root, "README.md"), "# Docs\n")

        local snapshot = details:compute({
            root = root,
        })

        assert.are.same({ "yaml", "json", "toml" }, vim.tbl_map(function(language)
            return language.name
        end, snapshot.languages))
        assert.are.same({ 50, 25, 25 }, vim.tbl_map(function(language)
            return language.percent
        end, snapshot.languages))
        assert.is_true(snapshot.avg_lines_per_file ~= nil)
    end)

    it("counts average lines from unknown-filetype text files", function()
        write_file(fs.join(root, "note.md"), "title\nbody\n")
        write_file(fs.join(root, "changelog.txt"), "line\n")

        local snapshot = details:compute({
            root = root,
        })

        assert.are.same({}, snapshot.languages)
        assert.are.equal(1.5, snapshot.avg_lines_per_file)
    end)
end)
