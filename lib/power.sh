# shellcheck shell=bash
# mujo power: lock, suspend, logout, reboot, shutdown.

mujo_register power "Lock, suspend, logout, reboot, shutdown"

POWER_ACTIONS=(lock suspend logout reboot shutdown)

help_power() {
  cat <<EOF
Usage: $MUJO_NAME power [list]
       $MUJO_NAME power lock | suspend
       $MUJO_NAME power logout | reboot | shutdown --yes
       $MUJO_NAME power profile [power-saver | balanced | performance]
       $MUJO_NAME power awake [on | off | toggle]
       $MUJO_NAME power limit [PERCENT | off]
       $MUJO_NAME power auto [on | off | toggle]
       $MUJO_NAME power battery [refresh | solid] [on | off | toggle]

lock      Lock the screen. The lock screen is part of the Quickshell UI, so
          this needs the graphical session (exit 3 otherwise).
suspend   Suspend to RAM.
logout    End the session. Unsaved work in open apps is lost.
reboot    Restart the machine.
shutdown  Power off.

profile   Show or set the power profile (power-profiles-daemon). Journaled;
          can be undone.
awake     Keep the screen from locking and switching off by itself, by
          stopping the idle daemon (hypridle); off starts it again.
          Journaled; can be undone. Lasts until you log out.

limit     Stop charging at PERCENT (50 to 100) to spare the battery; off
          means charge to 100. Uses the kernel's charge threshold if the
          battery has one, otherwise framework_tool (package
          framework-system). Needs sudo, so run it in a terminal. The
          laptop's firmware remembers the limit. Journaled; can be undone.
auto      Follow the charger: power-saver on battery, balanced when plugged
          in. The interface makes the switch when the charger is plugged in
          or pulled ('$MUJO_NAME power sync' does it by hand). Journaled;
          can be undone.

battery   What to save while on battery, each switched on its own:
          refresh  the built-in screen runs at its lowest refresh rate
                   (60 Hz instead of 120) and returns to its usual one on
                   the charger;
          solid    the frame and its panels are drawn solid, without the
                   blurred desktop behind them, while "glass" is on.
          Both follow the charger like auto does, and need Hyprland.
          Journaled; can be undone.

logout, reboot and shutdown cannot be undone and need --yes. --dry-run shows
the command that would run. Each action is recorded in the journal first.
EOF
}

# power_command ACTION: print the command that performs it, one word per line.
power_command() {
  case $1 in
    lock) printf '%s\n' qs -c "$MUJO_NAME" ipc call lock lock ;;
    suspend) printf '%s\n' systemctl suspend ;;
    reboot) printf '%s\n' systemctl reboot ;;
    shutdown) printf '%s\n' systemctl poweroff ;;
    logout)
      if [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; then
        if command -v hyprshutdown >/dev/null 2>&1; then
          printf '%s\n' hyprshutdown
        else
          printf '%s\n' hyprctl dispatch 'hl.dsp.exit()'
        fi
      elif [[ -n ${XDG_SESSION_ID:-} ]]; then
        printf '%s\n' loginctl terminate-session "$XDG_SESSION_ID"
      else
        return 1
      fi
      ;;
  esac
}

# The power-profiles service is reached over D-Bus with busctl; its own
# command-line tool needs Python modules that are not always installed.
POWER_PP_DEST=org.freedesktop.UPower.PowerProfiles
POWER_PP_PATH=/org/freedesktop/UPower/PowerProfiles

power_profile_get() {
  busctl --json=short get-property "$POWER_PP_DEST" "$POWER_PP_PATH" "$POWER_PP_DEST" ActiveProfile 2>/dev/null \
    | jq -er '.data'
}

power_profile_list() {
  busctl --json=short get-property "$POWER_PP_DEST" "$POWER_PP_PATH" "$POWER_PP_DEST" Profiles 2>/dev/null \
    | jq -er '[.data[] | .Profile.data] | join(" ")'
}

