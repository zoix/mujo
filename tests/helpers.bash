# shellcheck shell=bash
# Shared setup for the bats tests: every test runs against a throwaway
# XDG config/state directory, never the real home.

MUJO_REPO=$(cd -- "$(dirname -- "${BATS_TEST_FILENAME}")/.." && pwd)

mujo_test_env() {
  export XDG_CONFIG_HOME=$BATS_TEST_TMPDIR/config
  export XDG_STATE_HOME=$BATS_TEST_TMPDIR/state
  export XDG_CACHE_HOME=$BATS_TEST_TMPDIR/cache
  export MUJO_SYSROOT=$BATS_TEST_TMPDIR/sysroot
  unset WAYLAND_DISPLAY HYPRLAND_INSTANCE_SIGNATURE MUJO_ROOT MUJO_UNDO_OF
  MUJO="$MUJO_REPO/bin/mujo"
}

setup() {
  mujo_test_env
}

# Put the test doubles in tests/stubs (wpctl, nmcli, brightnessctl, ...) first
# on PATH. Their state lives in $STUB_STATE, a fresh directory per test.
use_stubs() {
  export STUB_STATE=$BATS_TEST_TMPDIR/stubs
  mkdir -p "$STUB_STATE"
  PATH=$MUJO_REPO/tests/stubs:$PATH
}

# data FILTER: apply a jq filter to .data of the JSON in $output.
data() {
  # shellcheck disable=SC2154  # $output is set by bats' `run`
  jq -r ".data | $1" <<<"$output"
}

mujo() {
  "$MUJO" "$@"
}

state() {
  printf '%s\n' "$XDG_STATE_HOME/mujo"
}

conf() {
  printf '%s\n' "$XDG_CONFIG_HOME"
}
