# shellcheck shell=bash
# Shared pieces of the interactive commands (launcher, menu, Wi-Fi, keys,
# clipboard): the floating window, the terminal check and the fzf wrapper.

# tui_window NAME [ARGS...]: run `mujo NAME ARGS` in a floating terminal
# with the class mujo.tui.NAME (Hyprland floats and centres that class).
# Running it again while the window is open closes it, so one key toggles.
tui_window() {
  local name=$1 class
  shift
  class=$MUJO_NAME.tui.$name
  require_wayland
  # The launcher, the system menu, the wallpaper picker, the power menu and
  # the dashboard have a panel in the Quickshell UI. Use it when the UI is running;
  # otherwise fall back to the terminal version below.
  local panel=""
  case "$name $*" in
    "launch "|"launch pick") panel="launcher apps" ;;
    "menu "|"menu pick") panel="launcher actions" ;;
    "wall pick") panel="launcher wallpapers" ;;
    "clip "|"clip pick") panel="launcher clipboard" ;;
    "keys tui") panel="launcher keys" ;;
    "net tui") panel="launcher wifi" ;;
    "calc ") panel="launcher calc" ;;
    "emoji "|"emoji pick") panel="launcher emoji" ;;
    "power "|"power list") panel="session toggle" ;;
    "sys ") panel="dashboard toggle" ;;
    "sys workspaces") panel="dashboard workspaces" ;;
    "sys activity") panel="dashboard activity" ;;
    "status ") panel="sidebar toggle" ;;
    "about ") panel="about toggle" ;;
  esac
  if [[ -n $panel ]] && command -v qs >/dev/null 2>&1; then
    # shellcheck disable=SC2086  # target and function are two words
    if timeout 2 qs -c "$MUJO_NAME" ipc call $panel >/dev/null 2>&1; then
      exit "$EXIT_OK"
    fi
  fi
  [[ $name == power ]] && die "$EXIT_ENV" "the power menu is part of the Quickshell UI, which is not running"
  [[ $name == about ]] && die "$EXIT_ENV" "the about card is part of the Quickshell UI, which is not running"
  [[ $name == sys ]] && die "$EXIT_ENV" "the dashboard is part of the Quickshell UI, which is not running"
  need setsid
  # (The window may have been started as "ghostty" or as "/usr/bin/ghostty".)
  if pkill -f -- "^(/usr/bin/)?ghostty --class=${class//./\\.} " 2>/dev/null; then
    exit "$EXIT_OK"
  fi
  tui_term "$class" "$MUJO_NAME $name" env MUJO_WINDOW=1 "$MUJO_BIN" "$name" "$@"
  exit "$EXIT_OK"
}

# tui_term CLASS TITLE [CMD...]: open the terminal (Ghostty) as its own
# program, running CMD or, without one, a shell. An empty CLASS gives an
# ordinary terminal window. Ghostty wants a class with a dot in it.
tui_term() {
  local class=$1 title=$2
  shift 2
  need ghostty
  local -a cmd=(ghostty)
  [[ -n $class ]] && cmd+=("--class=$class")
  # The drop-down terminal has a few settings of its own (theme consumer
  # ghostty-drop): a see-through background while glass is on.
  if [[ $class == "$MUJO_NAME.drop" && -f $MUJO_CONFIG_HOME/ghostty/$MUJO_NAME-drop ]]; then
    cmd+=("--config-file=$MUJO_CONFIG_HOME/ghostty/$MUJO_NAME-drop")
  fi
  [[ -n $title ]] && cmd+=("--title=$title")
  (( $# )) && cmd+=(-e "$@")
  tui_detach "${cmd[@]}"
}

# Interactive commands need a terminal and fzf, and have no JSON form.
tui_require() {
  (( OPT_JSON )) && usage_error "'$MUJO_CMD' is interactive and has no --json output"
  need fzf
  [[ -t 0 && -t 2 ]] \
    || die "$EXIT_ENV" "'$MUJO_NAME $MUJO_CMD' needs a terminal (inside the desktop, add --window)"
  # The generated fzf theme; zsh exports this, a keybinding's environment does not.
  if [[ -z ${FZF_DEFAULT_OPTS_FILE:-} && -f $MUJO_CONFIG_HOME/fzf/mujo.fzfrc ]]; then
    export FZF_DEFAULT_OPTS_FILE=$MUJO_CONFIG_HOME/fzf/mujo.fzfrc
  fi
}

# tui_pick [FZF-OPTIONS...]: choose one line from stdin. Fails if cancelled.
tui_pick() {
  fzf --no-multi --cycle --height=100% "$@"
}

# tui_detach CMD...: start a program that outlives this terminal.
# It must not inherit mujo's output (fd 1-3) or its lock (fd 9): a pipe such
# as `mujo ... --json | jq` would otherwise wait for that program to exit.
#
# With systemd, it also gets its own scope. mujo is often run by the
# interface, which is a service; without a scope every app it launched would
# belong to that service and be killed whenever the service restarts.
tui_detach() {
  if command -v systemd-run >/dev/null 2>&1 && [[ -S ${XDG_RUNTIME_DIR:-/nonexistent}/bus ]]; then
    setsid -f systemd-run --user --scope --quiet --collect -- "$@" >/dev/null 2>&1 </dev/null 3>&- 9>&-
  else
    setsid -f "$@" >/dev/null 2>&1 </dev/null 3>&- 9>&-
  fi
}

tui_pause() {
  local _
  printf '\n%s' "Press Enter to continue " >&2
  read -r _ || true
}
