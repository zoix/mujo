-- Session daemons, started once when Hyprland starts.
-- The Quickshell UI (qs -c karma) and hypridle join this list in phase 3,
-- when their configs exist.

hl.env("TERMINAL", "kitty")

hl.on("hyprland.start", function()
    -- Lets GUI apps ask for elevated privileges.
    hl.exec_cmd("systemctl --user start hyprpolkitagent")
    -- Clipboard history for `karma clip` (phase 2).
    hl.exec_cmd("wl-paste --type text --watch cliphist store")
    hl.exec_cmd("wl-paste --type image --watch cliphist store")
    -- Transitional: keeps the Vicinae launcher working until `karma launch`
    -- replaces it in phase 2. Does nothing if Vicinae was removed.
    hl.exec_cmd("command -v vicinae >/dev/null 2>&1 && vicinae server")
end)
