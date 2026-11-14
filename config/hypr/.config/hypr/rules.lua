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

-- The package picker and command output need more room than a menu: the
-- description beside the list is wide.
hl.window_rule({
    name   = "karma-tui-wide",
    match  = { class = "^karma-tui-(pkg|show)$" },
    size   = { "monitor_w * 0.8", "monitor_h * 0.8" },
    center = true,
})

-- With "glass" on, the desktop behind the frame and its panels is blurred.
-- The rest of that layer is fully transparent and stays untouched.
do
    local cfg = (os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")) .. "/hypr/"
    local t = require(cfg .. "karma_tokens")
    hl.layer_rule({
        name         = "karma-glass",
        match        = { namespace = "karma-frame" },
        blur         = true,
        ignore_alpha = 0.3,
        enabled      = t.glass,
    })
end
