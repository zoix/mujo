#!/usr/bin/env bats
# The control-plane commands (phase 2), run against the test doubles in
# tests/stubs so that nothing touches the real audio, network or backlight.

load helpers

setup() {
  mujo_test_env
  use_stubs
}

journal_count() {
  if [[ -f $(state)/journal.jsonl ]]; then wc -l <"$(state)/journal.jsonl"; else echo 0; fi
}

# ---- shared plumbing ---------------------------------------------------------

@test "json_array keeps arguments that look like options" {
  run bash -c "source '$MUJO_REPO/lib/core.sh'; json_array display night on --temp 3500"
  [ "$status" -eq 0 ]
  [ "$output" = '["display","night","on","--temp","3500"]' ]
}

@test "step_value resolves absolute and relative values and clamps" {
  run bash -c "source '$MUJO_REPO/lib/core.sh'; step_value +5 40 0 100; step_value -50 40 0 100; step_value 70% 40 0 100; step_value +90 40 0 100"
  [ "$output" = $'45\n0\n70\n100' ]
  run bash -c "source '$MUJO_REPO/lib/core.sh'; step_value loud 40 0 100"
  [ "$status" -ne 0 ]
}

@test "every command has help" {
  for c in status audio net bt display wall dnd notify power shot record calc emoji term focus weather clip launch menu keys sys time services about pkg doctor update uninstall; do
    run mujo help "$c"
    [ "$status" -eq 0 ]
    [[ $output == "Usage: mujo $c"* ]]
  done
}

# ---- audio -------------------------------------------------------------------

@test "audio status reports levels and devices" {
  run mujo audio --json
  [ "$status" -eq 0 ]
  [ "$(data .output.volume)" = 40 ]
  [ "$(data .output.device)" = Speaker ]
  [ "$(data '.outputs | length')" = 2 ]
  [ "$(data '.inputs[0].name')" = alsa_input.mic ]
}

@test "audio volume changes, is journaled, and undo restores it" {
  run mujo audio volume +15 --json
  [ "$status" -eq 0 ]
  [ "$(data .before.volume)" = 40 ]
  [ "$(data .after.volume)" = 55 ]
  [ "$(data .after.muted)" = false ]
  [ "$(data .journal_id)" != null ]
  run mujo undo
  [ "$status" -eq 0 ]
  run mujo audio volume --json
  [ "$(data .volume)" = 40 ]
}

@test "raising the volume unmutes, lowering does not, and undo restores both" {
  mujo audio mute on
  run mujo audio volume -10 --json
  [ "$(data .after.muted)" = true ]
  run mujo audio volume +20 --json
  [ "$(data .after.volume)" = 50 ]
  [ "$(data .after.muted)" = false ]
  mujo undo
  run mujo audio --json
  [ "$(data .output.volume)" = 30 ]
  [ "$(data .output.muted)" = true ]
}

@test "audio volume --dry-run shows a diff and changes nothing" {
  run mujo audio volume 80 --dry-run
  [ "$status" -eq 0 ]
  [[ $output == *'-  "volume": 40'* ]]
  [[ $output == *'+  "volume": 80'* ]]
  [ "$(journal_count)" -eq 0 ]
  run mujo audio volume --json
  [ "$(data .volume)" = 40 ]
}

@test "audio volume clamps at 100, ignores a no-op and rejects nonsense" {
  run mujo audio volume +500 --json
  [ "$(data .after.volume)" = 100 ]
  run mujo audio volume 100 --json
  [ "$(data .changed)" = false ]
  [ "$(journal_count)" -eq 1 ]
  run mujo audio volume loud
  [ "$status" -eq 2 ]
}

@test "audio mute --input mutes only the microphone, and undo unmutes it" {
  run mujo audio mute --input --json
  [ "$(data .after.muted)" = true ]
  run mujo audio --json
  [ "$(data .input.muted)" = true ]
  [ "$(data .output.muted)" = false ]
  mujo undo
  run mujo audio --json
  [ "$(data .input.muted)" = false ]
}

@test "audio output switches the default device by name and undo switches back" {
  run mujo audio output alsa_output.hdmi
  [ "$status" -eq 0 ]
  run mujo audio --json
  [ "$(data .output.device)" = HDMI ]
  mujo undo
  run mujo audio --json
  [ "$(data .output.device)" = Speaker ]
  run mujo audio output nothing-like-this
  [ "$status" -eq 1 ]
}

# ---- display -----------------------------------------------------------------

@test "display brightness changes, never goes below 1, and undo restores it" {
  run mujo display brightness -200 --json
  [ "$(data .before.brightness)" = 50 ]
  [ "$(data .after.brightness)" = 1 ]
  mujo undo
  run mujo display brightness --json
  [ "$(data .percent)" = 50 ]
}

