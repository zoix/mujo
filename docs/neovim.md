# Neovim

The config is in `config/nvim/.config/nvim/` and is linked to `~/.config/nvim`.
Plugins are fetched by lazy.nvim on first start (`:Lazy` to see or update them).

The leader key is **Space**. Press it and wait: a panel lists what can follow.
The same works for `g`, `z`, `]`, `[` and others. `Space ?` lists the keys of
the current buffer; `Space f k` searches all keymaps; `Space f :` searches all
commands with their descriptions. Typing `:` lists matching commands as you type.

| Keys | Does |
| --- | --- |
| `Space Space` | Find anything (files, buffers, recent) |
| `Space f f` / `f r` / `f s` / `f c` | Find files / recent files / text in the project / the word under the cursor |
| `Space e e` / `e f` | File explorer / show the current file in it |
| `Space b x`, `Shift+H`, `Shift+L` | Close buffer, previous, next |
| `Space s v` / `s h` / `s x` / `s m` | Split vertically / horizontally / close split / maximize |
| `Ctrl+H/J/K/L` | Move between splits |
| `Space g g` | Lazygit; `g p`, `g a`, `g r`, `g b`: preview, stage, undo a change, blame |
| `Alt+I` | Terminal |
| `Space w r` / `w s` | Restore / save the session for this folder |
| `Space c f` / `c r` / `c a` / `c d` | Format / rename / code action / explain the problem |
| `gd`, `K`, `grr` | Definition, documentation, references (with a language server) |
| `jk` | Leave insert mode |
| `sa`, `sd`, `sr` | Add, delete, replace surrounding brackets or quotes |
| `gc` | Comment |

**Language servers** are used when installed; nothing is downloaded behind your
back. Install the ones you need with `mujo pkg install`, for example
`lua-language-server`, `gopls`, `typescript-language-server`, `pyright`,
`bash-language-server`. The same goes for formatters (`stylua`, `prettier`,
`shfmt`, `ruff`), which run on save.

**Syntax parsers** for more languages are compiled with `tree-sitter-cli`
(on mujo's package list). Without it only Lua, C, Markdown, Vim and help
files get tree-based highlighting.

The colours follow the desktop: Catppuccin Mocha in dark mode, Latte in light
mode (read when Neovim starts), on the terminal's own background.

## Plugins

| Plugin | For |
| --- | --- |
| lazy.nvim | Plugin manager |
| catppuccin | Colours |
| which-key | The panel that lists what a key can be followed by |
| snacks.nvim | Picker, file explorer, start screen, notifications, terminal, lazygit |
| mini.nvim | Status line, buffer tabs, icons, auto-pairs, surround, text objects |
| noice (with nui) | The command line as a box in the middle of the screen; messages as notifications |
| gitsigns | Changed lines in the margin |
| todo-comments | Highlights TODO and FIXME |
| persistence | Sessions per folder |
| nvim-treesitter | Syntax parsers |
| blink.cmp | Completion, also on the command line |
| nvim-lspconfig | How to start each language server |
| conform | Formatting on save |
