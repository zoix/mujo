# shellcheck shell=bash
# Core of the karma CLI: name, paths, global flags, the output contract and errors.
#
# Output contract (docs/cli.md):
#   - Human text by default. With --json, exactly one JSON object on stdout:
#       {"schema_version":1,"ok":true,"command":"...","dry_run":false,"data":{...}}
#       {"schema_version":1,"ok":false,"command":"...","error":{"code":N,"message":"..."}}
#   - Exit codes: 0 ok, 1 failure, 2 usage error, 3 unsupported environment.
#   - Final output goes to fd 3 (a copy of the real stdout) so `die` and `emit`
#     still reach the user when called inside a command substitution.

KARMA_NAME=karma
KARMA_VERSION=0.1.0
KARMA_SCHEMA_VERSION=1

EXIT_OK=0
EXIT_FAIL=1
EXIT_USAGE=2
EXIT_ENV=3

KARMA_CONFIG_HOME=${XDG_CONFIG_HOME:-$HOME/.config}
KARMA_STATE_HOME=${XDG_STATE_HOME:-$HOME/.local/state}
KARMA_CONFIG_DIR=$KARMA_CONFIG_HOME/$KARMA_NAME
KARMA_STATE_DIR=$KARMA_STATE_HOME/$KARMA_NAME
# shellcheck disable=SC2034  # used by config.sh and theme.sh
KARMA_CONFIG_FILE=$KARMA_CONFIG_DIR/config.json
# shellcheck disable=SC2034  # used by journal.sh
KARMA_JOURNAL=$KARMA_STATE_DIR/journal.jsonl

OPT_JSON=0
OPT_DRY_RUN=0
OPT_YES=0
OPT_HELP=0
KARMA_ARGS=()   # arguments left after the global flags are removed
KARMA_ARGV=()   # the same, kept intact for the journal
KARMA_CMD=""    # command being run, e.g. "theme accent"
KARMA_CLEANUP=()

declare -A KARMA_CMD_SUMMARY=()
KARMA_CMD_ORDER=()

# karma_register NAME SUMMARY: make cmd_NAME / help_NAME reachable from the dispatcher.
karma_register() {
  KARMA_CMD_ORDER+=("$1")
  KARMA_CMD_SUMMARY[$1]=$2
}

# Remove global flags from anywhere in the argument list. `--` stops flag parsing.
karma_parse_globals() {
  KARMA_ARGS=()
  local passthrough=0 a
  for a in "$@"; do
    if (( passthrough )); then KARMA_ARGS+=("$a"); continue; fi
    # shellcheck disable=SC2034  # OPT_YES is read by commands that cannot be undone (phase 2)
    case $a in
      --json) OPT_JSON=1 ;;
      --dry-run) OPT_DRY_RUN=1 ;;
      --yes|-y) OPT_YES=1 ;;
      --help|-h) OPT_HELP=1 ;;
      --) passthrough=1 ;;
      *) KARMA_ARGS+=("$a") ;;
    esac
  done
  # shellcheck disable=SC2034  # used by journal.sh
  KARMA_ARGV=("${KARMA_ARGS[@]}")
}

# Make sure fd 3 exists (bin/karma opens it; this covers sourcing from tests).
karma_init_fds() {
  { true >&3; } 2>/dev/null || exec 3>&1
}

karma_cleanup() {
  local p
  for p in "${KARMA_CLEANUP[@]}"; do rm -rf -- "$p"; done
}

# karma_tmpdir VAR: create a temporary directory removed on exit.
karma_tmpdir() {
  local d
  d=$(mktemp -d "${TMPDIR:-/tmp}/$KARMA_NAME.XXXXXX")
  KARMA_CLEANUP+=("$d")
  printf -v "$1" '%s' "$d"
}

# Human output (suppressed in JSON mode).
say() {
  (( OPT_JSON )) || printf '%s\n' "$*" >&3
}

# Print a file or stdin to the user (suppressed in JSON mode).
say_stream() {
  if (( OPT_JSON )); then cat >/dev/null; else cat >&3; fi
}

warn() {
  printf '%s: warning: %s\n' "$KARMA_NAME" "$*" >&2
}

# die CODE MESSAGE: report an error in the right format and exit.
die() {
  local code=$1
  shift
  if (( OPT_JSON )); then
    jq -cn --argjson v "$KARMA_SCHEMA_VERSION" --arg cmd "$KARMA_CMD" \
      --argjson code "$code" --arg msg "$*" \
      '{schema_version: $v, ok: false, command: $cmd, error: {code: $code, message: $msg}}' >&3
  else
    printf '%s: %s\n' "$KARMA_NAME" "$*" >&2
  fi
  exit "$code"
}

