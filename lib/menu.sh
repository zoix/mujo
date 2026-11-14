# shellcheck shell=bash
# karma menu: the system menu. One fzf list that reaches every other command.

karma_register menu "System menu TUI (every command)"

help_menu() {
  cat <<EOF
Usage: $KARMA_NAME menu [pick] [--window]
       $KARMA_NAME menu list

pick  Choose an action with fzf (the default). Settings report their result
      and return to the menu; tools such as the Wi-Fi picker take over the
      window. Logout, reboot and shutdown ask for confirmation.
list  The menu entries and the command behind each one.
EOF
}

# Entries: label <TAB> kind <TAB> command
#   run     run `karma <command>`, show the result, return to the menu
#   tui     replace the menu with `karma <command>`
#   app     replace the menu with a program
#   shot    close the menu, then run `karma <command>` (so it is not in the picture)
#   accent  pick an accent, then run `karma theme accent <name>`
#   confirm ask first, then run `karma <command> --yes`
menu_entries() {
  local t=$'\t'
  cat <<EOF
Apps: open the launcher${t}tui${t}launch
Wi-Fi: networks${t}tui${t}net tui
Wi-Fi: switch the radio on or off${t}run${t}net wifi toggle
Bluetooth: devices${t}tui${t}bt tui
Bluetooth: switch on or off${t}run${t}bt power toggle
Audio: mixer${t}app${t}wiremix
Audio: mute or unmute${t}run${t}audio mute toggle
Audio: mute or unmute the microphone${t}run${t}audio mute toggle --input
Audio: volume up${t}run${t}audio volume +10
Audio: volume down${t}run${t}audio volume -10
Display: brightness up${t}run${t}display brightness +10
Display: brightness down${t}run${t}display brightness -10
Display: night light on or off${t}run${t}display night toggle
Theme: accent colour${t}accent${t}theme accent
Theme: reduce motion on${t}run${t}theme reduce-motion on
Theme: reduce motion off${t}run${t}theme reduce-motion off
Wallpaper: next${t}run${t}wall next
Wallpaper: previous${t}run${t}wall prev
Screenshot: region${t}shot${t}shot region
Screenshot: window${t}shot${t}shot window
Screenshot: screen${t}shot${t}shot screen
Clipboard: history${t}tui${t}clip
Keys: cheat sheet${t}tui${t}keys tui
Files${t}app${t}yazi
System monitor${t}app${t}btop
Status: everything at a glance${t}run${t}status
Journal: recent actions${t}run${t}log
Journal: undo the last action${t}run${t}undo
Power: lock${t}run${t}power lock
Power: suspend${t}run${t}power suspend
Power: log out${t}confirm${t}power logout
Power: reboot${t}confirm${t}power reboot
Power: shut down${t}confirm${t}power shutdown
EOF
}

cmd_menu() {
  local sub=${1:-pick}
  (( $# )) && shift
  karma_set_cmd "menu $sub"
  (( $# == 0 )) || usage_error "unexpected argument '$1'"
  case $sub in
    list)
      menu_entries | gawk -F'\t' '{ printf "%-40s %s\n", $1, ($2 == "app" ? $3 : "'"$KARMA_NAME"' " $3) }' | say_stream
      menu_entries | jq -cRn '{entries: [inputs | split("\t") | {label: .[0], kind: .[1], command: .[2]}]}' | emit
      ;;
    pick) menu_loop ;;
    *) usage_error "unknown subcommand '$sub'" ;;
  esac
}

menu_loop() {
  tui_require
  local row label kind command answer accent
  local -a argv
  while true; do
    row=$(menu_entries | tui_pick --delimiter '\t' --with-nth 1 --prompt 'Menu > ') || return 0
    IFS=$'\t' read -r label kind command <<<"$row"
    read -r -a argv <<<"$command"
    case $kind in
      tui) exec "$KARMA_BIN" "${argv[@]}" ;;
      app)
        command -v "${argv[0]}" >/dev/null 2>&1 || { warn "${argv[0]} is not installed"; tui_pause; continue; }
        exec "${argv[@]}"
        ;;
      shot)
        # Give the menu window time to close before the capture starts.
        tui_detach sh -c 'sleep 0.4; exec "$@"' sh "$KARMA_BIN" "${argv[@]}"
        return 0
        ;;
      accent)
        accent=$("$KARMA_BIN" theme accent --json | jq -r '.data.available[]' \
          | tui_pick --prompt 'Accent > ') || continue
        "$KARMA_BIN" theme accent "$accent" || true
        tui_pause
        ;;
      confirm)
        printf '%s? This cannot be undone. [y/N] ' "${label#*: }" >&2
        read -r answer || answer=""
        [[ $answer == [yY]* ]] || continue
        "$KARMA_BIN" "${argv[@]}" --yes || tui_pause
        ;;
      run)
        "$KARMA_BIN" "${argv[@]}" || true
        tui_pause
        ;;
    esac
  done
}
