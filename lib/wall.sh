# shellcheck shell=bash
# karma wall: the wallpaper setting. karma stores the choice in config.json
# and tells the Quickshell UI, which draws it (phase 3).

karma_register wall "Set or cycle the wallpaper"

help_wall() {
  cat <<EOF
Usage: $KARMA_NAME wall [status]
       $KARMA_NAME wall list
       $KARMA_NAME wall index
       $KARMA_NAME wall pick [--window]
       $KARMA_NAME wall set FILE
       $KARMA_NAME wall next | prev
       $KARMA_NAME wall clear
       $KARMA_NAME wall dir [DIRECTORY]
       $KARMA_NAME wall clock [on | off | toggle]

status  The current wallpaper and the directory that next/prev cycle through.
list    The images in the wallpaper directory.
index   Make a thumbnail of each image and measure its brightness and main
        colour, so that choosing it later is instant. Done on demand too.
pick    Choose from them. With --window inside the desktop this is the
        thumbnail strip of the Quickshell UI; in a terminal it is an fzf list
        with a preview of each image (in kitty), where Enter applies the
        image and keeps the list open.
set     Use FILE (png, jpg, jpeg or webp).
next    The image after the current one in the wallpaper directory, by name.
prev    The image before it.
clear   No wallpaper: the plain background colour.
dir     Show or set the wallpaper directory (default: ~/Pictures/Wallpapers).
clock   Show or hide the clock on the desktop (and the bars beside it that
        follow the music).

Every change is journaled and can be undone. The Quickshell UI draws the
wallpaper. While '$KARMA_NAME theme mode' is auto (the default), a bright
wallpaper switches every app to the light palette and a dark one back.
EOF
}

wall_current() {
  config_read | jq -r '.wallpaper // empty'
}

wall_dir() {
  config_read | jq -r --arg d "$HOME/Pictures/Wallpapers" '.wallpaper_dir // $d'
}

# ---- image analysis, cached -------------------------------------------------
#
# Wallpapers are often huge (8K PNGs take seconds to decode), so each image
# is read once: a small thumbnail is written to the cache, and the brightness
# and dominant colour are measured on that. The cache key includes the
# file's size and modification time, so an edited image is measured again.

WALL_CACHE=${XDG_CACHE_HOME:-$HOME/.cache}/$KARMA_NAME/wallpapers

wall_key() {
  printf '%s|%s' "$1" "$(stat -c '%s|%Y' -- "$1" 2>/dev/null)" | sha1sum | cut -c1-20
}

# wall_thumb FILE: print the path of its thumbnail, creating it if needed.
wall_thumb() {
  local file=$1 thumb
  [[ -n $file && -f $file ]] || return 1
  thumb=$WALL_CACHE/$(wall_key "$file").jpg
  if [[ ! -s $thumb ]]; then
    command -v magick >/dev/null 2>&1 || return 1
    mkdir -p -- "$WALL_CACHE"
    if magick "${file}[0]" -resize '480x480' -quality 85 "$thumb.tmp.jpg" 2>/dev/null; then
      mv -f -- "$thumb.tmp.jpg" "$thumb"
    else
      rm -f -- "$thumb.tmp.jpg"
      return 1
    fi
  fi
  printf '%s\n' "$thumb"
}

# wall_info FILE: print "MODE ACCENT HUE" for an image, from the cache if it
# is there. ACCENT and HUE are "-" when the image has no colour to speak of.
wall_info() {
  local file=$1 thumb info mode colour
  thumb=$(wall_thumb "$file") || return 1
  info=${thumb%.jpg}.info
  # (An entry with fewer than three fields is from an older version.)
  if [[ ! -s $info || $(wc -w <"$info") -lt 3 ]]; then
    mode=$(wall_measure_mode "$thumb") || return 1
    colour=$(wall_measure_accent "$thumb") || colour="- -"
    printf '%s %s\n' "$mode" "$colour" >"$info"
  fi
  cat -- "$info"
}

