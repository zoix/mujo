-- Finding things, files, git, sessions.
return {
  -- One library for the picker, the file explorer, the start screen,
  -- notifications, the terminal and lazygit.
  {
    "folke/snacks.nvim",
    priority = 900,
    lazy = false,
    opts = {
      bigfile = { enabled = true },
      dashboard = {
        enabled = true,
        sections = {
          { section = "header" },
          { section = "keys", gap = 1, padding = 1 },
          { icon = " ", title = "Recent files", section = "recent_files", cwd = true, indent = 2, padding = 1 },
          { section = "startup" },
        },
      },
      explorer = { enabled = true },
      indent = { enabled = true, animate = { enabled = false } },
      input = { enabled = true },
      notifier = { enabled = true },
      picker = { enabled = true },
      quickfile = { enabled = true },
      scope = { enabled = true },
      statuscolumn = { enabled = true },
      words = { enabled = true },
    },
    keys = {
      -- find
      { "<leader>ff", function() Snacks.picker.files({ hidden = true }) end, desc = "Find files" },
      { "<leader>fr", function() Snacks.picker.recent() end, desc = "Recent files" },
      { "<leader>fs", function() Snacks.picker.grep() end, desc = "Find text in the project" },
      { "<leader>fc", function() Snacks.picker.grep_word() end, desc = "Find the word under the cursor", mode = { "n", "x" } },
      { "<leader>fb", function() Snacks.picker.buffers() end, desc = "Open buffers" },
      { "<leader>fh", function() Snacks.picker.help() end, desc = "Help pages" },
      { "<leader>fk", function() Snacks.picker.keymaps() end, desc = "Keymaps" },
      { "<leader>f:", function() Snacks.picker.commands() end, desc = "Commands, with descriptions" },
      { "<leader><space>", function() Snacks.picker.smart() end, desc = "Find anything" },
      -- explorer
      { "<leader>ee", function() Snacks.explorer() end, desc = "File explorer" },
      { "<leader>ef", function() Snacks.explorer.reveal() end, desc = "Show this file in the explorer" },
      -- buffers and windows
      { "<leader>bx", function() Snacks.bufdelete() end, desc = "Close this buffer" },
      { "<leader>sm", function() Snacks.zen.zoom() end, desc = "Maximize or restore this split" },
      { "<leader>z", function() Snacks.zen() end, desc = "Zen mode" },
      -- git, terminal, notifications
      { "<leader>gg", function() Snacks.lazygit() end, desc = "Lazygit" },
      { "<leader>gl", function() Snacks.picker.git_log() end, desc = "Git log" },
      { "<leader>gs", function() Snacks.picker.git_status() end, desc = "Git status" },
      { "<A-i>", function() Snacks.terminal() end, desc = "Terminal", mode = { "n", "t" } },
      { "<leader>ns", function() Snacks.notifier.show_history() end, desc = "Notification history" },
    },
  },

  -- Changed lines in the margin; stage or undo a change without leaving.
  {
    "lewis6991/gitsigns.nvim",
    event = { "BufReadPre", "BufNewFile" },
    opts = {
      on_attach = function(buffer)
        local gs = require("gitsigns")
        local function map(keys, action, desc)
          vim.keymap.set("n", keys, action, { buffer = buffer, desc = desc })
        end
        map("]h", function() gs.nav_hunk("next") end, "Next change")
        map("[h", function() gs.nav_hunk("prev") end, "Previous change")
        map("<leader>gp", gs.preview_hunk, "Preview this change")
        map("<leader>ga", gs.stage_hunk, "Stage this change")
        map("<leader>gr", gs.reset_hunk, "Undo this change")
        map("<leader>gb", function() gs.blame_line({ full = true }) end, "Who changed this line")
      end,
    },
  },

  -- TODO, FIXME and friends stand out; ]t and [t jump between them.
  {
    "folke/todo-comments.nvim",
    event = { "BufReadPre", "BufNewFile" },
    dependencies = { "nvim-lua/plenary.nvim" },
    opts = {},
    keys = {
      -- (Listed here so that pressing it loads the plugin, which adds this picker.)
      { "<leader>ft", function() Snacks.picker.todo_comments() end, desc = "TODO comments" },
      { "]t", function() require("todo-comments").jump_next() end, desc = "Next TODO" },
      { "[t", function() require("todo-comments").jump_prev() end, desc = "Previous TODO" },
    },
  },

  -- Sessions: the open files of a project, saved when you leave.
  {
    "folke/persistence.nvim",
    event = "BufReadPre",
    opts = {},
    keys = {
      { "<leader>wr", function() require("persistence").load() end, desc = "Restore the session for this folder" },
      { "<leader>ws", function() require("persistence").save() end, desc = "Save the session" },
    },
  },
}
