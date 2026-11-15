# shellcheck shell=bash
# mujo display: backlight brightness (brightnessctl) and the night light
# (hyprsunset, driven through `hyprctl hyprsunset`).

mujo_register display "Brightness and night light"

DISPLAY_NIGHT_DEFAULT=4000   # kelvin
DISPLAY_NIGHT_MIN=1000
DISPLAY_NIGHT_MAX=10000

help_display() {
  cat <<EOF
Usage: $MUJO_NAME display [status]
       $MUJO_NAME display brightness [N | +N | -N]
       $MUJO_NAME display night [on | off | toggle] [--temp KELVIN]

status      Brightness and the night light state.
brightness  Show or set the backlight in percent (1-100); +N and -N are steps.
night       Show or switch the night light. --temp sets the colour temperature
            ($DISPLAY_NIGHT_MIN-$DISPLAY_NIGHT_MAX K, default $DISPLAY_NIGHT_DEFAULT) and is remembered.
            Needs a running Hyprland session (exit 3 otherwise).

Changes are journaled; '$MUJO_NAME undo' puts the previous value back.
EOF
}

# display_backlight: print "DEVICE PERCENT". Fails without a backlight.
display_backlight() {
  command -v brightnessctl >/dev/null 2>&1 || return 1
  local line
  line=$(brightnessctl -m -c backlight 2>/dev/null | head -n 1)
  [[ -n $line ]] || return 1
  awk -F, '{ gsub(/%/, "", $4); print $1, $4 }' <<<"$line"
}

display_night_temp() {
  config_read | jq -r --argjson d "$DISPLAY_NIGHT_DEFAULT" '.night_temperature // $d'
}

# display_night: JSON {on, temperature}. Fails outside Hyprland.
# hyprsunset answers "true" to `identity get` while it applies no colour change.
display_night() {
  [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]] || return 1
  command -v hyprctl >/dev/null 2>&1 || return 1
  local answer temp on=false
  temp=$(display_night_temp)
  answer=$(hyprctl hyprsunset identity get 2>/dev/null) || answer=""
  if [[ $answer == false ]]; then
    on=true
    answer=$(hyprctl hyprsunset temperature 2>/dev/null) || answer=""
    [[ $answer =~ ^[0-9]+$ ]] && temp=$answer
  fi
  jq -cn --argjson on "$on" --argjson t "$temp" '{on: $on, temperature: $t}'
}

display_state() {
  local bl night brightness=null
  if bl=$(display_backlight); then
    brightness=$(jq -cn --arg d "${bl% *}" --argjson p "${bl#* }" '{device: $d, percent: $p}')
  fi
  night=$(display_night) || night=null
  [[ $brightness != null || $night != null ]] || return 1
  jq -cn --argjson b "$brightness" --argjson n "$night" '{brightness: $b, night: $n}'
}

display_night_word() {
  if [[ $1 == true ]]; then echo "on ($2 K)"; else echo off; fi
}

cmd_display() {
  local sub=${1:-status}
  (( $# )) && shift
  mujo_set_cmd "display $sub"
  case $sub in
    status) display_cmd_status "$@" ;;
    brightness) display_cmd_brightness "$@" ;;
    night) display_cmd_night "$@" ;;
    *) usage_error "unknown subcommand '$sub'" ;;
  esac
}

