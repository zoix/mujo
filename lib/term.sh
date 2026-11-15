# shellcheck shell=bash
# mujo term: a drop-down terminal that one key shows and hides.

mujo_register term "Show or hide the drop-down terminal"

help_term() {
  cat <<EOF
Usage: $MUJO_NAME term

Shows the drop-down terminal over whatever is on screen, or hides it again.
It is one Ghostty window that keeps running while hidden, so what was in it
is still there the next time. The first call starts it. Needs Hyprland.
EOF
}

cmd_term() {
  (( $# == 0 )) || usage_error "unexpected argument '$1'"
  local class=$MUJO_NAME.drop
  if (( OPT_DRY_RUN )); then
    say "Would show or hide the drop-down terminal"
    jq -n '{started: false, toggled: false}' | emit
    return 0
  fi
  require_hyprland
  local have
  have=$(hyprctl clients -j 2>/dev/null | jq --arg c "$class" '[.[] | select(.class == $c)] | length') || have=0
  if (( have == 0 )); then
    # A window rule (rules.lua) puts it on its own hidden workspace, which
    # opening the window also shows.
    tui_term "$class" "terminal"
    say "Started the drop-down terminal"
    jq -n '{started: true, toggled: true}' | emit
    return 0
  fi
  [[ $(hyprctl dispatch 'hl.dsp.workspace.toggle_special("term")' 2>&1) == ok ]] \
    || die "$EXIT_FAIL" "Hyprland did not toggle the drop-down terminal"
  say "Toggled the drop-down terminal"
  jq -n '{started: false, toggled: true}' | emit
}
