# tmux

`config/tmux` is mujo's tmux setup. The colours are not in it: they come
from `~/.config/tmux/mujo-theme.conf`, which `mujo theme build` generates
from the design tokens, so tmux follows the accent, the light or dark mode
and the wallpaper palette like everything else. A running tmux picks up a
theme change at once.

Your own settings go in `~/.config/tmux/local.conf`, which is loaded last
and never overwritten.

The prefix is `Ctrl+A`.

| Keys | Action |
|---|---|
| `prefix c` | New window, in the current pane's directory |
| `prefix %` / `prefix "` | Split side by side / one above the other |
| `Ctrl+H` `J` `K` `L` | Move between panes (inside Neovim the keys go to the editor) |
| `prefix Ctrl+L` | Clear the screen |
| `prefix g` / `prefix G` | lazygit in a new window / in a pop-up |
| `prefix Ctrl+E` | Jump to another session |
| `prefix Ctrl+F` | Jump to a window of this session |
| `prefix t` | Show or hide the status line |
| `prefix r` | Load `tmux.conf` again |

The status line is plain text on the terminal's own background, with a thin
rule above it to keep it apart from the program in the pane. On the
left are the session name in the accent colour (red while the prefix is
held, yellow in copy mode) and the windows with their flags (`*` current,
`-` last, `Z` zoomed), the current one bright and bold. On the right is the
pane title.

While the active pane runs Neovim, the status line is laid out to go with
Neovim's own: an empty row instead of the rule, then the session name and
the windows as `1:name*`, starting in the same column as Neovim's mode. On
the right are the pane title in quotes, the time and the date.

No plugin manager is used; pane movement that cooperates with Neovim is a
few lines in `tmux.conf`.
