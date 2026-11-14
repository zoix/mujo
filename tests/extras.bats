#!/usr/bin/env bats
# Battery care, focus timer, weather, pending updates, calculator, emoji and
# recording: everything external is a test double from tests/stubs.

load helpers

setup() {
  karma_test_env
  use_stubs
}

karma() { "$KARMA" "$@"; }

@test "power limit: framework_tool sets it, undo restores, bad values are refused" {
  run karma power limit --json
  [ "$(data .limit)" = 100 ]
  [ "$(data .method)" = framework_tool ]
  karma power limit 80
  [ "$(<"$STUB_STATE/charge-limit")" = 80 ]
  run karma power limit --json
  [ "$(data .limit)" = 80 ]
  karma undo
  [ "$(<"$STUB_STATE/charge-limit")" = 100 ]
  run karma power limit 30
  [ "$status" -eq 2 ]
  run karma power limit lots
  [ "$status" -eq 2 ]
}

@test "power limit: the kernel's threshold file is used when there is one" {
  bat=$KARMA_SYSROOT/sys/class/power_supply/BAT1
  mkdir -p "$bat"
  echo 100 >"$bat/charge_control_end_threshold"
  run karma power limit --json
  [ "$(data .method)" = kernel ]
  karma power limit 75
  [ "$(<"$bat/charge_control_end_threshold")" = 75 ]
  [ ! -e "$STUB_STATE/charge-limit" ]
}

@test "power auto: the profile follows the charger only while it is on" {
  ac=$KARMA_SYSROOT/sys/class/power_supply/ACAD
  mkdir -p "$ac"
  echo Mains >"$ac/type"
  echo 0 >"$ac/online"
  run karma power sync --json
  [ "$(data .auto)" = false ]
  [ "$(karma power profile --json | jq -r .data.profile)" = balanced ]
  karma power auto on
  [ "$(karma power profile --json | jq -r .data.profile)" = power-saver ]
  echo 1 >"$ac/online"
  run karma power sync --json
  [ "$(data .changed)" = true ]
  [ "$(data .profile)" = balanced ]
  karma undo
  run karma power auto --json
  [ "$(data .auto)" = false ]
}

@test "focus: start turns do-not-disturb on, stop puts it back" {
  run karma focus --json
  [ "$(data .running)" = false ]
  karma focus start 30
  run karma focus --json
  [ "$(data .running)" = true ]
  [ "$(data .minutes_left)" = 30 ]
  [ "$(karma dnd --json | jq -r .data.dnd)" = true ]
  grep -q -- '--on-active=30m' "$STUB_STATE/systemd-run.log"
  run karma focus start
  [ "$status" -eq 1 ]
  karma focus stop
  [ "$(karma dnd --json | jq -r .data.dnd)" = false ]
  run karma focus --json
  [ "$(data .running)" = false ]
  run karma focus start 0
  [ "$status" -eq 2 ]
}

@test "focus: do-not-disturb that was already on stays on afterwards" {
  karma dnd on
  karma focus start 5
  karma focus finish
  [ "$(karma dnd --json | jq -r .data.dnd)" = true ]
  run karma focus --json
  [ "$(data .running)" = false ]
}

@test "weather: nothing is asked until a place is set" {
  run karma weather --json
  [ "$status" -eq 0 ]
  [ "$(data .set)" = false ]
  [ ! -e "$STUB_STATE/curl.log" ]
}

@test "weather: set, show from the cache, units, clear" {
  karma weather set "Springfield, Oregon"
  [ "$(jq -r .weather.region "$XDG_CONFIG_HOME/karma/config.json")" = "Oregon, United States" ]
  [ "$(jq -r .weather.lat "$XDG_CONFIG_HOME/karma/config.json")" = 44.05 ]
  run karma weather --json
  [ "$(data .temperature)" = 12 ]
  [ "$(data .description)" = "Light rain" ]
  [ "$(data .high)" = 14 ]
  asked=$(grep -c forecast "$STUB_STATE/curl.log")
  karma weather
  [ "$(grep -c forecast "$STUB_STATE/curl.log")" = "$asked" ]
  karma weather units f
  karma weather
  grep -q 'temperature_unit=fahrenheit' "$STUB_STATE/curl.log"
  karma weather clear
  run karma weather --json
  [ "$(data .set)" = false ]
  run karma weather set Nowhere
  [ "$status" -eq 1 ]
}

