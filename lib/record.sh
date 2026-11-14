# shellcheck shell=bash
# karma record: screen recording with wf-recorder.

karma_register record "Record the screen or a region to a video file"

help_record() {
  cat <<EOF
Usage: $KARMA_NAME record [toggle] [region | screen] [--audio] [--dir DIRECTORY]
       $KARMA_NAME record start [region | screen] [--audio] [--dir DIRECTORY]
       $KARMA_NAME record stop
       $KARMA_NAME record status

toggle  Start a recording, or stop the one that is running (the default).
start   region: drag an area first (the default). screen: the focused monitor.
        --audio also records what the speakers play.
stop    Finish the recording; the file's path is copied to the clipboard.
status  Whether a recording is running, and its file.

The video is saved as karma-<date>-<time>.mp4 in ~/Videos/Recordings (or
--dir, or "record_dir" in config.json). While one is running the bar shows
a red dot; clicking it stops the recording. Needs wf-recorder and a Wayland
session. Recordings are not journaled: they change no setting.
EOF
}

RECORD_PID=${XDG_RUNTIME_DIR:-/tmp}/$KARMA_NAME-record.pid

# Prints "PID<TAB>FILE" if a recording is running.
record_running() {
  local pid file
  [[ -f $RECORD_PID ]] || return 1
  IFS=$'\t' read -r pid file <"$RECORD_PID" || return 1
  if ! [[ $pid =~ ^[0-9]+$ ]] || ! kill -0 "$pid" 2>/dev/null; then
    rm -f -- "$RECORD_PID"
    return 1
  fi
  printf '%s\t%s\n' "$pid" "$file"
}

record_stop() {
  local pid file n=0
  IFS=$'\t' read -r pid file <<<"$1"
  # wf-recorder finishes the file when interrupted.
  kill -INT "$pid" 2>/dev/null || true
  while kill -0 "$pid" 2>/dev/null && (( n < 50 )); do sleep 0.1; n=$(( n + 1 )); done
  rm -f -- "$RECORD_PID"
  ui_ipc record state false
  if command -v wl-copy >/dev/null 2>&1 && [[ -n ${WAYLAND_DISPLAY:-} ]]; then
    printf '%s' "$file" | wl-copy >/dev/null 2>&1 3>&- 9>&- || true
  fi
  say "Saved $file"
  if command -v notify-send >/dev/null 2>&1; then
    timeout 2 notify-send -a "$KARMA_NAME" -t 4000 "Recording saved" "$file" >/dev/null 2>&1 3>&- || true
  fi
  jq -n --arg f "$file" '{recording: false, path: $f}' | emit
}

cmd_record() {
  local sub=toggle mode="" audio=0 dir=""
  case ${1:-} in
    toggle|start|stop|status) sub=$1; shift ;;
  esac
  while (( $# )); do
    case $1 in
      region|screen)
        [[ -z $mode ]] || usage_error "choose one of region or screen"
        mode=$1; shift ;;
      --audio) audio=1; shift ;;
      --dir) [[ -n ${2:-} ]] || usage_error "--dir needs a directory"; dir=$2; shift 2 ;;
      *) usage_error "unexpected argument '$1'" ;;
    esac
  done
  karma_set_cmd "record $sub"
  local running=""
  running=$(record_running) || running=""

  case $sub in
    status)
      if [[ -n $running ]]; then say "Recording to ${running#*$'\t'}"; else say "Not recording."; fi
      jq -n --arg f "${running#*$'\t'}" --argjson r "$([[ -n $running ]] && echo true || echo false)" \
        '{recording: $r, path: (if $r then $f else null end)}' | emit
      return 0
      ;;
    stop)
      [[ -n $running ]] || die "$EXIT_FAIL" "no recording is running"
      record_stop "$running"
      return 0
      ;;
    toggle)
      if [[ -n $running ]]; then record_stop "$running"; return 0; fi
      ;;
    start)
      [[ -z $running ]] || die "$EXIT_FAIL" "a recording is already running ('$KARMA_NAME record stop' ends it)"
      ;;
  esac

  mode=${mode:-region}
  dir=${dir:-$(config_read | jq -r --arg d "${XDG_VIDEOS_DIR:-$HOME/Videos}/Recordings" '.record_dir // $d')}
  local path
  path=$dir/$KARMA_NAME-$(date +%Y%m%d-%H%M%S).mp4
  if (( OPT_DRY_RUN )); then
    say "record $mode (dry run, nothing recorded)"
    say "Would save to: $path"
    jq -n --arg p "$path" --arg m "$mode" '{recording: false, mode: $m, path: $p}' | emit
    return 0
  fi
  require_wayland
  need wf-recorder
  local -a args=(-f "$path")
  if [[ $mode == region ]]; then
    need slurp
    local geometry
    geometry=$(slurp 2>/dev/null) || die "$EXIT_FAIL" "selection cancelled"
    args+=(-g "$geometry")
  elif [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]] && command -v hyprctl >/dev/null 2>&1; then
    local output
    output=$(hyprctl monitors -j 2>/dev/null | jq -r '.[] | select(.focused) | .name' 2>/dev/null) || output=""
    [[ -n $output ]] && args+=(-o "$output")
  fi
  (( audio )) && args+=(--audio)
  mkdir -p -- "$dir" || die "$EXIT_FAIL" "cannot create $dir"
  setsid wf-recorder "${args[@]}" >/dev/null 2>&1 </dev/null 3>&- 9>&- &
  local pid=$!
  sleep 0.3
  kill -0 "$pid" 2>/dev/null || die "$EXIT_FAIL" "wf-recorder could not start"
  printf '%s\t%s\n' "$pid" "$path" >"$RECORD_PID"
  ui_ipc record state true
  say "Recording to $path ('$KARMA_NAME record stop' ends it)"
  jq -n --arg p "$path" --arg m "$mode" '{recording: true, mode: $m, path: $p}' | emit
}
