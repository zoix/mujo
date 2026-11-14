# shellcheck shell=bash
# karma keys: the keybinding cheat sheet, read live from Hyprland.

karma_register keys "Keybinding cheat sheet (TUI: keys tui)"

help_keys() {
  cat <<EOF
Usage: $KARMA_NAME keys [list]
       $KARMA_NAME keys tui [--window]
       $KARMA_NAME keys run DESCRIPTION

list  Every keybinding with its description (the default).
tui   Search the list with fzf; Enter does what the chosen binding does.
run   Do what the binding with that exact description does, as if its keys
      had been pressed. Bindings that only make sense on their key (dragging
      a window with the mouse, the lid switch) cannot be run.

The list comes from 'hyprctl binds -j', so it always matches what is bound.
Needs a running Hyprland session (exit 3 otherwise).
EOF
}

# keys_json: JSON array of {keys, description, mods, key, locked, repeat, mouse}.
keys_json() {
  hyprctl binds -j 2>/dev/null | jq -c '
    def mods: . as $m
      | [[64, "SUPER"], [4, "CTRL"], [8, "ALT"], [1, "SHIFT"]]
      | map(select((($m / .[0]) | floor) % 2 == 1) | .[1]);
    def keyname:
      if .key == "" then "code:\(.keycode)"
      elif .key == "mouse:272" then "left mouse"
      elif .key == "mouse:273" then "right mouse"
      elif .key == "mouse_down" then "scroll down"
      elif .key == "mouse_up" then "scroll up"
      elif (.key | startswith("switch:")) then (.key | sub("^switch:"; "") | sub(":"; " "))
      else .key end;
    ($actions[0] // [] | map({key: .description, value: .action}) | from_entries) as $run
    | [.[] | (.modmask | mods) as $mods
     | {keys: (($mods + [keyname]) | join(" + ")),
        description: (if .has_description and .description != "" then .description else .dispatcher end),
        mods: $mods, key, locked, repeat, mouse,
        action: (if .has_description then $run[.description] else null end)}]' \
    --slurpfile actions <(cat "${XDG_RUNTIME_DIR:-/nonexistent}/karma-binds.json" 2>/dev/null || echo "[]")
}

keys_table() {
  jq -r '.[] | "\(.keys)\t\(.description)"' <<<"$1" | column -t -s $'\t'
}

cmd_keys() {
  local sub=${1:-list}
  (( $# )) && shift
  karma_set_cmd "keys $sub"
  if [[ $sub == run ]]; then
    (( $# == 1 )) || usage_error "run needs exactly one description (see '$KARMA_NAME keys')"
    require_hyprland
    local action
    action=$(keys_json | jq -r --arg d "$1" '[.[] | select(.description == $d)][0] | .action // empty')
    [[ -n $action ]] || die "$EXIT_FAIL" "no binding '$1' that can be run (see '$KARMA_NAME keys')"
    if (( OPT_DRY_RUN )); then
      say "Would run: $action"
    else
      [[ $(hyprctl dispatch "$action" 2>&1) == ok ]] || die "$EXIT_FAIL" "Hyprland did not accept: $action"
      say "Ran: $1"
    fi
    jq -n --arg d "$1" --arg a "$action" '{description: $d, action: $a}' | emit
    return 0
  fi
  (( $# == 0 )) || usage_error "unexpected argument '$1'"
  case $sub in
    list|tui) ;;
    *) usage_error "unknown subcommand '$sub'" ;;
  esac
  [[ $sub == tui ]] && tui_require
  require_hyprland
  need column
  local binds
  binds=$(keys_json) || binds=""
  [[ -n $binds ]] || die "$EXIT_FAIL" "could not read the keybindings from Hyprland"
  if [[ $sub == tui ]]; then
    local row
    row=$(jq -r '.[] | "\(.description)\t\(.keys)"' <<<"$binds" | column -t -s $'\t' -o $'\t' \
      | tui_pick --delimiter '\t' --prompt 'Keys > ' --header 'Type to search; Enter runs it; Escape closes') || return 0
    row=${row%%$'\t'*}
    "$KARMA_BIN" keys run "${row%"${row##*[![:space:]]}"}" || true
    return 0
  fi
  keys_table "$binds" | say_stream
  jq -n --argjson b "$binds" '{binds: $b}' | emit
}
