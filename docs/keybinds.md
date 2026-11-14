# Keybindings

Defined in `config/hypr/.config/hypr/binds.lua`; every bind has a description
that `karma keys` (phase 2) reads from `hyprctl binds -j`. `SUPER` is the
Windows key.

## Apps

| Keys | Action |
| --- | --- |
| `SUPER + Return` | Terminal (kitty) |
| `SUPER + E` | File manager (yazi in kitty) |
| `SUPER + Space` | Launcher (Vicinae while it is installed; `karma launch` in phase 2) |

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
| `Print` | Screenshot a region to the clipboard |
| `Shift + Print` | Screenshot the focused monitor to the clipboard |
| `SUPER + Shift + Escape` | Log out |
| Volume, mute, mic mute, brightness, media keys | As labelled; they also work on the lock screen |
| Lid closed / opened | Laptop panel off / on (from `host.lua`) |
