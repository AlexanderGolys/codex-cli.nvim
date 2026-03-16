local root = vim.loop.cwd()

vim.opt.rtp:prepend(root)
vim.opt.rtp:append(root .. "/tests")
vim.opt.rtp:append(root .. "/lua")

local test_root = root .. "/.cache/clodex-nvim-test"
local lazy_root = test_root .. "/data/lazy"

vim.fn.mkdir(lazy_root, "p")

local function bootstrap_snacks()
    local lazypath = lazy_root .. "/lazy.nvim"
    if not vim.uv.fs_stat(lazypath .. "/lua/lazy/init.lua") then
        local git = vim.fn.exepath("git")
        if git == "" then
            return false, "git executable is missing; cannot install test dependencies"
        end

        local result = vim.fn.system({
            git,
            "clone",
            "--filter=blob:none",
            "--branch=stable",
            "https://github.com/folke/lazy.nvim.git",
            lazypath,
        })
        if vim.v.shell_error ~= 0 then
            return false, vim.trim(result)
        end
    end

    vim.opt.runtimepath:prepend(lazypath)

    local ok, lazy = pcall(require, "lazy")
    if not ok then
        return false, "failed to require lazy.nvim"
    end

    lazy.setup({
        {
            "folke/snacks.nvim",
            name = "snacks",
            lazy = false,
            priority = 1000,
        },
        {
            "nvim-lua/plenary.nvim",
            name = "plenary",
            lazy = false,
            priority = 1000,
        },
    }, {
        root = lazy_root,
        lockfile = lazy_root .. "/lazy-lock.json",
        install = {
            missing = true,
        },
    })

    pcall(function()
        vim.cmd("runtime! plugin/plenary.vim")
    end)

    return true
end

local function install_test_stubs()
    local function stub_win(opts)
        return { win = 0, buf = 0, opts = opts }
    end
    local snacks_win = setmetatable({
        resolve = function(_style, opts)
            return opts
        end,
    }, {
        __call = function(_, _style, opts)
            return stub_win(opts)
        end,
    })

    package.loaded["snacks"] = {
        terminal = {
            open = function()
            end,
        },
        win = snacks_win,
    }
    package.loaded["snacks.input"] = {
        input = function(opts, callback)
            callback(opts and opts.default or nil)
        end,
    }
    package.loaded["snacks.picker.select"] = {
        select = function(_items, _opts, on_choice)
            on_choice(nil)
        end,
    }
    package.loaded["snacks.picker"] = {}
    package.loaded["snacks.terminal"] = {
        open = function(_cmd) end,
    }
    package.loaded["snacks.lazygit"] = {
        open = function() end,
    }
    package.loaded["snacks.win"] = {
        resolve = function(_style, opts)
            return opts
        end,
        open = function(_style, opts)
            return stub_win(opts)
        end,
        __call = snacks_win.__call,
    }
end

if not bootstrap_snacks() then
    install_test_stubs()
end
