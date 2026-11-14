# shellcheck shell=bash
# Shared pieces of the interactive commands (launcher, menu, Wi-Fi, keys,
# clipboard): the floating window, the terminal check and the fzf wrapper.

# tui_window NAME [ARGS...]: run `karma NAME ARGS` in a floating kitty window
# with the class karma-tui-NAME (Hyprland floats and centres that class).
# Running it again while the window is open closes it, so one key toggles.
tui_window() {
  local name=$1 class
  shift
  class=$KARMA_NAME-tui-$name
  require_wayland
  # The launcher, the system menu, the wallpaper picker and the power menu
  # have a panel in the Quickshell UI. Use it when the UI is running;
  # otherwise fall back to the terminal version below.
  local panel=""
  case "$name $*" in
    "launch "|"launch pick") panel="launcher apps" ;;
    "menu "|"menu pick") panel="launcher actions" ;;
    "wall pick") panel="launcher wallpapers" ;;
    "power "|"power list") panel="session toggle" ;;
  esac
  if [[ -n $panel ]] && command -v qs >/dev/null 2>&1; then
    # shellcheck disable=SC2086  # target and function are two words
    if timeout 2 qs -c "$KARMA_NAME" ipc call $panel >/dev/null 2>&1; then
      exit "$EXIT_OK"
    fi
  fi
  [[ $name == power ]] && die "$EXIT_ENV" "the power menu is part of the Quickshell UI, which is not running"
  need kitty setsid
  if pkill -f -- "^kitty --class $class " 2>/dev/null; then
    exit "$EXIT_OK"
  fi
  tui_detach kitty --class "$class" --title "$KARMA_NAME $name" -o remember_window_size=no \
    -e "$KARMA_BIN" "$name" "$@"
  exit "$EXIT_OK"
}

# Interactive commands need a terminal and fzf, and have no JSON form.
tui_require() {
  (( OPT_JSON )) && usage_error "'$KARMA_CMD' is interactive and has no --json output"
  need fzf
  [[ -t 0 && -t 2 ]] \
    || die "$EXIT_ENV" "'$KARMA_NAME $KARMA_CMD' needs a terminal (inside the desktop, add --window)"
  # The generated fzf theme; zsh exports this, a keybinding's environment does not.
  if [[ -z ${FZF_DEFAULT_OPTS_FILE:-} && -f $KARMA_CONFIG_HOME/fzf/karma.fzfrc ]]; then
    export FZF_DEFAULT_OPTS_FILE=$KARMA_CONFIG_HOME/fzf/karma.fzfrc
  fi
}

# tui_pick [FZF-OPTIONS...]: choose one line from stdin. Fails if cancelled.
tui_pick() {
  fzf --no-multi --cycle --height=100% "$@"
}

# tui_detach CMD...: start a program that outlives this terminal.
# It must not inherit karma's output (fd 1-3) or its lock (fd 9): a pipe such
# as `karma ... --json | jq` would otherwise wait for that program to exit.
tui_detach() {
  setsid -f "$@" >/dev/null 2>&1 </dev/null 3>&- 9>&-
}

tui_pause() {
  local _
  printf '\n%s' "Press Enter to continue " >&2
  read -r _ || true
}