@test "display night needs a Hyprland session" {
  run mujo display night on
  [ "$status" -eq 3 ]
  run mujo display --json
  [ "$status" -eq 0 ]
  [ "$(data .night)" = null ]
}

@test "display scale steps through the scales that fit, is kept for Hyprland, and undo drops it" {
  run mujo display scale
  [ "$status" -eq 3 ]
  export HYPRLAND_INSTANCE_SIGNATURE=test
  lua=$(state)/scale.lua
  run mujo display scale --json
  [ "$(data .monitor)" = eDP-1 ]
  [ "$(data .scale)" = 2 ]
  [ "$(data .chosen)" = false ]
  [ "$(data '.choices | map(tostring) | join(" ")')" = "1 1.066667 1.2 1.25 1.333333 1.5 1.6 1.666667 1.875 2 2.133333 2.4 2.5 2.666667 3" ]
  [ ! -e "$lua" ]
  run mujo display scale bigger --json
  [ "$(data .after.scale)" = 2.133333 ]
  [ "$(cat "$lua")" = 'return { ["eDP-1"] = "2.133333" }' ]
  grep -qx reload "$STUB_STATE/hyprctl.log"
  # a number picks the nearest scale that fits
  run mujo display scale 1.55 --monitor eDP-1 --json
  [ "$(data .after.scale)" = 1.5 ]
  [ "$(cat "$lua")" = 'return { ["eDP-1"] = "1.5" }' ]
  mujo undo
  [ "$(cat "$lua")" = 'return { ["eDP-1"] = "2.133333" }' ]
  run mujo display --json
  [ "$(data .scale.monitor)" = eDP-1 ]
  mujo display scale reset
  [ ! -e "$lua" ]
  [ "$(jq -c .display_scale "$XDG_CONFIG_HOME/mujo/config.json")" = '{}' ]
  run mujo display scale reset
  [[ $output == *"Nothing to do"* ]]
  run mujo display scale 4
  [ "$status" -eq 2 ]
  run mujo display scale bigger --monitor HDMI-9
  [ "$status" -eq 1 ]
}

# ---- wallpaper ---------------------------------------------------------------

@test "wall set, next, clear and undo" {
  walls=$BATS_TEST_TMPDIR/walls
  mkdir -p "$walls"
  touch "$walls/a.png" "$walls/b.jpg" "$walls/notes.txt"
  mujo wall dir "$walls"
  run mujo wall --json
  [ "$(data .available)" = 2 ]
  [ "$(data .wallpaper)" = null ]

  mujo wall next
  run mujo wall --json
  [ "$(data .wallpaper)" = "$walls/a.png" ]
  mujo wall next
  mujo wall next
  run mujo wall --json
  [ "$(data .wallpaper)" = "$walls/a.png" ]
  mujo wall prev
  run mujo wall --json
  [ "$(data .wallpaper)" = "$walls/b.jpg" ]

  mujo undo
  run mujo wall --json
  [ "$(data .wallpaper)" = "$walls/a.png" ]

  run mujo wall set "$walls/notes.txt"
  [ "$status" -eq 1 ]
  mujo wall clear
  run mujo wall --json
  [ "$(data .wallpaper)" = null ]
}

# ---- light and dark mode ----------------------------------------------------------

@test "theme mode light rebuilds with the light palette and undo returns to dark" {
  mujo theme build
  run mujo theme mode --json
  [ "$(data .mode)" = dark ]
  [ "$(data .preference)" = auto ]
  dark_bg=$(mujo theme show color.bg.base --json | jq -r .data.value)

  mujo theme mode light
  light_bg=$(mujo theme show color.bg.base --json | jq -r .data.value)
  [ "$dark_bg" != "$light_bg" ]
  grep -q "$light_bg" "$(conf)/ghostty/mujo-theme"
  grep -q 'gtk-application-prefer-dark-theme=0' "$(conf)/gtk-3.0/settings.ini"
  run mujo theme check
  [ "$status" -eq 0 ]

  mujo undo
  run mujo theme mode --json
  [ "$(data .mode)" = dark ]
  [ "$(data .preference)" = auto ]
  run mujo theme mode sepia
  [ "$status" -eq 2 ]
}

