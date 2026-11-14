# shellcheck shell=bash
# karma shot: screenshots with grim and slurp, saved to a file and copied to
# the clipboard.

karma_register shot "Region, window or screen screenshot"

help_shot() {
  cat <<EOF
Usage: $KARMA_NAME shot [region | window | screen] [--no-save] [--no-copy] [--dir DIRECTORY]

region  Drag to select an area (the default). Escape cancels.
window  The focused window.
screen  The focused monitor.

The image is saved as karma-<date>-<time>.png in ~/Pictures/Screenshots (or
--dir, or "screenshot_dir" in config.json) and copied to the clipboard.
--no-save copies only; --no-copy saves only. Needs a Wayland session
(exit 3 otherwise). Screenshots are not journaled: they change no setting.
EOF
}

shot_dir() {
  config_read | jq -r --arg d "${XDG_PICTURES_DIR:-$HOME/Pictures}/Screenshots" '.screenshot_dir // $d'
}

cmd_shot() {
  local mode="" save=1 copy=1 dir=""
  while (( $# )); do
    case $1 in
      region|window|screen)
        [[ -z $mode ]] || usage_error "choose one of region, window or screen"
        mode=$1
        shift
        ;;
      --no-save) save=0; shift ;;
      --no-copy) copy=0; shift ;;
      --dir) [[ -n ${2:-} ]] || usage_error "--dir needs a directory"; dir=$2; shift 2 ;;
      *) usage_error "unexpected argument '$1'" ;;
    esac
  done
  mode=${mode:-region}
  karma_set_cmd "shot $mode"
  (( save || copy )) || usage_error "--no-save and --no-copy together leave nothing to do"
  dir=${dir:-$(shot_dir)}
  local path=""
  if (( save )); then
    # Two shots in the same second must not overwrite each other.
    local stamp n=1
    stamp=$(date +%Y%m%d-%H%M%S)
    path=$dir/$KARMA_NAME-$stamp.png
    while [[ -e $path ]]; do
      n=$(( n + 1 ))
      path=$dir/$KARMA_NAME-$stamp-$n.png
    done
  fi

  if (( OPT_DRY_RUN )); then
    say "shot $mode (dry run, nothing captured)"
    (( save )) && say "Would save to: $path"
    (( copy )) && say "Would copy the image to the clipboard"
    jq -n --arg m "$mode" --arg p "$path" --argjson c "$copy" \
      '{mode: $m, path: (if $p == "" then null else $p end), copied: ($c == 1), geometry: null}' | emit
    return 0
  fi

  require_wayland
  need grim
  (( copy )) && need wl-copy
  local -a grim_args=()
  local geometry=""
  case $mode in
    region)
      need slurp
      geometry=$(slurp 2>/dev/null) || die "$EXIT_FAIL" "selection cancelled"
      grim_args=(-g "$geometry")
      ;;
    window)
      require_hyprland
      geometry=$(hyprctl activewindow -j 2>/dev/null \
        | jq -r 'select(.at != null) | "\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"' 2>/dev/null) || geometry=""
      [[ -n $geometry ]] || die "$EXIT_FAIL" "no focused window"
      grim_args=(-g "$geometry")
      ;;
    screen)
      if [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]] && command -v hyprctl >/dev/null 2>&1; then
        geometry=$(hyprctl monitors -j 2>/dev/null | jq -r '.[] | select(.focused) | .name' 2>/dev/null) || geometry=""
      fi
      [[ -n $geometry ]] && grim_args=(-o "$geometry")
      ;;
  esac

  local file=$path
  if (( save )); then
    mkdir -p -- "$dir" || die "$EXIT_FAIL" "cannot create $dir"
  else
    local tmp
    karma_tmpdir tmp
    file=$tmp/shot.png
  fi
  grim "${grim_args[@]}" "$file" 2>/dev/null || die "$EXIT_FAIL" "grim could not capture the screen"
  if (( copy )); then
    # wl-copy stays in the background to serve the clipboard, so it gets none of our fds.
    wl-copy --type image/png <"$file" >/dev/null 2>&1 3>&- 9>&- \
      || warn "could not copy the image to the clipboard"
  fi

  if (( save )); then say "Saved $path$( (( copy )) && echo " and copied it to the clipboard" || true)"
  else say "Copied the screenshot to the clipboard"; fi
  if command -v notify-send >/dev/null 2>&1; then
    timeout 2 notify-send -a "$KARMA_NAME" -t 3000 "Screenshot" \
      "$( (( save )) && echo "$path" || echo "Copied to the clipboard")" >/dev/null 2>&1 3>&- || true
  fi
  jq -n --arg m "$mode" --arg p "$path" --argjson c "$copy" --arg g "$geometry" \
    '{mode: $m, path: (if $p == "" then null else $p end), copied: ($c == 1),
      geometry: (if $g == "" then null else $g end)}' | emit
}
