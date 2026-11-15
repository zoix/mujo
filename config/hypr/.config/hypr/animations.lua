-- Motion from the design tokens: three curves (standard, enter, exit) and
-- three speeds (fast, normal, slow). Things appear with the enter curve and
-- leave with the exit curve; nothing bounces. With reduce_motion on
-- (`mujo theme reduce-motion on`) every animation is off.

-- Absolute path: this file is a link into the checkout (see hyprland.lua).
local cfg = (os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")) .. "/hypr/"
local t = require(cfg .. "mujo_tokens")

if t.reduce_motion then
    hl.config({ animations = { enabled = false } })
    return
end

hl.config({ animations = { enabled = true } })

hl.curve("mujo_standard", t.curves.standard)
hl.curve("mujo_enter",    t.curves.enter)
hl.curve("mujo_exit",     t.curves.exit)

local s = t.speed

-- Gentle motion (`mujo theme motion gentle`): the speeds from the tokens are
-- already slower, and things fade in place instead of sliding or growing,
-- which is easier on the eyes.
local gentle  = t.gentle
local pop     = gentle and "popin 97%" or "popin 90%"
local layers  = gentle and "fade" or "slide"
local spaces  = gentle and "fade" or "slidevert"
local special = gentle and "fade" or "slidefadevert"

hl.animation({ leaf = "global",        enabled = true, speed = s.normal, bezier = "mujo_standard" })
hl.animation({ leaf = "border",        enabled = true, speed = s.fast,   bezier = "mujo_standard" })
hl.animation({ leaf = "windowsIn",     enabled = true, speed = s.normal, bezier = "mujo_enter",    style = pop })
hl.animation({ leaf = "windowsOut",    enabled = true, speed = s.fast,   bezier = "mujo_exit",     style = pop })
hl.animation({ leaf = "windowsMove",   enabled = true, speed = s.normal, bezier = "mujo_standard" })
hl.animation({ leaf = "fadeIn",        enabled = true, speed = s.normal, bezier = "mujo_enter" })
hl.animation({ leaf = "fadeOut",       enabled = true, speed = s.fast,   bezier = "mujo_exit" })
hl.animation({ leaf = "fadeSwitch",    enabled = true, speed = s.fast,   bezier = "mujo_standard" })
hl.animation({ leaf = "layersIn",      enabled = true, speed = s.normal, bezier = "mujo_enter",    style = layers })
hl.animation({ leaf = "layersOut",     enabled = true, speed = s.fast,   bezier = "mujo_exit",     style = layers })
hl.animation({ leaf = "fadeLayersIn",  enabled = true, speed = s.normal, bezier = "mujo_enter" })
hl.animation({ leaf = "fadeLayersOut", enabled = true, speed = s.fast,   bezier = "mujo_exit" })
-- The bar lists workspaces vertically, so workspaces slide vertically.
hl.animation({ leaf = "workspaces",    enabled = true, speed = s.slow,   bezier = "mujo_standard", style = spaces })
hl.animation({ leaf = "specialWorkspace", enabled = true, speed = s.normal, bezier = "mujo_enter", style = special })
