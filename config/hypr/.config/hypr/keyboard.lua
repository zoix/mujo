-- The built-in keyboard is switched off while an external one is connected
-- (`mujo keyboard auto`). `mujo keyboard sync` writes
-- ~/.local/state/mujo/keyboard.lua as
--   return { boot = "<boot id>", off = { "at-translated-set-2-keyboard" } }
-- while that is the case and removes it otherwise, then reloads Hyprland.
--
-- A file left over from an earlier boot is ignored: the external keyboard
-- may be gone by now, and nothing would be left to type with.

local mujo = "$HOME/.local/bin/mujo "

-- Follows keyboards as they are plugged in and pulled; syncs once at start.
hl.on("hyprland.start", function()
    hl.exec_cmd(mujo .. "keyboard watch")
end)

local state = (os.getenv("XDG_STATE_HOME") or (os.getenv("HOME") .. "/.local/state")) .. "/mujo/keyboard.lua"
local file = io.open(state, "r")
if not file then
    return
end
file:close()

local ok, chosen = pcall(dofile, state)
if not ok or type(chosen) ~= "table" or type(chosen.off) ~= "table" then
    return
end

local boot = io.open("/proc/sys/kernel/random/boot_id", "r")
local id = boot and boot:read("l") or nil
if boot then
    boot:close()
end
if id == nil or chosen.boot ~= id then
    return
end

for _, name in ipairs(chosen.off) do
    hl.device({ name = name, enabled = false })
end
