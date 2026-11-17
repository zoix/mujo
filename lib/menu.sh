# shellcheck shell=bash
# mujo menu: the system menu. One fzf list that reaches every other command.

mujo_register menu "System menu TUI (every command)"

help_menu() {
  cat <<EOF
Usage: $MUJO_NAME menu [pick] [--window]
       $MUJO_NAME menu list
       $MUJO_NAME menu run LABEL

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
#   run     run `mujo <command>`, show the result, return to the menu
#   show    the same for commands with long or interactive output: from the
#           interface they get a floating terminal that stays open
#   tui     replace the menu with `mujo <command>`
#   app     replace the menu with a program
#   shot    close the menu, then run `mujo <command>` (so it is not in the picture)
#   accent  pick an accent, then run `mujo theme accent <name>`
#   mode    pick dark, light or auto, then run `mujo theme mode <name>`
#   confirm ask first, then run `mujo <command> --yes`
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
Display: bigger text (screen scale up)${t}run${t}display scale bigger
Display: smaller text (screen scale down)${t}run${t}display scale smaller
Theme: accent colour${t}accent${t}theme accent
Theme: colours from the wallpaper${t}run${t}theme palette wallpaper
Theme: Catppuccin colours${t}run${t}theme palette catppuccin
Theme: glass (see-through panels) on or off${t}run${t}theme glass toggle
Theme: gentle motion (slower, fades)${t}run${t}theme motion gentle
Theme: normal motion${t}run${t}theme motion normal
Theme: reduce motion on${t}run${t}theme reduce-motion on
Theme: reduce motion off${t}run${t}theme reduce-motion off
Notifications: do not disturb on or off${t}run${t}dnd toggle
Focus: start 25 minutes${t}run${t}focus start 25
Focus: start 50 minutes${t}run${t}focus start 50
Focus: stop${t}run${t}focus stop
Weather: now${t}run${t}weather
Power: follow the charger on or off${t}run${t}power auto toggle
Time zone: follow where you are, on or off${t}run${t}time auto toggle
Keyboard: built-in off with an external one, on or off${t}run${t}keyboard auto toggle
Keyboard: flash the Voyager with the newest download${t}show${t}voyager flash
Power: 60 Hz on battery on or off${t}run${t}power battery refresh toggle
Power: solid panels on battery on or off${t}run${t}power battery solid toggle
Power: charge limit 80%${t}show${t}power limit 80
Power: charge limit off${t}show${t}power limit off
Power: charge limit on or off${t}show${t}power limit toggle
Wallpaper: choose${t}tui${t}wall pick
Theme: dark, light or follow the wallpaper${t}mode${t}theme mode
Wallpaper: desktop clock on or off${t}run${t}wall clock toggle
Wallpaper: next${t}run${t}wall next
Wallpaper: previous${t}run${t}wall prev
Screenshot: region${t}shot${t}shot region
Screenshot: window${t}shot${t}shot window
Screenshot: screen${t}shot${t}shot screen
Screenshot: copy the text in an area${t}shot${t}shot text
Recording: start or stop (area)${t}shot${t}record toggle region
Recording: start or stop (screen)${t}shot${t}record toggle screen
Recording: screen with sound${t}shot${t}record start screen --audio
Clipboard: history${t}tui${t}clip
Keys: cheat sheet${t}tui${t}keys tui
Calculator${t}tui${t}calc
Emoji: find and copy${t}tui${t}emoji
Terminal: show or hide the drop-down${t}run${t}term
Files${t}app${t}yazi
System monitor${t}app${t}btop
Status: everything at a glance${t}run${t}status
Journal: recent actions${t}run${t}log
Journal: undo the last action${t}run${t}undo
Packages: search and install${t}tui${t}pkg install
Packages: remove${t}tui${t}pkg remove
System: quick settings${t}tui${t}status
System: dashboard${t}tui${t}sys
System: about this machine${t}tui${t}about
System: health check (doctor)${t}show${t}doctor
System: update mujo and packages${t}show${t}update
System: check for updates now${t}run${t}update check --refresh
System: show what rolling back the last update would do${t}show${t}update rollback --dry-run
System: show what uninstall would do${t}show${t}uninstall --dry-run
Power: lock${t}run${t}power lock
Power: suspend${t}run${t}power suspend
Power: log out${t}confirm${t}power logout
Power: reboot${t}confirm${t}power reboot
Power: shut down${t}confirm${t}power shutdown
EOF
}

