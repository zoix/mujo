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
  for c in status audio net bt display wall power shot clip launch menu keys; do
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
  [ "$(data .journal_id)" != null ]
  run karma undo
  [ "$status" -eq 0 ]
  run karma audio volume --json
  [ "$(data .volume)" = 40 ]
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