@test "theme motion gentle slows every duration and tells Hyprland to fade" {
  mujo theme build
  normal=$(jq .durationNormal "$(conf)/quickshell/mujo/theme/tokens.json")
  mujo theme motion gentle
  gentle=$(jq .durationNormal "$(conf)/quickshell/mujo/theme/tokens.json")
  [ "$gentle" -gt "$normal" ]
  grep -q 'gentle = true' "$(conf)/hypr/mujo_tokens.lua"
  mujo undo
  [ "$(jq .durationNormal "$(conf)/quickshell/mujo/theme/tokens.json")" = "$normal" ]
  run mujo theme motion fast
  [ "$status" -eq 2 ]
}

@test "theme glass makes the panels see-through and tells Hyprland to blur" {
  mujo theme build
  tokens=$(conf)/quickshell/mujo/theme/tokens.json
  [ "$(jq .panelOpacity "$tokens")" = 1 ]
  mujo theme glass on
  [ "$(jq '.panelOpacity < 1' "$tokens")" = true ]
  grep -q 'glass = true' "$(conf)/hypr/mujo_tokens.lua"
  # the drop-down terminal's background joins in
  grep -qx 'background-opacity = 0.82' "$(conf)/ghostty/mujo-drop"
  grep -qx 'background-opacity = 0.96' "$(conf)/ghostty/mujo-theme"
  grep -qx 'background-blur = true' "$(conf)/ghostty/mujo-theme"
  mujo undo
  [ "$(jq .panelOpacity "$tokens")" = 1 ]
  grep -qx 'background-opacity = 1' "$(conf)/ghostty/mujo-drop"
  grep -qx 'background-opacity = 1' "$(conf)/ghostty/mujo-theme"
  grep -qx 'background-blur = false' "$(conf)/ghostty/mujo-theme"
}

@test "the console palette for /etc is the same in light and dark mode" {
  mujo theme build
  before=$(sha256sum <"$(state)/theme/system/vtrgb/palette.vtrgb")
  mujo theme mode light
  [ "$before" = "$(sha256sum <"$(state)/theme/system/vtrgb/palette.vtrgb")" ]
}

@test "with mode auto a bright wallpaper switches to light, and undoing it switches back" {
  walls=$BATS_TEST_TMPDIR/walls
  mkdir -p "$walls"
  touch "$walls/bright-sky.png" "$walls/night.png"
  mujo theme build

  mujo wall set "$walls/night.png"
  run mujo theme mode --json
  [ "$(data .mode)" = dark ]

  run mujo wall set "$walls/bright-sky.png"
  [ "$status" -eq 0 ]
  [[ $output == *"mode dark -> light"* ]]
  run mujo theme mode --json
  [ "$(data .mode)" = light ]

  # undo skips the automatic mode entry and reverts the wallpaper, which syncs the mode
  mujo undo
  run mujo wall --json
  [ "$(data .wallpaper)" = "$walls/night.png" ]
  run mujo theme mode --json
  [ "$(data .mode)" = dark ]
}

@test "with the accent on auto it follows the wallpaper's colour; a chosen accent stays" {
  walls=$BATS_TEST_TMPDIR/walls
  mkdir -p "$walls"
  touch "$walls/blue-lake.png" "$walls/grey.png"
  mujo theme build
  run mujo theme accent --json
  [ "$(data .accent)" = mauve ]
  [ "$(data .preference)" = auto ]

  mujo wall set "$walls/blue-lake.png"
  run mujo theme accent --json
  [ "$(data .accent)" = blue ]
  # a grey image has no colour to follow: back to the default accent
  mujo wall set "$walls/grey.png"
  run mujo theme accent --json
  [ "$(data .accent)" = mauve ]

  mujo theme accent green
  mujo wall set "$walls/blue-lake.png"
  run mujo theme accent --json
  [ "$(data .accent)" = green ]
  [ "$(data .preference)" = green ]
}

@test "wall list reports thumbnails once the folder is indexed" {
  walls=$BATS_TEST_TMPDIR/walls
  mkdir -p "$walls"
  touch "$walls/a.png"
  export XDG_CACHE_HOME=$BATS_TEST_TMPDIR/cache
  mujo wall dir "$walls"
  run mujo wall list --json
  [ "$(data '.images[0].name')" = a ]
  [ "$(data '.images[0].thumb')" = null ]
  mujo wall index
  run mujo wall list --json
  [ -f "$(data '.images[0].thumb')" ]
}

@test "menu run performs an entry without a terminal" {
  run mujo menu run "Audio: mute or unmute"
  [ "$status" -eq 0 ]
  run mujo audio --json
  [ "$(data .output.muted)" = true ]
  run mujo menu run "No such entry"
  [ "$status" -eq 1 ]
  run mujo menu list --json
  [ "$(data '[.entries[] | select(.command == "theme accent blue")] | length')" = 1 ]
}

