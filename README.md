# karma

A terminal-first desktop for Arch Linux: Hyprland (Lua config), a Quickshell
interface and a `karma` CLI that owns every change to the system, with
dry runs, a journal and undo. Catppuccin Mocha, one accent.

**Status: phase 1 (installer and base session).** `install.sh` sets up
Hyprland with the karma look, kitty, a themed zsh, greetd with tuigreet and
the console palette. The control-plane commands arrive in phase 2 and the
Quickshell bar in phase 3.

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
karma theme accent            # show the accent and the 13 others
karma theme accent blue       # rebuild every app's colours; journaled
karma log                     # what changed
karma undo                    # put it back
karma theme reduce-motion on  # no animations anywhere
```

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
