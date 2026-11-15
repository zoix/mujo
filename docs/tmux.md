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

The status line shows the session name (red while the prefix is held), the
windows, the host name and the time.

No plugin manager is used; pane movement that cooperates with Neovim is a
few lines in `tmux.conf`.
