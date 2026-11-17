-- The scale chosen with `mujo display scale`, per screen. The choice is kept
-- in ~/.local/state/mujo/scale.lua as { ["eDP-1"] = "1.5" } and wins over the
-- scale written in host.lua (and in the battery savings), so the mode and the
-- position stay where they are set and only the size of things changes.
--
-- Loaded before host.lua: every hl.monitor() after this point passes through
-- here. hyprland.lua calls finish() last, for a screen host.lua has no line
-- for.

local state = (os.getenv("XDG_STATE_HOME") or (os.getenv("HOME") .. "/.local/state")) .. "/mujo/scale.lua"

-- Hyprland's own function, also after a reload that kept this Lua state.
local set_monitor = hl.mujo_set_monitor or hl.monitor
hl.mujo_set_monitor = set_monitor

local scales = {}
local file = io.open(state, "r")
if file then
    file:close()
    local ok, chosen = pcall(dofile, state)
    if ok and type(chosen) == "table" then
        scales = chosen
    end
end

local seen = {}

hl.monitor = function(rule)
    if type(rule) ~= "table" or scales[rule.output] == nil then
        return set_monitor(rule)
    end
    seen[rule.output] = true
    local with_scale = {}
    for key, value in pairs(rule) do
        with_scale[key] = value
    end
    with_scale.scale = scales[rule.output]
    return set_monitor(with_scale)
end

return {
    finish = function()
        for output, scale in pairs(scales) do
            if not seen[output] then
                set_monitor({ output = output, mode = "preferred", position = "auto", scale = scale })
            end
        end
    end,
}
