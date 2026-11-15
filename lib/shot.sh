# shellcheck shell=bash
# mujo shot: screenshots with grim and slurp, saved to a file and copied to
# the clipboard.

mujo_register shot "Region, window or screen screenshot"

help_shot() {
  cat <<EOF
Usage: $MUJO_NAME shot [region | window | screen] [--no-save] [--no-copy] [--dir DIRECTORY]
       $MUJO_NAME shot region [--geometry "X,Y WxH" | --slurp]
       $MUJO_NAME shot text [--geometry "X,Y WxH"] [--lang LANGUAGE]
       $MUJO_NAME shot copy FILE
       $MUJO_NAME shot open FILE

region  Choose an area (the default). With the interface running, the screen
        freezes: click a window or drag a rectangle, Escape cancels. Without
        it, or with --slurp, slurp draws the selection. --geometry takes the
        area as given and asks nothing.
window  The focused window.
screen  The focused monitor.
text    Drag an area; the text in it is read (tesseract) and copied to the
        clipboard. No image is kept. --lang names the language data to use
        (default eng; e.g. spa needs the package tesseract-data-spa).

copy    Put a saved screenshot on the clipboard again.
open    Open a saved screenshot or recording in the program for its type.

The image is saved as mujo-<date>-<time>.png in ~/Pictures/Screenshots (or
--dir, or "screenshot_dir" in config.json) and copied to the clipboard.
--no-save copies only; --no-copy saves only. Needs a Wayland session
(exit 3 otherwise). Screenshots are not journaled: they change no setting.
EOF
}

shot_dir() {
  config_read | jq -r --arg d "${XDG_PICTURES_DIR:-$HOME/Pictures}/Screenshots" '.screenshot_dir // $d'
}