# The entries for list and run: sub-menus are written out, and the power
# entries are left to the power panel (or `mujo power`).
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
  [[ -n $row ]] || die "$EXIT_FAIL" "no menu entry '$1' (see '$MUJO_NAME menu list')"
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
      out=$("$MUJO_BIN" "${argv[@]}" 2>&1 3>&1) || true
      out=${out%%$'\n'*}
      if ui_session && command -v notify-send >/dev/null 2>&1; then
        timeout 2 notify-send -a "$MUJO_NAME" -t 4000 "$label" "$out" >/dev/null 2>&1 3>&- || true
      fi
      say "$out"
      ;;
    tui) "$MUJO_BIN" "${argv[@]}" --window ;;
    show)
      require_wayland
      # A floating terminal that runs the command and waits, so the output
      # can be read (and sudo can ask for the password).
      tui_term "$MUJO_NAME.tui.show" "$MUJO_NAME ${argv[*]}" \
        sh -c '"$@"; printf "\nPress Enter to close "; read -r _' sh "$MUJO_BIN" "${argv[@]}"
      ;;
    app)
      require_wayland
      need "${argv[0]}"
      tui_term "" "" "${argv[@]}"
      ;;
    shot) tui_detach sh -c 'sleep 0.4; exec "$@"' sh "$MUJO_BIN" "${argv[@]}" ;;
    confirm) "$MUJO_BIN" power --window ;;
  esac
  jq -n --arg l "$label" --arg k "$kind" --arg c "$command" '{label: $l, kind: $k, command: $c, done: true}' | emit
}

cmd_menu() {
  local sub=${1:-pick}
  (( $# )) && shift
  mujo_set_cmd "menu $sub"
  if [[ $sub == run ]]; then
    (( $# == 1 )) || usage_error "run needs exactly one label (see '$MUJO_NAME menu list')"
    menu_run "$1"
    return 0
  fi
  (( $# == 0 )) || usage_error "unexpected argument '$1'"
  case $sub in
    list)
      menu_entries_flat | gawk -F'\t' '{ printf "%-40s %s\n", $1, ($2 == "app" ? $3 : "'"$MUJO_NAME"' " $3) }' | say_stream
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
      tui) exec "$MUJO_BIN" "${argv[@]}" ;;
      app)
        command -v "${argv[0]}" >/dev/null 2>&1 || { warn "${argv[0]} is not installed"; tui_pause; continue; }
        exec "${argv[@]}"
        ;;
      shot)
        # Give the menu window time to close before the capture starts.
        tui_detach sh -c 'sleep 0.4; exec "$@"' sh "$MUJO_BIN" "${argv[@]}"
        return 0
        ;;
      accent)
        accent=$("$MUJO_BIN" theme accent --json | jq -r '.data.available[]' \
          | tui_pick --prompt 'Accent > ') || continue
        "$MUJO_BIN" theme accent "$accent" || true
        tui_pause
        ;;
      mode)
        accent=$(printf '%s\n' auto dark light | tui_pick --prompt 'Mode > ') || continue
        "$MUJO_BIN" theme mode "$accent" || true
        tui_pause
        ;;
      confirm)
        printf '%s? This cannot be undone. [y/N] ' "${label#*: }" >&2
        read -r answer || answer=""
        [[ $answer == [yY]* ]] || continue
        "$MUJO_BIN" "${argv[@]}" --yes || tui_pause
        ;;
      run|show)
        "$MUJO_BIN" "${argv[@]}" || true
        tui_pause
        ;;
    esac
  done
}