usage_error() {
  die "$EXIT_USAGE" "$* (see '$KARMA_NAME ${KARMA_CMD:+$KARMA_CMD }--help')"
}

# emit: wrap the JSON on stdin in the success envelope (JSON mode only).
emit() {
  if (( OPT_JSON )); then
    jq -c --argjson v "$KARMA_SCHEMA_VERSION" --arg cmd "$KARMA_CMD" \
      --argjson dry "$( (( OPT_DRY_RUN )) && echo true || echo false)" \
      '{schema_version: $v, ok: true, command: $cmd, dry_run: $dry, data: .}' >&3
  else
    cat >/dev/null
  fi
}

# need CMD...: fail with exit 3 if a dependency is missing.
need() {
  local c
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || die "$EXIT_ENV" "missing dependency: $c"
  done
}

# Commands that only make sense inside a graphical session call this first.
require_wayland() {
  [[ -n ${WAYLAND_DISPLAY:-} ]] \
    || die "$EXIT_ENV" "'$KARMA_NAME $KARMA_CMD' needs a Wayland session (WAYLAND_DISPLAY is not set)"
}

# atomic_write DEST: write stdin to DEST via a temporary file and rename.
atomic_write() {
  local dest=$1 dir tmp
  dir=$(dirname -- "$dest")
  mkdir -p -- "$dir"
  tmp=$(mktemp "$dir/.$KARMA_NAME.XXXXXX")
  if ! cat >"$tmp"; then rm -f -- "$tmp"; return 1; fi
  chmod 644 -- "$tmp"
  mv -f -- "$tmp" "$dest"
}

# Serialise mutating commands. The lock is released when the process exits.
karma_lock() {
  mkdir -p -- "$KARMA_STATE_DIR"
  exec 9>"$KARMA_STATE_DIR/.lock"
  flock -w 10 9 || die "$EXIT_FAIL" "another $KARMA_NAME action is still running"
}

# json_array ARGS...: print the arguments as a JSON array of strings.
json_array() {
  jq -cn '$ARGS.positional' --args "$@"
}

karma_help() {
  local name
  cat <<EOF
$KARMA_NAME $KARMA_VERSION: control plane for the $KARMA_NAME desktop

Usage: $KARMA_NAME [global flags] <command> [arguments]

Commands:
EOF
  for name in "${KARMA_CMD_ORDER[@]}"; do
    printf '  %-10s %s\n' "$name" "${KARMA_CMD_SUMMARY[$name]}"
  done
  cat <<EOF
  version    Print the version
  help       Show help for a command

Global flags (accepted anywhere on the line):
  --json      Print one JSON object (see docs/cli.md)
  --dry-run   Show what would change and change nothing
  --yes, -y   Confirm actions that cannot be undone
  --help, -h  Show help

Exit codes: 0 ok, 1 failure, 2 usage error, 3 unsupported environment.
EOF
}

karma_main() {
  karma_init_fds
  trap karma_cleanup EXIT
  karma_parse_globals "$@"
  need jq flock
  set -- "${KARMA_ARGS[@]}"

  local cmd=${1:-}
  case $cmd in
    "")
      if (( OPT_HELP )); then karma_help >&3; exit "$EXIT_OK"; fi
      karma_help >&2
      exit "$EXIT_USAGE"
      ;;
    help)
      shift
      if (( $# == 0 )); then karma_help >&3; exit "$EXIT_OK"; fi
      OPT_HELP=1
      cmd=$1
      ;;
    version)
      KARMA_CMD=version
      say "$KARMA_NAME $KARMA_VERSION"
      jq -n --arg v "$KARMA_VERSION" '{version: $v}' | emit
      exit "$EXIT_OK"
      ;;
  esac
  [[ $cmd == help ]] || shift

  if [[ -z ${KARMA_CMD_SUMMARY[$cmd]+x} ]]; then
    die "$EXIT_USAGE" "unknown command '$cmd' (see '$KARMA_NAME --help')"
  fi
  KARMA_CMD=$cmd
  if (( OPT_HELP )); then
    "help_${cmd//-/_}" "$@" >&3
    exit "$EXIT_OK"
  fi
  "cmd_${cmd//-/_}" "$@"
}
