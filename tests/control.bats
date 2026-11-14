#!/usr/bin/env bats
# The control-plane commands (phase 2), run against the test doubles in
# tests/stubs so that nothing touches the real audio, network or backlight.

load helpers

setup() {
  karma_test_env
  use_stubs
}

journal_count() {
  if [[ -f $(state)/journal.jsonl ]]; then wc -l <"$(state)/journal.jsonl"; else echo 0; fi
}

# ---- shared plumbing ---------------------------------------------------------

@test "json_array keeps arguments that look like options" {
  run bash -c "source '$KARMA_REPO/lib/core.sh'; json_array display night on --temp 3500"
  [ "$status" -eq 0 ]
  [ "$output" = '["display","night","on","--temp","3500"]' ]
}

@test "step_value resolves absolute and relative values and clamps" {
  run bash -c "source '$KARMA_REPO/lib/core.sh'; step_value +5 40 0 100; step_value -50 40 0 100; step_value 70% 40 0 100; step_value +90 40 0 100"
  [ "$output" = $'45\n0\n70\n100' ]
  run bash -c "source '$KARMA_REPO/lib/core.sh'; step_value loud 40 0 100"
  [ "$status" -ne 0 ]
}

@test "every command has help" {
  for c in status audio net bt display wall dnd power shot clip launch menu keys sys pkg doctor update uninstall; do
    run karma help "$c"
    [ "$status" -eq 0 ]
    [[ $output == "Usage: karma $c"* ]]
  done
}

# ---- audio -------------------------------------------------------------------

@test "audio status reports levels and devices" {
  run karma audio --json
  [ "$status" -eq 0 ]
  [ "$(data .output.volume)" = 40 ]
  [ "$(data .output.device)" = Speaker ]
  [ "$(data '.outputs | length')" = 2 ]
  [ "$(data '.inputs[0].name')" = alsa_input.mic ]
}

@test "audio volume changes, is journaled, and undo restores it" {
  run karma audio volume +15 --json
  [ "$status" -eq 0 ]
  [ "$(data .before.volume)" = 40 ]
  [ "$(data .after.volume)" = 55 ]
  [ "$(data .after.muted)" = false ]
  [ "$(data .journal_id)" != null ]
  run karma undo
  [ "$status" -eq 0 ]
  run karma audio volume --json
  [ "$(data .volume)" = 40 ]
}

@test "raising the volume unmutes, lowering does not, and undo restores both" {
  karma audio mute on
  run karma audio volume -10 --json
  [ "$(data .after.muted)" = true ]
  run karma audio volume +20 --json
  [ "$(data .after.volume)" = 50 ]
  [ "$(data .after.muted)" = false ]
  karma undo
  run karma audio --json
  [ "$(data .output.volume)" = 30 ]
  [ "$(data .output.muted)" = true ]
}

@test "audio volume --dry-run shows a diff and changes nothing" {
  run karma audio volume 80 --dry-run
  [ "$status" -eq 0 ]
  [[ $output == *'-  "volume": 40'* ]]
  [[ $output == *'+  "volume": 80'* ]]
  [ "$(journal_count)" -eq 0 ]
  run karma audio volume --json
  [ "$(data .volume)" = 40 ]
}

@test "audio volume clamps at 100, ignores a no-op and rejects nonsense" {
  run karma audio volume +500 --json
  [ "$(data .after.volume)" = 100 ]
  run karma audio volume 100 --json
  [ "$(data .changed)" = false ]
  [ "$(journal_count)" -eq 1 ]
  run karma audio volume loud
  [ "$status" -eq 2 ]
}

@test "audio mute --input mutes only the microphone, and undo unmutes it" {
  run karma audio mute --input --json
  [ "$(data .after.muted)" = true ]
  run karma audio --json
  [ "$(data .input.muted)" = true ]
  [ "$(data .output.muted)" = false ]
  karma undo
  run karma audio --json
  [ "$(data .input.muted)" = false ]
}

@test "audio output switches the default device by name and undo switches back" {
  run karma audio output alsa_output.hdmi
  [ "$status" -eq 0 ]
  run karma audio --json
  [ "$(data .output.device)" = HDMI ]
  karma undo
  run karma audio --json
  [ "$(data .output.device)" = Speaker ]
  run karma audio output nothing-like-this
  [ "$status" -eq 1 ]
}

# ---- display -----------------------------------------------------------------