display_cmd_status() {
  (( $# == 0 )) || usage_error "unexpected argument '$1'"
  local state
  state=$(display_state) || die "$EXIT_ENV" "no backlight found and no Hyprland session for the night light"
  jq -r '
    (if .brightness then "Brightness   \(.brightness.percent)% (\(.brightness.device))" else "Brightness   no backlight" end),
    (if .night == null then "Night light  needs a Hyprland session"
     elif .night.on then "Night light  on, \(.night.temperature) K"
     else "Night light  off" end)' <<<"$state" | say_stream
  printf '%s' "$state" | emit
}

display_cmd_brightness() {
  (( $# <= 1 )) || usage_error "too many arguments"
  need brightnessctl
  local bl dev cur new
  bl=$(display_backlight) || die "$EXIT_ENV" "no backlight device found"
  read -r dev cur <<<"$bl"
  if (( $# == 0 )); then
    say "Brightness: $cur% ($dev)"
    jq -n --arg d "$dev" --argjson p "$cur" '{device: $d, percent: $p}' | emit
    return 0
  fi
  new=$(step_value "$1" "$cur" 1 100) || usage_error "expected a percentage such as 40, +5 or -5, got '$1'"
  local before after
  before=$(jq -cn --argjson p "$cur" '{brightness: $p}')
  change_begin "display brightness: $cur% -> $new%" "$before" "$(jq -cn --argjson p "$new" '{brightness: $p}')" \
    || return 0
  brightnessctl -q -d "$dev" set "$new%" 2>/dev/null \
    || die "$EXIT_FAIL" "brightnessctl could not set the backlight (no permission outside a local session?)"
  bl=$(display_backlight) || bl="$dev $new"
  new=${bl#* }
  after=$(jq -cn --argjson p "$new" '{brightness: $p}')
  change_end "display brightness: $cur% -> $new%" "$before" "$after" "$(json_array display brightness "$cur")"
  ui_ipc osd brightness "$new"
}

display_cmd_night() {
  local word="" temp=""
  while (( $# )); do
    case $1 in
      --temp)
        if [[ ! ${2:-} =~ ^[0-9]{1,6}$ ]] || (( $2 < DISPLAY_NIGHT_MIN || $2 > DISPLAY_NIGHT_MAX )); then
          usage_error "--temp needs a value from $DISPLAY_NIGHT_MIN to $DISPLAY_NIGHT_MAX"
        fi
        temp=$2
        shift 2
        ;;
      --*) usage_error "unknown option '$1'" ;;
      *)
        [[ -z $word ]] || usage_error "too many arguments"
        word=$1
        shift
        ;;
    esac
  done
  require_hyprland
  need hyprsunset
  local cur cur_on cur_temp new_on
  cur=$(display_night) || die "$EXIT_ENV" "cannot read the night light state"
  cur_on=$(jq -r .on <<<"$cur")
  cur_temp=$(jq -r .temperature <<<"$cur")
  if [[ -z $word && -z $temp ]]; then
    say "Night light: $(display_night_word "$cur_on" "$cur_temp")"
    printf '%s' "$cur" | emit
    return 0
  fi
  new_on=$(on_off "${word:-on}" "$cur_on") || usage_error "expected on, off or toggle, got '$word'"
  temp=${temp:-$cur_temp}
  local planned summary
  planned=$(jq -cn --argjson on "$new_on" --argjson t "$temp" '{on: $on, temperature: $t}')
  summary="display night: $(display_night_word "$cur_on" "$cur_temp") -> $(display_night_word "$new_on" "$temp")"
  change_begin "$summary" "$cur" "$planned" || return 0

  if [[ $new_on == true ]]; then
    if ! pgrep -x hyprsunset >/dev/null 2>&1; then
      # The daemon is started on first use and stays for the session.
      tui_detach hyprsunset -t "$temp"
      for _ in 1 2 3 4 5 6 7 8 9 10; do
        [[ $(hyprctl hyprsunset identity get 2>/dev/null) == @(true|false) ]] && break
        sleep 0.2
      done
    fi
    [[ $(hyprctl hyprsunset temperature "$temp" 2>/dev/null) == ok ]] \
      || die "$EXIT_FAIL" "hyprsunset did not accept the temperature"
  elif [[ $cur_on == true ]]; then
    [[ $(hyprctl hyprsunset identity 2>/dev/null) == ok ]] \
      || die "$EXIT_FAIL" "hyprsunset did not switch off"
  fi
  mujo_lock
  config_set night_temperature "$temp"
  config_set night_on "$new_on"
  change_end "$summary" "$cur" "$planned" \
    "$(json_array display night "$([[ $cur_on == true ]] && echo on || echo off)" --temp "$cur_temp")"
}
