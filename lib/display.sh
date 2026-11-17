# shellcheck shell=bash
# mujo display: backlight brightness (brightnessctl), the night light
# (hyprsunset, driven through `hyprctl hyprsunset`) and the scale of a screen
# (how big text and everything else is drawn).

mujo_register display "Brightness, night light and screen scale"

DISPLAY_NIGHT_DEFAULT=4000   # kelvin
DISPLAY_NIGHT_MIN=1000
DISPLAY_NIGHT_MAX=10000

help_display() {
  cat <<EOF
Usage: $MUJO_NAME display [status]
       $MUJO_NAME display brightness [N | +N | -N]
       $MUJO_NAME display night [on | off | toggle] [--temp KELVIN]
       $MUJO_NAME display scale [bigger | smaller | N | reset] [--monitor NAME]

status      Brightness, the night light state and the scale.
brightness  Show or set the backlight in percent (1-100); +N and -N are steps.
night       Show or switch the night light. --temp sets the colour temperature
            ($DISPLAY_NIGHT_MIN-$DISPLAY_NIGHT_MAX K, default $DISPLAY_NIGHT_DEFAULT) and is remembered.
            Needs a running Hyprland session (exit 3 otherwise).
scale       Show or set how big a screen draws everything: the screen with
            the focus, or the one named with --monitor. bigger and smaller
            step through the scales that fit the screen's resolution; a
            number such as 1.5 picks the nearest of those. The choice wins
            over the scale in host.lua and is kept; reset drops it.
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

# Read by config/hypr scale.lua: the scale chosen for each screen.
DISPLAY_SCALE_STATE=$MUJO_STATE_DIR/scale.lua

# display_scale [MONITOR]: JSON {monitor, scale, chosen, choices} for the
# focused screen or the one named. choices are the scales from 1 to 3 at
# which the resolution divides into whole pixels (Hyprland counts scale in
# steps of 1/120); scale is the one of them that was chosen, or else the one
# the screen runs at (Hyprland reports that rounded, and a moment late after
# a change). Fails outside Hyprland and for a screen that is not there.
display_scale() {
  [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]] || return 1
  command -v hyprctl >/dev/null 2>&1 || return 1
  local chosen
  chosen=$(config_read | jq -c '.display_scale // {}')
  hyprctl monitors -j 2>/dev/null | jq -ce --arg want "${1:-}" --argjson chosen "$chosen" '
    (if $want == "" then first(.[] | select(.focused)) // .[0]
     else first(.[] | select(.name == $want)) end) as $m
    | select($m != null)
    | [range(120; 361) as $k
       | select(($m.width * 120) % $k == 0 and ($m.height * 120) % $k == 0)
       | ($k / 120 * 1000000 | round) / 1000000] as $choices
    | {monitor: $m.name, scale: ($choices | min_by(. - ($chosen[$m.name] // $m.scale) | fabs)),
       chosen: ($chosen[$m.name] != null), choices: $choices}'
}

# Write the chosen scales where Hyprland reads them, and have it read them.
display_scale_apply() {
  local chosen
  chosen=$(config_read | jq -c '.display_scale // {}')
  if [[ $chosen == '{}' ]]; then
    rm -f -- "$DISPLAY_SCALE_STATE"
  else
    jq -r '"return { " + (to_entries | map("[\(.key | @json)] = \(.value | tostring | @json)") | join(", ")) + " }"' \
      <<<"$chosen" | atomic_write "$DISPLAY_SCALE_STATE"
  fi
  hyprctl reload >/dev/null 2>&1 || warn "Hyprland did not reload; the scale applies at the next login"
  # Programs that run through XWayland read their size from Xft.dpi when
  # they start (see config/hypr compat.lua): the largest scale times 96.
  if ui_session && command -v xrdb >/dev/null 2>&1; then
    local dpi
    dpi=$(hyprctl monitors -j 2>/dev/null | jq '[.[].scale] | max * 96 | round' 2>/dev/null) || dpi=""
    [[ $dpi =~ ^[0-9]+$ ]] && xrdb -merge <<<"Xft.dpi: $dpi" 2>/dev/null || true
  fi
}

display_state() {
  local bl night scale brightness=null
  if bl=$(display_backlight); then
    brightness=$(jq -cn --arg d "${bl% *}" --argjson p "${bl#* }" '{device: $d, percent: $p}')
  fi
  night=$(display_night) || night=null
  scale=$(display_scale) || scale=null
  [[ $brightness != null || $night != null ]] || return 1
  jq -cn --argjson b "$brightness" --argjson n "$night" --argjson s "$scale" '{brightness: $b, night: $n, scale: $s}'
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
    scale) display_cmd_scale "$@" ;;
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
     else "Night light  off" end),
    (if .scale then "Scale        \(.scale.scale) (\(.scale.monitor))" else empty end)' <<<"$state" | say_stream
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

display_cmd_scale() {
  local word="" monitor=""
  while (( $# )); do
    case $1 in
      --monitor)
        [[ -n ${2:-} ]] || usage_error "--monitor needs the name of a screen"
        monitor=$2
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
  local cur name
  cur=$(display_scale "$monitor") \
    || die "$EXIT_FAIL" "$([[ -n $monitor ]] && echo "no screen named '$monitor'" || echo "cannot read the screens from Hyprland")"
  name=$(jq -r .monitor <<<"$cur")
  if [[ -z $word ]]; then
    jq -r '"Scale: \(.scale) on \(.monitor)" + (if .chosen then "" else " (from host.lua)" end),
      "Fits this screen: \(.choices | map(tostring) | join(", "))"' <<<"$cur" | say_stream
    printf '%s' "$cur" | emit
    return 0
  fi
  local new
  case $word in
    bigger|+) new=$(jq '.scale as $s | first(.choices[] | select(. > $s + 0.001)) // $s' <<<"$cur") ;;
    smaller|-) new=$(jq '.scale as $s | last(.choices[] | select(. < $s - 0.001)) // $s' <<<"$cur") ;;
    reset) new=null ;;
    *)
      [[ $word =~ ^[1-3](\.[0-9]{1,6})?$ ]] && new=$(jq --argjson w "$word" 'select($w <= 3) | .choices | min_by(. - $w | fabs)' <<<"$cur")
      [[ -n ${new:-} ]] || usage_error "expected bigger, smaller, reset or a scale from 1 to 3, got '$word'"
      ;;
  esac
  local before planned summary
  before=$(jq -c '{monitor, scale, chosen}' <<<"$cur")
  if [[ $new == null ]]; then
    planned=$(jq -c 'if .chosen then {monitor, scale: null, chosen: false} else . end' <<<"$before")
    summary="display scale: $name back to the scale in host.lua"
  else
    planned=$(jq -c --argjson n "$new" 'if .scale == $n then . else {monitor, scale: $n, chosen: true} end' <<<"$before")
    summary="display scale: $name $(jq -r .scale <<<"$before") -> $new"
  fi
  change_begin "$summary" "$before" "$planned" || return 0
  mujo_lock
  config_set display_scale "$(config_read | jq -c --arg m "$name" --argjson n "$new" \
    '(.display_scale // {}) | if $n == null then del(.[$m]) else .[$m] = $n end')"
  display_scale_apply
  local after=$planned undo
  if [[ $new == null ]]; then
    # What host.lua says is only known once Hyprland has applied it.
    sleep 0.3
    after=$(display_scale "$name" | jq -c '{monitor, scale, chosen}') || after=$planned
  fi
  if [[ $(jq -r .chosen <<<"$before") == true ]]; then
    undo=$(json_array display scale "$(jq -r .scale <<<"$before")" --monitor "$name")
  else
    undo=$(json_array display scale reset --monitor "$name")
  fi
  change_end "$summary" "$before" "$after" "$undo"
}
