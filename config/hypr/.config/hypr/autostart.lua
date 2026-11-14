-- Session daemons, started once when Hyprland starts.

hl.env("TERMINAL", "kitty")

hl.on("hyprland.start", function()
    -- Lets GUI apps ask for elevated privileges.
    hl.exec_cmd("systemctl --user start hyprpolkitagent")
    -- The karma interface: frame, bar, notifications, OSD, wallpaper, lock
    -- screen. It owns the notification service, so it starts first.
    hl.exec_cmd("qs -c karma")
    -- Locks after a while without input, and before sleep (hypridle.conf).
    hl.exec_cmd("hypridle")
    -- Clipboard history for `karma clip`.
    hl.exec_cmd("wl-paste --type text --watch cliphist store")
    hl.exec_cmd("wl-paste --type image --watch cliphist store")
end)
