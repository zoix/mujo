# shellcheck shell=bash
# karma audio: volume, mute and the default output/input device, through
# WirePlumber (wpctl). Device lists come from pw-dump.

karma_register audio "Volume, mute, output and input device"

help_audio() {
  cat <<EOF
Usage: $KARMA_NAME audio [status]
       $KARMA_NAME audio volume [N | +N | -N] [--input] [--muted on|off]
       $KARMA_NAME audio mute [on | off | toggle] [--input]
       $KARMA_NAME audio output [ID | NAME]
       $KARMA_NAME audio input [ID | NAME]
       $KARMA_NAME audio tui [--window]

status   Volume and mute of the default output and input, and every device.
volume   Show or set the volume in percent (0-100); +N and -N are steps.
         Raising the volume also unmutes. --muted sets mute in the same step.
mute     Show or change mute; without a word it toggles.
output   List the outputs, or make one the default (by id or node name).
input    The same for inputs (microphones).
tui      Open the wiremix mixer (per-application volumes, routing).

--input makes volume and mute act on the default microphone.
Changes are journaled; '$KARMA_NAME undo' puts the previous value back.
EOF
}

audio_target() {
  if [[ $1 == input ]]; then echo @DEFAULT_AUDIO_SOURCE@; else echo @DEFAULT_AUDIO_SINK@; fi
}

# audio_level KIND: print "PERCENT MUTED" (for example "40 false").
audio_level() {
  local out
  out=$(LC_ALL=C wpctl get-volume "$(audio_target "$1")" 2>/dev/null) || return 1
  [[ $out == Volume:* ]] || return 1
  LC_ALL=C awk '{ printf "%d %s\n", $2 * 100 + 0.5, ($3 == "[MUTED]" ? "true" : "false") }' <<<"$out"
}

# audio_devices KIND: JSON array of {id, name, description, default}.
audio_devices() {
  local class=Audio/Sink def
  [[ $1 == input ]] && class=Audio/Source
  def=$(wpctl inspect "$(audio_target "$1")" 2>/dev/null | sed -n '1s/^id \([0-9]*\),.*/\1/p')
  pw-dump 2>/dev/null | jq -c --arg c "$class" --argjson d "${def:-null}" '
    [.[] | select(.type == "PipeWire:Interface:Node" and .info.props["media.class"] == $c)
     | {id, name: .info.props["node.name"],
        description: (.info.props["node.description"] // .info.props["node.name"]),
        default: (.id == $d)}]'
}

# audio_state: the whole picture as JSON. Fails if PipeWire cannot be reached.
audio_state() {
  command -v wpctl >/dev/null 2>&1 || return 1
  command -v pw-dump >/dev/null 2>&1 || return 1
  local out in outs ins
  out=$(audio_level output) || out=""
  in=$(audio_level input) || in=""
  outs=$(audio_devices output) || return 1
  ins=$(audio_devices input) || return 1
  [[ -n $out || -n $in || $outs != "[]" || $ins != "[]" ]] || return 1
  jq -cn --arg out "$out" --arg in "$in" --argjson outs "$outs" --argjson ins "$ins" '
    def level($s; $devs): if $s == "" then null else ($s | split(" ")) as $p
      | {volume: ($p[0] | tonumber), muted: ($p[1] == "true"),
         device: ([$devs[] | select(.default) | .description][0] // null)} end;
    {output: level($out; $outs), input: level($in; $ins), outputs: $outs, inputs: $ins}'
}

audio_need() {
  need wpctl pw-dump
  wpctl status >/dev/null 2>&1 \
    || die "$EXIT_ENV" "PipeWire is not reachable (is the user session running?)"
}

# Tell the UI to show the on-screen display. Best effort.
audio_osd() {
  local level
  level=$(audio_level "$1") || return 0
  # shellcheck disable=SC2086  # two words on purpose: percent and muted
  ui_ipc osd "$([[ $1 == input ]] && echo microphone || echo volume)" $level
}

# Split "--input" out of the arguments: sets AUDIO_KIND and AUDIO_ARGS.
audio_parse() {
  AUDIO_KIND=output
  AUDIO_ARGS=()
  AUDIO_MUTED=""
  while (( $# )); do
    case $1 in
      --input) AUDIO_KIND=input ;;
      --output) AUDIO_KIND=output ;;
      --muted)
        AUDIO_MUTED=$(on_off "${2:-}" false) || usage_error "--muted needs on or off"
        shift
        ;;
      --*) usage_error "unknown option '$1'" ;;
      *) AUDIO_ARGS+=("$1") ;;
    esac
    shift
  done
}

