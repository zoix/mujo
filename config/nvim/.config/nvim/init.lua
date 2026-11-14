-- Neovim for the karma desktop: a small setup that stays out of the way.
--
--   lua/options.lua   editor behaviour
--   lua/keymaps.lua   keys that need no plugin (the leader is Space)
--   lua/plugins/      one file per group of plugins, loaded by lazy.nvim
--
-- Press Space and wait: which-key lists everything that can follow.
-- :Lazy shows the plugins; :checkhealth shows what is missing.

require("options")
require("keymaps")

-- lazy.nvim, the plugin manager: fetched on first start.
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.uv.fs_stat(lazypath) then
  local out = vim.fn.system({
    "git", "clone", "--filter=blob:none", "--branch=stable",
    "https://github.com/folke/lazy.nvim.git", lazypath,
  })
  if vim.v.shell_error ~= 0 then
    vim.api.nvim_echo({ { "Could not fetch lazy.nvim:\n" .. out, "ErrorMsg" } }, true, {})
    return
  end
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup("plugins", {
  install = { colorscheme = { "catppuccin" } },
  checker = { enabled = true, notify = false },
  change_detection = { notify = false },
})
