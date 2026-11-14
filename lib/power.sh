# shellcheck shell=bash
# karma power: lock, suspend, logout, reboot, shutdown.

karma_register power "Lock, suspend, logout, reboot, shutdown"

POWER_ACTIONS=(lock suspend logout reboot shutdown)

help_power() {
  cat <<EOF
Usage: $KARMA_NAME power [list]
       $KARMA_NAME power lock | suspend
       $KARMA_NAME power logout | reboot | shutdown --yes
       $KARMA_NAME power profile [power-saver | balanced | performance]
       $KARMA_NAME power awake [on | off | toggle]

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

logout, reboot and shutdown cannot be undone and need --yes. --dry-run shows
the command that would run. Each action is recorded in the journal first.
EOF
}

# power_command ACTION: print the command that performs it, one word per line.
power_command() {
  case $1 in
    lock) printf '%s\n' qs -c "$KARMA_NAME" ipc call lock lock ;;
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
  karma_lock
  config_set awake "$new"
  change_end "power awake: $word_cur -> $word_new" "$before" "$after" "$(json_array power awake "$word_cur")"
}

cmd_power() {
  local action=${1:-list}
  (( $# )) && shift
  karma_set_cmd "power $action"
  case $action in
    profile) power_cmd_profile "$@"; return 0 ;;
    awake) power_cmd_awake "$@"; return 0 ;;
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