@test "display brightness changes, never goes below 1, and undo restores it" {
  run karma display brightness -200 --json
  [ "$(data .before.brightness)" = 50 ]
  [ "$(data .after.brightness)" = 1 ]
  karma undo
  run karma display brightness --json
  [ "$(data .percent)" = 50 ]
}

@test "display night needs a Hyprland session" {
  run karma display night on
  [ "$status" -eq 3 ]
  run karma display --json
  [ "$status" -eq 0 ]
  [ "$(data .night)" = null ]
}

# ---- wallpaper ---------------------------------------------------------------

@test "wall set, next, clear and undo" {
  walls=$BATS_TEST_TMPDIR/walls
  mkdir -p "$walls"
  touch "$walls/a.png" "$walls/b.jpg" "$walls/notes.txt"
  karma wall dir "$walls"
  run karma wall --json
  [ "$(data .available)" = 2 ]
  [ "$(data .wallpaper)" = null ]

  karma wall next
  run karma wall --json
  [ "$(data .wallpaper)" = "$walls/a.png" ]
  karma wall next
  karma wall next
  run karma wall --json
  [ "$(data .wallpaper)" = "$walls/a.png" ]
  karma wall prev
  run karma wall --json
  [ "$(data .wallpaper)" = "$walls/b.jpg" ]

  karma undo
  run karma wall --json
  [ "$(data .wallpaper)" = "$walls/a.png" ]

  run karma wall set "$walls/notes.txt"
  [ "$status" -eq 1 ]
  karma wall clear
  run karma wall --json
  [ "$(data .wallpaper)" = null ]
}

# ---- light and dark mode ----------------------------------------------------------

@test "theme mode light rebuilds with the light palette and undo returns to dark" {
  karma theme build
  run karma theme mode --json
  [ "$(data .mode)" = dark ]
  [ "$(data .preference)" = auto ]
  dark_bg=$(karma theme show color.bg.base --json | jq -r .data.value)

  karma theme mode light
  light_bg=$(karma theme show color.bg.base --json | jq -r .data.value)
  [ "$dark_bg" != "$light_bg" ]
  grep -q "$light_bg" "$(conf)/kitty/karma-theme.conf"
  grep -q 'gtk-application-prefer-dark-theme=0' "$(conf)/gtk-3.0/settings.ini"
  run karma theme check
  [ "$status" -eq 0 ]

  karma undo
  run karma theme mode --json
  [ "$(data .mode)" = dark ]
  [ "$(data .preference)" = auto ]
  run karma theme mode sepia
  [ "$status" -eq 2 ]
}

@test "theme motion gentle slows every duration and tells Hyprland to fade" {
  karma theme build
  normal=$(jq .durationNormal "$(conf)/quickshell/karma/theme/tokens.json")
  karma theme motion gentle
  gentle=$(jq .durationNormal "$(conf)/quickshell/karma/theme/tokens.json")
  [ "$gentle" -gt "$normal" ]
  grep -q 'gentle = true' "$(conf)/hypr/karma_tokens.lua"
  karma undo
  [ "$(jq .durationNormal "$(conf)/quickshell/karma/theme/tokens.json")" = "$normal" ]
  run karma theme motion fast
  [ "$status" -eq 2 ]
}

@test "the console palette for /etc is the same in light and dark mode" {
  karma theme build
  before=$(sha256sum <"$(state)/theme/system/vtrgb/palette.vtrgb")
  karma theme mode light
  [ "$before" = "$(sha256sum <"$(state)/theme/system/vtrgb/palette.vtrgb")" ]
}

@test "with mode auto a bright wallpaper switches to light, and undoing it switches back" {
  walls=$BATS_TEST_TMPDIR/walls
  mkdir -p "$walls"
  touch "$walls/bright-sky.png" "$walls/night.png"
  karma theme build

  karma wall set "$walls/night.png"
  run karma theme mode --json
  [ "$(data .mode)" = dark ]

  run karma wall set "$walls/bright-sky.png"
  [ "$status" -eq 0 ]
  [[ $output == *"mode dark -> light"* ]]
  run karma theme mode --json
  [ "$(data .mode)" = light ]

  # undo skips the automatic mode entry and reverts the wallpaper, which syncs the mode
  karma undo
  run karma wall --json
  [ "$(data .wallpaper)" = "$walls/night.png" ]
  run karma theme mode --json
  [ "$(data .mode)" = dark ]
}

