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
            -- The touchpad keeps working while keys are pressed. With the
            -- default (true) a finger that lands within half a second of a
            -- keystroke is ignored until the timeout ends.
            disable_while_typing = false,
            -- A tap followed by a touch does not start a drag. A finger that
            -- loses contact for an instant mid-movement reads as exactly
            -- that, and the pointer began selecting text on its own. Press
            -- the pad down to drag.
            tap_and_drag = false,
        },
    },
})