# shot_text GEOMETRY LANG: read the text in an area and copy it.
shot_text() {
  local geometry=$1 lang=$2 tmp text
  if (( OPT_DRY_RUN )); then
    say "shot text (dry run, nothing captured)"
    jq -n '{mode: "text", text: null, copied: false}' | emit
    return 0
  fi
  require_wayland
  need grim tesseract wl-copy
  if [[ -z $geometry ]]; then
    need slurp
    geometry=$(slurp 2>/dev/null) || die "$EXIT_FAIL" "selection cancelled"
  fi
  mujo_tmpdir tmp
  grim -g "$geometry" "$tmp/text.png" 2>/dev/null || die "$EXIT_FAIL" "grim could not capture the screen"
  text=$(tesseract "$tmp/text.png" - -l "$lang" 2>/dev/null) \
    || die "$EXIT_FAIL" "tesseract could not read the image (is tesseract-data-$lang installed?)"
  # Trailing blank lines and the form feed tesseract ends with are dropped.
  text=$(printf '%s' "$text" | tr -d '\f' | sed -e :a -e '/^[[:space:]]*$/{$d;N;ba' -e '}')
  if [[ -z ${text//[[:space:]]/} ]]; then
    ui_notify "Text from screen" "No text was found in that area."
    die "$EXIT_FAIL" "no text was found in that area"
  fi
  printf '%s' "$text" | wl-copy >/dev/null 2>&1 3>&- 9>&- || die "$EXIT_FAIL" "could not copy the text"
  say "Copied $(wc -w <<<"$text") word(s) to the clipboard"
  if ui_session && command -v notify-send >/dev/null 2>&1; then
    timeout 2 notify-send -a "$MUJO_NAME" -t 4000 "Text copied" "${text:0:120}" >/dev/null 2>&1 3>&- || true
  fi
  jq -n --arg t "$text" '{mode: "text", text: $t, copied: true}' | emit
}

# shot_file SUB FILE: copy a saved screenshot to the clipboard again, or open
# a screenshot or recording in the program for its type.
shot_file() {
  local sub=$1 file=${2:-}
  [[ -n $file ]] || usage_error "$sub needs a file"
  [[ -f $file ]] || die "$EXIT_FAIL" "no such file: $file"
  mujo_set_cmd "shot $sub"
  if (( OPT_DRY_RUN )); then
    say "Would $sub $file"
    jq -n --arg f "$file" --arg a "$sub" '{file: $f, action: $a, done: false}' | emit
    return 0
  fi
  require_wayland
  if [[ $sub == copy ]]; then
    need wl-copy
    local mime
    mime=$(file -b --mime-type -- "$file" 2>/dev/null) || mime=image/png
    wl-copy --type "$mime" <"$file" >/dev/null 2>&1 3>&- 9>&- \
      || die "$EXIT_FAIL" "could not copy $file"
    ui_notify "Copied" "$(basename -- "$file")"
    say "Copied $file"
  else
    need xdg-open
    tui_detach xdg-open "$file"
    say "Opened $file"
  fi
  jq -n --arg f "$file" --arg a "$sub" '{file: $f, action: $a, done: true}' | emit
}

cmd_shot() {
  if [[ ${1:-} == copy || ${1:-} == open ]]; then
    (( $# <= 2 )) || usage_error "unexpected argument '$3'"
    shot_file "$@"
    return 0
  fi
  local mode="" save=1 copy=1 dir="" given="" use_slurp=0 lang=eng
  while (( $# )); do
    case $1 in
      --lang) [[ ${2:-} =~ ^[a-z_+]+$ ]] || usage_error "--lang needs a language such as eng"; lang=$2; shift 2 ;;
      region|window|screen|text)
        [[ -z $mode ]] || usage_error "choose one of region, window, screen or text"
        mode=$1
        shift
        ;;
      --geometry)
        [[ ${2:-} =~ ^-?[0-9]+,-?[0-9]+\ [0-9]+x[0-9]+$ ]] || usage_error "--geometry needs \"X,Y WxH\""
        given=$2
        shift 2
        ;;
      --slurp) use_slurp=1; shift ;;
      --no-save) save=0; shift ;;
      --no-copy) copy=0; shift ;;
      --dir) [[ -n ${2:-} ]] || usage_error "--dir needs a directory"; dir=$2; shift 2 ;;
      *) usage_error "unexpected argument '$1'" ;;
    esac
  done
  mode=${mode:-region}
  mujo_set_cmd "shot $mode"
  if [[ $mode == text ]]; then
    shot_text "$given" "$lang"
    return 0
  fi
  (( save || copy )) || usage_error "--no-save and --no-copy together leave nothing to do"
  dir=${dir:-$(shot_dir)}
  local path=""
  if (( save )); then
    # Two shots in the same second must not overwrite each other.
    local stamp n=1
    stamp=$(date +%Y%m%d-%H%M%S)
    path=$dir/$MUJO_NAME-$stamp.png
    while [[ -e $path ]]; do
      n=$(( n + 1 ))
      path=$dir/$MUJO_NAME-$stamp-$n.png
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
      if [[ -n $given ]]; then
        geometry=$given
      elif (( ! use_slurp )) && command -v qs >/dev/null 2>&1 \
           && timeout 2 qs -c "$MUJO_NAME" ipc call picker open >/dev/null 2>&1; then
        # The interface's picker takes over; it runs this command again
        # with --geometry once an area is chosen.
        say "Choose the area on screen."
        jq -n '{mode: "region", path: null, copied: false, geometry: null, picking: true}' | emit
        return 0
      else
        need slurp
        geometry=$(slurp 2>/dev/null) || die "$EXIT_FAIL" "selection cancelled"
      fi
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
    mujo_tmpdir tmp
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
  if ui_session && command -v notify-send >/dev/null 2>&1; then
    timeout 2 notify-send -a "$MUJO_NAME" -t 3000 "Screenshot" \
      "$( (( save )) && echo "$path" || echo "Copied to the clipboard")" >/dev/null 2>&1 3>&- || true
  fi
  jq -n --arg m "$mode" --arg p "$path" --argjson c "$copy" --arg g "$geometry" \
    '{mode: $m, path: (if $p == "" then null else $p end), copied: ($c == 1),
      geometry: (if $g == "" then null else $g end)}' | emit
}
