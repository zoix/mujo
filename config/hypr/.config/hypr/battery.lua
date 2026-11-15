-- What mujo saves while the laptop runs on battery (`mujo power battery`).
-- `mujo power sync` writes ~/.local/state/mujo/battery.lua when the charger
-- is unplugged and removes it when it is plugged in, then reloads Hyprland:
--   solid    no blur behind the frame and its panels (they are drawn opaque)
--   monitor  the built-in screen at its lower refresh rate
-- Loaded after host.lua, so these win over the lines there while they apply.

local state = (os.getenv("XDG_STATE_HOME") or (os.getenv("HOME") .. "/.local/state")) .. "/mujo/battery.lua"
local file = io.open(state, "r")
if not file then
    return
end
file:close()

local ok, saving = pcall(dofile, state)
if not ok or type(saving) ~= "table" then
    return
end

if saving.solid then
    hl.config({ decoration = { blur = { enabled = false } } })
end
if type(saving.monitor) == "table" then
    hl.monitor(saving.monitor)
end
