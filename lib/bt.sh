# shellcheck shell=bash
# karma bt: Bluetooth status and power through bluetoothctl; pairing and
# device management happen in bluetui.

karma_register bt "Bluetooth status and power (TUI: bt tui)"

help_bt() {
  cat <<EOF
Usage: $KARMA_NAME bt [status]
       $KARMA_NAME bt power [on | off | toggle]
       $KARMA_NAME bt tui [--window]

status  The adapter and the paired devices.
power   Show or switch the adapter. Journaled; can be undone.
tui     Open bluetui to scan, pair and connect devices.
EOF
}

bt_ctl() {
  timeout 4 bluetoothctl --timeout 3 "$@" 2>/dev/null
}

# bt_state: JSON snapshot. Fails if there is no adapter or no bluetoothd.
bt_state() {
  command -v bluetoothctl >/dev/null 2>&1 || return 1
  local show paired connected
  show=$(bt_ctl show) || return 1
  [[ $show == Controller* ]] || return 1
  paired=$(bt_ctl devices Paired) || paired=""
  connected=$(bt_ctl devices Connected) || connected=""
  jq -cn --arg show "$show" --arg paired "$paired" --arg connected "$connected" '
    def devices($s): [$s | split("\n")[] | select(startswith("Device "))
      | split(" ") | {address: .[1], name: (.[2:] | join(" "))}];
    (devices($connected) | map(.address)) as $on
    | {powered: ($show | test("\n\\s*Powered: yes")),
       adapter: ($show | split("\n")[0] | split(" ")[1]),
       name: (($show | capture("\n\\s*Alias: (?<a>[^\n]*)").a) // null),
       devices: (devices($paired) | map(. + {connected: (.address as $a | $on | index($a) != null)}))}'
}

bt_need() {
  need bluetoothctl
  BT_STATE=$(bt_state) || die "$EXIT_ENV" "no Bluetooth adapter found (is bluetooth.service running?)"
}

cmd_bt() {
  local sub=${1:-status}
  (( $# )) && shift
  karma_set_cmd "bt $sub"
  case $sub in
    status) bt_cmd_status "$@" ;;
    power) bt_cmd_power "$@" ;;
    tui) bt_cmd_tui "$@" ;;
    *) usage_error "unknown subcommand '$sub'" ;;
  esac
}

bt_cmd_status() {
  (( $# == 0 )) || usage_error "unexpected argument '$1'"
  bt_need
  jq -r '
    "Bluetooth  \(if .powered then "on" else "off" end)  (\(.name // .adapter))",
    (.devices[] | "  \(if .connected then "*" else " " end) \(.name)  \(.address)")' <<<"$BT_STATE" | say_stream
  printf '%s' "$BT_STATE" | emit
}

bt_cmd_power() {
  (( $# <= 1 )) || usage_error "too many arguments"
  bt_need
  local cur new
  cur=$(jq -r .powered <<<"$BT_STATE")
  if (( $# == 0 )); then
    say "Bluetooth: $([[ $cur == true ]] && echo on || echo off)"
    jq -n --argjson p "$cur" '{powered: $p}' | emit
    return 0
  fi
  new=$(on_off "$1" "$cur") || usage_error "expected on, off or toggle, got '$1'"
  local word_cur word_new before after
  word_cur=$([[ $cur == true ]] && echo on || echo off)
  word_new=$([[ $new == true ]] && echo on || echo off)
  before=$(jq -cn --argjson p "$cur" '{powered: $p}')
  after=$(jq -cn --argjson p "$new" '{powered: $p}')
  change_begin "bt power: $word_cur -> $word_new" "$before" "$after" || return 0
  bt_ctl power "$word_new" >/dev/null \
    || die "$EXIT_FAIL" "could not switch Bluetooth $word_new (blocked by rfkill?)"
  change_end "bt power: $word_cur -> $word_new" "$before" "$after" "$(json_array bt power "$word_cur")"
}

bt_cmd_tui() {
  (( $# == 0 )) || usage_error "unexpected argument '$1'"
  (( OPT_JSON )) && usage_error "'$KARMA_CMD' is interactive and has no --json output"
  need bluetui
  [[ -t 0 && -t 2 ]] \
    || die "$EXIT_ENV" "'$KARMA_NAME $KARMA_CMD' needs a terminal (inside the desktop, add --window)"
  exec bluetui
}
