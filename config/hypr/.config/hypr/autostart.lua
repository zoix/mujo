-- Session daemons, started once when Hyprland starts.
-- The Quickshell UI (qs -c karma) and hypridle join this list in phase 3,
-- when their configs exist.

hl.env("TERMINAL", "kitty")

hl.on("hyprland.start", function()
    -- Lets GUI apps ask for elevated privileges.
    hl.exec_cmd("systemctl --user start hyprpolkitagent")
    -- Clipboard history for `karma clip`.
    hl.exec_cmd("wl-paste --type text --watch cliphist store")
    hl.exec_cmd("wl-paste --type image --watch cliphist store")
end)
