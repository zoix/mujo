#!/usr/bin/env bats
# Dispatcher, global flags and the output contract.

load helpers

@test "--help lists the commands and exits 0" {
  run karma --help
  [ "$status" -eq 0 ]
  [[ $output == *"theme"* ]]
  [[ $output == *"undo"* ]]
}

@test "no arguments prints help to stderr and exits 2" {
  run karma
  [ "$status" -eq 2 ]
}

@test "unknown command exits 2" {
  run karma frobnicate
  [ "$status" -eq 2 ]
  [[ $output == *"unknown command 'frobnicate'"* ]]
}

@test "help for a command works both ways" {
  run karma help theme
  [ "$status" -eq 0 ]
  [[ $output == *"reduce-motion"* ]]
  run karma theme --help
  [ "$status" -eq 0 ]
  [[ $output == *"reduce-motion"* ]]
}

@test "version --json follows the envelope" {
  run karma version --json
  [ "$status" -eq 0 ]
  [ "$(jq -r .schema_version <<<"$output")" = 1 ]
  [ "$(jq -r .ok <<<"$output")" = true ]
  [ "$(jq -r .command <<<"$output")" = version ]
}

@test "usage errors in --json mode are a JSON error with code 2" {
  run karma theme accent nope --json
  [ "$status" -eq 2 ]
  [ "$(jq -r .ok <<<"$output")" = false ]
  [ "$(jq -r .error.code <<<"$output")" = 2 ]
}

@test "global flags are accepted anywhere" {
  run karma --json theme accent
  [ "$status" -eq 0 ]
  [ "$(jq -r .data.accent <<<"$output")" = mauve ]
}

@test "require_wayland exits 3 without a session" {
  run bash -c "source '$KARMA_REPO/lib/core.sh'; karma_init_fds; KARMA_CMD=shot; require_wayland"
  [ "$status" -eq 3 ]
  [[ $output == *"needs a Wayland session"* ]]
}