@test "with the accent on auto it follows the wallpaper's colour; a chosen accent stays" {
  walls=$BATS_TEST_TMPDIR/walls
  mkdir -p "$walls"
  touch "$walls/blue-lake.png" "$walls/grey.png"
  karma theme build
  run karma theme accent --json
  [ "$(data .accent)" = mauve ]
  [ "$(data .preference)" = auto ]

  karma wall set "$walls/blue-lake.png"
  run karma theme accent --json
  [ "$(data .accent)" = blue ]
  # a grey image has no colour to follow: back to the default accent
  karma wall set "$walls/grey.png"
  run karma theme accent --json
  [ "$(data .accent)" = mauve ]

  karma theme accent green
  karma wall set "$walls/blue-lake.png"
  run karma theme accent --json
  [ "$(data .accent)" = green ]
  [ "$(data .preference)" = green ]
}

@test "wall list reports thumbnails once the folder is indexed" {
  walls=$BATS_TEST_TMPDIR/walls
  mkdir -p "$walls"
  touch "$walls/a.png"
  export XDG_CACHE_HOME=$BATS_TEST_TMPDIR/cache
  karma wall dir "$walls"
  run karma wall list --json
  [ "$(data '.images[0].name')" = a ]
  [ "$(data '.images[0].thumb')" = null ]
  karma wall index
  run karma wall list --json
  [ -f "$(data '.images[0].thumb')" ]
}

@test "menu run performs an entry without a terminal" {
  run karma menu run "Audio: mute or unmute"
  [ "$status" -eq 0 ]
  run karma audio --json
  [ "$(data .output.muted)" = true ]
  run karma menu run "No such entry"
  [ "$status" -eq 1 ]
  run karma menu list --json
  [ "$(data '[.entries[] | select(.command == "theme accent blue")] | length')" = 1 ]
}

@test "the wallpaper palette tints the colours with the wallpaper's hue and follows it" {
  walls=$BATS_TEST_TMPDIR/walls
  mkdir -p "$walls"
  touch "$walls/blue-lake.png" "$walls/grey.png"
  karma theme build
  tokens=$(conf)/quickshell/karma/theme/tokens.json
  plain=$(jq -r .bgBase "$tokens")
  console=$(sha256sum <"$(state)/theme/system/vtrgb/palette.vtrgb")
  karma wall set "$walls/blue-lake.png"

  karma theme palette wallpaper
  run karma theme palette --json
  [ "$(data .palette)" = wallpaper ]
  [ "$(data '.hue >= 200 and .hue <= 240')" = true ]
  tinted=$(jq -r .bgBase "$tokens")
  [ "$tinted" != "$plain" ]
  [ "$(jq -r .accentName "$tokens")" = wallpaper ]
  # errors stay red, and the console palette in /etc is not affected
  [ "$(jq -r .stateError "$tokens")" = "#f38ba8" ]
  [ "$console" = "$(sha256sum <"$(state)/theme/system/vtrgb/palette.vtrgb")" ]
  run karma theme check
  [ "$status" -eq 0 ]

  # a grey wallpaper has no hue to use: the plain colours come back
  karma wall set "$walls/grey.png"
  [ "$(jq -r .bgBase "$tokens")" = "$plain" ]
  karma wall set "$walls/blue-lake.png"
  [ "$(jq -r .bgBase "$tokens")" = "$tinted" ]

  karma theme palette catppuccin
  [ "$(jq -r .bgBase "$tokens")" = "$plain" ]
  [ "$(jq -r .accentName "$tokens")" = blue ]
  run karma theme palette neon
  [ "$status" -eq 2 ]
}

@test "a fixed mode ignores the wallpaper" {
  walls=$BATS_TEST_TMPDIR/walls
  mkdir -p "$walls"
  touch "$walls/bright-sky.png"
  karma theme build
  karma theme mode dark
  karma wall set "$walls/bright-sky.png"
  run karma theme mode --json
  [ "$(data .mode)" = dark ]
  [ "$(data .preference)" = dark ]
  karma theme mode auto
  run karma theme mode --json
  [ "$(data .mode)" = light ]
}

# ---- do not disturb ------------------------------------------------------------

@test "dnd on, off and undo" {
  run karma dnd --json
  [ "$(data .dnd)" = false ]
  karma dnd on
  [ "$(jq -r .dnd "$(conf)/karma/config.json")" = true ]
  karma undo
  run karma dnd --json
  [ "$(data .dnd)" = false ]
  run karma dnd maybe
  [ "$status" -eq 2 ]
}

