# CLI reference

Every command has `--help` and `--json`; every command that changes something
has `--dry-run`.

| Command | Does | Needs |
| --- | --- | --- |
| `karma status` | One snapshot of everything below | nothing (missing parts are `null`) |
| `karma audio` | Volume, mute, default output and input | PipeWire (`wpctl`, `pw-dump`) |
| `karma net` | Wi-Fi status, scan, connect, forget, radio; `net tui` | NetworkManager (`nmcli`) |
| `karma bt` | Bluetooth status and power; `bt tui` opens bluetui | `bluetoothctl` |
| `karma display` | Brightness; night light | `brightnessctl`; Hyprland + `hyprsunset` |
| `karma theme` | Build, check, accent, reduce-motion | nothing |
| `karma wall` | Set or cycle the wallpaper | nothing |
| `karma dnd` | Do not disturb for notifications | nothing |
| `karma notify` | `open`: go to the app of the newest notification; `clear`: dismiss all | the interface |
| `karma power` | lock, suspend, logout, reboot, shutdown | `systemctl`; lock needs the UI |
| `karma shot` | Region, window or screen screenshot | Wayland (`grim`, `slurp`, `wl-copy`) |
| `karma clip` | Clipboard history picker; `clip list`, `clip clear` | `cliphist`; picking needs Wayland |
| `karma launch` | Application launcher; `launch list`, `launch run` | `fzf`; starting needs Wayland |
| `karma menu` | System menu over every command | `fzf` |
| `karma keys` | Keybinding cheat sheet; `keys tui` | Hyprland |
| `karma log` / `undo` | Action journal | nothing |
| `karma pkg` | Search, install and remove packages with fzf | `pacman`, `sudo`; `yay` or `paru` for the AUR |
| `karma sys` | Processor, memory, temperature, disk, uptime | nothing |
| `karma doctor` | Check packages, links, theme, services, session | nothing |
| `karma update` | Update karma (git) and the system (pacman), with a summary | `git`; `pacman` and `sudo` |
| `karma uninstall` | Remove karma's links and restore the backups | `sudo` for the `/etc` part |

A command whose "Needs" are missing exits with code 3 and says what is missing.

## Contract

**Global flags**, accepted anywhere on the line (`--` ends flag parsing):

| Flag | Effect |
| --- | --- |
| `--json` | Print exactly one JSON object on stdout |
| `--dry-run` | Print what would change (as a diff); change and record nothing |
| `--yes`, `-y` | Confirm an action that cannot be undone |
| `--window` | Open the command in a floating terminal; again closes it (needs Wayland) |
| `--help`, `-h` | Help for the command |

**Exit codes:** 0 ok, 1 failure, 2 usage error, 3 unsupported environment
(missing dependency, or a command that needs Wayland run without it).

**JSON envelope** (`schema_version` 1):

```json
{"schema_version": 1, "ok": true, "command": "theme accent", "dry_run": false, "data": { }}
{"schema_version": 1, "ok": false, "command": "theme accent", "error": {"code": 2, "message": "..."}}
```

Warnings go to stderr in both modes. Human error messages go to stderr.

## Journal entry

One per line in `~/.local/state/karma/journal.jsonl`:

```json
{
  "schema_version": 1,
  "id": "20261114T094622Z-3df5",
  "time": "2026-11-14T09:46:22Z",
  "command": ["theme", "accent", "blue"],
  "summary": "theme accent: mauve -> blue",
  "before": {"accent": "mauve"},
  "after": {"accent": "blue"},
  "undo": ["theme", "accent", "mauve"],
  "reversible": true,
  "undo_of": null
}
```

## State-changing commands

Volume, mute, device, brightness, night light, Wi-Fi, Bluetooth power and
wallpaper changes all run the same way and return the same `data`:

```json
{"journal_id": "20261114T163855Z-4662", "changed": true,
 "before": {"volume": 40}, "after": {"volume": 45}}
```

- Nothing to change: `changed` is `false`, `journal_id` is `null`, nothing is journaled.
- `--dry-run`: prints a diff of `before` and `after`, `journal_id` is `null`.
- Otherwise the change is applied and journaled, and `karma undo` reverts it.

