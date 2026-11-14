-- Keyboard and pointer defaults. The keyboard layout chosen during install,
-- and anything specific to this machine, is set in host.lua, which loads
-- after this file and wins.

hl.config({
    input = {
        kb_layout    = "us",
        kb_variant   = "",
        kb_options   = "",
        follow_mouse = 1,
        sensitivity  = 0,
        touchpad = {
            natural_scroll = false,
        },
    },
})
