-- Editor behaviour. Kept from the previous setup unless noted.
local opt = vim.opt

opt.number = true
opt.relativenumber = true
opt.cursorline = true
opt.signcolumn = "yes"         -- no text shift when signs appear
opt.wrap = false
opt.scrolloff = 6              -- (new) keep some lines around the cursor
opt.termguicolors = true

opt.tabstop = 2
opt.shiftwidth = 2
opt.expandtab = true
opt.autoindent = true
opt.smartindent = true

opt.ignorecase = true
opt.smartcase = true           -- case matters once a capital is typed
opt.inccommand = "split"       -- (new) preview :s replacements while typing

opt.clipboard:append("unnamedplus")  -- yank and paste use the system clipboard
opt.splitright = true
opt.splitbelow = true
opt.swapfile = false
opt.undofile = true            -- (new) undo history survives closing the file
opt.updatetime = 250
opt.timeoutlen = 400           -- how soon which-key appears
opt.confirm = true             -- (new) ask instead of failing on unsaved changes
opt.mouse = "a"

-- (new) No command row under the status line, so the status line sits right
-- above tmux's. The command line and messages are drawn by noice
-- (plugins/ui.lua). The status line already shows the mode and the position.
opt.cmdheight = 0
opt.showmode = false
opt.ruler = false

-- Folds follow the syntax tree where a parser exists; everything starts open.
opt.foldmethod = "expr"
opt.foldexpr = "v:lua.vim.treesitter.foldexpr()"
opt.foldlevelstart = 99
opt.foldtext = ""

-- Light or dark as the desktop is: mujo keeps the mode in its config file.
local function mujo_mode()
  local path = (os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")) .. "/mujo/config.json"
  local file = io.open(path, "r")
  if not file then return "dark" end
  local text = file:read("*a")
  file:close()
  local ok, config = pcall(vim.json.decode, text)
  return ok and type(config) == "table" and config.mode == "light" and "light" or "dark"
end
opt.background = mujo_mode()

-- Briefly highlight what was yanked.
vim.api.nvim_create_autocmd("TextYankPost", {
  callback = function() vim.hl.on_yank({ timeout = 150 }) end,
})

-- The title of the terminal (and of the tmux pane): the folder, then "nvim".
opt.title = true
opt.titlestring = "%{fnamemodify(getcwd(), ':t')} - nvim"

-- Inside tmux, tell it that this pane runs Neovim: mujo's tmux.conf then
-- lays its status line out to go with Neovim's (docs/tmux.md).
if vim.env.TMUX and vim.env.TMUX_PANE then
  local function tell_tmux(running)
    return vim.system({
      "tmux", "set", "-p", "-t", vim.env.TMUX_PANE, "@mujo_nvim", running and "1" or "", ";", "mujo-status",
    })
  end
  vim.api.nvim_create_autocmd({ "VimEnter", "VimResume" }, {
    callback = function() tell_tmux(true) end,
  })
  vim.api.nvim_create_autocmd({ "VimLeavePre", "VimSuspend" }, {
    callback = function() tell_tmux(false):wait(500) end,
  })
end