Without a value the same subcommand only reports the current state.

## Interactive commands

`launch`, `menu`, `clip`, `wall pick`, `net tui`, `keys tui`, `bt tui` and `audio tui` need a terminal
(exit 3 without one) and have no `--json` form (exit 2). With `--window` they
open in a floating kitty window with the class `karma-tui-<command>`; running
the same command again closes that window, so one key toggles it. Four of
them have a panel in the Quickshell UI, which `--window` uses instead while
the UI runs: `launch`, `menu`, `wall pick`, `clip`, `keys tui`, `net tui`,
`power` (the power menu) and `sys` (the dashboard). `bt tui` and `audio tui`
are full terminal programs (bluetui, wiremix) and stay in a terminal. Each has a
non-interactive sibling for scripts: `launch list`, `menu list`, `clip list`,
`net scan`, `keys`, `bt`.

## karma status

`data`: `{audio, network, bluetooth, display, theme, wallpaper, battery, session}`.
Each of the first four has the shape of its own command's status below, or is
`null` when it cannot be read here. `theme` is `{accent, reduce_motion}`,
`wallpaper` a path or `null`, `battery` `{name, percent, status}` or `null`,
`session` `{wayland, hyprland, type}`.

## karma audio

| Subcommand | Mutates | Notes |
| --- | --- | --- |
| `status` (default) | no | Levels and devices |
| `volume [N\|+N\|-N] [--input] [--muted on\|off]` | yes | Percent, clamped to 0-100. Raising the volume unmutes; `--muted` sets mute in the same step |
| `mute [on\|off\|toggle] [--input]` | yes | Without a word: toggle |
| `output [ID\|NAME]`, `input [ID\|NAME]` | yes | Without an argument: list |
| `tui` | - | The wiremix mixer |

`--input` targets the default microphone. Status `data`:

```json
{"output": {"volume": 40, "muted": false, "device": "Speaker"},
 "input": {"volume": 100, "muted": false, "device": "Microphone"},
 "outputs": [{"id": 54, "name": "alsa_output...", "description": "Speaker", "default": true}],
 "inputs": []}
```

`volume` and `mute` without a value: `{"volume": 40, "muted": false}`.
`output`/`input` without an argument: `{"devices": [...]}`. State keys in
`before`/`after`: `volume` and `muted` (both, for a volume change), `device` (node name). Undo of a device
change uses the node name, which survives a restart; ids do not.

## karma display

| Subcommand | Mutates | Notes |
| --- | --- | --- |
| `status` (default) | no | `{brightness: {device, percent} \| null, night: {on, temperature} \| null}` |
| `brightness [N\|+N\|-N]` | yes | Percent, clamped to 1-100. Without a value: `{device, percent}` |
| `night [on\|off\|toggle] [--temp K]` | yes | 1000-10000 K, default 4000; needs Hyprland |

The night light is hyprsunset, started on first use. The temperature is kept
in `config.json` (`night_temperature`); whether it is on is not restored at
the next login.

## karma net

| Subcommand | Mutates | Notes |
| --- | --- | --- |
| `status` (default) | no | See below |
| `scan [--no-rescan]` | no | `{networks: [{ssid, signal, security, in_use, saved}]}`, one row per SSID |
| `connect SSID [--password-stdin]` | yes | Undo reconnects to the previous network (or disconnects) |
| `disconnect` | yes | Undo reconnects |
| `forget SSID` | yes | Needs `--yes`; not reversible |
| `wifi [on\|off\|toggle]` | yes | The radio. Without a word: `{wifi_enabled}` |
| `tui` | - | fzf picker |

Status `data`:

```json
{"wifi_enabled": true,
 "wifi": {"device": "wlan0", "ssid": "Home", "signal": 80, "ip4": "192.0.2.9/24"},
 "connectivity": "full",
 "connections": [{"device": "wlan0", "type": "wifi", "state": "connected", "connection": "Home"}]}
```

From the interface the result of `connect` is shown as a notification.
Passwords are never written to the journal. On a terminal `connect` lets
nmcli ask for the password; `--password-stdin` reads one line instead.

