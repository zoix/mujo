-- Keybindings. Every bind carries a description so that `karma keys` can
-- list them from `hyprctl binds -j`.
--
-- Anything that changes the system goes through the karma CLI, so it is
-- journaled, can be undone and shows the OSD. The binds call karma by its
-- full path: Hyprland's own PATH does not include ~/.local/bin.
--
-- Each bind is also written, with the Lua expression of its action, to
-- $XDG_RUNTIME_DIR/karma-binds.json. `karma keys run DESCRIPTION` runs that
-- expression, which is how Enter in the keybinding list (SUPER + /) works.

local mod      = "SUPER"
local terminal = "kitty"
local karma    = "$HOME/.local/bin/karma "

local recorded = {}

-- run(cmd): a shell command, as a dispatcher plus the expression that makes it.
local function run(cmd)
    return { dsp = hl.dsp.exec_cmd(cmd), expr = "hl.dsp.exec_cmd(" .. string.format("%q", cmd) .. ")" }
end

-- act(expr): any other dispatcher, written once as a Lua expression.
local function act(expr)
    return { dsp = load("return " .. expr)(), expr = expr }
end

-- bind(keys, action, description, opts): action is run(...), act(...), or a
-- plain dispatcher for binds that only make sense on their key (mouse drags).
local function bind(keys, action, description, opts)
    local o = opts or {}
    o.description = description
    if type(action) == "table" and action.expr then
        recorded[#recorded + 1] = { description = description, expr = action.expr }
        hl.bind(keys, action.dsp, o)
    else
        hl.bind(keys, action, o)
    end
end

-- Apps
bind(mod .. " + Return", run(terminal), "Open a terminal")
bind(mod .. " + E", run(terminal .. " --class karma-files -e yazi"), "Open the file manager (yazi)")
bind(mod .. " + space", run(karma .. "launch --window"), "Open the launcher")
bind(mod .. " + X", run(karma .. "menu --window"), "Open the system menu")
bind(mod .. " + V", run(karma .. "clip --window"), "Open the clipboard history")
bind(mod .. " + W", run(karma .. "net tui --window"), "Open the Wi-Fi picker")
bind(mod .. " + SHIFT + W", run(karma .. "wall pick --window"), "Choose a wallpaper")
bind(mod .. " + D", run(karma .. "sys --window"), "Open the dashboard")
bind(mod .. " + Tab", run(karma .. "sys workspaces --window"), "Show all workspaces")
bind(mod .. " + N", run(karma .. "notify open"), "Go to the newest notification")
bind(mod .. " + A", run(karma .. "status --window"), "Open quick settings")
bind(mod .. " + slash", run(karma .. "keys tui --window"), "Show the keybindings")
bind(mod .. " + grave", run(karma .. "term"), "Show or hide the drop-down terminal")
bind(mod .. " + C", run(karma .. "calc --window"), "Open the calculator")
bind(mod .. " + period", run(karma .. "emoji --window"), "Open the emoji picker")

-- Windows
bind(mod .. " + Q", act('hl.dsp.window.close()'), "Close the window")
bind(mod .. " + F", act('hl.dsp.window.float({ action = "toggle" })'), "Toggle floating")
bind(mod .. " + SHIFT + F", act('hl.dsp.window.fullscreen({ action = "toggle", mode = "fullscreen" })'), "Toggle fullscreen")
bind(mod .. " + M", act('hl.dsp.window.fullscreen({ action = "toggle", mode = "maximized" })'), "Toggle maximized")
bind(mod .. " + T", act('hl.dsp.layout("togglesplit")'), "Toggle the split direction")

local directions = { H = "left", J = "down", K = "up", L = "right" }
for key, dir in pairs(directions) do
    bind(mod .. " + " .. key, act('hl.dsp.focus({ direction = "' .. dir .. '" })'), "Focus the window " .. dir)
    bind(mod .. " + SHIFT + " .. key, act('hl.dsp.window.swap({ direction = "' .. dir .. '" })'), "Swap with the window " .. dir)
end

bind(mod .. " + mouse:272", hl.dsp.window.drag(), "Move a window with the mouse", { mouse = true })
bind(mod .. " + mouse:273", hl.dsp.window.resize(), "Resize a window with the mouse", { mouse = true })

-- Workspaces: SUPER+1..9 and 0 (= workspace 10)
for i = 1, 10 do
    local key = i % 10
    bind(mod .. " + " .. key, act('hl.dsp.focus({ workspace = ' .. i .. ' })'), "Go to workspace " .. i)
    bind(mod .. " + SHIFT + " .. key, act('hl.dsp.window.move({ workspace = ' .. i .. ' })'), "Move the window to workspace " .. i)
end
bind(mod .. " + mouse_down", act('hl.dsp.focus({ workspace = "e+1" })'), "Next workspace")
bind(mod .. " + mouse_up", act('hl.dsp.focus({ workspace = "e-1" })'), "Previous workspace")

bind(mod .. " + S", act('hl.dsp.workspace.toggle_special("scratch")'), "Show or hide the scratchpad")
bind(mod .. " + SHIFT + S", act('hl.dsp.window.move({ workspace = "special:scratch" })'), "Move the window to the scratchpad")

-- Screenshots (saved to ~/Pictures/Screenshots and copied to the clipboard)
bind("Print", run(karma .. "shot region"), "Screenshot a region")
bind("SHIFT + Print", run(karma .. "shot screen"), "Screenshot this monitor")
bind(mod .. " + Print", run(karma .. "shot window"), "Screenshot the focused window")
bind(mod .. " + O", run(karma .. "shot text"), "Copy text from an area of the screen")
bind(mod .. " + R", run(karma .. "record toggle region"), "Record an area of the screen, or stop recording")
bind(mod .. " + SHIFT + R", run(karma .. "record toggle screen"), "Record the screen, or stop recording")

-- Session
bind(mod .. " + Escape", run(karma .. "power lock"), "Lock the screen")
bind(mod .. " + SHIFT + Escape", run(karma .. "power --window"), "Open the power menu")

-- Hardware keys: work on the lock screen too, and repeat while held.
local held = { locked = true, repeating = true }
bind("XF86AudioRaiseVolume", run(karma .. "audio volume +5"), "Volume up", held)
bind("XF86AudioLowerVolume", run(karma .. "audio volume -5"), "Volume down", held)
bind("XF86AudioMute", run(karma .. "audio mute toggle"), "Mute", { locked = true })
bind("XF86AudioMicMute", run(karma .. "audio mute toggle --input"), "Mute the microphone", { locked = true })
bind("XF86MonBrightnessUp", run(karma .. "display brightness +5"), "Brightness up", { locked = true, repeating = true })
bind("XF86MonBrightnessDown", run(karma .. "display brightness -5"), "Brightness down", { locked = true, repeating = true })
-- Media transport is not a system setting, so playerctl is called directly.
bind("XF86AudioNext", run("playerctl next"), "Next track", { locked = true })
bind("XF86AudioPrev", run("playerctl previous"), "Previous track", { locked = true })
bind("XF86AudioPlay", run("playerctl play-pause"), "Play or pause", { locked = true })
bind("XF86AudioPause", run("playerctl play-pause"), "Play or pause", { locked = true })

-- Write the list for `karma keys run`. Never fatal: without the file the
-- keys still work, only running a bind from the list does not.
pcall(function()
    local dir = os.getenv("XDG_RUNTIME_DIR")
    if not dir then return end
    local function q(text)
        return '"' .. text:gsub('\\', '\\\\'):gsub('"', '\\"') .. '"'
    end
    local rows = {}
    for _, b in ipairs(recorded) do
        rows[#rows + 1] = '{"description":' .. q(b.description) .. ',"action":' .. q(b.expr) .. '}'
    end
    local file = io.open(dir .. "/karma-binds.json", "w")
    if file then
        file:write("[" .. table.concat(rows, ",") .. "]\n")
        file:close()
    end
end)
