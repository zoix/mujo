# Keybindings

Defined in `config/hypr/.config/hypr/binds.lua`; every bind has a description
that `karma keys` reads from `hyprctl binds -j`. `SUPER + /` shows this list on
screen. `SUPER` is the Windows key.

## Apps

| Keys | Action |
| --- | --- |
| `SUPER + Return` | Terminal (kitty) |
| `SUPER + E` | File manager (yazi in kitty) |
| `SUPER + Space` | Launcher (`karma launch`) |
| `SUPER + X` | System menu (`karma menu`) |
| `SUPER + V` | Clipboard history (`karma clip`) |
| `SUPER + W` | Wi-Fi picker (`karma net tui`) |
| `SUPER + /` | Keybindings (`karma keys tui`) |

These open in a floating terminal; the same key closes it again.

## Windows

| Keys | Action |
| --- | --- |
| `SUPER + Q` | Close the window |
| `SUPER + F` | Toggle floating |
| `SUPER + Shift + F` | Toggle fullscreen |
| `SUPER + M` | Toggle maximized |
| `SUPER + T` | Toggle the split direction |
| `SUPER + H / J / K / L` | Focus left / down / up / right |
| `SUPER + Shift + H / J / K / L` | Swap with the window left / down / up / right |
| `SUPER + left drag` | Move a window |
| `SUPER + right drag` | Resize a window |

## Workspaces

| Keys | Action |
| --- | --- |
| `SUPER + 1 ... 9, 0` | Go to workspace 1 ... 10 |
| `SUPER + Shift + 1 ... 9, 0` | Move the window to workspace 1 ... 10 |
| `SUPER + scroll` | Next / previous workspace |
| `SUPER + S` | Show or hide the scratchpad |
| `SUPER + Shift + S` | Move the window to the scratchpad |

## Session and hardware

| Keys | Action |
| --- | --- |
| `Print` | Screenshot a region (saved and copied) |
| `Shift + Print` | Screenshot the focused monitor |
| `SUPER + Print` | Screenshot the focused window |
| `SUPER + Shift + Escape` | Log out |
| Volume, mute, mic mute, brightness | Through `karma audio` and `karma display`: journaled, undoable; they also work on the lock screen |
| Media keys | Next, previous, play/pause (playerctl) |
| Lid closed / opened | Laptop panel off / on (from `host.lua`) |