## karma bt

`status` (default): `{powered, adapter, name, devices: [{address, name, connected}]}`
(paired devices). `power [on|off|toggle]` mutates; without a word it returns
`{powered}`. `tui` opens bluetui.

## karma wall

| Subcommand | Mutates | Notes |
| --- | --- | --- |
| `status` (default) | no | `{wallpaper, directory, available}` |
| `list` | no | `{directory, current, images: [{path, name, thumb}]}`; `thumb` is `null` until indexed |
| `index` | no | Cache a thumbnail and the brightness and main colour of each image (`~/.cache/karma/wallpapers`) |
| `pick` | - | With `--window` in the desktop: the thumbnail strip of the UI, which applies as you move. In a terminal: an fzf list with a preview (in kitty) |
| `set FILE` | yes | png, jpg, jpeg or webp |
| `next`, `prev` | yes | Cycle through the directory by name |
| `clear` | yes | No wallpaper |
| `dir [DIRECTORY]` | yes | Default `~/Pictures/Wallpapers`. Without an argument: `{directory}` |
| `clock [on\|off\|toggle]` | yes | The clock on the desktop, with the bars that follow the music |

The choice is stored in `config.json` (`wallpaper`, `wallpaper_dir`) and sent
to the UI (`wallpaper set PATH`), which draws it on every screen.

While `theme mode` is `auto`, a wallpaper change also sets the mode from the
image's mean brightness (ImageMagick; 55% or more is light). That step has
its own journal entry, marked not reversible, so `karma undo` reverts the
wallpaper, and the mode follows it back.

## karma dnd

`dnd [on|off|toggle]` mutates `dnd` in `config.json`; without a word it
returns `{dnd}`. While it is on the UI shows only critical notifications.

## karma power

`power profile [NAME]` shows or sets the power profile (`power-saver`,
`balanced`, `performance`; needs power-profiles-daemon); `power awake
[on|off|toggle]` keeps the session from locking by itself by stopping the idle
daemon. Both are journaled and can be undone.

`power` or `power list`: `{actions: [...]}`. `lock`, `suspend`, `logout`,
`reboot`, `shutdown` return `{journal_id, action, command}`; with `--dry-run`
nothing runs and `journal_id` is `null`. `logout`, `reboot` and `shutdown`
need `--yes` (exit 2 without it). Entries are journaled as not reversible.
`lock` calls the Quickshell lock screen and exits 3 while the UI is not running.

## karma shot

`shot [region|window|screen] [--no-save] [--no-copy] [--dir DIR]`, and for
`region` also `--geometry "X,Y WxH"` (take exactly that area) or `--slurp`.
With the interface running, `region` opens its area picker and returns at
once with `picking: true`; the picker then runs the command again with
`--geometry`.
`data`: `{mode, path, copied, geometry}`. Saves to `~/Pictures/Screenshots`
(`screenshot_dir` in `config.json`) and copies to the clipboard. Not journaled.

## karma clip

`pick` (default, interactive), `list [--limit N]`: `{entries: [{id, preview}]}`,
`copy ID`: put that entry back on the clipboard (`{id, copied}`; needs Wayland),
`clear` (needs `--yes`, not reversible).

## karma launch

`pick` (default, interactive), `list`:
`{apps: [{id, name, comment, exec, terminal, file, launches}]}`, most used
first. `run ID`: `{id, name, exec, terminal, started}`; `--dry-run` prints the
command. Launch counts live in `~/.local/state/karma/launch-history.tsv`.

## karma menu

`pick` (default, interactive), `list`: `{entries: [{label, kind, command}]}`,
`run LABEL`: do what that entry does without a terminal (`{label, kind, command, done}`);
a setting's result is shown as a notification. The UI's launcher uses it.
`kind` is `run`, `tui`, `app`, `shot`, `accent` or `confirm`.

## karma keys

`list` (default): `{binds: [{keys, description, mods, key, locked, repeat, mouse}]}`.
`tui`: search with fzf.

## karma pkg

