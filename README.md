# karma

A terminal-first desktop for Arch Linux: Hyprland (Lua config), a Quickshell
interface and a `karma` CLI that owns every change to the system, with
dry runs, a journal and undo. Catppuccin Mocha (dark) or Latte (light), chosen from the wallpaper; one accent.

**Status: phase 3 (the interface).** `install.sh` sets up Hyprland with the
karma look, kitty, a themed zsh, greetd with tuigreet and the console
palette. The `karma` CLI controls audio, Wi-Fi, Bluetooth, brightness, night
light, wallpaper, power, screenshots and the clipboard, with fzf TUIs for the
launcher, the system menu, Wi-Fi and the keybindings. The Quickshell interface
draws the frame, the bar, notifications, the volume and brightness display,
the wallpaper and the lock screen. Phase 4 adds `karma doctor`, `update` and
`uninstall`.

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

```sh
karma status                  # audio, network, display, theme, battery
karma audio volume +5         # every change is journaled...
karma undo                    # ...and can be put back
karma log                     # what changed
karma net tui                 # pick a Wi-Fi network
karma theme accent blue       # rebuild every app's colours
karma display night on        # night light
karma power reboot --dry-run  # see what an action would do
```

`SUPER + Space` opens the launcher, `SUPER + X` the system menu.
Everything works over SSH or on a TTY except what needs the screen.

Keys: [docs/keybinds.md](docs/keybinds.md).

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
