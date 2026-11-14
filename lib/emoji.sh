# shellcheck shell=bash
# karma emoji: find an emoji by name and copy it.

karma_register emoji "Emoji picker"

help_emoji() {
  cat <<EOF
Usage: $KARMA_NAME emoji [pick] [--window]
       $KARMA_NAME emoji list
       $KARMA_NAME emoji copy EMOJI

pick  Search by name with fzf; Enter copies the emoji (the default).
list  Every emoji with its name.
copy  Put EMOJI on the clipboard.

The names come from the Unicode list (package unicode-emoji). Skin-tone
variants are left out to keep the list short.
EOF
}

emoji_file() {
  echo "${KARMA_SYSROOT:-}/usr/share/unicode/emoji/emoji-test.txt"
}

# "EMOJI<TAB>name" per line.
emoji_rows() {
  local f
  f=$(emoji_file)
  [[ -r $f ]] || die "$EXIT_ENV" "the emoji list is missing: install the package unicode-emoji"
  gawk '/; fully-qualified/ && !/skin tone/ {
    sub(/^[^#]*# /, "")
    emoji = $1
    sub(/^[^ ]+ E[0-9.]+ /, "")
    print emoji "\t" $0
  }' "$f"
}

emoji_copy() {
  require_wayland
  need wl-copy
  printf '%s' "$1" | wl-copy >/dev/null 2>&1 3>&- 9>&- || die "$EXIT_FAIL" "could not copy the emoji"
  say "Copied $1"
  jq -n --arg e "$1" '{emoji: $e, copied: true}' | emit
}

cmd_emoji() {
  local sub=${1:-pick}
  (( $# )) && shift
  karma_set_cmd "emoji $sub"
  case $sub in
    list)
      (( $# == 0 )) || usage_error "unexpected argument '$1'"
      local rows
      rows=$(emoji_rows)
      say_stream <<<"$rows"
      jq -cRn '{emoji: [inputs | split("\t") | {emoji: .[0], name: .[1]}]}' <<<"$rows" | emit
      ;;
    copy)
      (( $# == 1 )) && [[ -n $1 ]] || usage_error "copy needs exactly one emoji"
      emoji_copy "$1"
      ;;
    pick)
      (( $# == 0 )) || usage_error "unexpected argument '$1'"
      tui_require
      local row
      row=$(emoji_rows | tui_pick --prompt 'Emoji > ') || return 0
      emoji_copy "${row%%$'\t'*}"
      ;;
    *) usage_error "unknown subcommand '$sub'" ;;
  esac
}
