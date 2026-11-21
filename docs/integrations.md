# Integrations

Programs that work with mujo without being part of it. mujo does not load
plug-ins; an integration is a separate program that uses what mujo already
publishes and can be removed without touching mujo.

## What an integration can rely on

| Interface | Use |
| --- | --- |
| `~/.config/quickshell/mujo/theme/tokens.json` | The resolved colour, type, shape and motion roles, rewritten by every `mujo theme build`. Read it, and watch it for changes, to follow the theme live ([tokens.md](tokens.md)). Read-only: the next build overwrites edits. |
| `mujo <command> --json` | Stable, versioned output of every command ([cli.md](cli.md)). |
| Its own Quickshell config (`qs -c <name>`) | A widget of its own beside mujo's interface, with nothing added to mujo's config. |

An integration should not write to `~/.config/mujo/config.json`, the journal,
or the files under `~/.config/quickshell/mujo/`: `mujo theme build`,
`mujo update` and `mujo uninstall` own those.

## Tempo

[Tempo](https://github.com/zoix/tempo) is a local-first time tracker and
invoicing app for people who bill by the hour (desktop app and CLI). It runs
without mujo; with mujo it can:

- **Follow the theme.** In Tempo: Settings, Appearance, *Follow Mujo's
  theme*. It reads `tokens.json` and changes with the accent, the mode and
  the palette while it is open.
- **Show its timer on the desktop.** `tempo mujo install` adds a separate
  Quickshell config (`qs -c tempo`): a small pill with the elapsed time and
  pause and stop under the pointer, drawn with mujo's tokens.
  `tempo mujo uninstall` removes it.

Tempo's timer and `mujo focus` are different things and do not interact:
`focus` counts down and silences notifications, Tempo counts billable time
up. They keep separate state and neither starts or stops the other.

Tempo's guide: <https://github.com/zoix/tempo/blob/main/docs/mujo.md>
