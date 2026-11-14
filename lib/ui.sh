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
    "") ;;
    *) warn "unknown reload hook '$1'" ;;
  esac
}