# ---- network -----------------------------------------------------------------

@test "net status and scan" {
  run karma net --json
  [ "$status" -eq 0 ]
  [ "$(data .wifi.ssid)" = HomeNet ]
  [ "$(data .wifi.signal)" = 80 ]
  run karma net scan --json
  [ "$(data '.networks | length')" = 3 ]
  [ "$(data '.networks[0].ssid')" = HomeNet ]
  [ "$(data '.networks[0].signal')" = 80 ]
  [ "$(data '.networks[] | select(.security == "open") | .ssid')" = "Open:Net" ]
  [ "$(data '.networks[] | select(.ssid == "Cafe") | .saved')" = true ]
}

@test "net connect is undoable and returns to the previous network" {
  run karma net connect Cafe
  [ "$status" -eq 0 ]
  run karma net --json
  [ "$(data .wifi.ssid)" = Cafe ]
  karma undo
  run karma net --json
  [ "$(data .wifi.ssid)" = HomeNet ]
}

@test "net connect reads a password from stdin and never journals it" {
  run karma net connect Locked </dev/null
  [ "$status" -eq 1 ]
  run bash -c "echo hunter2 | '$KARMA' net connect Locked --password-stdin"
  [ "$status" -eq 0 ]
  ! grep -q hunter2 "$(state)/journal.jsonl"
}

@test "net forget needs --yes and cannot be undone" {
  run karma net forget Cafe
  [ "$status" -eq 2 ]
  run karma net forget Cafe --yes --json
  [ "$status" -eq 0 ]
  run karma log --json
  [ "$(data '.entries[0].reversible')" = false ]
  run karma net forget Cafe --yes
  [ "$status" -eq 1 ]
}

@test "net wifi off and undo" {
  karma net wifi off
  run karma net wifi --json
  [ "$(data .wifi_enabled)" = false ]
  karma undo
  run karma net wifi --json
  [ "$(data .wifi_enabled)" = true ]
}

# ---- bluetooth ---------------------------------------------------------------

@test "bt status, power off and undo" {
  run karma bt --json
  [ "$(data .powered)" = true ]
  [ "$(data '.devices | length')" = 2 ]
  [ "$(data '.devices[] | select(.connected) | .name')" = Mouse ]
  [ "$(data '.devices[0].name')" = "Head Phones" ]
  karma bt power toggle
  run karma bt power --json
  [ "$(data .powered)" = false ]
  karma undo
  run karma bt power --json
  [ "$(data .powered)" = true ]
}

# ---- power -------------------------------------------------------------------

@test "power reboot needs --yes; --dry-run shows the command" {
  run karma power reboot
  [ "$status" -eq 2 ]
  [ ! -e "$STUB_STATE/systemctl.log" ]
  run karma power reboot --dry-run --json
  [ "$status" -eq 0 ]
  [ "$(data '.command | join(" ")')" = "systemctl reboot" ]
  [ ! -e "$STUB_STATE/systemctl.log" ]
}

@test "power suspend and shutdown --yes run systemctl and are journaled" {
  karma power suspend
  karma power shutdown --yes
  [ "$(cat "$STUB_STATE/systemctl.log")" = $'suspend\npoweroff' ]
  run karma log --json
  [ "$(data '.entries[0].summary')" = "power shutdown" ]
  [ "$(data '.entries[0].reversible')" = false ]
}

@test "power lock needs the graphical session" {
  run karma power lock
  [ "$status" -eq 3 ]
}

# ---- commands that need a session or a terminal ---------------------------------

@test "shot, keys and --window exit 3 without a session" {
  run karma shot screen
  [ "$status" -eq 3 ]
  run karma keys
  [ "$status" -eq 3 ]
  run karma menu --window
  [ "$status" -eq 3 ]
  run karma shot window --dry-run --json
  [ "$status" -eq 0 ]
  [ "$(data .mode)" = window ]
}

@test "interactive commands refuse --json and need a terminal" {
  for c in "menu" "launch" "net tui" "clip"; do
    # shellcheck disable=SC2086  # two words on purpose
    run karma $c --json </dev/null
    [ "$status" -eq 2 ]
    # shellcheck disable=SC2086
    run karma $c </dev/null
    [ "$status" -eq 3 ]
  done
}

# ---- clipboard ---------------------------------------------------------------

