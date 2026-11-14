# shellcheck shell=bash
# karma power: lock, suspend, logout, reboot, shutdown.

karma_register power "Lock, suspend, logout, reboot, shutdown"

POWER_ACTIONS=(lock suspend logout reboot shutdown)

help_power() {
  cat <<EOF
Usage: $KARMA_NAME power [list]
       $KARMA_NAME power lock | suspend
       $KARMA_NAME power logout | reboot | shutdown --yes

lock      Lock the screen. The lock screen is part of the Quickshell UI, so
          this needs the graphical session (exit 3 otherwise).
suspend   Suspend to RAM.
logout    End the session. Unsaved work in open apps is lost.
reboot    Restart the machine.
shutdown  Power off.

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

cmd_power() {
  local action=${1:-list}
  (( $# )) && shift
  karma_set_cmd "power $action"
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
