# karma

A terminal-first desktop for Arch Linux: Hyprland (Lua config), a Quickshell
interface and a `karma` CLI that owns every change to the system, with
dry runs, a journal and undo. Catppuccin Mocha (dark) or Latte (light), chosen from the wallpaper; one accent.
Optionally the whole palette is tinted with the wallpaper's colour.

**Status: phase 4 (complete).** `install.sh` sets up Hyprland with the karma
look, kitty and Ghostty, a themed zsh, greetd with tuigreet and the console
palette. The `karma` CLI controls audio, Wi-Fi, Bluetooth, brightness, night
light, wallpaper, theme, power, screenshots and the clipboard, and every
change can be previewed, is journaled and can be undone. The Quickshell
interface draws a frame around the screen with a bar on the left; the
launcher, the power menu, notifications and the volume display grow out of
that frame. Light or dark and the accent colour follow the wallpaper.

## Install

```sh
./install.sh --dry-run    # see everything it would do; changes nothing
./install.sh              # a few questions, the plan, one confirmation
```

Then reboot: greetd starts on tty1 and logs you into Hyprland.
Existing configs are backed up to `~/.local/state/karma/backups/` first.
Details, flags and what happens to an existing `hyprland.conf`:
[docs/install.md](docs/install.md).

## Use

| Keys | Opens |
| --- | --- |
| `SUPER + Space` | Launcher; type `>` for every karma command |
| `SUPER + Shift + W` | Wallpaper strip; moving along it applies the image |
| `SUPER + Shift + Escape` | Power menu |
| `SUPER + Escape` | Lock |
| `SUPER + /` | All keybindings |

Everything is also a command, and works over SSH or on a TTY except what
needs the screen:

```sh
karma status                  # audio, network, display, theme, battery
karma audio volume +5         # every change is journaled...
karma undo                    # ...and can be put back
karma log                     # what changed
karma net tui                 # pick a Wi-Fi network
karma theme mode light        # or dark, or auto (follow the wallpaper)
karma theme accent blue       # or auto
karma power reboot --dry-run  # see what an action would do
karma doctor                  # is everything in place?
karma update                  # karma and the system
```

Put your wallpapers in `~/Pictures/Wallpapers`. All keys:
[docs/keybinds.md](docs/keybinds.md). All commands: [docs/cli.md](docs/cli.md).

## Remove

```sh
karma uninstall --dry-run     # shows the plan
karma uninstall --yes         # restores what install.sh backed up
```

## Develop

```sh
tests/lint.sh    # shellcheck, bats, theme check, Lua and zsh syntax, qmllint
```

To try the theme engine without touching your config:

```sh
export XDG_CONFIG_HOME=$(mktemp -d) XDG_STATE_HOME=$(mktemp -d)
bin/karma theme build && bin/karma theme check
```

## Docs

- [Architecture](docs/architecture.md)
- [Installing](docs/install.md)
- [Keybindings](docs/keybinds.md)
- [Design tokens and templates](docs/tokens.md)
- [CLI reference](docs/cli.md)
