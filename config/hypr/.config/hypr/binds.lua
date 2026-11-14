-- Keybindings. Every bind carries a description so that `karma keys` can
-- list them from `hyprctl binds -j`.
--
-- Anything that changes the system goes through the karma CLI, so it is
-- journaled, can be undone and shows the OSD. The binds call karma by its
-- full path: Hyprland's own PATH does not include ~/.local/bin.

local mod      = "SUPER"
local terminal = "kitty"
local karma    = "$HOME/.local/bin/karma "

local function bind(keys, dispatcher, description, opts)
    local o = opts or {}
    o.description = description
    hl.bind(keys, dispatcher, o)
end

-- Apps
bind(mod .. " + Return", hl.dsp.exec_cmd(terminal), "Open a terminal")
bind(mod .. " + E", hl.dsp.exec_cmd(terminal .. " --class karma-files -e yazi"), "Open the file manager (yazi)")
bind(mod .. " + space", hl.dsp.exec_cmd(karma .. "launch --window"), "Open the launcher")
bind(mod .. " + X", hl.dsp.exec_cmd(karma .. "menu --window"), "Open the system menu")
bind(mod .. " + V", hl.dsp.exec_cmd(karma .. "clip --window"), "Open the clipboard history")
bind(mod .. " + W", hl.dsp.exec_cmd(karma .. "net tui --window"), "Open the Wi-Fi picker")
bind(mod .. " + SHIFT + W", hl.dsp.exec_cmd(karma .. "wall pick --window"), "Choose a wallpaper")
bind(mod .. " + D", hl.dsp.exec_cmd(karma .. "sys --window"), "Open the dashboard")
bind(mod .. " + slash", hl.dsp.exec_cmd(karma .. "keys tui --window"), "Show the keybindings")

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

-- Screenshots (saved to ~/Pictures/Screenshots and copied to the clipboard)
bind("Print", hl.dsp.exec_cmd(karma .. "shot region"), "Screenshot a region")
bind("SHIFT + Print", hl.dsp.exec_cmd(karma .. "shot screen"), "Screenshot this monitor")
bind(mod .. " + Print", hl.dsp.exec_cmd(karma .. "shot window"), "Screenshot the focused window")

-- Session
bind(mod .. " + Escape", hl.dsp.exec_cmd(karma .. "power lock"), "Lock the screen")
bind(mod .. " + SHIFT + Escape", hl.dsp.exec_cmd(karma .. "power --window"), "Open the power menu")

-- Hardware keys: work on the lock screen too, and repeat while held.
local held = { locked = true, repeating = true }
bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd(karma .. "audio volume +5"), "Volume up", held)
bind("XF86AudioLowerVolume", hl.dsp.exec_cmd(karma .. "audio volume -5"), "Volume down", held)
bind("XF86AudioMute", hl.dsp.exec_cmd(karma .. "audio mute toggle"), "Mute", { locked = true })
bind("XF86AudioMicMute", hl.dsp.exec_cmd(karma .. "audio mute toggle --input"), "Mute the microphone", { locked = true })
bind("XF86MonBrightnessUp", hl.dsp.exec_cmd(karma .. "display brightness +5"), "Brightness up", { locked = true, repeating = true })
bind("XF86MonBrightnessDown", hl.dsp.exec_cmd(karma .. "display brightness -5"), "Brightness down", { locked = true, repeating = true })
-- Media transport is not a system setting, so playerctl is called directly.
bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"), "Next track", { locked = true })
bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"), "Previous track", { locked = true })
bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), "Play or pause", { locked = true })
bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), "Play or pause", { locked = true })
