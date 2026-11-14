# shellcheck shell=bash
# karma clip: clipboard history (cliphist) with an fzf picker.

karma_register clip "Clipboard history picker"

help_clip() {
  cat <<EOF
Usage: $KARMA_NAME clip [pick] [--window]
       $KARMA_NAME clip list [--limit N]
       $KARMA_NAME clip copy ID
       $KARMA_NAME clip clear --yes

pick   Choose an entry with fzf and copy it back to the clipboard (the
       default). Ctrl-X deletes the entry under the cursor. Needs Wayland.
list   The history, newest first (default 50 entries).
copy   Put the entry with that id (from 'list') back on the clipboard.
clear  Delete the whole history. Cannot be undone.
EOF
}

cmd_clip() {
  local sub=${1:-pick}
  (( $# )) && shift
  karma_set_cmd "clip $sub"
  need cliphist
  case $sub in
    pick) clip_cmd_pick "$@" ;;
    list) clip_cmd_list "$@" ;;
    copy)
      (( $# == 1 )) || usage_error "copy needs exactly one entry id (see '$KARMA_NAME clip list')"
      [[ $1 =~ ^[0-9]+$ ]] || usage_error "an entry id is a number, got '$1'"
      require_wayland
      need wl-copy
      cliphist decode "$1" | wl-copy >/dev/null 2>&1 3>&- 9>&- \
        || die "$EXIT_FAIL" "could not copy entry $1"
      say "Copied entry $1 to the clipboard"
      jq -n --arg id "$1" '{id: $id, copied: true}' | emit
      ;;
    clear) clip_cmd_clear "$@" ;;
    *) usage_error "unknown subcommand '$sub'" ;;
  esac
}

clip_cmd_list() {
  local limit=50
  while (( $# )); do
    case $1 in
      --limit) [[ ${2:-} =~ ^[0-9]+$ ]] || usage_error "--limit needs a number"; limit=$2; shift 2 ;;
      *) usage_error "unexpected argument '$1'" ;;
    esac
  done
  local entries
  entries=$(cliphist list 2>/dev/null | head -n "$limit" \
    | jq -cRn '[inputs | split("\t") | {id: .[0], preview: (.[1:] | join("\t"))}]') || entries='[]'
  if [[ $entries == "[]" ]]; then
    say "The clipboard history is empty."
  else
    jq -r '.[] | "\(.id)\t\(.preview)"' <<<"$entries" | say_stream
  fi
  jq -n --argjson e "$entries" '{entries: $e}' | emit
}

clip_cmd_clear() {
  (( $# == 0 )) || usage_error "unexpected argument '$1'"
  confirm_irreversible "Clearing the clipboard history"
  local count before
  count=$(cliphist list 2>/dev/null | wc -l)
  before=$(jq -cn --argjson n "$count" '{entries: $n}')
  change_begin "clip clear: $count entries deleted" "$before" '{"entries":0}' || return 0
  cliphist wipe || die "$EXIT_FAIL" "cliphist could not clear the history"
  change_end "clip clear: $count entries deleted" "$before" '{"entries":0}' null
}

clip_cmd_pick() {
  (( $# == 0 )) || usage_error "unexpected argument '$1'"
  tui_require
  require_wayland
  need wl-copy
  local out key row
  while true; do
    out=$(cliphist list 2>/dev/null \
      | tui_pick --delimiter '\t' --with-nth 2.. --prompt 'Clipboard > ' \
          --header 'Enter copy   Ctrl-X delete' --expect=ctrl-x) || return 0
    key=$(sed -n 1p <<<"$out")
    row=$(sed -n 2p <<<"$out")
    [[ -n $row ]] || return 0
    if [[ $key == ctrl-x ]]; then
      cliphist delete <<<"$row" || true
      continue
    fi
    cliphist decode <<<"$row" | wl-copy >/dev/null 2>&1 3>&- 9>&- \
      || die "$EXIT_FAIL" "could not copy the entry"
    return 0
  done
}
