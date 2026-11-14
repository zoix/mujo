# shellcheck shell=bash
# karma focus: a countdown that keeps notifications quiet while it runs.

karma_register focus "Focus timer: do-not-disturb for a set time"

help_focus() {
  cat <<EOF
Usage: $KARMA_NAME focus [status]
       $KARMA_NAME focus start [MINUTES]
       $KARMA_NAME focus stop

start   Begin a focus session (25 minutes unless you say otherwise, up to
        480). Do-not-disturb goes on and the bar counts the minutes down.
stop    End it now.
status  Whether one is running and how long is left (the default).

When the time is up, do-not-disturb goes back to what it was and a
notification says so. Start and stop are journaled and can be undone.
EOF
}

FOCUS_UNIT=$KARMA_NAME-focus

# focus_state: the "focus" object from the config ({until, dnd_before}), or
# nothing if no session is running (one whose time has passed is not).
focus_state() {
  config_read | jq -ce --argjson now "$(date +%s)" '.focus | select(type == "object" and .until > $now)'
}

focus_end() {
  local summary=$1 cfg dnd_before before after
  cfg=$(config_read)
  dnd_before=$(jq -r '.focus.dnd_before == true' <<<"$cfg")
  before=$(jq -c '{focus: true, until: .focus.until}' <<<"$cfg")
  after='{"focus":false}'
  karma_lock
  jq --argjson d "$dnd_before" 'del(.focus) | .dnd = $d' <<<"$cfg" | atomic_write "$KARMA_CONFIG_FILE"
  systemctl --user stop "$FOCUS_UNIT.timer" >/dev/null 2>&1 || true
  ui_ipc notify reload
  change_end "$summary" "$before" "$after" null
}

cmd_focus() {
  local sub=${1:-status}
  (( $# )) && shift
  karma_set_cmd "focus $sub"
  local state="" now left
  now=$(date +%s)
  state=$(focus_state) || state=""
  case $sub in
    status)
      (( $# == 0 )) || usage_error "unexpected argument '$1'"
      if [[ -n $state ]]; then
        left=$(( ($(jq -r .until <<<"$state") - now + 59) / 60 ))
        say "Focus: $left minute(s) left"
        jq -n --argjson s "$state" --argjson l "$left" '{running: true, until: $s.until, minutes_left: $l}' | emit
      else
        say "Focus: not running"
        jq -n '{running: false, until: null, minutes_left: 0}' | emit
      fi
      ;;
    start)
      (( $# <= 1 )) || usage_error "too many arguments"
      local minutes=${1:-25}
      if ! [[ $minutes =~ ^[0-9]{1,3}$ ]] || (( 10#$minutes < 1 || 10#$minutes > 480 )); then
        usage_error "expected a number of minutes from 1 to 480, got '$minutes'"
      fi
      minutes=$(( 10#$minutes ))
      [[ -z $state ]] || die "$EXIT_FAIL" "a focus session is already running ('$KARMA_NAME focus stop' ends it)"
      local until=$(( now + minutes * 60 )) cfg dnd before after
      cfg=$(config_read)
      dnd=$(jq -r '.dnd == true' <<<"$cfg")
      before='{"focus":false}'
      after=$(jq -cn --argjson u "$until" '{focus: true, until: $u}')
      change_begin "focus: $minutes minute(s)" "$before" "$after" || return 0
      karma_lock
      jq --argjson u "$until" --argjson d "$dnd" '.focus = {until: $u, dnd_before: $d} | .dnd = true' <<<"$cfg" \
        | atomic_write "$KARMA_CONFIG_FILE"
      # A one-off timer ends the session even if this terminal is long gone.
      if command -v systemd-run >/dev/null 2>&1; then
        systemctl --user stop "$FOCUS_UNIT.timer" >/dev/null 2>&1 || true
        systemd-run --user --quiet --collect --unit "$FOCUS_UNIT" --on-active="${minutes}m" \
          "$KARMA_BIN" focus finish >/dev/null 2>&1 3>&- 9>&- \
          || warn "could not schedule the end; run '$KARMA_NAME focus stop' yourself"
      fi
      ui_ipc notify reload
      change_end "focus: $minutes minute(s)" "$before" "$after" "$(json_array focus stop)"
      ;;
    stop)
      (( $# == 0 )) || usage_error "unexpected argument '$1'"
      if [[ -z $state ]] && ! config_read | jq -e '.focus != null' >/dev/null; then
        say "Nothing to do: no focus session is running."
        jq -n '{journal_id: null, changed: false, before: {focus: false}, after: {focus: false}}' | emit
        return 0
      fi
      if (( OPT_DRY_RUN )); then
        say "focus: stopped (dry run, nothing changed)"
        jq -n '{journal_id: null, changed: true, before: {focus: true}, after: {focus: false}}' | emit
        return 0
      fi
      focus_end "focus: stopped"
      ;;
    finish)
      # Called by the timer when the time is up.
      config_read | jq -e '.focus != null' >/dev/null || return 0
      focus_end "focus: finished"
      if command -v notify-send >/dev/null 2>&1; then
        timeout 2 notify-send -a "$KARMA_NAME" -t 8000 "Focus time is over" "Notifications are back to normal." >/dev/null 2>&1 3>&- || true
      fi
      ;;
    *) usage_error "unknown subcommand '$sub'" ;;
  esac
}
