# shellcheck shell=bash
# Best-effort pushes to running programs after a change. Never fatal.

ui_session() {
  [[ -n ${WAYLAND_DISPLAY:-} ]]
}

# ui_ipc TARGET FUNCTION [ARGS...]: call a Quickshell IPC handler if the UI runs.
ui_ipc() {
  ui_session || return 0
  command -v qs >/dev/null 2>&1 || return 0
  timeout 2 qs -c "$KARMA_NAME" ipc call "$@" >/dev/null 2>&1 || true
}

# ui_notify TITLE BODY: a desktop notification, for results of commands that
# were started from the interface and have no terminal to print to.
ui_notify() {
  ui_session || return 0
  [[ -t 1 ]] && return 0
  command -v notify-send >/dev/null 2>&1 || return 0
  timeout 2 notify-send -a "$KARMA_NAME" -t 4000 "$1" "$2" >/dev/null 2>&1 3>&- || true
}

# ui_reload NAME: run a named reload hook from design/consumers.json.
ui_reload() {
  case $1 in
    quickshell) ui_ipc theme reload ;;
    hyprland)
      if [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]] && command -v hyprctl >/dev/null 2>&1; then
        hyprctl reload >/dev/null 2>&1 || true
      fi
      ;;
    kitty) pkill -USR1 -x kitty >/dev/null 2>&1 || true ;;
    ghostty) pkill -USR2 -x ghostty >/dev/null 2>&1 || true ;;
    gtk) ;;  # handled by theme.sh, which knows the resolved tokens
    "") ;;
    *) warn "unknown reload hook '$1'" ;;
  esac
}
