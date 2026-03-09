local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h")
local local_lazy = vim.fn.expand("~/.local/share/nvim/lazy/lazy.nvim")
local local_snacks = vim.fn.expand("~/.local/share/nvim/lazy/snacks.nvim")
local lazypath = vim.loop.fs_stat(local_lazy) and local_lazy or (vim.fn.stdpath("data") .. "/lazy/lazy.nvim")

if not vim.loop.fs_stat(lazypath) then
  local url = "https://github.com/folke/lazy.nvim.git"
  local result = vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "--branch=stable",
    url,
    lazypath,
  })

  if vim.v.shell_error ~= 0 then
    vim.api.nvim_echo({
      { "Failed to bootstrap lazy.nvim:\n", "ErrorMsg" },
      { result, "WarningMsg" },
    }, true, {})
    vim.cmd("cquit")
  end
end

vim.opt.rtp:prepend(lazypath)
vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

local snacks = {
  "folke/snacks.nvim",
  priority = 1000,
  lazy = false,
  opts = {},
}

if vim.loop.fs_stat(local_snacks) then
  snacks.dir = local_snacks
end

require("lazy").setup({
  spec = {
    snacks,
    {
      dir = root,
      name = "codex-cli.nvim",
      dependencies = {
        "folke/snacks.nvim",
      },
      opts = {},
    },
  },
  change_detection = {
    notify = false,
  },
  performance = {
    rtp = {
      reset = false,
    },
  },
})
