# Keybindings

Defined in `config/hypr/.config/hypr/binds.lua`; every bind has a description
that `karma keys` reads from `hyprctl binds -j`. `SUPER + /` shows this list on
screen. `SUPER` is the Windows key.

## Apps

| Keys | Action |
| --- | --- |
| `SUPER + Return` | Terminal (kitty) |
| `SUPER + E` | File manager (yazi in kitty) |
| `SUPER + Space` | Launcher (`karma launch`); Tab or `>` switches to karma's commands, Tab or Backspace back |
| `SUPER + X` | System menu (`karma menu`) |
| `SUPER + V` | Clipboard history (`karma clip`) |
| ``SUPER + ` `` | Show or hide the drop-down terminal (`karma term`) |
| `SUPER + C` | Calculator in the launcher (`karma calc`); typing `=` in the launcher gets there too |
| `SUPER + .` | Emoji picker in the launcher (`karma emoji`) |
| `SUPER + N` | Go to the app of the newest notification (the same as clicking it) |
| `SUPER + A` | Quick settings: toggles, notification history, look, sound and screen. Tab or the arrow keys change page (Quick, Look, System); 1, 2, 3 go straight to one |
| `SUPER + Tab` | All workspaces as miniatures; arrows (or H/J/K/L) move, Enter goes there, Tab or 1 turns to the Today page, Escape closes |
| `SUPER + D` | Dashboard: calendar, weather, system gauges, media (`karma sys`); Tab, the arrow keys or 2 turn to the Workspaces page, Escape closes. It also opens when the pointer touches the middle of the top edge |
| `SUPER + W` | Wi-Fi picker (`karma net tui`) |
| `SUPER + Shift + W` | Wallpaper picker (`karma wall pick`) |
| `SUPER + /` | Keybindings (`karma keys tui`); Enter does what the chosen one does |

All of these are panels of the interface (the launcher in different modes).
Without the interface, each falls back to a floating terminal. The same key closes each again.

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
| `Print` | Screenshot an area: click a window or drag a rectangle (saved and copied) |
| `Shift + Print` | Screenshot the focused monitor |
| `SUPER + Print` | Screenshot the focused window |
| `SUPER + O` | Copy the text in an area of the screen (`karma shot text`) |
| `SUPER + R` | Record an area of the screen; again to stop (`karma record`) |
| `SUPER + Shift + R` | Record the whole screen; again to stop |
| `SUPER + Escape` | Lock the screen |
| `SUPER + Shift + Escape` | Power menu: lock, sleep, log out, reboot, shut down |
| Volume, mute, mic mute, brightness | Through `karma audio` and `karma display`: journaled, undoable; they also work on the lock screen |
| Media keys | Next, previous, play/pause (playerctl) |
| Lid closed / opened | Laptop panel off / on (from `host.lua`) |
