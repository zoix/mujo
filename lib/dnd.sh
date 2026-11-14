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
