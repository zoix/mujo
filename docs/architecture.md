# Architecture

karma is a desktop for Arch Linux on Hyprland. It has two layers with a strict
split: **the core decides, Quickshell presents.**

```
 Terminal / TTY / SSH      Floating TUIs            Quickshell UI
   karma <command>     launcher, menu, wifi    bar, OSD, notifications
          \                    |                  |        ^       :
           \                   |      karma --json|        | notify (IPC)
            v                  v                  v        |       :
          +---------------------------------------------------+    : read-only
          |                karma core (CLI)                   |    : state
          |            plan -> apply -> record                |    :
          |         --dry-run · --json · exit codes           |    :
          +---------------------------------------------------+    :
             | record           ^ build            | apply         :
             v                  |                  v               v
      Action journal       Design tokens       System services
      journal.jsonl        tokens.json         wpctl, nmcli, hyprctl
      karma log / undo     theme build -> apps bluetoothctl, systemd
```

## Rules

1. **One control plane.** Every change to the system is a `karma` subcommand.
   Quickshell and the TUIs never call `nmcli`, `wpctl`, `brightnessctl` or
   `hyprctl` to change anything; they run `karma <command> --json`.
2. **Reading is presentation.** Quickshell may read live state from its native
   services (Pipewire, UPower, Hyprland IPC, SystemTray, Notifications).
3. **Every action has a consequence.** Mutating commands run as
   *plan, apply, record*:
   - `--dry-run` prints the plan as a diff and changes nothing.
   - Applying appends an entry to `~/.local/state/karma/journal.jsonl` with the
     state before and after and an undo command.
   - `karma log` lists entries; `karma undo [id]` reverts one. Actions that
     cannot be undone say so and require `--yes`.
4. **Headless first.** Only commands that truly need Wayland check for it, and
   they exit with code 3. Everything else works over SSH or on a TTY.
5. **Stable output.** Human text by default; `--json` prints one object with a
   `schema_version` (see [cli.md](cli.md)). Exit codes: 0 ok, 1 failure,
   2 usage error, 3 unsupported environment.
6. **Push, don't poll.** After a change, karma notifies the UI with
   `qs -c karma ipc call <target> <function>`, best effort and never fatal.
   Quickshell's IPC targets (`osd`, `notify`, `theme`, `bar`) hold no logic.
7. **Tokens before widgets.** `design/tokens.json` is the only place a colour,
   size, font or duration is written. `karma theme build` renders it into every
   consumer; `karma theme check` fails on drift or hardcoded values
   (see [tokens.md](tokens.md)).

## Code layout

| Path | Role |
| --- | --- |
| `install.sh` | Installer: questions, plan, backups, stow, packages, `/etc`, services ([install.md](install.md)) |
| `bin/karma` | Entry point: opens fd 3, sources `lib/`, dispatches |
| `lib/core.sh` | Name, paths, global flags, output contract, errors, locking |
| `lib/config.sh` | `~/.config/karma/config.json` read and write |
| `lib/journal.sh` | Journal format, `karma log`, `karma undo` |
| `lib/ui.sh` | Best-effort reload hooks and Quickshell IPC |
| `lib/theme.sh` | `karma theme`: plan, build, check, settings, restore, lint |
| `lib/theme.jq` | Token resolver and template renderer (jq module) |
| `design/` | `tokens.json`, `consumers.json`, `templates/`, `check-allow.txt` |
| `config/` | Hand-written configs, one GNU Stow package per directory: `hypr`, `kitty`, `zsh`, `bin` |
| `system/` | Files for `/etc` that are not generated (the console palette unit); installed only by `install.sh` |
| `packages/` | `pacman.txt` (installed), `aur.txt` (empty), `replaced.txt` (offered for removal) |
| `tests/` | bats tests and `lint.sh` |

Each command module calls `karma_register NAME SUMMARY` and defines
`cmd_NAME` and `help_NAME`. Global flags (`--json`, `--dry-run`, `--yes`,
`--help`) are stripped from anywhere on the line before dispatch.

## Runtime paths

| Path | Contents |
| --- | --- |
| `~/.local/share/karma/` | The installed checkout, or a link to it (`git pull && karma theme build` updates) |
| `~/.local/state/karma/backups/<time>/` | What `install.sh` replaced, with `manifest.json` (for `karma uninstall`) |
| `~/.local/state/karma/install.log` | Full log of every install run |
| `~/.config/karma/config.json` | User settings: accent, reduce_motion, wallpaper, terminal, ... |
| `~/.local/state/karma/journal.jsonl` | Action journal |
| `~/.local/state/karma/snapshots/<id>/` | Files replaced by a journaled build, for undo |
| `~/.local/state/karma/theme/` | Resolved tokens, manifest, staged system files |

## Linking and generated files

Configs are linked with `stow --no-folding`, so directories in `~/.config` are
real and only files are symlinks. Stow resolves the checkout path, so the links
point at the real checkout directory; moving it means running `install.sh`
again from the new place. Two files are written once by the installer and then
belong to the user: `~/.config/hypr/host.lua` (monitors, keyboard, lid switch)
and `~/.config/zsh/local.zsh` (aliases, tool hooks). Generated theme files are written next to
those links as ordinary files and are never stored in the repo. Files for
`/etc` (greetd, the console palette) are rendered into
`~/.local/state/karma/theme/system/` and installed by the installer, which
shows every file it writes.

## Undo model

The journal is append-only. An entry's `undo` is a karma argv; `karma undo`
re-runs karma with it and `KARMA_UNDO_OF` set, so the undo is itself a journaled
entry with `undo_of`. `karma undo` without an id picks the newest entry that is
reversible, is not itself an undo, and has not been undone, so repeated calls
walk back through history. Undoing an undo entry by id re-applies the original
change.

`theme build` snapshots every file it replaces; its undo is
`karma theme restore <id>`, which puts those files back (and removes files the
build created). Restoring leaves the files out of step with `tokens.json` until
the next build, and `theme check` reports that as drift.