@test "the wallpaper palette tints the colours with the wallpaper's hue and follows it" {
  walls=$BATS_TEST_TMPDIR/walls
  mkdir -p "$walls"
  touch "$walls/blue-lake.png" "$walls/grey.png"
  mujo theme build
  tokens=$(conf)/quickshell/mujo/theme/tokens.json
  plain=$(jq -r .bgBase "$tokens")
  console=$(sha256sum <"$(state)/theme/system/vtrgb/palette.vtrgb")
  mujo wall set "$walls/blue-lake.png"

  mujo theme palette wallpaper
  run mujo theme palette --json
  [ "$(data .palette)" = wallpaper ]
  [ "$(data '.hue >= 200 and .hue <= 240')" = true ]
  tinted=$(jq -r .bgBase "$tokens")
  [ "$tinted" != "$plain" ]
  [ "$(jq -r .accentName "$tokens")" = wallpaper ]
  # errors stay red, and the console palette in /etc is not affected
  [ "$(jq -r .stateError "$tokens")" = "#f38ba8" ]
  [ "$console" = "$(sha256sum <"$(state)/theme/system/vtrgb/palette.vtrgb")" ]
  run mujo theme check
  [ "$status" -eq 0 ]

  # a grey wallpaper has no hue to use: the plain colours come back
  mujo wall set "$walls/grey.png"
  [ "$(jq -r .bgBase "$tokens")" = "$plain" ]
  mujo wall set "$walls/blue-lake.png"
  [ "$(jq -r .bgBase "$tokens")" = "$tinted" ]

  mujo theme palette catppuccin
  [ "$(jq -r .bgBase "$tokens")" = "$plain" ]
  [ "$(jq -r .accentName "$tokens")" = blue ]
  run mujo theme palette neon
  [ "$status" -eq 2 ]
}

@test "a fixed mode ignores the wallpaper" {
  walls=$BATS_TEST_TMPDIR/walls
  mkdir -p "$walls"
  touch "$walls/bright-sky.png"
  mujo theme build
  mujo theme mode dark
  mujo wall set "$walls/bright-sky.png"
  run mujo theme mode --json
  [ "$(data .mode)" = dark ]
  [ "$(data .preference)" = dark ]
  mujo theme mode auto
  run mujo theme mode --json
  [ "$(data .mode)" = light ]
}

# ---- do not disturb ------------------------------------------------------------

@test "dnd on, off and undo" {
  run mujo dnd --json
  [ "$(data .dnd)" = false ]
  mujo dnd on
  [ "$(jq -r .dnd "$(conf)/mujo/config.json")" = true ]
  mujo undo
  run mujo dnd --json
  [ "$(data .dnd)" = false ]
  run mujo dnd maybe
  [ "$status" -eq 2 ]
}

# ---- network -----------------------------------------------------------------

@test "net status and scan" {
  run mujo net --json
  [ "$status" -eq 0 ]
  [ "$(data .wifi.ssid)" = HomeNet ]
  [ "$(data .wifi.signal)" = 80 ]
  run mujo net scan --json
  [ "$(data '.networks | length')" = 3 ]
  [ "$(data '.networks[0].ssid')" = HomeNet ]
  [ "$(data '.networks[0].signal')" = 80 ]
  [ "$(data '.networks[] | select(.security == "open") | .ssid')" = "Open:Net" ]
  [ "$(data '.networks[] | select(.ssid == "Cafe") | .saved')" = true ]
}

@test "net connect is undoable and returns to the previous network" {
  run mujo net connect Cafe
  [ "$status" -eq 0 ]
  run mujo net --json
  [ "$(data .wifi.ssid)" = Cafe ]
  mujo undo
  run mujo net --json
  [ "$(data .wifi.ssid)" = HomeNet ]
}

@test "net connect reads a password from stdin and never journals it" {
  run mujo net connect Locked </dev/null
  [ "$status" -eq 1 ]
  run bash -c "echo hunter2 | '$MUJO' net connect Locked --password-stdin"
  [ "$status" -eq 0 ]
  ! grep -q hunter2 "$(state)/journal.jsonl"
}

@test "net forget needs --yes and cannot be undone" {
  run mujo net forget Cafe
  [ "$status" -eq 2 ]
  run mujo net forget Cafe --yes --json
  [ "$status" -eq 0 ]
  run mujo log --json
  [ "$(data '.entries[0].reversible')" = false ]
  run mujo net forget Cafe --yes
  [ "$status" -eq 1 ]
}

@test "net wifi off and undo" {
  mujo net wifi off
  run mujo net wifi --json
  [ "$(data .wifi_enabled)" = false ]
  mujo undo
  run mujo net wifi --json
  [ "$(data .wifi_enabled)" = true ]
}

