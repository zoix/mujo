-- Gaps, borders, rounding and colours. Every value comes from
-- karma_tokens.lua, which `karma theme build` generates from design/tokens.json.
-- Depth comes from background steps only: no shadows, no blur.

-- Absolute path: this file is a link into the checkout (see hyprland.lua).
local cfg = (os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")) .. "/hypr/"
local t = require(cfg .. "karma_tokens")

hl.config({
    general = {
        gaps_in     = t.gaps_in,
        gaps_out    = t.gaps_out,
        border_size = t.border_size,
        col = {
            active_border   = t.color.border_active,
            inactive_border = t.color.border_inactive,
        },
        resize_on_border = false,
        allow_tearing    = false,
        layout           = "dwindle",
    },
    decoration = {
        rounding         = t.rounding,
        active_opacity   = 1.0,
        inactive_opacity = 1.0,
        shadow = { enabled = false },
        blur   = { enabled = false },
    },
    dwindle = {
        preserve_split = true,
    },
    misc = {
        force_default_wallpaper  = 0,
        disable_hyprland_logo    = true,
        disable_splash_rendering = true,
        background_color         = t.color.bg_frame,
        -- If the lock screen's process dies, a restarted one may take over
        -- the lock instead of leaving the session stuck.
        allow_session_lock_restore = true,
    },
})
