#!/usr/bin/env bats
# Battery care, focus timer, weather, pending updates, calculator, emoji and
# recording: everything external is a test double from tests/stubs.

load helpers

setup() {
  mujo_test_env
  use_stubs
}

mujo() { "$MUJO" "$@"; }

@test "power limit: framework_tool sets it, undo restores, bad values are refused" {
  run mujo power limit --json
  [ "$(data .limit)" = 100 ]
  [ "$(data .method)" = framework_tool ]
  mujo power limit 80
  [ "$(<"$STUB_STATE/charge-limit")" = 80 ]
  run mujo power limit --json
  [ "$(data .limit)" = 80 ]
  mujo undo
  [ "$(<"$STUB_STATE/charge-limit")" = 100 ]
  run mujo power limit 30
  [ "$status" -eq 2 ]
  run mujo power limit lots
  [ "$status" -eq 2 ]
}

@test "power limit: the kernel's threshold file is used when there is one" {
  bat=$MUJO_SYSROOT/sys/class/power_supply/BAT1
  mkdir -p "$bat"
  echo 100 >"$bat/charge_control_end_threshold"
  run mujo power limit --json
  [ "$(data .method)" = kernel ]
  mujo power limit 75
  [ "$(<"$bat/charge_control_end_threshold")" = 75 ]
  [ ! -e "$STUB_STATE/charge-limit" ]
}

@test "power auto: the profile follows the charger only while it is on" {
  ac=$MUJO_SYSROOT/sys/class/power_supply/ACAD
  mkdir -p "$ac"
  echo Mains >"$ac/type"
  echo 0 >"$ac/online"
  run mujo power sync --json
  [ "$(data .auto)" = false ]
  [ "$(mujo power profile --json | jq -r .data.profile)" = balanced ]
  mujo power auto on
  [ "$(mujo power profile --json | jq -r .data.profile)" = power-saver ]
  echo 1 >"$ac/online"
  run mujo power sync --json
  [ "$(data .changed)" = true ]
  [ "$(data .profile)" = balanced ]
  mujo undo
  run mujo power auto --json
  [ "$(data .auto)" = false ]
}

@test "power battery: solid panels and a lower refresh rate apply only on battery" {
  ac=$MUJO_SYSROOT/sys/class/power_supply/ACAD
  mkdir -p "$ac"
  echo Mains >"$ac/type"
  echo 0 >"$ac/online"
  export HYPRLAND_INSTANCE_SIGNATURE=test
  lua=$(state)/battery.lua
  run mujo power battery --json
  [ "$(data .refresh)" = false ]
  [ "$(data .solid)" = false ]
  run mujo power sync --json
  [ "$(data .battery.on_battery)" = true ]
  [ "$(data .battery.changed)" = false ]
  [ ! -e "$lua" ]
  # solid panels only matter while glass is on
  mujo power battery solid on
  [ ! -e "$lua" ]
  mujo theme glass on >/dev/null
  mujo power battery refresh on
  [ "$(cat "$lua")" = 'return { solid = true, monitor = { output = "eDP-1", mode = "2880x1920@60.00", position = "0x0", scale = "2" } }' ]
  grep -qx reload "$STUB_STATE/hyprctl.log"
  # asked again on battery, the mode chosen at first is kept
  echo 60 >"$STUB_STATE/refresh"
  run mujo power sync --json
  [ "$(data .battery.changed)" = false ]
  [ "$(data .battery.monitor.mode)" = "2880x1920@60.00" ]
  # the charger lifts both
  echo 1 >"$ac/online"
  run mujo power sync --json
  [ "$(data .battery.changed)" = true ]
  [ "$(data .battery.on_battery)" = false ]
  [ ! -e "$lua" ]
  [ "$(jq -r .battery_now "$XDG_CONFIG_HOME/mujo/config.json")" = null ]
  # each switch is journaled and can be undone
  mujo undo
  run mujo power battery refresh --json
  [ "$(data .refresh)" = false ]
  run mujo power battery glass on
  [ "$status" -eq 2 ]
}

@test "focus: start turns do-not-disturb on, stop puts it back" {
  run mujo focus --json
  [ "$(data .running)" = false ]
  mujo focus start 30
  run mujo focus --json
  [ "$(data .running)" = true ]
  [ "$(data .minutes_left)" = 30 ]
  [ "$(mujo dnd --json | jq -r .data.dnd)" = true ]
  grep -q -- '--on-active=30m' "$STUB_STATE/systemd-run.log"
  run mujo focus start
  [ "$status" -eq 1 ]
  mujo focus stop
  [ "$(mujo dnd --json | jq -r .data.dnd)" = false ]
  run mujo focus --json
  [ "$(data .running)" = false ]
  run mujo focus start 0
  [ "$status" -eq 2 ]
}

