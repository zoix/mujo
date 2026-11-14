# CLI reference

Every command has `--help` and `--json`; every command that changes something
has `--dry-run`. `karma doctor`, `karma update` and `karma uninstall` arrive in
phase 4.

| Command | Does | Needs |
| --- | --- | --- |
| `karma status` | One snapshot of everything below | nothing (missing parts are `null`) |
| `karma audio` | Volume, mute, default output and input | PipeWire (`wpctl`, `pw-dump`) |
| `karma net` | Wi-Fi status, scan, connect, forget, radio; `net tui` | NetworkManager (`nmcli`) |
| `karma bt` | Bluetooth status and power; `bt tui` opens bluetui | `bluetoothctl` |
| `karma display` | Brightness; night light | `brightnessctl`; Hyprland + `hyprsunset` |
| `karma theme` | Build, check, accent, reduce-motion | nothing |
| `karma wall` | Set or cycle the wallpaper | nothing |
| `karma power` | lock, suspend, logout, reboot, shutdown | `systemctl`; lock needs the UI |
| `karma shot` | Region, window or screen screenshot | Wayland (`grim`, `slurp`, `wl-copy`) |
| `karma clip` | Clipboard history picker; `clip list`, `clip clear` | `cliphist`; picking needs Wayland |
| `karma launch` | Application launcher; `launch list`, `launch run` | `fzf`; starting needs Wayland |
| `karma menu` | System menu over every command | `fzf` |
| `karma keys` | Keybinding cheat sheet; `keys tui` | Hyprland |
| `karma log` / `undo` | Action journal | nothing |

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

`launch`, `menu`, `clip`, `net tui`, `keys tui` and `bt tui` need a terminal
(exit 3 without one) and have no `--json` form (exit 2). With `--window` they
open in a floating kitty window with the class `karma-tui-<command>`; running
the same command again closes that window, so one key toggles it. Each has a
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
| `volume [N\|+N\|-N] [--input]` | yes | Percent, clamped to 0-100 |
| `mute [on\|off\|toggle] [--input]` | yes | Without a word: toggle |
| `output [ID\|NAME]`, `input [ID\|NAME]` | yes | Without an argument: list |

`--input` targets the default microphone. Status `data`:

```json
{"output": {"volume": 40, "muted": false, "device": "Speaker"},
 "input": {"volume": 100, "muted": false, "device": "Microphone"},
 "outputs": [{"id": 54, "name": "alsa_output...", "description": "Speaker", "default": true}],
 "inputs": []}
```

`volume` and `mute` without a value: `{"volume": 40, "muted": false}`.
`output`/`input` without an argument: `{"devices": [...]}`. State keys in
`before`/`after`: `volume`, `muted`, `device` (node name). Undo of a device
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
| `set FILE` | yes | png, jpg, jpeg or webp |
| `next`, `prev` | yes | Cycle through the directory by name |
| `clear` | yes | No wallpaper |
| `dir [DIRECTORY]` | yes | Default `~/Pictures/Wallpapers`. Without an argument: `{directory}` |

The choice is stored in `config.json` (`wallpaper`, `wallpaper_dir`) and sent
to the UI (`wallpaper set PATH`). The Quickshell UI of phase 3 draws it.

## karma power

`power` or `power list`: `{actions: [...]}`. `lock`, `suspend`, `logout`,
`reboot`, `shutdown` return `{journal_id, action, command}`; with `--dry-run`
nothing runs and `journal_id` is `null`. `logout`, `reboot` and `shutdown`
need `--yes` (exit 2 without it). Entries are journaled as not reversible.
`lock` calls the Quickshell lock screen and exits 3 while that is not running.

## karma shot

`shot [region|window|screen] [--no-save] [--no-copy] [--dir DIR]`.
`data`: `{mode, path, copied, geometry}`. Saves to `~/Pictures/Screenshots`
(`screenshot_dir` in `config.json`) and copies to the clipboard. Not journaled.

## karma clip

`pick` (default, interactive), `list [--limit N]`: `{entries: [{id, preview}]}`,
`clear` (needs `--yes`, not reversible).

## karma launch

`pick` (default, interactive), `list`:
`{apps: [{id, name, comment, exec, terminal, file, launches}]}`, most used
first. `run ID`: `{id, name, exec, terminal, started}`; `--dry-run` prints the
command. Launch counts live in `~/.local/state/karma/launch-history.tsv`.

## karma menu

`pick` (default, interactive), `list`: `{entries: [{label, kind, command}]}`.
`kind` is `run`, `tui`, `app`, `shot`, `accent` or `confirm`.

## karma keys

`list` (default): `{binds: [{keys, description, mods, key, locked, repeat, mouse}]}`.
`tui`: search with fzf.

## UI notifications

After a change karma calls the Quickshell IPC, best effort:
`osd volume PERCENT MUTED`, `osd microphone PERCENT MUTED`,
`osd brightness PERCENT`, `wallpaper set PATH`, `theme reload`, and
`lock lock` for `power lock`. These targets are implemented in phase 3.

## karma theme

| Subcommand | Mutates | Notes |
| --- | --- | --- |
| `build [ID...]` | yes | Render all or the given consumers. Journaled; undo restores the previous files |
| `check [ID...]` | no | Exit 1 on drift or hardcoded values |
| `accent [NAME]` | yes | Without NAME: show. With NAME: set in config.json, rebuild, journal |
| `reduce-motion [on\|off]` | yes | Same pattern for `reduce_motion` |
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