# ---- bluetooth ---------------------------------------------------------------

@test "bt status, power off and undo" {
  run mujo bt --json
  [ "$(data .powered)" = true ]
  [ "$(data '.devices | length')" = 2 ]
  [ "$(data '.devices[] | select(.connected) | .name')" = Mouse ]
  [ "$(data '.devices[0].name')" = "Head Phones" ]
  mujo bt power toggle
  run mujo bt power --json
  [ "$(data .powered)" = false ]
  mujo undo
  run mujo bt power --json
  [ "$(data .powered)" = true ]
}

# ---- power -------------------------------------------------------------------

@test "power reboot needs --yes; --dry-run shows the command" {
  run mujo power reboot
  [ "$status" -eq 2 ]
  [ ! -e "$STUB_STATE/systemctl.log" ]
  run mujo power reboot --dry-run --json
  [ "$status" -eq 0 ]
  [ "$(data '.command | join(" ")')" = "systemctl reboot" ]
  [ ! -e "$STUB_STATE/systemctl.log" ]
}

@test "power suspend and shutdown --yes run systemctl and are journaled" {
  mujo power suspend
  mujo power shutdown --yes
  [ "$(cat "$STUB_STATE/systemctl.log")" = $'suspend\npoweroff' ]
  run mujo log --json
  [ "$(data '.entries[0].summary')" = "power shutdown" ]
  [ "$(data '.entries[0].reversible')" = false ]
}

@test "power profile changes and undo restores it" {
  run mujo power profile --json
  [ "$(data .profile)" = balanced ]
  [ "$(data '.available | length')" = 3 ]
  mujo power profile power-saver
  run mujo power profile --json
  [ "$(data .profile)" = power-saver ]
  mujo undo
  run mujo power profile --json
  [ "$(data .profile)" = balanced ]
  run mujo power profile turbo
  [ "$status" -eq 2 ]
}

@test "power lock needs the graphical session" {
  run mujo power lock
  [ "$status" -eq 3 ]
}

# ---- commands that need a session or a terminal ---------------------------------

@test "shot, keys and --window exit 3 without a session" {
  run mujo shot screen
  [ "$status" -eq 3 ]
  run mujo keys
  [ "$status" -eq 3 ]
  run mujo menu --window
  [ "$status" -eq 3 ]
  run mujo shot region --geometry "not a rectangle"
  [ "$status" -eq 2 ]
  run mujo shot region --geometry "10,20 300x200" --dry-run --json
  [ "$status" -eq 0 ]
  run mujo shot window --dry-run --json
  [ "$status" -eq 0 ]
  [ "$(data .mode)" = window ]
}

@test "interactive commands refuse --json and need a terminal" {
  for c in "menu" "launch" "net tui" "clip"; do
    # shellcheck disable=SC2086  # two words on purpose
    run mujo $c --json </dev/null
    [ "$status" -eq 2 ]
    # shellcheck disable=SC2086
    run mujo $c </dev/null
    [ "$status" -eq 3 ]
  done
}

# ---- clipboard ---------------------------------------------------------------

@test "clip list and clear" {
  run mujo clip list --json
  [ "$(data '.entries | length')" = 2 ]
  [ "$(data '.entries[0].preview')" = "second entry" ]
  run mujo clip copy 2
  [ "$status" -eq 3 ]
  run mujo clip copy second
  [ "$status" -eq 2 ]
  run mujo clip clear
  [ "$status" -eq 2 ]
  mujo clip clear --yes
  run mujo clip list --json
  [ "$(data '.entries | length')" = 0 ]
}

# ---- launcher ----------------------------------------------------------------