# wall_mode FILE: "light" for a bright image, "dark" otherwise and for no
# wallpaper. Fails if the image cannot be measured.
wall_mode() {
  local info
  if [[ -z $1 ]]; then
    echo dark
    return 0
  fi
  info=$(wall_info "$1") || return 1
  printf '%s\n' "${info%% *}"
}

# wall_accent FILE: the accent closest to the image's dominant colour. Fails
# without a wallpaper or for a nearly grey image, so that the caller falls
# back to the default accent.
wall_accent() {
  local info accent
  [[ -n $1 ]] || return 1
  info=$(wall_info "$1") || return 1
  read -r _ accent _ <<<"$info"
  [[ $accent != - ]] || return 1
  printf '%s\n' "$accent"
}

# wall_hue FILE: the hue (0-359) of the image's dominant colour. Fails like wall_accent.
wall_hue() {
  local info hue
  [[ -n $1 ]] || return 1
  info=$(wall_info "$1") || return 1
  read -r _ _ hue <<<"$info"
  [[ $hue =~ ^[0-9]+$ ]] || return 1
  printf '%s\n' "$hue"
}

wall_measure_mode() {
  local mean
  mean=$(magick "$1" -resize '64x64!' -colorspace Gray -format '%[fx:int(mean*100)]' info: 2>/dev/null) || return 1
  [[ $mean =~ ^[0-9]+$ ]] || return 1
  if (( mean >= 55 )); then echo light; else echo dark; fi
}

