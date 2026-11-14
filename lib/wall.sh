# shellcheck shell=bash
# karma wall: the wallpaper setting. karma stores the choice in config.json
# and tells the Quickshell UI, which draws it (phase 3).

karma_register wall "Set or cycle the wallpaper"

help_wall() {
  cat <<EOF
Usage: $KARMA_NAME wall [status]
       $KARMA_NAME wall set FILE
       $KARMA_NAME wall next | prev
       $KARMA_NAME wall clear
       $KARMA_NAME wall dir [DIRECTORY]

status  The current wallpaper and the directory that next/prev cycle through.
set     Use FILE (png, jpg, jpeg or webp).
next    The image after the current one in the wallpaper directory, by name.
prev    The image before it.
clear   No wallpaper: the plain background colour.
dir     Show or set the wallpaper directory (default: ~/Pictures/Wallpapers).

Every change is journaled and can be undone. The Quickshell UI draws the
wallpaper; until it runs, the setting is stored but nothing on screen changes.
EOF
}

wall_current() {
  config_read | jq -r '.wallpaper // empty'
}

wall_dir() {
  config_read | jq -r --arg d "$HOME/Pictures/Wallpapers" '.wallpaper_dir // $d'
}

wall_is_image() {
  [[ ${1,,} == *.png || ${1,,} == *.jpg || ${1,,} == *.jpeg || ${1,,} == *.webp ]]
}

# Images in the wallpaper directory, sorted by name, one per line.
wall_images() {
  local dir f
  dir=$(wall_dir)
  [[ -d $dir ]] || return 0
  for f in "$dir"/*; do
    [[ -f $f ]] && wall_is_image "$f" && printf '%s\n' "$f"
  done | LC_ALL=C sort
}

wall_state() {
  local count
  count=$(wall_images | wc -l)
  jq -cn --arg w "$(wall_current)" --arg d "$(wall_dir)" --argjson n "$count" \
    '{wallpaper: (if $w == "" then null else $w end), directory: $d, available: $n}'
}

# wall_apply NEW-PATH-OR-EMPTY: the plan/apply/record tail shared by set, next, prev and clear.
wall_apply() {
  local new=$1 cur before after undo
  cur=$(wall_current)
  before=$(jq -cn --arg w "$cur" '{wallpaper: (if $w == "" then null else $w end)}')
  after=$(jq -cn --arg w "$new" '{wallpaper: (if $w == "" then null else $w end)}')
  local summary="wall: ${cur:-none} -> ${new:-none}"
  change_begin "$summary" "$before" "$after" || return 0
  karma_lock
  config_set wallpaper "$(jq -c .wallpaper <<<"$after")"
  if [[ -n $cur ]]; then undo=$(json_array wall set "$cur"); else undo=$(json_array wall clear); fi
  change_end "$summary" "$before" "$after" "$undo"
  ui_ipc wallpaper set "$new"
}

cmd_wall() {
  local sub=${1:-status}
  (( $# )) && shift
  karma_set_cmd "wall $sub"
  case $sub in
    status)
      (( $# == 0 )) || usage_error "unexpected argument '$1'"
      local state
      state=$(wall_state)
      jq -r '"Wallpaper  \(.wallpaper // "none")", "Directory  \(.directory) (\(.available) image(s))"' <<<"$state" | say_stream
      printf '%s' "$state" | emit
      ;;
    set)
      (( $# == 1 )) || usage_error "set needs exactly one file"
      [[ -f $1 ]] || die "$EXIT_FAIL" "no such file: $1"
      wall_is_image "$1" || die "$EXIT_FAIL" "not a png, jpg, jpeg or webp file: $1"
      wall_apply "$(readlink -f -- "$1")"
      ;;
    next|prev)
      (( $# == 0 )) || usage_error "unexpected argument '$1'"
      local -a images
      mapfile -t images < <(wall_images)
      (( ${#images[@]} )) || die "$EXIT_FAIL" "no images in $(wall_dir) (see '$KARMA_NAME wall dir')"
      local cur i idx=-1 n=${#images[@]}
      cur=$(wall_current)
      for i in "${!images[@]}"; do
        [[ ${images[i]} == "$cur" ]] && idx=$i
      done
      if [[ $sub == next ]]; then
        idx=$(( (idx + 1) % n ))
      elif (( idx <= 0 )); then
        idx=$(( n - 1 ))
      else
        idx=$(( idx - 1 ))
      fi
      wall_apply "${images[idx]}"
      ;;
    clear)
      (( $# == 0 )) || usage_error "unexpected argument '$1'"
      wall_apply ""
      ;;
    dir)
      (( $# <= 1 )) || usage_error "too many arguments"
      local cur
      cur=$(wall_dir)
      if (( $# == 0 )); then
        say "Wallpaper directory: $cur"
        jq -n --arg d "$cur" '{directory: $d}' | emit
        return 0
      fi
      [[ -d $1 ]] || die "$EXIT_FAIL" "no such directory: $1"
      local new before after
      new=$(readlink -f -- "$1")
      before=$(jq -cn --arg d "$cur" '{directory: $d}')
      after=$(jq -cn --arg d "$new" '{directory: $d}')
      change_begin "wall dir: $cur -> $new" "$before" "$after" || return 0
      karma_lock
      config_set wallpaper_dir "$(jq -c .directory <<<"$after")"
      change_end "wall dir: $cur -> $new" "$before" "$after" "$(json_array wall dir "$cur")"
      ;;
    *) usage_error "unknown subcommand '$sub'" ;;
  esac
}
