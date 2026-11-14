# Design tokens

`design/tokens.json` is the only place a colour, size, font or duration is
written. Everything else reads roles from it through generated files.

## Schema (version 1)

| Key | Contents |
| --- | --- |
| `schema_version` | `1` |
| `defaults` | `accent` (one of `accents`), `reduce_motion` (bool). Overridden by `~/.config/karma/config.json` |
| `palette` | The 26 Catppuccin Mocha colours, lowercase `#rrggbb`. The only place raw names appear |
| `accents` | The 14 names allowed as accent |
| `color` | Roles: `bg.{frame,base,raised,control}`, `border.subtle`, `text.{primary,muted,on_accent}`, `accent`, `state.{success,warning,error,info}` |
| `term` | Terminal `fg`, `bg`, `cursor`, `selection_bg` and 16 `ansi` colours (Catppuccin's mapping) |
| `console` | Linux console palette (`ansi`, background slot 0 is `base`, magenta slots are the accent) and `slot` names used by tuigreet |
| `font` | `family`, `terminal_pt` (kitty), `ui_pt` (GTK), `size.{xs,sm,md,lg,xl,display}` px, `weight.{regular,emphasis,heavy}` |
| `space` | `xs` 4, `sm` 8, `md` 12, `lg` 16, `xl` 24, `xxl` 32 |
| `radius` | `sm` 6, `md` 10, `lg` 14, `xl` 18, `full` |
| `border` | `thin` 1, `focus` 2 |
| `layout` | `frame`, `bar`, `gap_in`, `gap_out`, `osd_width` |
| `motion` | `duration.{fast,normal,slow}` ms; `ease.{standard,enter,exit}` as `[x1, y1, x2, y2]` |

Elevation is not a token: depth comes from the `bg.*` steps, never shadows or blur.

### References

A string value of the form `"{path}"` refers to another token, e.g.
`"frame": "{palette.crust}"`. Array items are addressed by index
(`{term.ansi.5}`). `{accent}` is reserved: it resolves to
`palette[settings.accent]`.

Resolution (`lib/theme.jq`, `resolve`) runs up to 8 passes and fails on an
unresolved reference, a cycle, an unknown accent or a palette value that is
not lowercase `#rrggbb`. With `reduce_motion` on, every `motion.duration` is 0.
The result, plus a `settings` object, is what templates see; `karma theme show`
prints it.

## Templates

Templates live in `design/templates/` and contain placeholders:

```
{{ path }}
{{ path | filter }}
{{ path | filter(0.8) }}
```

The spaces inside the braces are required. Only text that matches this exact
form is replaced, so a literal `{{` in Lua or QML is left alone. A placeholder
that is almost right (`{{path}}`, `{{ a |b }}`) is an error, as is an unknown
token or filter. There are no loops or conditionals.

Without a filter, strings print as-is, numbers and booleans as text, and arrays
joined with `,`.

| Filter | Input | Output for mauve / 220 / ease.standard |
| --- | --- | --- |
| `hex` | colour | `#cba6f7` |
| `bare` | colour | `cba6f7` |
| `rgb` | colour | `203, 166, 247` |
| `r`, `g`, `b` | colour | `203` |
| `hexa(a)` | colour | `#cba6f7cc` for `a = 0.8` |
| `qml_a(a)` | colour | `#cccba6f7` (QML is `#AARRGGBB`) |
| `hypr` | colour | `rgb(cba6f7)` |
| `hypra(a)` | colour | `rgba(cba6f7cc)` |
| `ms` / `s` / `ds` | number | `220` / `0.22` / `2.2` (Hyprland speed unit) |
| `px` | number | `220px` |
| `q` | any | JSON-quoted, safe in Lua, QML and TOML |
| `csv` | list | `0.2, 0, 0, 1` |
| `qml_curve` | curve | `[0.2, 0, 0, 1, 1, 1]` for `Easing.BezierSpline` |
| `lua_points` | curve | `{ {0.2, 0}, {0, 1} }` for `hl.curve` |

A colour or number filter applied to a list maps over it and joins with `,`;
`{{ console.ansi | r }}` gives the 16 values one `setvtrgb` line needs.

`karma theme render FILE` renders any template with the current tokens, for
trying things out.

## Consumers

`design/consumers.json` lists every generated file:

| Field | Meaning |
| --- | --- |
| `id` | Name used by `karma theme build ID` / `check ID` |
| `template` | Path under `design/templates/` |
| `target` | `@config/...` (XDG config), `@state/...`, or `/etc/...` |
| `scope` | `user` (written directly) or `system` (staged in `~/.local/state/karma/theme/system/`, installed by the installer) |
| `comment`, `comment_end` | Comment syntax for the "do not edit" header; empty for formats without comments |
| `reload` | Optional hook run after a change: `quickshell`, `hyprland`, `kitty` |
| `lint` | Repo paths of hand-written config that belongs with this consumer |

Current consumers (13): `quickshell` (Tokens.qml), `hypr` (karma_tokens.lua),
`kitty`, `btop`, `yazi`, `fzf` (FZF_DEFAULT_OPTS_FILE), `zsh`, `gtk3` and `gtk4`
(gtk.css colour overrides), `gtk3-settings` and `gtk4-settings` (settings.ini:
theme, dark preference, UI font), `greetd` (tuigreet theme), `vtrgb` (console
palette).

To add one: write the template, add an entry, run `karma theme build ID` and
`karma theme check ID`.

## Check

`karma theme check [ID...]` fails (exit 1) when:

1. A generated file is missing, edited by hand, or out of date (it differs from
   a fresh render). The diff is in the `--json` output.
2. A hardcoded value appears in hand-written files: `bin/`, `lib/`, `tui/`,
   `config/`, `system/` and `design/templates/`, or the consumer's own `lint`
   paths when IDs are given. Rules:
   - `hex-colour`: `#rrggbb` or `#rrggbbaa`
   - `colour-function`: `rgb(`, `rgba(`, `hsl(`, `hsla(`
   - `hex-int-colour`: `0xAARRGGBB`
   - `palette-name`: a distinctive Catppuccin name (mauve, crust, surface0, ...);
     names that are ordinary words (text, base, red, ...) are not flagged
   - `qml-literal`: a number other than 0 or 1 on a size, spacing, radius,
     margin, padding or duration property in a `.qml` file

Exceptions go in `design/check-allow.txt`, one per line:
`<path glob>|<ERE matched against the line>|<reason>`.

System files that are not installed yet are reported as notes, not failures.