# The accent whose hue is closest to the image's dominant colour, and that hue.
wall_measure_accent() {
  local file=$1
  local accents
  accents=$(jq -r '. as $t | .accents[] | "\(.) \($t.palette[.])"' "$THEME_TOKENS")
  # Eight representative colours with their pixel counts, then pick the one
  # that is both common and colourful, and match its hue.
  magick "${file}[0]" -resize '96x96!' -colors 8 -depth 8 -format '%c' histogram:info: 2>/dev/null \
    | gawk -v accents="$accents" '
      function hue(r, g, b,    mx, mn, d, h) {
        mx = (r > g ? (r > b ? r : b) : (g > b ? g : b)); mn = (r < g ? (r < b ? r : b) : (g < b ? g : b))
        d = mx - mn; SAT = (mx == 0 ? 0 : d / mx); VAL = mx / 255
        if (d == 0) return 0
        if (mx == r) h = (g - b) / d % 6; else if (mx == g) h = (b - r) / d + 2; else h = (r - g) / d + 4
        h *= 60; if (h < 0) h += 360
        return h
      }
      function hexhue(hex) {
        return hue(strtonum("0x" substr(hex, 2, 2)), strtonum("0x" substr(hex, 4, 2)), strtonum("0x" substr(hex, 6, 2)))
      }
      match($0, /#[0-9A-Fa-f]{6}/) {
        h = hexhue(substr($0, RSTART, 7)); count = $1 + 0
        score = count * SAT * SAT * (VAL < 0.2 ? VAL * 5 : 1)
        if (SAT >= 0.25 && score > best) { best = score; besthue = h; found = 1 }
      }
      END {
        if (!found) exit 1
        n = split(accents, lines, "\n"); bestd = 999
        for (i = 1; i <= n; i++) {
          split(lines[i], kv, " "); d = hexhue(kv[2]) - besthue; if (d < 0) d = -d; if (d > 180) d = 360 - d
          if (d < bestd) { bestd = d; name = kv[1] }
        }
        print name, int(besthue)
      }'
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
  # With the mode on auto, a bright wallpaper switches everything to light
  # and a dark one back; with the accent on auto it follows the wallpaper's
  # dominant colour. A separate karma run, so it gets its own lock,
  # journal entry and reloads; its output is not part of this command's.
  if [[ $(theme_mode_pref) == auto || $(theme_accent_pref) == auto || $(theme_palette_pref) == wallpaper ]]; then
    flock -u 9 2>/dev/null || true
    local out
    if out=$("$KARMA_BIN" theme sync 2>&1 3>&1); then
      [[ $out == *"nothing to do"* ]] || say "${out%%$'\n'*}"
    else
      warn "could not match the theme to the wallpaper: ${out%%$'\n'*}"
    fi
  fi
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
    list)
      (( $# == 0 )) || usage_error "unexpected argument '$1'"
      wall_images | say_stream
      # Thumbnails are listed only if they are already cached ('wall index').
      local image thumb
      wall_images | while IFS= read -r image; do
        thumb=$WALL_CACHE/$(wall_key "$image").jpg
        [[ -s $thumb ]] || thumb=""
        printf '%s\t%s\n' "$image" "$thumb"
      done | jq -cRn --arg c "$(wall_current)" --arg d "$(wall_dir)" \
        '{directory: $d, current: (if $c == "" then null else $c end),
          images: [inputs | split("\t") | {path: .[0], name: (.[0] | split("/") | last | sub("\\.[^.]*$"; "")),
            thumb: (if .[1] == "" then null else .[1] end)}]}' | emit
      ;;
    index)
      (( $# == 0 )) || usage_error "unexpected argument '$1'"
      local image count=0
      while IFS= read -r image; do
        wall_info "$image" >/dev/null || warn "could not read $image"
        count=$(( count + 1 ))
      done < <(wall_images)
      say "Indexed $count image(s) in $(wall_dir)"
      jq -n --argjson n "$count" --arg c "$WALL_CACHE" '{images: $n, cache: $c}' | emit
      ;;
    pick)
      (( $# == 0 )) || usage_error "unexpected argument '$1'"
      tui_require
      [[ -n $(wall_images | head -n 1) ]] \
        || die "$EXIT_FAIL" "no images in $(wall_dir) (put some there, or see '$KARMA_NAME wall dir')"
      local preview='file -b {1}'
      if [[ -n ${KITTY_WINDOW_ID:-} ]] && command -v kitty >/dev/null 2>&1; then
        preview='kitty icat --clear --transfer-mode=memory --stdin=no --place=${FZF_PREVIEW_COLUMNS}x${FZF_PREVIEW_LINES}@0x0 {1}'
      fi
      wall_images | gawk -F/ '{ print $0 "\t" $NF }' \
        | tui_pick --delimiter '\t' --with-nth 2 --prompt 'Wallpaper > ' \
            --header "$(tilde "$(wall_dir)")"$'\n'"Enter: apply"$'\n'"Escape: close" \
            --preview "$preview" --preview-window 'right,65%' \
            --bind "enter:execute-silent('$KARMA_BIN' wall set {1})" >/dev/null || true
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
    clock)
      (( $# <= 1 )) || usage_error "too many arguments"
      local cur new
      cur=$(config_read | jq -r '.desktop_clock != false')
      if (( $# == 0 )); then
        say "Desktop clock: $([[ $cur == true ]] && echo on || echo off)"
        jq -n --argjson c "$cur" '{desktop_clock: $c}' | emit
        return 0
      fi
      new=$(on_off "$1" "$cur") || usage_error "expected on, off or toggle, got '$1'"
      local before after wc wn
      wc=$([[ $cur == true ]] && echo on || echo off)
      wn=$([[ $new == true ]] && echo on || echo off)
      before=$(jq -cn --argjson c "$cur" '{desktop_clock: $c}')
      after=$(jq -cn --argjson c "$new" '{desktop_clock: $c}')
      change_begin "wall clock: $wc -> $wn" "$before" "$after" || return 0
      karma_lock
      config_set desktop_clock "$new"
      change_end "wall clock: $wc -> $wn" "$before" "$after" "$(json_array wall clock "$wc")"
      ;;
    *) usage_error "unknown subcommand '$sub'" ;;
  esac
}
