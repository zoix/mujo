# shellcheck shell=bash
# Shared setup for the bats tests: every test runs against a throwaway
# XDG config/state directory, never the real home.

KARMA_REPO=$(cd -- "$(dirname -- "${BATS_TEST_FILENAME}")/.." && pwd)

setup() {
  export XDG_CONFIG_HOME=$BATS_TEST_TMPDIR/config
  export XDG_STATE_HOME=$BATS_TEST_TMPDIR/state
  export KARMA_SYSROOT=$BATS_TEST_TMPDIR/sysroot
  unset WAYLAND_DISPLAY HYPRLAND_INSTANCE_SIGNATURE KARMA_ROOT KARMA_UNDO_OF
  KARMA="$KARMA_REPO/bin/karma"
}

karma() {
  "$KARMA" "$@"
}

state() {
  printf '%s\n' "$XDG_STATE_HOME/karma"
}

conf() {
  printf '%s\n' "$XDG_CONFIG_HOME"
}