@test "weather: no network is an error, not a crash" {
  karma weather set Springfield
  touch "$STUB_STATE/offline"
  run karma weather --refresh
  [ "$status" -eq 1 ]
}

@test "update check counts pending packages and keeps the answer" {
  printf '%s\n' "linux 7.3.4-1 -> 7.3.5-1" "jq 1.8-1 -> 1.8.2-1" "bash 5.3-1 -> 5.3-2" >"$STUB_STATE/pending"
  run karma update check --json
  [ "$(data .count)" = 3 ]
  [ "$(data '.repo[0]')" = linux ]
  : >"$STUB_STATE/pending"
  run karma update check --json
  [ "$(data .count)" = 3 ]
  run karma update check --refresh --json
  [ "$(data .count)" = 0 ]
}

@test "calc gives the result and fails on nonsense" {
  run karma calc "6 * 7" --json
  [ "$(data .result)" = 42 ]
  run karma calc 6 '*' 7
  [ "$output" = 42 ]
  run karma calc what
  [ "$status" -eq 1 ]
  run karma calc
  [ "$status" -eq 2 ]
}

@test "emoji list reads the Unicode file and leaves out skin tones" {
  run karma emoji list
  [ "$status" -eq 3 ]
  dir=$KARMA_SYSROOT/usr/share/unicode/emoji
  mkdir -p "$dir"
  cat >"$dir/emoji-test.txt" <<'EOF'
# group: Smileys & Emotion
1F600                                                  ; fully-qualified     # 😀 E1.0 grinning face
263A                                                   ; unqualified         # ☺ E0.6 smiling face
1F44B 1F3FB                                            ; fully-qualified     # 👋🏻 E1.0 waving hand: light skin tone
1F1E8 1F1E6                                            ; fully-qualified     # 🇨🇦 E2.0 flag: Canada
EOF
  run karma emoji list --json
  [ "$(data '.emoji | length')" = 2 ]
  [ "$(data '.emoji[0].name')" = "grinning face" ]
  [ "$(data '.emoji[1].emoji')" = "🇨🇦" ]
}

@test "record: status, a dry run, and needing a session" {
  run karma record status --json
  [ "$(data .recording)" = false ]
  run karma record start screen --dry-run --json
  [ "$(data .recording)" = false ]
  [[ "$(data .path)" == */Videos/Recordings/karma-*.mp4 ]]
  run karma record start screen
  [ "$status" -eq 3 ]
  run karma record stop
  [ "$status" -eq 1 ]
}

@test "record: start writes the file name down, stop ends the recorder" {
  export WAYLAND_DISPLAY=wayland-test XDG_RUNTIME_DIR=$BATS_TEST_TMPDIR/run
  mkdir -p "$XDG_RUNTIME_DIR"
  run karma record start screen --dir "$BATS_TEST_TMPDIR/vid" --json
  [ "$status" -eq 0 ]
  [ "$(data .recording)" = true ]
  grep -q -- "-f $BATS_TEST_TMPDIR/vid/karma-" "$STUB_STATE/wf-recorder.args"
  run karma record status --json
  [ "$(data .recording)" = true ]
  run karma record start screen
  [ "$status" -eq 1 ]
  run karma record toggle --json
  [ "$(data .recording)" = false ]
  run karma record status --json
  [ "$(data .recording)" = false ]
}

@test "shot text and term need a session" {
  run karma shot text
  [ "$status" -eq 3 ]
  run karma term
  [ "$status" -eq 3 ]
}