# The words that make an undo command act on the same device kind.
audio_kind_flag() {
  if [[ $AUDIO_KIND == input ]]; then printf '%s\n' --input; fi
}

audio_label() {
  if [[ $AUDIO_KIND == input ]]; then echo microphone; else echo volume; fi
}

audio_mute_word() {
  if [[ $1 == true ]]; then echo on; else echo off; fi
}

cmd_audio() {
  local sub=${1:-status}
  (( $# )) && shift
  karma_set_cmd "audio $sub"
  case $sub in
    status) audio_cmd_status "$@" ;;
    volume) audio_cmd_volume "$@" ;;
    mute) audio_cmd_mute "$@" ;;
    output|input) audio_cmd_device "$sub" "$@" ;;
    tui)
      (( $# == 0 )) || usage_error "unexpected argument '$1'"
      (( OPT_JSON )) && usage_error "'$KARMA_CMD' is interactive and has no --json output"
      need wiremix
      [[ -t 0 && -t 2 ]] \
        || die "$EXIT_ENV" "'$KARMA_NAME $KARMA_CMD' needs a terminal (inside the desktop, add --window)"
      exec wiremix
      ;;
    *) usage_error "unknown subcommand '$sub'" ;;
  esac
}

audio_cmd_status() {
  (( $# == 0 )) || usage_error "unexpected argument '$1'"
  audio_need
  local state
  state=$(audio_state) || die "$EXIT_ENV" "PipeWire is not reachable (is the user session running?)"
  jq -r '
    def line($label; $l): if $l == null then "\($label)  none"
      else "\($label)  \($l.volume)%\(if $l.muted then " (muted)" else "" end)  \($l.device // "")" end;
    line("Output"; .output), line("Input "; .input),
    (.outputs[] | "  out \(.id)\(if .default then " *" else "  " end) \(.description)"),
    (.inputs[]  | "  in  \(.id)\(if .default then " *" else "  " end) \(.description)")' <<<"$state" | say_stream
  printf '%s' "$state" | emit
}

audio_cmd_volume() {
  audio_parse "$@"
  (( ${#AUDIO_ARGS[@]} <= 1 )) || usage_error "too many arguments"
  audio_need
  local level cur muted new
  level=$(audio_level "$AUDIO_KIND") || die "$EXIT_FAIL" "no default $AUDIO_KIND device"
  read -r cur muted <<<"$level"
  if (( ${#AUDIO_ARGS[@]} == 0 )); then
    say "$(audio_label): $cur%$([[ $muted == true ]] && echo " (muted)" || true)"
    jq -n --argjson v "$cur" --argjson m "$muted" '{volume: $v, muted: $m}' | emit
    return 0
  fi
  new=$(step_value "${AUDIO_ARGS[0]}" "$cur" 0 100) \
    || usage_error "expected a percentage such as 40, +5 or -5, got '${AUDIO_ARGS[0]}'"
  # Turning the volume up while muted unmutes, as the keys on any device do.
  local new_muted=$muted
  if [[ -n $AUDIO_MUTED ]]; then
    new_muted=$AUDIO_MUTED
  elif (( new > cur )); then
    new_muted=false
  fi
  local before planned after undo summary
  summary="audio $(audio_label): $cur% -> $new%"
  if [[ $new_muted != "$muted" ]]; then
    summary+=", $([[ $new_muted == true ]] && echo muted || echo unmuted)"
  fi
  before=$(jq -cn --argjson v "$cur" --argjson m "$muted" '{volume: $v, muted: $m}')
  planned=$(jq -cn --argjson v "$new" --argjson m "$new_muted" '{volume: $v, muted: $m}')
  change_begin "$summary" "$before" "$planned" || return 0
  local target
  target=$(audio_target "$AUDIO_KIND")
  wpctl set-volume -l 1.0 "$target" "$new%" || die "$EXIT_FAIL" "wpctl could not set the volume"
  if [[ $new_muted != "$muted" ]]; then
    wpctl set-mute "$target" "$([[ $new_muted == true ]] && echo 1 || echo 0)" \
      || die "$EXIT_FAIL" "wpctl could not change mute"
  fi
  level=$(audio_level "$AUDIO_KIND") || level="$new $new_muted"
  after=$(jq -cn --argjson v "${level% *}" --argjson m "${level#* }" '{volume: $v, muted: $m}')
  # shellcheck disable=SC2046  # the flag is optional
  undo=$(json_array audio volume "$cur" --muted "$([[ $muted == true ]] && echo on || echo off)" $(audio_kind_flag))
  change_end "$summary" "$before" "$after" "$undo"
  audio_osd "$AUDIO_KIND"
}

audio_cmd_mute() {
  audio_parse "$@"
  (( ${#AUDIO_ARGS[@]} <= 1 )) || usage_error "too many arguments"
  audio_need
  local level cur new
  level=$(audio_level "$AUDIO_KIND") || die "$EXIT_FAIL" "no default $AUDIO_KIND device"
  cur=${level#* }
  new=$(on_off "${AUDIO_ARGS[0]:-toggle}" "$cur") \
    || usage_error "expected on, off or toggle, got '${AUDIO_ARGS[0]}'"
  local before after summary undo
  summary="audio $([[ $AUDIO_KIND == input ]] && echo "microphone " || true)mute: $(audio_mute_word "$cur") -> $(audio_mute_word "$new")"
  before=$(jq -cn --argjson m "$cur" '{muted: $m}')
  after=$(jq -cn --argjson m "$new" '{muted: $m}')
  change_begin "$summary" "$before" "$after" || return 0
  wpctl set-mute "$(audio_target "$AUDIO_KIND")" "$([[ $new == true ]] && echo 1 || echo 0)" \
    || die "$EXIT_FAIL" "wpctl could not change mute"
  # shellcheck disable=SC2046  # the flag is optional
  undo=$(json_array audio mute "$([[ $cur == true ]] && echo on || echo off)" $(audio_kind_flag))
  change_end "$summary" "$before" "$after" "$undo"
  audio_osd "$AUDIO_KIND"
}

audio_cmd_device() {
  local kind=$1
  shift
  (( $# <= 1 )) || usage_error "too many arguments"
  audio_need
  local devices
  devices=$(audio_devices "$kind")
  if (( $# == 0 )); then
    jq -r '.[] | "\(.id)\(if .default then " *" else "  " end) \(.description)  (\(.name))"' <<<"$devices" | say_stream
    jq -n --argjson d "$devices" '{devices: $d}' | emit
    return 0
  fi
  local want=$1 pick cur
  pick=$(jq -c --arg w "$want" '[.[] | select((.id | tostring) == $w or .name == $w)][0] // empty' <<<"$devices")
  [[ -n $pick ]] || die "$EXIT_FAIL" "no $kind device '$want' (see '$KARMA_NAME audio $kind')"
  cur=$(jq -c '[.[] | select(.default)][0] // {name: null, description: "none"}' <<<"$devices")
  local before after summary undo=null
  summary="audio $kind: $(jq -r .description <<<"$cur") -> $(jq -r .description <<<"$pick")"
  before=$(jq -c '{device: .name}' <<<"$cur")
  after=$(jq -c '{device: .name}' <<<"$pick")
  change_begin "$summary" "$before" "$after" || return 0
  wpctl set-default "$(jq -r .id <<<"$pick")" || die "$EXIT_FAIL" "wpctl could not change the default device"
  if [[ -n $(jq -r '.name // empty' <<<"$cur") ]]; then
    undo=$(json_array audio "$kind" "$(jq -r .name <<<"$cur")")
  fi
  change_end "$summary" "$before" "$after" "$undo"
}
