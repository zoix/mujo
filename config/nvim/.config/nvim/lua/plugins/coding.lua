-- Syntax, completion, language servers, formatting.
return {
  -- Syntax trees: better highlighting, folding and text objects. Parsers
  -- are compiled with the tree-sitter command; without it Neovim's built-in
  -- ones (Lua, C, Markdown, Vim, help) still work.
  {
    "nvim-treesitter/nvim-treesitter",
    branch = "main",
    lazy = false,
    build = ":TSUpdate",
    config = function()
      if vim.fn.executable("tree-sitter") == 1 then
        require("nvim-treesitter").install({
          "bash", "c", "css", "dockerfile", "gitignore", "go", "html", "javascript", "json",
          "lua", "markdown", "markdown_inline", "python", "qmljs", "query", "toml", "tsx",
          "typescript", "vim", "vimdoc", "yaml",
        })
      end
      vim.api.nvim_create_autocmd("FileType", {
        callback = function(event)
          -- Starts highlighting if a parser for this file type exists.
          pcall(vim.treesitter.start, event.buf)
        end,
      })
    end,
  },

  -- Completion while typing, in buffers and on the command line: type ":"
  -- and the matching commands are listed.
  {
    "saghen/blink.cmp",
    version = "1.*",
    event = { "InsertEnter", "CmdlineEnter" },
    dependencies = { "rafamadriz/friendly-snippets" },
    opts = {
      keymap = {
        preset = "enter",
        ["<Tab>"] = { "select_next", "snippet_forward", "fallback" },
        ["<S-Tab>"] = { "select_prev", "snippet_backward", "fallback" },
      },
      completion = {
        documentation = { auto_show = true, auto_show_delay_ms = 300 },
        list = { selection = { preselect = false } },
      },
      cmdline = {
        keymap = { preset = "cmdline" },
        completion = { menu = { auto_show = true } },
      },
      sources = { default = { "lsp", "path", "snippets", "buffer" } },
      signature = { enabled = true },
    },
  },

  -- Language servers. Neovim talks to them itself; this plugin only knows
  -- how to start each one. A server is used if its program is installed
  -- (for example: karma pkg install, then lua-language-server or gopls).
  {
    "neovim/nvim-lspconfig",
    event = { "BufReadPre", "BufNewFile" },
    config = function()
      local servers = {
        lua_ls = "lua-language-server",
        gopls = "gopls",
        ts_ls = "typescript-language-server",
        pyright = "pyright-langserver",
        bashls = "bash-language-server",
        rust_analyzer = "rust-analyzer",
        clangd = "clangd",
        qmlls = "qmlls6",
      }
      for name, program in pairs(servers) do
        if vim.fn.executable(program) == 1 then
          vim.lsp.enable(name)
        end
      end

      vim.diagnostic.config({ virtual_text = { spacing = 2 }, severity_sort = true, float = { border = "rounded" } })

      -- Neovim's own keys: K docs, grn rename, gra code action, grr
      -- references, gri implementation, gO symbols. Plus a few on the leader.
      vim.api.nvim_create_autocmd("LspAttach", {
        callback = function(event)
          local function map(keys, action, desc)
            vim.keymap.set("n", keys, action, { buffer = event.buf, desc = desc })
          end
          map("gd", function() Snacks.picker.lsp_definitions() end, "Go to definition")
          map("<leader>cr", vim.lsp.buf.rename, "Rename")
          map("<leader>ca", vim.lsp.buf.code_action, "Code action")
          map("<leader>cd", vim.diagnostic.open_float, "Explain the problem here")
          map("<leader>cs", function() Snacks.picker.lsp_symbols() end, "Symbols in this file")
          map("<leader>cx", function() Snacks.picker.diagnostics_buffer() end, "Problems in this file")
        end,
      })
    end,
  },

  -- Formatting on save, with whichever formatter is installed; otherwise
  -- the language server's own. <leader>cf formats now.
  {
    "stevearc/conform.nvim",
    event = "BufWritePre",
    cmd = "ConformInfo",
    opts = {
      formatters_by_ft = {
        lua = { "stylua" },
        go = { "gofmt" },
        sh = { "shfmt" },
        python = { "ruff_format" },
        javascript = { "prettier" }, typescript = { "prettier" },
        json = { "prettier" }, yaml = { "prettier" }, markdown = { "prettier" },
        css = { "prettier" }, html = { "prettier" },
      },
      format_on_save = { timeout_ms = 1000, lsp_format = "fallback" },
    },
    keys = {
      { "<leader>cf", function() require("conform").format({ lsp_format = "fallback" }) end, desc = "Format this file" },
    },
  },
}
