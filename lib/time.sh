# shellcheck shell=bash
# mujo time: the time zone, and keeping it right while travelling. The clock
# itself is kept by the system (NTP); only the zone depends on where you are.

mujo_register time "Time zone; follow where you are"

help_time() {
  cat <<EOF
Usage: $MUJO_NAME time
       $MUJO_NAME time auto [on | off | toggle]
       $MUJO_NAME time sync

(none)  The time zone and whether it follows where you are.
auto    While it is on, the zone is checked each time the network changes
        and set to the one the connection is in. Journaled; can be undone.
sync    Check now (what auto does). Without auto it only reports.

The zone comes from the network address: ipinfo.io (or ipwho.is when that
does not answer) is asked which zone this connection is in. They see the
address and nothing else. Behind a VPN the answer is the VPN's zone; turn
auto off there. Changing the zone without a password needs the rule that
install.sh puts in /etc/polkit-1/rules.d.
EOF
}

TIME_LOOKUP=${MUJO_TIME_LOOKUP:-https://ipinfo.io/timezone}
TIME_LOOKUP_2=${MUJO_TIME_LOOKUP_2:-https://ipwho.is/?fields=success,timezone.id}
TIME_ZONEINFO=/usr/share/zoneinfo

time_zone_now() {
  local zone
  zone=$(timedatectl show --property=Timezone --value 2>/dev/null) || zone=""
  [[ -n $zone ]] || return 1
  printf '%s\n' "$zone"
}

# A name such as Europe/Lisbon that this system has a zone file for.
time_zone_valid() {
  [[ $1 =~ ^[A-Za-z0-9_+-]+(/[A-Za-z0-9_+-]+){0,2}$ ]] && [[ -f $TIME_ZONEINFO/$1 ]]
}

# The zone of this connection, by network address. Fails without an answer.
time_zone_here() {
  local zone
  zone=$(curl -fsS --max-time 8 "$TIME_LOOKUP" 2>/dev/null | tr -d '[:space:]') || zone=""
  if ! time_zone_valid "$zone"; then
    zone=$(curl -fsS --max-time 8 "$TIME_LOOKUP_2" 2>/dev/null | jq -r '.timezone.id // empty' 2>/dev/null) || zone=""
  fi
  time_zone_valid "$zone" || return 1
  printf '%s\n' "$zone"
}

time_cmd_show() {
  (( $# == 0 )) || usage_error "unexpected argument '$1'"
  need timedatectl
  local zone auto
  zone=$(time_zone_now) || die "$EXIT_ENV" "could not read the time zone"
  auto=$(config_read | jq -r '.time_auto == true')
  say "Time zone: $zone ($(TZ=$zone date +'%H:%M, UTC%:z'))"
  say "Follows where you are: $([[ $auto == true ]] && echo on || echo off)"
  jq -n --arg z "$zone" --argjson a "$auto" '{zone: $z, auto: $a}' | emit
}

# Not journaled: it only carries out the "auto" setting, which is.
time_cmd_sync() {
  (( $# == 0 )) || usage_error "unexpected argument '$1'"
  need timedatectl
  need curl
  local auto cur here
  auto=$(config_read | jq -r '.time_auto == true')
  cur=$(time_zone_now) || die "$EXIT_ENV" "could not read the time zone"
  here=$(time_zone_here) || die "$EXIT_FAIL" "could not find out which time zone this connection is in"
  if [[ $here == "$cur" ]]; then
    say "Time zone: $cur (matches this connection)"
    jq -n --arg z "$cur" --argjson a "$auto" '{auto: $a, changed: false, zone: $z, here: $z}' | emit
    return 0
  fi
  if [[ $auto != true ]] || (( OPT_DRY_RUN )); then
    say "Time zone: $cur; this connection is in $here."
    [[ $auto == true ]] || say "time auto is off; the zone was left alone."
    jq -n --arg z "$cur" --arg h "$here" --argjson a "$auto" '{auto: $a, changed: false, zone: $z, here: $h}' | emit
    return 0
  fi
  timedatectl --no-ask-password set-timezone "$here" 2>/dev/null \
    || die "$EXIT_ENV" "not allowed to change the time zone; run ./install.sh once to install the rule for it"
  say "Time zone: $cur -> $here"
  # A running program keeps the zone it started with, so the interface (the
  # clock in the bar) is started again; then it can show the notification.
  if ui_session && systemctl --user --quiet is-active "$MUJO_NAME-ui.service" 2>/dev/null; then
    timeout 10 systemctl --user restart "$MUJO_NAME-ui.service" >/dev/null 2>&1 || true
    sleep 2
  fi
  ui_notify "Time zone" "Now $here (was $cur)"
  jq -n --arg z "$here" --arg p "$cur" '{auto: true, changed: true, zone: $z, here: $z, previous: $p}' | emit
}

time_cmd_auto() {
  (( $# <= 1 )) || usage_error "too many arguments"
  local cur new
  cur=$(config_read | jq -r '.time_auto == true')
  if (( $# == 0 )); then
    say "Time zone follows where you are: $([[ $cur == true ]] && echo on || echo off)"
    jq -n --argjson a "$cur" '{auto: $a}' | emit
    return 0
  fi
  new=$(on_off "$1" "$cur") || usage_error "expected on, off or toggle, got '$1'"
  local wc wn before after
  wc=$([[ $cur == true ]] && echo on || echo off)
  wn=$([[ $new == true ]] && echo on || echo off)
  before=$(jq -cn --argjson a "$cur" '{auto: $a}')
  after=$(jq -cn --argjson a "$new" '{auto: $a}')
  change_begin "time auto: $wc -> $wn" "$before" "$after" || return 0
  mujo_lock
  config_set time_auto "$new"
  change_end "time auto: $wc -> $wn" "$before" "$after" "$(json_array time auto "$wc")"
  if [[ $new == true ]]; then
    flock -u 9 2>/dev/null || true
    "$MUJO_BIN" time sync >/dev/null 2>&1 3>&1 || true
  fi
}

cmd_time() {
  local action=${1:-show}
  (( $# )) && shift
  case $action in
    show) time_cmd_show "$@" ;;
    auto) mujo_set_cmd "time auto"; time_cmd_auto "$@" ;;
    sync) mujo_set_cmd "time sync"; time_cmd_sync "$@" ;;
    *) usage_error "unknown action '$action' (expected auto or sync)" ;;
  esac
}
