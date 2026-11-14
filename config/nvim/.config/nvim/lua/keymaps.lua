-- Keys that need no plugin. The leader is Space; keys for plugins are in
-- their own files. Every mapping has a description, which which-key shows.
vim.g.mapleader = " "
vim.g.maplocalleader = " "

local map = vim.keymap.set

map("i", "jk", "<Esc>", { desc = "Leave insert mode" })
map("n", "<Esc>", "<cmd>nohlsearch<CR>", { desc = "Clear search highlights" })
map("n", "<leader>nh", "<cmd>nohlsearch<CR>", { desc = "Clear search highlights" })

map("n", "<leader>+", "<C-a>", { desc = "Increment number" })
map("n", "<leader>-", "<C-x>", { desc = "Decrement number" })

-- Splits
map("n", "<leader>sv", "<C-w>v", { desc = "Split vertically" })
map("n", "<leader>sh", "<C-w>s", { desc = "Split horizontally" })
map("n", "<leader>se", "<C-w>=", { desc = "Make splits equal" })
map("n", "<leader>sx", "<cmd>close<CR>", { desc = "Close this split" })
map("n", "<C-h>", "<C-w>h", { desc = "Go to the split on the left" })
map("n", "<C-j>", "<C-w>j", { desc = "Go to the split below" })
map("n", "<C-k>", "<C-w>k", { desc = "Go to the split above" })
map("n", "<C-l>", "<C-w>l", { desc = "Go to the split on the right" })

-- Tabs
map("n", "<leader>to", "<cmd>tabnew<CR>", { desc = "New tab" })
map("n", "<leader>tx", "<cmd>tabclose<CR>", { desc = "Close tab" })
map("n", "<leader>tn", "<cmd>tabnext<CR>", { desc = "Next tab" })
map("n", "<leader>tp", "<cmd>tabprevious<CR>", { desc = "Previous tab" })
map("n", "<leader>tf", "<cmd>tabnew %<CR>", { desc = "Open this file in a new tab" })

-- Buffers (closing one is <leader>bx, in plugins/editor.lua)
map("n", "<leader>bn", "<cmd>bnext<CR>", { desc = "Next buffer" })
map("n", "<leader>bp", "<cmd>bprevious<CR>", { desc = "Previous buffer" })
map("n", "<S-l>", "<cmd>bnext<CR>", { desc = "Next buffer" })
map("n", "<S-h>", "<cmd>bprevious<CR>", { desc = "Previous buffer" })

-- Small comforts
map("n", "<leader>w", "<cmd>write<CR>", { desc = "Save" })
map("n", "<leader>q", "<cmd>quit<CR>", { desc = "Quit this window" })
map("v", "<", "<gv", { desc = "Indent less, keep the selection" })
map("v", ">", ">gv", { desc = "Indent more, keep the selection" })
map("v", "J", ":m '>+1<CR>gv=gv", { desc = "Move the selection down", silent = true })
map("v", "K", ":m '<-2<CR>gv=gv", { desc = "Move the selection up", silent = true })