@test "launch list reads desktop entries, hides hidden ones and prefers the user's" {
  export XDG_DATA_HOME=$BATS_TEST_TMPDIR/data XDG_DATA_DIRS=$BATS_TEST_TMPDIR/sys
  mkdir -p "$XDG_DATA_HOME/applications" "$XDG_DATA_DIRS/applications"
  printf '[Desktop Entry]\nType=Application\nName=Editor\nComment=Edit text\nExec=editor --new %%F\n\n[Desktop Action x]\nName=Wrong\nExec=wrong\n' \
    >"$XDG_DATA_DIRS/applications/editor.desktop"
  printf '[Desktop Entry]\nType=Application\nName=Secret\nExec=secret\nNoDisplay=true\n' \
    >"$XDG_DATA_DIRS/applications/secret.desktop"
  printf '[Desktop Entry]\nType=Application\nName=Other DE\nExec=other\nOnlyShowIn=GNOME;\n' \
    >"$XDG_DATA_DIRS/applications/other.desktop"
  printf '[Desktop Entry]\nType=Application\nName=Top\nExec=top\nTerminal=true\n' \
    >"$XDG_DATA_DIRS/applications/top.desktop"
  printf '[Desktop Entry]\nType=Application\nName=My Top\nExec=mytop\nTerminal=true\n' \
    >"$XDG_DATA_HOME/applications/top.desktop"

  run mujo launch list --json
  [ "$status" -eq 0 ]
  [ "$(data '[.apps[].id] | sort | join(" ")')" = "editor top" ]
  [ "$(data '.apps[] | select(.id == "editor") | .exec')" = "editor --new" ]
  [ "$(data '.apps[] | select(.id == "top") | .name')" = "My Top" ]
  [ "$(data '.apps[] | select(.id == "top") | .terminal')" = true ]

  run mujo launch run top --dry-run
  [ "$status" -eq 0 ]
  [[ $output == *"Would run: ghostty -e mytop"* ]]
  run mujo launch run editor
  [ "$status" -eq 3 ]
  run mujo launch run missing
  [ "$status" -eq 1 ]
}

@test "sys reports counters and percentages" {
  run mujo sys --json
  [ "$status" -eq 0 ]
  [ "$(data '.cpu.total > .cpu.idle')" = true ]
  [ "$(data '.memory.percent >= 0 and .memory.percent <= 100')" = true ]
  [ "$(data '.uptime_s > 0')" = true ]
  run mujo sys --window
  [ "$status" -eq 3 ]
}

@test "pkg list names the packages and marks installed ones; the pickers need a terminal" {
  run mujo pkg list --json
  [ "$status" -eq 0 ]
  [ "$(data '[.packages[] | select(.installed) | .name] | sort | join(" ")')" = "bash jq linux" ]
  [ "$(data '.packages[] | select(.name == "firefox") | .installed')" = false ]
  [ "$(data '.packages[] | select(.source == "aur") | .name')" = some-aur-tool ]
  run mujo pkg install </dev/null
  [ "$status" -eq 3 ]
  run mujo pkg remove --json
  [ "$status" -eq 2 ]
}

@test "sys activity lists the latest changes, the battery's day and the captures" {
  run mujo audio volume +15
  mkdir -p "$XDG_PICTURES_DIR/Screenshots" "$MUJO_SYSROOT/var/lib/upower"
  : >"$XDG_PICTURES_DIR/Screenshots/mujo-20261114-224524.png"
  now=$(date +%s)
  printf '%s\t%s\t%s\n' $((now - 90000)) 80.000 discharging $((now - 3600)) 40.000 discharging $((now - 60)) 55.000 charging \
    >"$MUJO_SYSROOT/var/lib/upower/history-charge-TEST.dat"
  run mujo sys activity --json
  [ "$status" -eq 0 ]
  [[ "$(data '.changes[0].summary')" == "audio volume:"* ]]
  [ "$(data '.changes[0].reversible')" = true ]
  # only the last 24 hours of the battery's record
  [ "$(data '.battery | length')" -eq 2 ]
  [ "$(data '.battery[-1][1]')" -eq 55 ]
  [ "$(data '.captures[0].kind')" = screenshot ]
  [[ "$(data '.captures[0].path')" == */mujo-20261114-224524.png ]]
  run mujo sys --json
  [ "$(data .net)" = null ]
}

@test "shot copy and open want an existing file" {
  run mujo shot copy
  [ "$status" -eq 2 ]
  run mujo shot open /nonexistent.png
  [ "$status" -eq 1 ]
  : >"$BATS_TEST_TMPDIR/a.png"
  run mujo shot copy "$BATS_TEST_TMPDIR/a.png" --dry-run --json
  [ "$status" -eq 0 ]
  [ "$(data .done)" = false ]
  run mujo shot folder recordings --dry-run --json
  [ "$(data .folder)" = "$XDG_VIDEOS_DIR/Recordings" ]
  run mujo shot folder --dry-run --json
  [ "$(data .folder)" = "$XDG_PICTURES_DIR/Screenshots" ]
  run mujo shot folder elsewhere
  [ "$status" -eq 2 ]
}

