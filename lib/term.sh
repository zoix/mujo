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
  term_place "$class"
  say "Toggled the drop-down terminal"
  jq -n '{started: false, toggled: true}' | emit
}

# term_place CLASS: put the drop-down terminal where its window rule would.
# The rule (mujo-drop in rules.lua, same fractions) only applies when the
# window opens, and the window lives for days: after a change of scale or
# of monitor it would keep the old size and sit off-centre.
term_place() {
  local class=$1 want have
  # Where it belongs on the monitor that shows it now; nothing while hidden.
  want=$(hyprctl monitors -j 2>/dev/null | jq -r '
    first(.[] | select(.specialWorkspace.name == "special:term"))
    | .scale as $s
    | (if .transform % 2 == 1 then [.height, .width] else [.width, .height] end
       | map(. / $s)) as [$w, $h]
    | [.x + $w * 0.1, .y + $h * 0.04, $w * 0.8, $h * 0.5] | map(floor) | @tsv' \
    2>/dev/null) || return 0
  [[ -n $want ]] || return 0
  have=$(hyprctl clients -j 2>/dev/null | jq -r --arg c "$class" \
    'first(.[] | select(.class == $c)) | .at + .size | @tsv') || return 0
  [[ $want == "$have" ]] && return 0
  local x y w h
  read -r x y w h <<<"$want"
  hyprctl dispatch "hl.dsp.window.resize({ x = $w, y = $h, window = \"class:$class\" })" >/dev/null 2>&1
  hyprctl dispatch "hl.dsp.window.move({ x = $x, y = $y, window = \"class:$class\" })" >/dev/null 2>&1
  return 0
}