@test "focus: do-not-disturb that was already on stays on afterwards" {
  mujo dnd on
  mujo focus start 5
  mujo focus finish
  [ "$(mujo dnd --json | jq -r .data.dnd)" = true ]
  run mujo focus --json
  [ "$(data .running)" = false ]
}

@test "weather: nothing is asked until a place is set" {
  run mujo weather --json
  [ "$status" -eq 0 ]
  [ "$(data .set)" = false ]
  [ ! -e "$STUB_STATE/curl.log" ]
}

@test "weather: set, show from the cache, units, clear" {
  mujo weather set "Springfield, Oregon"
  [ "$(jq -r .weather.region "$XDG_CONFIG_HOME/mujo/config.json")" = "Oregon, United States" ]
  [ "$(jq -r .weather.lat "$XDG_CONFIG_HOME/mujo/config.json")" = 44.05 ]
  run mujo weather --json
  [ "$(data .temperature)" = 12 ]
  [ "$(data .description)" = "Light rain" ]
  [ "$(data .high)" = 14 ]
  asked=$(grep -c forecast "$STUB_STATE/curl.log")
  mujo weather
  [ "$(grep -c forecast "$STUB_STATE/curl.log")" = "$asked" ]
  mujo weather units f
  mujo weather
  grep -q 'temperature_unit=fahrenheit' "$STUB_STATE/curl.log"
  mujo weather clear
  run mujo weather --json
  [ "$(data .set)" = false ]
  run mujo weather set Nowhere
  [ "$status" -eq 1 ]
}

@test "weather: no network is an error, not a crash" {
  mujo weather set Springfield
  touch "$STUB_STATE/offline"
  run mujo weather --refresh
  [ "$status" -eq 1 ]
}

@test "update check counts pending packages and keeps the answer" {
  printf '%s\n' "linux 7.3.4-1 -> 7.3.5-1" "jq 1.8-1 -> 1.8.2-1" "bash 5.3-1 -> 5.3-2" >"$STUB_STATE/pending"
  run mujo update check --json
  [ "$(data .count)" = 3 ]
  [ "$(data '.repo[0]')" = linux ]
  : >"$STUB_STATE/pending"
  run mujo update check --json
  [ "$(data .count)" = 3 ]
  run mujo update check --refresh --json
  [ "$(data .count)" = 0 ]
}

@test "calc gives the result and fails on nonsense" {
  run mujo calc "6 * 7" --json
  [ "$(data .result)" = 42 ]
  run mujo calc 6 '*' 7
  [ "$output" = 42 ]
  run mujo calc what
  [ "$status" -eq 1 ]
  run mujo calc
  [ "$status" -eq 2 ]
}

@test "emoji list reads the Unicode file and leaves out skin tones" {
  run mujo emoji list
  [ "$status" -eq 3 ]
  dir=$MUJO_SYSROOT/usr/share/unicode/emoji
  mkdir -p "$dir"
  cat >"$dir/emoji-test.txt" <<'EOF'
# group: Smileys & Emotion
1F600                                                  ; fully-qualified     # 😀 E1.0 grinning face
263A                                                   ; unqualified         # ☺ E0.6 smiling face
1F44B 1F3FB                                            ; fully-qualified     # 👋🏻 E1.0 waving hand: light skin tone
1F1E8 1F1E6                                            ; fully-qualified     # 🇨🇦 E2.0 flag: Canada
EOF
  run mujo emoji list --json
  [ "$(data '.emoji | length')" = 2 ]
  [ "$(data '.emoji[0].name')" = "grinning face" ]
  [ "$(data '.emoji[1].emoji')" = "🇨🇦" ]
}

@test "record: status, a dry run, and needing a session" {
  run mujo record status --json
  [ "$(data .recording)" = false ]
  run mujo record start screen --dry-run --json
  [ "$(data .recording)" = false ]
  [[ "$(data .path)" == */videos/Recordings/mujo-*.mp4 ]]
  run mujo record start screen
  [ "$status" -eq 3 ]
  run mujo record stop
  [ "$status" -eq 1 ]
}

@test "record: start writes the file name down, stop ends the recorder" {
  export WAYLAND_DISPLAY=wayland-test XDG_RUNTIME_DIR=$BATS_TEST_TMPDIR/run
  mkdir -p "$XDG_RUNTIME_DIR"
  run mujo record start screen --dir "$BATS_TEST_TMPDIR/vid" --json
  [ "$status" -eq 0 ]
  [ "$(data .recording)" = true ]
  grep -q -- "-f $BATS_TEST_TMPDIR/vid/mujo-" "$STUB_STATE/wf-recorder.args"
  run mujo record status --json
  [ "$(data .recording)" = true ]
  run mujo record start screen
  [ "$status" -eq 1 ]
  run mujo record toggle --json
  [ "$(data .recording)" = false ]
  run mujo record status --json
  [ "$(data .recording)" = false ]
}

@test "shot text and term need a session" {
  run mujo shot text
  [ "$status" -eq 3 ]
  run mujo term
  [ "$status" -eq 3 ]
}
