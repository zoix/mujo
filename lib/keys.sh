# shellcheck shell=bash
# karma keys: the keybinding cheat sheet, read live from Hyprland.

karma_register keys "Keybinding cheat sheet (TUI: keys tui)"

help_keys() {
  cat <<EOF
Usage: $KARMA_NAME keys [list]
       $KARMA_NAME keys tui [--window]

list  Every keybinding with its description (the default).
tui   Search the list with fzf.

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
    [.[] | (.modmask | mods) as $mods
     | {keys: (($mods + [keyname]) | join(" + ")),
        description: (if .has_description and .description != "" then .description else .dispatcher end),
        mods: $mods, key, locked, repeat, mouse}]'
}

keys_table() {
  jq -r '.[] | "\(.keys)\t\(.description)"' <<<"$1" | column -t -s $'\t'
}

cmd_keys() {
  local sub=${1:-list}
  (( $# )) && shift
  karma_set_cmd "keys $sub"
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
    keys_table "$binds" | tui_pick --prompt 'Keys > ' --header 'Type to search; Escape closes' >/dev/null || true
    return 0
  fi
  keys_table "$binds" | say_stream
  jq -n --argjson b "$binds" '{binds: $b}' | emit
}