@test "about reports the machine, the health check and the latest changes" {
  run mujo audio volume +15
  [ "$status" -eq 0 ]
  run mujo about --json
  [ "$status" -eq 0 ]
  [ "$(data .mujo.version)" = "$(mujo version | awk '{ print $2 }')" ]
  [ "$(data .kernel)" = "$(uname -r)" ]
  [ "$(data .packages)" -eq 3 ]
  [ "$(data '.doctor | has("failed")')" = true ]
  [ "$(data .updates)" = null ]
  [ "$(data .snapshot)" = null ]
  [[ "$(data '.recent[0].summary')" == "audio volume:"* ]]
  [ "$(data '.recent[0].reversible')" = true ]
  # after a count of the pending updates, about has it too
  run mujo update check --json
  run mujo about --json
  [ "$(data .updates.count)" -eq 2 ]
  run mujo about
  [[ $output == *"Kernel"* && $output == *"Latest changes:"* ]]
}

# ---- doctor and update --------------------------------------------------------

@test "doctor reports what is missing and exits 1" {
  export HOME=$BATS_TEST_TMPDIR/home
  mkdir -p "$HOME"
  run mujo doctor --json
  [ "$status" -eq 1 ]
  [ "$(data .ok)" = false ]
  [ "$(data '.checks[] | select(.group == "links") | .status')" = fail ]
  [ "$(data '.checks[] | select(.group == "packages") | .status')" = ok ]
  [ "$(data '.checks[] | select(.group == "session") | .status')" = skip ]
  [[ $(data '.checks[] | select(.group == "theme") | .fix') == *"theme build"* ]]
}

@test "update --dry-run lists pending packages and changes nothing" {
  run mujo update --dry-run --json
  [ "$status" -eq 0 ]
  [ "$(data '.system.packages | length')" = 2 ]
  [ "$(journal_count)" -eq 0 ]
  grep -q "linux 7.3.4-1" "$STUB_STATE/packages"
}

@test "update upgrades the system, reports it and recommends a reboot for a new kernel" {
  run mujo update --system-only </dev/null
  [ "$status" -eq 2 ]
  # --system-only: the test must never run git pull in the real checkout
  # pacman's own output goes to stderr in --json mode; stdout is the JSON alone
  output=$(mujo update --system-only --yes --json 2>/dev/null </dev/null)
  [ "$(data '.system.packages | join(" ")')" = "jq linux" ]
  # AUR packages are updated through the helper
  grep -q -- "-Sua --noconfirm" "$STUB_STATE/yay.log"
  [ "$(data .reboot_recommended)" = true ]
  run mujo log --json
  [ "$(data '.entries[0].reversible')" = false ]
  # no snapper configuration for /: no snapshot, and snapper is never called
  [ ! -e "$STUB_STATE/snapper.log" ]
}

snapper_config() {
  mkdir -p "$MUJO_SYSROOT/etc/snapper/configs"
  printf '%s\n' 'SUBVOLUME="/home"' >"$MUJO_SYSROOT/etc/snapper/configs/home"
  printf '%s\n' '# root' 'SUBVOLUME="/"' 'FSTYPE="btrfs"' >"$MUJO_SYSROOT/etc/snapper/configs/root"
}

@test "update takes a snapshot before and after when snapper covers /" {
  snapper_config
  run mujo update --system-only --dry-run
  [[ $output == *"Snapshot: one before and one after"* ]]
  [ ! -e "$STUB_STATE/snapper.log" ]
  output=$(mujo update --system-only --yes --json 2>/dev/null </dev/null)
  [ "$(data .snapshot.config)" = root ]
  [ "$(data .snapshot.pre)" = 41 ]
  [ "$(data .snapshot.post)" = 42 ]
  [ "$(sed -n 1p "$STUB_STATE/snapper.log")" = "-c root create --type pre --cleanup-algorithm number --print-number --description mujo update" ]
  [[ $(sed -n 2p "$STUB_STATE/snapper.log") == "-c root create --type post --pre-number 41 "*"2 package(s)" ]]
  [ "$(jq -r '.packages | join(" ")' "$(state)/update-snapshot.json")" = "jq linux" ]
  run mujo update snapshots
  [ "$status" -eq 0 ]
  [[ $output == *"41 | 41 | 42"* ]]
}

@test "update --no-snapshot skips the snapshots, and a failing snapper does not stop the update" {
  snapper_config
  output=$(mujo update --system-only --no-snapshot --yes --json 2>/dev/null </dev/null)
  [ "$(data .snapshot)" = null ]
  [ ! -e "$STUB_STATE/snapper.log" ]
  touch "$STUB_STATE/snapper.fail"
  rm -f "$STUB_STATE/packages"
  output=$(mujo update --system-only --yes --json 2>/dev/null </dev/null)
  [ "$(data .snapshot)" = null ]
  [ "$(data '.system.packages | join(" ")')" = "jq linux" ]
  [ ! -e "$(state)/update-snapshot.json" ]
}