power_cmd_profile() {
  (( $# <= 1 )) || usage_error "too many arguments"
  need busctl
  local cur list
  cur=$(power_profile_get) || die "$EXIT_ENV" "power-profiles-daemon is not running"
  list=$(power_profile_list) || list=$cur
  if (( $# == 0 )); then
    say "Power profile: $cur"
    say "Available: $list"
    jq -n --arg p "$cur" --arg l "$list" '{profile: $p, available: ($l | split(" ") | map(select(length > 0)))}' | emit
    return 0
  fi
  [[ " $list " == *" $1 "* ]] || usage_error "unknown profile '$1'; choose one of: $list"
  local before after
  before=$(jq -cn --arg p "$cur" '{profile: $p}')
  after=$(jq -cn --arg p "$1" '{profile: $p}')
  change_begin "power profile: $cur -> $1" "$before" "$after" || return 0
  busctl set-property "$POWER_PP_DEST" "$POWER_PP_PATH" "$POWER_PP_DEST" ActiveProfile s "$1" 2>/dev/null \
    || die "$EXIT_FAIL" "could not set the power profile"
  change_end "power profile: $cur -> $1" "$before" "$after" "$(json_array power profile "$cur")"
}

power_awake_state() {
  if pgrep -x hypridle >/dev/null 2>&1; then echo false; else echo true; fi
}

power_cmd_awake() {
  (( $# <= 1 )) || usage_error "too many arguments"
  local cur new
  cur=$(power_awake_state)
  if (( $# == 0 )); then
    say "Keep awake: $([[ $cur == true ]] && echo on || echo off)"
    jq -n --argjson a "$cur" '{awake: $a}' | emit
    return 0
  fi
  new=$(on_off "$1" "$cur") || usage_error "expected on, off or toggle, got '$1'"
  local word_cur word_new before after
  word_cur=$([[ $cur == true ]] && echo on || echo off)
  word_new=$([[ $new == true ]] && echo on || echo off)
  before=$(jq -cn --argjson a "$cur" '{awake: $a}')
  after=$(jq -cn --argjson a "$new" '{awake: $a}')
  change_begin "power awake: $word_cur -> $word_new" "$before" "$after" || return 0
  require_wayland
  need hypridle
  if [[ $new == true ]]; then
    pkill -x hypridle || true
  else
    tui_detach hypridle
  fi
  mujo_lock
  config_set awake "$new"
  change_end "power awake: $word_cur -> $word_new" "$before" "$after" "$(json_array power awake "$word_cur")"
}

# The battery's charge threshold file, if the kernel offers one.
power_limit_file() {
  local f
  for f in "${MUJO_SYSROOT:-}"/sys/class/power_supply/BAT*/charge_control_end_threshold; do
    [[ -e $f ]] && { echo "$f"; return 0; }
  done
  return 1
}

# The limit in force: read from the kernel if it can be, otherwise the one
# mujo set last (asking the firmware needs root).
power_limit_get() {
  local f
  if f=$(power_limit_file); then
    cat -- "$f"
  else
    config_read | jq -r '.charge_limit // 100'
  fi
}

power_cmd_limit() {
  (( $# <= 1 )) || usage_error "too many arguments"
  local cur new f="" how
  cur=$(power_limit_get)
  if f=$(power_limit_file); then how=kernel
  elif command -v framework_tool >/dev/null 2>&1; then how=framework_tool
  else how=none; fi
  if (( $# == 0 )); then
    if (( cur >= 100 )); then say "Charge limit: off (charges to 100%)"; else say "Charge limit: $cur%"; fi
    [[ $how == none ]] && say "No way to set one here: the battery has no charge threshold and framework_tool is not installed (package framework-system)."
    [[ $how == framework_tool ]] && say "(The value $MUJO_NAME set last; the firmware is not asked, that needs root.)"
    jq -n --argjson l "$cur" --arg h "$how" '{limit: $l, method: $h}' | emit
    return 0
  fi
  if [[ $1 == off ]]; then new=100
  elif [[ $1 =~ ^[0-9]{2,3}%?$ ]] && (( ${1%\%} >= 50 && ${1%\%} <= 100 )); then new=${1%\%}
  else usage_error "expected a percentage from 50 to 100, or off; got '$1'"; fi
  local before after
  before=$(jq -cn --argjson l "$cur" '{limit: $l}')
  after=$(jq -cn --argjson l "$new" '{limit: $l}')
  change_begin "power limit: $cur% -> $new%" "$before" "$after" || return 0
  [[ $how != none ]] || die "$EXIT_ENV" "no way to set a charge limit: install framework-system (framework_tool)"
  need sudo
  local -a sudo=(sudo)
  [[ -t 0 ]] || sudo=(sudo -n)
  if [[ $how == kernel ]]; then
    say "Writing $new to $f (sudo)"
    printf '%s\n' "$new" | "${sudo[@]}" tee -- "$f" >/dev/null || die "$EXIT_FAIL" "could not write the charge threshold (sudo needs a terminal)"
  else
    say "Running: sudo framework_tool --charge-limit $new"
    "${sudo[@]}" framework_tool --charge-limit "$new" >/dev/null || die "$EXIT_FAIL" "framework_tool could not set the charge limit (sudo needs a terminal)"
  fi
  mujo_lock
  config_set charge_limit "$new"
  change_end "power limit: $cur% -> $new%" "$before" "$after" "$(json_array power limit "$cur")"
}

# True if a charger is connected (no mains supply at all counts as plugged in).
power_on_ac() {
  local f seen=0
  for f in "${MUJO_SYSROOT:-}"/sys/class/power_supply/*/online; do
    [[ -e $f && $(cat -- "${f%/online}/type" 2>/dev/null) == Mains ]] || continue
    seen=1
    [[ $(cat -- "$f") == 1 ]] && return 0
  done
  (( ! seen ))
}

# Read by config/hypr battery.lua while the battery savings apply.
POWER_BATTERY_STATE=$MUJO_STATE_DIR/battery.lua

power_has_hyprland() {
  [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]] && command -v hyprctl >/dev/null 2>&1
}

# The built-in screen at the lowest refresh rate its current resolution has,
# as {output, mode, position, scale}; nothing if it already runs that slowly.
power_battery_monitor() {
  power_has_hyprland || return 1
  hyprctl monitors -j 2>/dev/null | jq -ce '
    first(.[] | select(.name | test("^(eDP|LVDS|DSI)"))) as $m
    | [$m.availableModes[]
       | capture("^(?<w>[0-9]+)x(?<h>[0-9]+)@(?<r>[0-9.]+)Hz$")
       | select((.w | tonumber) == $m.width and (.h | tonumber) == $m.height and (.r | tonumber) >= 48)]
    | min_by(.r | tonumber)
    | select(. != null and (.r | tonumber) < $m.refreshRate - 1)
    | {output: $m.name, mode: "\(.w)x\(.h)@\(.r)", position: "\($m.x)x\($m.y)", scale: ($m.scale | tostring)}'
}

# Apply or lift the battery savings to match the power source and the two
# settings. Prints {on_battery, solid, monitor, changed}. Not journaled: it
# carries out settings that are.
power_battery_apply() {
  local config now want on_battery=true monitor=null solid=false
  config=$(config_read)
  now=$(jq -c '.battery_now // null' <<<"$config")
  power_on_ac && on_battery=false
  if [[ $on_battery == true ]]; then
    [[ $(jq -r '.battery_solid == true and .glass == true' <<<"$config") == true ]] && solid=true
    if [[ $(jq -r '.battery_refresh == true' <<<"$config") == true ]]; then
      # Keep the mode chosen when the charger was pulled: by now the screen
      # already runs at it, so asking again would find nothing to lower.
      monitor=$(jq -c '.monitor // null' <<<"$now")
      [[ $monitor != null ]] || monitor=$(power_battery_monitor) || monitor=null
    fi
  fi
  want=null
  if [[ $solid == true || $monitor != null ]]; then
    want=$(jq -cn --argjson s "$solid" --argjson m "$monitor" '{solid: $s, monitor: $m}')
  fi
  local changed=false
  if [[ $(jq -cS . <<<"$want") != "$(jq -cS . <<<"$now")" ]] && (( ! OPT_DRY_RUN )); then
    changed=true
    if [[ $want == null ]]; then
      rm -f -- "$POWER_BATTERY_STATE"
    else
      jq -r '"return { solid = \(.solid)"
        + (if .monitor then ", monitor = { output = \(.monitor.output | @json), mode = \(.monitor.mode | @json), position = \(.monitor.position | @json), scale = \(.monitor.scale | @json) }" else "" end)
        + " }"' <<<"$want" | atomic_write "$POWER_BATTERY_STATE"
    fi
    config_set battery_now "$want"
    if power_has_hyprland; then hyprctl reload >/dev/null 2>&1 || true; fi
    if [[ $want == null ]]; then say "Battery savings: lifted"
    else say "Battery savings: $(jq -r '[(if .solid then "solid panels" else empty end), (if .monitor then "screen at " + .monitor.mode else empty end)] | join(", ")' <<<"$want")"; fi
  fi
  jq -cn --argjson b "$on_battery" --argjson w "$want" --argjson c "$changed" \
    '{on_battery: $b, solid: ($w.solid // false), monitor: ($w.monitor // null), changed: $c}'
}

# Set the profile that suits the power source, and the battery savings. Not
# journaled: it only carries out the "auto" and "battery" settings, which are.
power_cmd_sync() {
  (( $# == 0 )) || usage_error "unexpected argument '$1'"
  local auto want cur battery
  battery=$(power_battery_apply)
  auto=$(config_read | jq -r '.power_auto == true')
  if power_on_ac; then want=balanced; else want=power-saver; fi
  if [[ $auto != true ]]; then
    say "power auto is off; the profile was left alone."
    jq -n --argjson b "$battery" '{auto: false, changed: false, battery: $b}' | emit
    return 0
  fi
  need busctl
  cur=$(power_profile_get) || die "$EXIT_ENV" "power-profiles-daemon is not running"
  if [[ $cur == "$want" ]] || (( OPT_DRY_RUN )); then
    say "Power profile: $cur (wanted: $want)"
    jq -n --arg p "$cur" --argjson b "$battery" '{auto: true, changed: false, profile: $p, battery: $b}' | emit
    return 0
  fi
  busctl set-property "$POWER_PP_DEST" "$POWER_PP_PATH" "$POWER_PP_DEST" ActiveProfile s "$want" 2>/dev/null \
    || die "$EXIT_FAIL" "could not set the power profile"
  say "Power profile: $cur -> $want"
  jq -n --arg p "$want" --argjson b "$battery" '{auto: true, changed: true, profile: $p, battery: $b}' | emit
}

power_cmd_battery() {
  (( $# <= 2 )) || usage_error "too many arguments"
  local config refresh solid
  config=$(config_read)
  refresh=$(jq -r '.battery_refresh == true' <<<"$config")
  solid=$(jq -r '.battery_solid == true' <<<"$config")
  if (( $# == 0 )); then
    say "On battery: lower refresh rate $([[ $refresh == true ]] && echo on || echo off), solid panels $([[ $solid == true ]] && echo on || echo off)"
    jq -n --argjson r "$refresh" --argjson s "$solid" --argjson n "$(jq -c '.battery_now // null' <<<"$config")" \
      '{refresh: $r, solid: $s, now: $n}' | emit
    return 0
  fi
  local what=$1 cur new
  case $what in
    refresh) cur=$refresh ;;
    solid) cur=$solid ;;
    *) usage_error "expected refresh or solid, got '$what'" ;;
  esac
  if (( $# == 1 )); then
    say "On battery, $what: $([[ $cur == true ]] && echo on || echo off)"
    jq -n --arg w "$what" --argjson v "$cur" '{($w): $v}' | emit
    return 0
  fi
  new=$(on_off "$2" "$cur") || usage_error "expected on, off or toggle, got '$2'"
  local wc wn before after
  wc=$([[ $cur == true ]] && echo on || echo off)
  wn=$([[ $new == true ]] && echo on || echo off)
  before=$(jq -cn --arg w "$what" --argjson v "$cur" '{($w): $v}')
  after=$(jq -cn --arg w "$what" --argjson v "$new" '{($w): $v}')
  change_begin "power battery $what: $wc -> $wn" "$before" "$after" || return 0
  mujo_lock
  config_set "battery_$what" "$new"
  change_end "power battery $what: $wc -> $wn" "$before" "$after" "$(json_array power battery "$what" "$wc")"
  flock -u 9 2>/dev/null || true
  "$MUJO_BIN" power sync >/dev/null 2>&1 3>&1 || true
}

power_cmd_auto() {
  (( $# <= 1 )) || usage_error "too many arguments"
  local cur new
  cur=$(config_read | jq -r '.power_auto == true')
  if (( $# == 0 )); then
    say "Power profile follows the charger: $([[ $cur == true ]] && echo on || echo off)"
    jq -n --argjson a "$cur" '{auto: $a}' | emit
    return 0
  fi
  new=$(on_off "$1" "$cur") || usage_error "expected on, off or toggle, got '$1'"
  local wc wn before after
  wc=$([[ $cur == true ]] && echo on || echo off)
  wn=$([[ $new == true ]] && echo on || echo off)
  before=$(jq -cn --argjson a "$cur" '{auto: $a}')
  after=$(jq -cn --argjson a "$new" '{auto: $a}')
  change_begin "power auto: $wc -> $wn" "$before" "$after" || return 0
  mujo_lock
  config_set power_auto "$new"
  change_end "power auto: $wc -> $wn" "$before" "$after" "$(json_array power auto "$wc")"
  if [[ $new == true ]]; then
    flock -u 9 2>/dev/null || true
    "$MUJO_BIN" power sync >/dev/null 2>&1 3>&1 || true
  fi
}

cmd_power() {
  local action=${1:-list}
  (( $# )) && shift
  mujo_set_cmd "power $action"
  case $action in
    profile) power_cmd_profile "$@"; return 0 ;;
    awake) power_cmd_awake "$@"; return 0 ;;
    limit) power_cmd_limit "$@"; return 0 ;;
    auto) power_cmd_auto "$@"; return 0 ;;
    battery) power_cmd_battery "$@"; return 0 ;;
    sync) power_cmd_sync "$@"; return 0 ;;
  esac
  (( $# == 0 )) || usage_error "unexpected argument '$1'"
  if [[ $action == list ]]; then
    say "Actions: ${POWER_ACTIONS[*]}"
    say "logout, reboot and shutdown need --yes."
    json_array "${POWER_ACTIONS[@]}" | jq '{actions: .}' | emit
    return 0
  fi
  [[ " ${POWER_ACTIONS[*]} " == *" $action "* ]] || usage_error "unknown action '$action'"

  local -a command
  mapfile -t command < <(power_command "$action") || true
  (( ${#command[@]} )) || die "$EXIT_ENV" "no session to log out of (not inside Hyprland or a logind session)"
  if [[ $action == lock ]]; then
    require_wayland
    need qs
  else
    need "${command[0]}"
  fi
  case $action in
    logout|reboot|shutdown) confirm_irreversible "power $action" ;;
  esac

  local cmd_json
  cmd_json=$(json_array "${command[@]}")
  if (( OPT_DRY_RUN )); then
    say "power $action (dry run, nothing done)"
    say "Would run: ${command[*]}"
    jq -n --arg a "$action" --argjson c "$cmd_json" '{journal_id: null, action: $a, command: $c}' | emit
    return 0
  fi

  if [[ $action == lock ]]; then
    timeout 3 "${command[@]}" >/dev/null 2>&1 \
      || die "$EXIT_ENV" "the lock screen is part of the Quickshell UI, which is not running"
  fi
  local jid
  jid=$(journal_new_id)
  journal_record "$jid" "power $action" '{}' "$(jq -cn --arg a "$action" '{action: $a}')" null
  if [[ $action != lock ]]; then
    "${command[@]}" >/dev/null 2>&1 || die "$EXIT_FAIL" "'${command[*]}' failed"
  fi
  say "power $action"
  jq -n --arg j "$jid" --arg a "$action" --argjson c "$cmd_json" '{journal_id: $j, action: $a, command: $c}' | emit
}
