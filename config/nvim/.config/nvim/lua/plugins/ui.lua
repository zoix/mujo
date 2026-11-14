-- How it looks, and the helpers that tell you what a key does.
return {
  -- Catppuccin, like the rest of the desktop: Mocha in dark mode, Latte in
  -- light mode. The background is the terminal's own.
  {
    "catppuccin/nvim",
    name = "catppuccin",
    priority = 1000,
    config = function()
      require("catppuccin").setup({
        flavour = "auto",
        background = { light = "latte", dark = "mocha" },
        transparent_background = true,
        integrations = {
          blink_cmp = true, gitsigns = true, mini = { enabled = true },
          snacks = { enabled = true }, treesitter = true, which_key = true,
        },
      })
      vim.cmd.colorscheme("catppuccin")
    end,
  },

  -- Press a key and wait: a panel lists what can follow. Works for Space,
  -- g, z, ], [, marks, registers and more. <leader>? lists this buffer's keys.
  {
    "folke/which-key.nvim",
    event = "VeryLazy",
    opts = {
      preset = "modern",
      spec = {
        { "<leader>b", group = "buffers" },
        { "<leader>c", group = "code" },
        { "<leader>e", group = "explorer" },
        { "<leader>f", group = "find" },
        { "<leader>g", group = "git" },
        { "<leader>n", group = "notifications" },
        { "<leader>s", group = "splits" },
        { "<leader>t", group = "tabs" },
        { "<leader>w", group = "session", mode = "n" },
      },
    },
    keys = {
      { "<leader>?", function() require("which-key").show({ global = false }) end, desc = "Keys for this buffer" },
    },
  },

  -- Status line, buffer tabs and icons from one small library.
  {
    "nvim-mini/mini.nvim",
    version = false,
    config = function()
      require("mini.icons").setup()
      MiniIcons.mock_nvim_web_devicons()
      require("mini.statusline").setup()
      require("mini.tabline").setup()
      require("mini.pairs").setup()      -- closes brackets and quotes
      require("mini.surround").setup()   -- sa add, sd delete, sr replace
      require("mini.ai").setup()         -- more "inside" and "around" objects
    end,
  },
}
