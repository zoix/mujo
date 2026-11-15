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

  -- The command line (":" and "/") opens as a small box in the middle of the
  -- screen instead of a row at the bottom, and messages become notifications.
  -- Hover and signature help stay as Neovim draws them.
  {
    "folke/noice.nvim",
    event = "VeryLazy",
    dependencies = { "MunifTanjim/nui.nvim" },
    opts = {
      cmdline = { view = "cmdline_popup" },
      lsp = {
        progress = { enabled = false },
        hover = { enabled = false },
        signature = { enabled = false },
      },
      presets = { long_message_to_split = true },
    },
  },

  -- Status line, buffer tabs and icons from one small library.
  {
    "nvim-mini/mini.nvim",
    version = false,
    config = function()
      require("mini.icons").setup()
      MiniIcons.mock_nvim_web_devicons()
      -- The status line. Left: the mode, the git branch, then the lines
      -- added, changed and removed, each with its icon and colour. Right:
      -- problems, the language servers, the indent width, the file type,
      -- the cursor position, and how far down the file it is. The file
      -- name is in the buffer tabs at the top.
      local statusline = require("mini.statusline")
      local diff_parts = {
        { "added", "MujoStatusAdded", "\u{f457}", { "GitSignsAdd", "Added" } },
        { "changed", "MujoStatusChanged", "\u{f459}", { "GitSignsChange", "Changed" } },
        { "removed", "MujoStatusRemoved", "\u{f458}", { "GitSignsDelete", "Removed" } },
      }
      -- The middle of the status line is a soft band one step above the
      -- background (the colour of the colour column), not the near-black
      -- the theme gives it. The git counts take the colours of the git
      -- signs, on that band.
      local function statusline_highlights()
        local bg = vim.api.nvim_get_hl(0, { name = "ColorColumn", link = false }).bg
        for _, name in ipairs({ "MiniStatuslineFilename", "MiniStatuslineInactive", "StatusLine", "StatusLineNC" }) do
          local hl = vim.api.nvim_get_hl(0, { name = name, link = false })
          hl.bg = bg
          vim.api.nvim_set_hl(0, name, hl)
        end
        for _, part in ipairs(diff_parts) do
          local fg
          for _, from in ipairs(part[4]) do
            fg = fg or vim.api.nvim_get_hl(0, { name = from, link = false }).fg
          end
          vim.api.nvim_set_hl(0, part[2], { fg = fg, bg = bg })
        end
      end
      statusline_highlights()
      vim.api.nvim_create_autocmd("ColorScheme", { callback = statusline_highlights })
      local function section_diff()
        local counts = vim.b.gitsigns_status_dict or {}
        local out = {}
        for _, part in ipairs(diff_parts) do
          local n = counts[part[1]] or 0
          if n > 0 then out[#out + 1] = "%#" .. part[2] .. "#" .. part[3] .. " " .. n end
        end
        return table.concat(out, " ")
      end
      statusline.setup({
        content = {
          active = function()
            local mode, mode_hl = statusline.section_mode({ trunc_width = 60 })
            local git = statusline.section_git({ trunc_width = 40 })
            local wide = not statusline.is_truncated(60)
            local diagnostics = statusline.section_diagnostics({ trunc_width = 75 })
            local servers = vim.tbl_map(function(client) return client.name end,
              vim.lsp.get_clients({ bufnr = 0 }))
            local lsp = wide and #servers > 0 and "[" .. table.concat(servers, " ") .. "]" or ""
            local indent = wide and "\u{f0312} " .. (vim.bo.expandtab and vim.fn.shiftwidth() or vim.bo.tabstop) or ""
            local filetype = vim.bo.filetype
            if filetype ~= "" then filetype = MiniIcons.get("filetype", filetype) .. " " .. filetype end
            local search = statusline.section_searchcount({ trunc_width = 75 })
            return statusline.combine_groups({
              { hl = mode_hl, strings = { mode:upper() } },
              { hl = "MiniStatuslineDevinfo", strings = { git } },
              "%<",
              { hl = "MiniStatuslineFilename", strings = { wide and section_diff() or "" } },
              "%=",
              { hl = "MiniStatuslineFilename", strings = { diagnostics, lsp, indent, filetype } },
              { hl = "MiniStatuslineFileinfo", strings = { search, "%l:%v" } },
              { hl = mode_hl, strings = { "%p%%/%L" } },
            })
          end,
        },
      })
      require("mini.tabline").setup()
      require("mini.pairs").setup()      -- closes brackets and quotes
      require("mini.surround").setup()   -- sa add, sd delete, sr replace
      require("mini.ai").setup()         -- more "inside" and "around" objects
    end,
  },
}
