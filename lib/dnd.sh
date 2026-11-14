# shellcheck shell=bash
# karma dnd: do-not-disturb for notifications. The setting lives in
# config.json; the Quickshell notification server reads it.

karma_register dnd "Do not disturb: hold back notifications"

help_dnd() {
  cat <<EOF
Usage: $KARMA_NAME dnd [on | off | toggle]

Show or switch do-not-disturb. While it is on, only critical notifications
are shown; the others are dropped, not saved for later. The bar shows a
crossed-out bell. Journaled; '$KARMA_NAME undo' switches it back.
EOF
}

dnd_state() {
  config_read | jq -r '.dnd == true'
}

cmd_dnd() {
  (( $# <= 1 )) || usage_error "too many arguments"
  local cur new
  cur=$(dnd_state)
  if (( $# == 0 )); then
    say "Do not disturb: $([[ $cur == true ]] && echo on || echo off)"
    jq -n --argjson d "$cur" '{dnd: $d}' | emit
    return 0
  fi
  new=$(on_off "$1" "$cur") || usage_error "expected on, off or toggle, got '$1'"
  local word_cur word_new before after
  word_cur=$([[ $cur == true ]] && echo on || echo off)
  word_new=$([[ $new == true ]] && echo on || echo off)
  before=$(jq -cn --argjson d "$cur" '{dnd: $d}')
  after=$(jq -cn --argjson d "$new" '{dnd: $d}')
  change_begin "dnd: $word_cur -> $word_new" "$before" "$after" || return 0
  karma_lock
  config_set dnd "$new"
  change_end "dnd: $word_cur -> $word_new" "$before" "$after" "$(json_array dnd "$word_cur")"
  ui_ipc notify reload
}

karma_register notify "Go to the newest notification's app, or dismiss all"

help_notify() {
  cat <<EOF
Usage: $KARMA_NAME notify open
       $KARMA_NAME notify clear

open   Do what a click on the newest notification on screen does: bring the
       app that sent it forward, on whatever workspace it is.
clear  Dismiss every notification on screen.

Both need the interface (exit 3 without it).
EOF
}

cmd_notify() {
  local sub=${1:-}
  (( $# == 1 )) || usage_error "expected 'open' or 'clear'"
  karma_set_cmd "notify $sub"
  case $sub in
    open|clear) ;;
    *) usage_error "unknown subcommand '$sub'" ;;
  esac
  require_wayland
  need qs
  timeout 2 qs -c "$KARMA_NAME" ipc call notify "$sub" >/dev/null 2>&1 \
    || die "$EXIT_ENV" "the interface is not running"
  say "notify $sub"
  jq -n --arg a "$sub" '{action: $a}' | emit
}
