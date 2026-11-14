# shellcheck shell=bash
# karma menu: the system menu. One fzf list that reaches every other command.

karma_register menu "System menu TUI (every command)"

help_menu() {
  cat <<EOF
Usage: $KARMA_NAME menu [pick] [--window]
       $KARMA_NAME menu list
       $KARMA_NAME menu run LABEL

pick  Choose an action with fzf (the default). Settings report their result
      and return to the menu; tools such as the Wi-Fi picker take over the
      window. Logout, reboot and shutdown ask for confirmation.
list  The menu entries and the command behind each one, with the accent
      and mode choices written out one per entry.
run   Do what the entry with that exact label does, without a terminal: a
      setting is changed and its result shown as a notification, a tool
      opens in a floating window. The Quickshell launcher uses this.
EOF
}

# Entries: label <TAB> kind <TAB> command
#   run     run `karma <command>`, show the result, return to the menu
#   tui     replace the menu with `karma <command>`
#   app     replace the menu with a program
#   shot    close the menu, then run `karma <command>` (so it is not in the picture)
#   accent  pick an accent, then run `karma theme accent <name>`
#   mode    pick dark, light or auto, then run `karma theme mode <name>`
#   confirm ask first, then run `karma <command> --yes`
menu_entries() {
  local t=$'\t'
  cat <<EOF
Apps: open the launcher${t}tui${t}launch
Wi-Fi: networks${t}tui${t}net tui
Wi-Fi: switch the radio on or off${t}run${t}net wifi toggle
Bluetooth: devices${t}tui${t}bt tui
Bluetooth: switch on or off${t}run${t}bt power toggle
Audio: mixer${t}tui${t}audio tui
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
Notifications: do not disturb on or off${t}run${t}dnd toggle
Wallpaper: choose${t}tui${t}wall pick
Theme: dark, light or follow the wallpaper${t}mode${t}theme mode
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

# The entries for list and run: sub-menus are written out, and the power
# entries are left to the power panel (or `karma power`).
menu_entries_flat() {
  local t=$'\t' a
  menu_entries | while IFS=$'\t' read -r label kind command; do
    case $kind in
      accent)
        for a in $(jq -r '.accents | join(" ")' "$THEME_TOKENS"); do
          printf '%s\n' "Theme: accent $a${t}run${t}theme accent $a"
        done
        printf '%s\n' "Theme: accent from the wallpaper${t}run${t}theme accent auto"
        ;;
      mode)
        printf '%s\n' "Theme: light${t}run${t}theme mode light" "Theme: dark${t}run${t}theme mode dark" \
          "Theme: light or dark from the wallpaper${t}run${t}theme mode auto"
        ;;
      *) printf '%s\n' "$label${t}$kind${t}$command" ;;
    esac
  done
}

# menu_run LABEL: perform one entry without a terminal.
menu_run() {
  local row label kind command out
  local -a argv
  row=$(menu_entries_flat | gawk -F'\t' -v l="$1" '$1 == l && !found { print; found = 1 }')
  [[ -n $row ]] || die "$EXIT_FAIL" "no menu entry '$1' (see '$KARMA_NAME menu list')"
  IFS=$'\t' read -r label kind command <<<"$row"
  read -r -a argv <<<"$command"
  if (( OPT_DRY_RUN )); then
    say "Would run ($kind): $command"
    jq -n --arg l "$label" --arg k "$kind" --arg c "$command" '{label: $l, kind: $k, command: $c, done: false}' | emit
    return 0
  fi
  case $kind in
    run)
      # The whole output is read before the first line is taken: cutting the
      # pipe early would kill the command in the middle of its work.
      out=$("$KARMA_BIN" "${argv[@]}" 2>&1 3>&1) || true
      out=${out%%$'\n'*}
      if ui_session && command -v notify-send >/dev/null 2>&1; then
        timeout 2 notify-send -a "$KARMA_NAME" -t 4000 "$label" "$out" >/dev/null 2>&1 3>&- || true
      fi
      say "$out"
      ;;
    tui) "$KARMA_BIN" "${argv[@]}" --window ;;
    app)
      require_wayland
      need kitty "${argv[0]}"
      tui_detach kitty -e "${argv[@]}"
      ;;
    shot) tui_detach sh -c 'sleep 0.4; exec "$@"' sh "$KARMA_BIN" "${argv[@]}" ;;
    confirm) "$KARMA_BIN" power --window ;;
  esac
  jq -n --arg l "$label" --arg k "$kind" --arg c "$command" '{label: $l, kind: $k, command: $c, done: true}' | emit
}

cmd_menu() {
  local sub=${1:-pick}
  (( $# )) && shift
  karma_set_cmd "menu $sub"
  if [[ $sub == run ]]; then
    (( $# == 1 )) || usage_error "run needs exactly one label (see '$KARMA_NAME menu list')"
    menu_run "$1"
    return 0
  fi
  (( $# == 0 )) || usage_error "unexpected argument '$1'"
  case $sub in
    list)
      menu_entries_flat | gawk -F'\t' '{ printf "%-40s %s\n", $1, ($2 == "app" ? $3 : "'"$KARMA_NAME"' " $3) }' | say_stream
      menu_entries_flat | jq -cRn '{entries: [inputs | split("\t") | {label: .[0], kind: .[1], command: .[2]}]}' | emit
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
      mode)
        accent=$(printf '%s\n' auto dark light | tui_pick --prompt 'Mode > ') || continue
        "$KARMA_BIN" theme mode "$accent" || true
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