| Subcommand | Mutates | Notes |
| --- | --- | --- |
| `install` (default) | yes | fzf over every package of the official repositories and, with `yay` or `paru`, the AUR. Tab marks several, Enter installs: `sudo pacman -S --needed` for official ones, the helper for AUR ones. A star marks installed packages |
| `remove` | yes | fzf over the packages you installed explicitly; Enter runs `sudo pacman -Rns`, which lists everything and asks |
| `list [--aur]` | no | `{packages: [{name, source, installed}]}`; `source` is `repo` or `aur` |

The pickers need a terminal (`--window` opens one) and have no `--json`.
Installs and removals are journaled as not reversible.

## karma sys

Read-only. `data`:

```json
{"cpu": {"total": 16560151, "idle": 16287148, "cores": 24},
 "memory": {"total_kb": 131156640, "available_kb": 127231148, "percent": 3},
 "temperature_c": 53, "disk": {"total_kb": 975694848, "used_kb": 15857984, "percent": 2},
 "uptime_s": 6896}
```

`cpu.total` and `cpu.idle` are counters since boot; the load between two
readings is `1 - Δidle / Δtotal`. `sys workspaces` lists the Hyprland
workspaces with their windows (`{workspaces: [{id, name, monitor, windows}]}`). The human output takes two readings itself.
`temperature_c` is `null` without a sensor. `sys --window` opens the dashboard.

## karma doctor

Read-only. `data`:

```json
{"ok": false, "failed": 1, "warnings": 1,
 "checks": [{"group": "links", "status": "fail",
             "message": "3 of 43 config file(s) are not linked: ...",
             "fix": "~/karma/install.sh --skip-system"}]}
```

`group` is `packages`, `links`, `theme`, `settings`, `services` or `session`;
`status` is `ok`, `warn`, `fail` or `skip` (session checks outside the
graphical session). Exit code 1 if any check failed; warnings do not fail.

## karma update

`update [--karma-only | --system-only]`. Pulls the checkout
(`git pull --ff-only`; skipped without an upstream branch), relinks the config
and rebuilds the theme if commits arrived, then runs `sudo pacman -Syu` and,
if `yay` or `paru` is installed, `yay -Sua` for AUR packages. In a
terminal they ask before installing; `--yes` passes `--noconfirm` and is
required without a terminal (exit 2 otherwise). `--dry-run` lists pending
packages and unmerged commits; only the AUR is asked over the network. `data`:

```json
{"journal_id": "...", "karma": {"state": "updated", "commits": 3},
 "system": {"packages": ["linux", "jq"]}, "reboot_recommended": true}
```

`karma.state` is `updated`, `current`, `no-upstream`, `failed`, `skipped`, or
`pending` (dry run). In `--json` mode pacman's own output goes to stderr.
Journaled as not reversible.

## karma uninstall

`uninstall [--skip-system]`, needs `--yes`; `--dry-run` prints the plan.
Removes the links from `config/`, moves what karma generated or wrote to
`~/.local/state/karma/uninstalled/<time>/`, restores the backups (files,
restowed and refolded dotfile packages) and, with sudo, the `/etc` files, the
previous login screen and locale. Packages are not removed. `data`:
`{journal_id, moved_to, steps: [...], notes: [...]}`; `notes` lists what could
not be restored. See [install.md](install.md).

## UI notifications

After a change karma calls the Quickshell IPC (`qs -c karma ipc call ...`),
best effort and never fatal. `qs -c karma ipc show` lists the targets:

| Target | Function | Called by |
| --- | --- | --- |
| `osd` | `volume PERCENT MUTED`, `microphone PERCENT MUTED`, `brightness PERCENT` | `karma audio`, `karma display` |
| `wallpaper` | `set PATH` | `karma wall` |
| `notify` | `reload` (re-read `config.json`), `clear` (dismiss all cards), `open` (go to the newest one's app) | `karma dnd`, `karma notify` |
| `theme` | `reload` (re-read the colours; the UI is not restarted) | `karma theme` |
| `lock` | `lock` | `karma power lock` |
| `launcher` | `apps`, `actions`, `wallpapers`, `clipboard`, `keys`, `wifi` (each toggles that mode), `close` | `--window` on `launch`, `menu`, `wall pick` |
| `session` | `toggle` (the power menu) | `karma power --window` |
| `dashboard` | `toggle`, `workspaces` (the page of workspace miniatures) | `karma sys --window`, `karma sys workspaces --window` |
| `sidebar` | `toggle` (quick settings) | `karma status --window` |
| `picker` | `open`, `close` (the screenshot area picker) | `karma shot region` |
| `bar` | `toggle` (hide or show the frame and bar) | by hand |

## karma theme

| Subcommand | Mutates | Notes |
| --- | --- | --- |
| `build [ID...]` | yes | Render all or the given consumers. Journaled; undo restores the previous files |
| `check [ID...]` | no | Exit 1 on drift or hardcoded values |
| `accent [NAME\|auto]` | yes | Without NAME: show. With NAME: set in config.json, rebuild, journal. `auto` (the default) picks the accent closest to the wallpaper's main colour |
| `palette [catppuccin\|wallpaper]` | yes | `wallpaper` tints backgrounds, borders and text with the wallpaper's main colour and makes the accent a colour of that hue (when the accent is `auto`); red, green and the other named colours stay. A wallpaper without a clear colour keeps the Catppuccin colours. Without a word: `{palette, hue, available}` |
| `mode [dark\|light\|auto]` | yes | Dark (Catppuccin Mocha) or light (Latte) palette for every app. `auto` (the default) follows the wallpaper: light when the image is bright. Without a word: `{mode, preference, available}` |
| `motion [normal\|gentle]` | yes | `gentle` makes every animation about twice as slow and has Hyprland fade instead of slide. Without a word: `{motion, reduce_motion, available}` |
| `glass [on\|off]` | yes | `on` makes the frame and its panels see-through, with the desktop blurred behind them |
| `reduce-motion [on\|off]` | yes | `on` switches every animation off |
| `list` | no | Consumers, paths and status |
| `show [PATH]` | no | Resolved tokens, or one subtree (`color.bg`, `term.ansi.5`) |
| `render FILE` | no | Render a template to stdout, no header |
| `restore SNAPSHOT` | yes | Put back files saved by a journaled build; used by `undo` |

`data` for `build`, `accent`, `reduce-motion` and `restore`:

```json
{
  "journal_id": "20261114T094622Z-3df5",
  "settings": {"accent": "blue", "reduce_motion": false},
  "files": [
    {"id": "kitty", "scope": "user", "path": "/home/u/.config/kitty/karma-theme.conf",
     "status": "changed", "diff": "--- ... (only with --dry-run)"}
  ]
}
```

`status` is one of `new`, `changed`, `unchanged` or `remove` (restore only).
`journal_id` is `null` for a dry run or a no-op. `accent` and `reduce-motion`
without an argument return `{"accent": "mauve", "available": [...]}` and
`{"reduce_motion": false}`.

`data` for `check`:

```json
{
  "ok": false,
  "problems": [
    {"kind": "drift", "consumer": "kitty", "path": "...", "message": "...", "diff": "..."},
    {"kind": "hardcoded", "file": "config/kitty/kitty.conf", "line": 1, "rule": "hex-colour", "text": "..."}
  ],
  "notes": [{"consumer": "greetd", "path": "/etc/greetd/config.toml", "message": "..."}]
}
```

`data` for `list`: `{"consumers": [{id, scope, path, status}]}`.
`data` for `show`: `{"path": "color.bg", "value": {...}}`.
`data` for `render`: `{"output": "..."}`.

## karma log

`karma log [--limit N]`, newest first (default 20).
`data`: `{"entries": [<journal entry> + {"undone_by": id | null}]}`.

## karma undo

`karma undo [ID]` with `--dry-run` and `--json` passed through. ID may be a
unique prefix. Output is the output of the undo command it runs (for example
`theme accent`). Errors: no matching entry, ambiguous prefix (exit 2), entry
not reversible, entry already undone (exit 1).

## karma version

`data`: `{"version": "0.1.0"}`.