@test "update rollback undoes the last update's changes and puts the kernel back in /boot" {
  snapper_config
  run mujo update rollback --yes
  [ "$status" -eq 1 ]
  [[ $output == *"no update with snapshots"* ]]
  mujo update --system-only --yes >/dev/null 2>&1 </dev/null
  mkdir -p "$MUJO_SYSROOT/usr/lib/modules/7.3.4-arch1-1" "$MUJO_SYSROOT/boot"
  echo old-kernel >"$MUJO_SYSROOT/usr/lib/modules/7.3.4-arch1-1/vmlinuz"
  echo linux >"$MUJO_SYSROOT/usr/lib/modules/7.3.4-arch1-1/pkgbase"
  echo new-kernel >"$MUJO_SYSROOT/boot/vmlinuz-linux"
  run mujo update rollback
  [ "$status" -eq 2 ]
  run mujo update rollback --dry-run
  [ "$status" -eq 0 ]
  [[ $output == *"undochange 41..42"* ]]
  ! grep -q undochange "$STUB_STATE/snapper.log"
  output=$(mujo update rollback --yes --json 2>/dev/null)
  [ "$(data '.kernels | join(" ")')" = linux ]
  [ "$(data .reboot_recommended)" = true ]
  grep -qx -- "-c root undochange 41..42" "$STUB_STATE/snapper.log"
  [ "$(cat "$MUJO_SYSROOT/boot/vmlinuz-linux")" = old-kernel ]
  [ "$(cat "$STUB_STATE/mkinitcpio.log")" = "-P" ]
  [ ! -e "$(state)/update-snapshot.json" ]
  # a pair can be named; a malformed one is a usage error
  run mujo update rollback 7..9 --yes
  [ "$status" -eq 0 ]
  grep -qx -- "-c root undochange 7..9" "$STUB_STATE/snapper.log"
  run mujo update rollback 9..7 --yes
  [ "$status" -eq 2 ]
  run mujo update rollback nine --yes
  [ "$status" -eq 2 ]
}

# ---- menu and status ---------------------------------------------------------

@test "every menu entry points at a real command" {
  run mujo menu list --json
  [ "$status" -eq 0 ]
  while IFS= read -r c; do
    run mujo help "$c"
    [ "$status" -eq 0 ]
  done < <(data '.entries[] | select(.kind != "app") | .command | split(" ")[0]' | sort -u)
}

@test "status has every section, and null for what is not available" {
  run mujo status --json
  [ "$status" -eq 0 ]
  [ "$(data 'keys | join(" ")')" = "audio battery bluetooth display network session theme wallpaper" ]
  [ "$(data .audio.output.volume)" = 40 ]
  [ "$(data .network.wifi.ssid)" = HomeNet ]
  [ "$(data .theme.accent)" = mauve ]
  [ "$(data .session.wayland)" = false ]

  # Without the backends on PATH the sections are null and the command still works.
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  for tool in bash jq flock cat rm date mktemp dirname readlink env wc sort head sed awk gawk; do
    ln -s "$(command -v "$tool")" "$BATS_TEST_TMPDIR/bin/$tool"
  done
  PATH=$BATS_TEST_TMPDIR/bin run "$MUJO" status --json
  [ "$status" -eq 0 ]
  [ "$(data .audio)" = null ]
  [ "$(data .network)" = null ]
  [ "$(data .bluetooth)" = null ]
}

@test "services lists what is enabled, one line for a service and its socket" {
  run mujo services --json
  [ "$(data '.services | length')" = 0 ]
  printf '%s\n' "docker.socket active Docker Socket" "docker.service inactive Docker Engine" \
    "tailscaled.service active Tailscale node agent" "sshd.service failed OpenSSH Daemon" \
    "cups.service inactive CUPS Scheduler" "NetworkManager.service active Network Manager" \
    "systemd-timesyncd.service active Network Time" "getty@.service inactive Getty" >"$STUB_STATE/units"
  run mujo services --json
  [ "$(data '[.services[].name] | join(" ")')" = "cups docker sshd tailscaled" ]
  [ "$(data '.services[] | select(.name == "docker") | .state')" = ready ]
  [ "$(data '.services[] | select(.name == "docker") | .units | join(" ")')" = "docker.service docker.socket" ]
  [ "$(data '.services[] | select(.name == "tailscaled") | .state')" = running ]
  [ "$(data '.services[] | select(.name == "sshd") | .state')" = failed ]
  [ "$(data '.services[] | select(.name == "cups") | .state')" = stopped ]
  run mujo services
  [[ $output == *"docker      ready (starts on first use)"* ]]
  run mujo services extra
  [ "$status" -eq 2 ]
}
