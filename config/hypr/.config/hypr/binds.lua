-- Keybindings. Every bind carries a description so that `karma keys`
-- (phase 2) can list them from `hyprctl binds -j`.
--
-- Phase 1 note: volume, brightness and screenshots call their tools
-- directly. Phase 2 moves them behind `karma audio`, `karma display` and
-- `karma shot`, so they are journaled and show the OSD. The launcher bind
-- uses Vicinae if it is still installed until `karma launch` exists.

local mod      = "SUPER"
local terminal = "kitty"

local function bind(keys, dispatcher, description, opts)
    local o = opts or {}
    o.description = description
    hl.bind(keys, dispatcher, o)
end

-- Apps
bind(mod .. " + Return", hl.dsp.exec_cmd(terminal), "Open a terminal")
bind(mod .. " + E", hl.dsp.exec_cmd(terminal .. " --class karma-files -e yazi"), "Open the file manager (yazi)")
bind(mod .. " + space", hl.dsp.exec_cmd("command -v vicinae >/dev/null 2>&1 && vicinae toggle"), "Open the launcher")

-- Windows
bind(mod .. " + Q", hl.dsp.window.close(), "Close the window")
bind(mod .. " + F", hl.dsp.window.float({ action = "toggle" }), "Toggle floating")
bind(mod .. " + SHIFT + F", hl.dsp.window.fullscreen({ action = "toggle", mode = "fullscreen" }), "Toggle fullscreen")
bind(mod .. " + M", hl.dsp.window.fullscreen({ action = "toggle", mode = "maximized" }), "Toggle maximized")
bind(mod .. " + T", hl.dsp.layout("togglesplit"), "Toggle the split direction")

local directions = { H = "left", J = "down", K = "up", L = "right" }
for key, dir in pairs(directions) do
    bind(mod .. " + " .. key, hl.dsp.focus({ direction = dir }), "Focus the window " .. dir)
    bind(mod .. " + SHIFT + " .. key, hl.dsp.window.swap({ direction = dir }), "Swap with the window " .. dir)
end

bind(mod .. " + mouse:272", hl.dsp.window.drag(), "Move a window with the mouse", { mouse = true })
bind(mod .. " + mouse:273", hl.dsp.window.resize(), "Resize a window with the mouse", { mouse = true })

-- Workspaces: SUPER+1..9 and 0 (= workspace 10)
for i = 1, 10 do
    local key = i % 10
    bind(mod .. " + " .. key, hl.dsp.focus({ workspace = i }), "Go to workspace " .. i)
    bind(mod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }), "Move the window to workspace " .. i)
end
bind(mod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }), "Next workspace")
bind(mod .. " + mouse_up", hl.dsp.focus({ workspace = "e-1" }), "Previous workspace")

bind(mod .. " + S", hl.dsp.workspace.toggle_special("scratch"), "Show or hide the scratchpad")
bind(mod .. " + SHIFT + S", hl.dsp.window.move({ workspace = "special:scratch" }), "Move the window to the scratchpad")

-- Screenshots (to the clipboard)
bind("Print", hl.dsp.exec_cmd('grim -g "$(slurp)" - | wl-copy --type image/png'), "Screenshot a region")
bind("SHIFT + Print", hl.dsp.exec_cmd('grim -o "$(hyprctl activeworkspace -j | jq -r .monitor)" - | wl-copy --type image/png'), "Screenshot this monitor")

-- Session
bind(mod .. " + SHIFT + Escape",
    hl.dsp.exec_cmd("command -v hyprshutdown >/dev/null 2>&1 && hyprshutdown || hyprctl dispatch 'hl.dsp.exit()'"),
    "Log out")

-- Hardware keys: work on the lock screen too, and repeat while held.
local held = { locked = true, repeating = true }
bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), "Volume up", held)
bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"), "Volume down", held)
bind("XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), "Mute", { locked = true })
bind("XF86AudioMicMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), "Mute the microphone", { locked = true })
bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("brightnessctl set 5%+"), "Brightness up", { locked = true, repeating = true })
bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl set 5%-"), "Brightness down", { locked = true, repeating = true })
bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"), "Next track", { locked = true })
bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"), "Previous track", { locked = true })
bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), "Play or pause", { locked = true })
bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), "Play or pause", { locked = true })
