-- App compatibility fixes, ported line by line from the previous
-- ~/.config/hypr/hyprland.conf (see docs/install.md, "What was ported").
-- Each block says what it fixes. Remove one only if you know the app no
-- longer needs it.

-- XWayland apps on a scaled monitor (eDP-1 at 2x, the Dell at 1.6x) would
-- otherwise be rendered at 1x and upscaled, which makes them blurry.
-- Old line: xwayland { force_zero_scaling = true }
hl.config({
    xwayland = {
        force_zero_scaling = true,
    },
})

-- Zen Browser 1.17 crashes at start on Hyprland 0.57 with "Wayland protocol
-- error: interface 'wp_image_description_v1' has no event 2": Hyprland
-- offers a newer colour-management protocol than Zen's bundled libraries
-- know. Without the colour-management pipeline the protocol is not offered.
-- Takes effect when Hyprland starts (log out and in). Not from the old
-- config; added 2026-11. Remove once Zen is updated and starts without it.
hl.config({
    render = {
        cm_enabled = false,
    },
})

-- Electron apps (Bitwarden, 1Password, VS Code, Slack, ...) run as native
-- Wayland clients instead of through XWayland: sharp text at fractional scale
-- and correct input handling.
-- Old line: env = ELECTRON_OZONE_PLATFORM_HINT,wayland
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "wayland")

-- The same for Chromium-based apps that read the older variable.
-- Old line: env = OZONE_PLATFORM,wayland
hl.env("OZONE_PLATFORM", "wayland")

-- One cursor size for Wayland (hyprcursor) and XWayland (Xcursor) apps, so
-- the pointer does not change size when it crosses an XWayland window.
-- Old lines: env = XCURSOR_SIZE,24 and env = HYPRCURSOR_SIZE,24
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")

-- Secret Service (org.freedesktop.secrets) for apps that store credentials
-- through libsecret: Bitwarden and other Electron apps' "safe storage",
-- Chromium, GNOME Online Accounts, git-credential-libsecret.
-- Old line: exec-once = /usr/bin/gnome-keyring-daemon --start --components=secrets,ssh,gpg
-- Only "secrets" is kept: gnome-keyring 48.0 disabled its ssh agent at build
-- time (upstream NEWS, !94), and GnuPG starts its own gpg-agent on demand.
-- The old line never ran on this machine: gnome-keyring was not installed.
hl.on("hyprland.start", function()
    hl.exec_cmd("gnome-keyring-daemon --start --components=secrets")
end)

-- Not ported: exec-once = xrdb -merge ~/.Xresources
-- ~/.Xresources does not exist, so the line did nothing.
