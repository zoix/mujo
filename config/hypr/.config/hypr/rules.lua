-- Window rules.
--
-- karma's TUIs (launcher, system menu, Wi-Fi, keys) open in kitty with a
-- class of the form karma-tui-<name>. They float, centred, at a size
-- relative to the monitor so they look the same on the laptop and the Dell.
-- Tiled tools (yazi, btop, a shell) use their normal class and tile.

hl.window_rule({
    name   = "karma-tui",
    match  = { class = "^karma-tui-.*$" },
    float  = true,
    -- kitty asks to be maximized if its last window was; a menu never should be.
    suppress_event = "maximize fullscreen",
    size   = { "monitor_w * 0.5", "monitor_h * 0.6" },
    center = true,
})
