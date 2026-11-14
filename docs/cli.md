# CLI reference

Phase 0 ships `theme`, `log`, `undo`, `version` and `help`. The remaining
commands arrive in phase 2 and follow the same contract.

## Contract

**Global flags**, accepted anywhere on the line (`--` ends flag parsing):

| Flag | Effect |
| --- | --- |
| `--json` | Print exactly one JSON object on stdout |
| `--dry-run` | Print what would change (as a diff); change and record nothing |
| `--yes`, `-y` | Confirm an action that cannot be undone |
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
