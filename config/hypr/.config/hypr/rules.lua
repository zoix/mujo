-- Window rules.
--
-- mujo's TUIs (launcher, system menu, Wi-Fi, keys) open in Ghostty with a
-- class of the form mujo.tui.<name>. They float, centred, at a size
-- relative to the monitor so they look the same on the laptop and the Dell.
-- Tiled tools (yazi, btop, a shell) use their normal class and tile.

hl.window_rule({
    name   = "mujo-tui",
    match  = { class = "^mujo\\.tui\\..*$" },
    float  = true,
    -- A menu is never maximized, whatever the terminal remembers.
    suppress_event = "maximize fullscreen",
    size   = { "monitor_w * 0.5", "monitor_h * 0.6" },
    center = true,
})

-- The package picker and command output need more room than a menu: the
-- description beside the list is wide.
hl.window_rule({
    name   = "mujo-tui-wide",
    match  = { class = "^mujo\\.tui\\.(pkg|show)$" },
    size   = { "monitor_w * 0.8", "monitor_h * 0.8" },
    center = true,
})

-- The drop-down terminal (mujo term, SUPER + `) lives on a hidden workspace
-- of its own and floats over the top half of the screen.
hl.window_rule({
    name      = "mujo-drop",
    match     = { class = "^mujo\\.drop$" },
    workspace = "special:term",
    float     = true,
    suppress_event = "maximize fullscreen",
    size      = { "monitor_w * 0.8", "monitor_h * 0.5" },
    move      = { "monitor_w * 0.1", "monitor_h * 0.04" },
})

-- With "glass" on, the desktop behind the frame and its panels is blurred.
-- The rest of that layer is fully transparent and stays untouched.
do
    local cfg = (os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")) .. "/hypr/"
    local t = require(cfg .. "mujo_tokens")
    hl.layer_rule({
        name         = "mujo-glass",
        match        = { namespace = "mujo-frame" },
        blur         = true,
        ignore_alpha = 0.3,
        enabled      = t.glass,
    })
end