@test "clip list and clear" {
  run karma clip list --json
  [ "$(data '.entries | length')" = 2 ]
  [ "$(data '.entries[0].preview')" = "second entry" ]
  run karma clip copy 2
  [ "$status" -eq 3 ]
  run karma clip copy second
  [ "$status" -eq 2 ]
  run karma clip clear
  [ "$status" -eq 2 ]
  karma clip clear --yes
  run karma clip list --json
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

  run karma launch list --json
  [ "$status" -eq 0 ]
  [ "$(data '[.apps[].id] | sort | join(" ")')" = "editor top" ]
  [ "$(data '.apps[] | select(.id == "editor") | .exec')" = "editor --new" ]
  [ "$(data '.apps[] | select(.id == "top") | .name')" = "My Top" ]
  [ "$(data '.apps[] | select(.id == "top") | .terminal')" = true ]

  run karma launch run top --dry-run
  [ "$status" -eq 0 ]
  [[ $output == *"Would run: kitty -e mytop"* ]]
  run karma launch run editor
  [ "$status" -eq 3 ]
  run karma launch run missing
  [ "$status" -eq 1 ]
}

@test "sys reports counters and percentages" {
  run karma sys --json
  [ "$status" -eq 0 ]
  [ "$(data '.cpu.total > .cpu.idle')" = true ]
  [ "$(data '.memory.percent >= 0 and .memory.percent <= 100')" = true ]
  [ "$(data '.uptime_s > 0')" = true ]
  run karma sys --window
  [ "$status" -eq 3 ]
}

@test "pkg list names the packages and marks installed ones; the pickers need a terminal" {
  run karma pkg list --json
  [ "$status" -eq 0 ]
  [ "$(data '[.packages[] | select(.installed) | .name] | sort | join(" ")')" = "bash jq linux" ]
  [ "$(data '.packages[] | select(.name == "firefox") | .installed')" = false ]
  [ "$(data '.packages[] | select(.source == "aur") | .name')" = some-aur-tool ]
  run karma pkg install </dev/null
  [ "$status" -eq 3 ]
  run karma pkg remove --json
  [ "$status" -eq 2 ]
}

# ---- doctor and update --------------------------------------------------------

@test "doctor reports what is missing and exits 1" {
  export HOME=$BATS_TEST_TMPDIR/home
  mkdir -p "$HOME"
  run karma doctor --json
  [ "$status" -eq 1 ]
  [ "$(data .ok)" = false ]
  [ "$(data '.checks[] | select(.group == "links") | .status')" = fail ]
  [ "$(data '.checks[] | select(.group == "packages") | .status')" = ok ]
  [ "$(data '.checks[] | select(.group == "session") | .status')" = skip ]
  [[ $(data '.checks[] | select(.group == "theme") | .fix') == *"theme build"* ]]
}

@test "update --dry-run lists pending packages and changes nothing" {
  run karma update --dry-run --json
  [ "$status" -eq 0 ]
  [ "$(data '.system.packages | length')" = 2 ]
  [ "$(journal_count)" -eq 0 ]
  grep -q "linux 7.3.4-1" "$STUB_STATE/packages"
}

@test "update upgrades the system, reports it and recommends a reboot for a new kernel" {
  run karma update --system-only </dev/null
  [ "$status" -eq 2 ]
  # pacman's own output goes to stderr in --json mode; stdout is the JSON alone
  output=$(karma update --yes --json 2>/dev/null </dev/null)
  [ "$(data '.system.packages | join(" ")')" = "jq linux" ]
  # AUR packages are updated through the helper
  grep -q -- "-Sua --noconfirm" "$STUB_STATE/yay.log"
  [ "$(data .reboot_recommended)" = true ]
  run karma log --json
  [ "$(data '.entries[0].reversible')" = false ]
}

# ---- menu and status ---------------------------------------------------------

@test "every menu entry points at a real command" {
  run karma menu list --json
  [ "$status" -eq 0 ]
  while IFS= read -r c; do
    run karma help "$c"
    [ "$status" -eq 0 ]
  done < <(data '.entries[] | select(.kind != "app") | .command | split(" ")[0]' | sort -u)
}

@test "status has every section, and null for what is not available" {
  run karma status --json
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
  PATH=$BATS_TEST_TMPDIR/bin run "$KARMA" status --json
  [ "$status" -eq 0 ]
  [ "$(data .audio)" = null ]
  [ "$(data .network)" = null ]
  [ "$(data .bluetooth)" = null ]
}
