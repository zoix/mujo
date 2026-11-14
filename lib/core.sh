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
OPT_WINDOW=0
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

# karma_set_cmd "NAME SUB": the command name used in JSON output and errors.
karma_set_cmd() {
  KARMA_CMD=$1
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
      --window) OPT_WINDOW=1 ;;
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

# Commands that talk to the compositor call this first.
require_hyprland() {
  [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]] \
    || die "$EXIT_ENV" "'$KARMA_NAME $KARMA_CMD' needs a running Hyprland session"
  need hyprctl
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

# ---- mutating commands: plan, apply, record --------------------------------
#
# Every simple state change uses the same three steps:
#   change_begin SUMMARY BEFORE PLANNED   || return 0   # no-op or dry run: reported, stop
#   <apply the change>
#   change_end SUMMARY BEFORE AFTER UNDO                # journal, report
# BEFORE, PLANNED and AFTER are JSON objects describing the state; UNDO is a
# JSON argv array for `karma undo`, or null if the change cannot be reverted.
# `data` in --json mode is always {journal_id, changed, before, after}.

change_begin() {
  local summary=$1 before=$2 planned=$3
  if [[ $(jq -cS . <<<"$before") == "$(jq -cS . <<<"$planned")" ]]; then
    say "Nothing to do: already in that state."
    jq -n --argjson b "$before" '{journal_id: null, changed: false, before: $b, after: $b}' | emit
    return 1
  fi
  if (( OPT_DRY_RUN )); then
    say "$summary (dry run, nothing changed)"
    diff -u --label current --label planned <(jq -S . <<<"$before") <(jq -S . <<<"$planned") \
      | say_stream || true
    jq -n --argjson b "$before" --argjson a "$planned" \
      '{journal_id: null, changed: true, before: $b, after: $a}' | emit
    return 1
  fi
  return 0
}

change_end() {
  local summary=$1 before=$2 after=$3 undo=$4 jid
  jid=$(journal_new_id)
  journal_record "$jid" "$summary" "$before" "$after" "$undo"
  say "$summary"
  if [[ $undo == null ]]; then
    say "Journal: $jid (cannot be undone)"
  else
    say "Journal: $jid (undo: $KARMA_NAME undo $jid)"
  fi
  jq -n --arg j "$jid" --argjson b "$before" --argjson a "$after" \
    '{journal_id: $j, changed: true, before: $b, after: $a}' | emit
}

# confirm_irreversible WHAT: actions that cannot be undone need --yes
# (a dry run is always allowed).
confirm_irreversible() {
  (( OPT_YES || OPT_DRY_RUN )) && return 0
  die "$EXIT_USAGE" "$1 cannot be undone; run it again with --yes (or --dry-run to preview)"
}

# on_off WORD CURRENT: print true/false for on|off|toggle; fail on anything else.
on_off() {
  case $1 in
    on|true) echo true ;;
    off|false) echo false ;;
    toggle) [[ $2 == true ]] && echo false || echo true ;;
    *) return 1 ;;
  esac
}

# step_value SPEC CURRENT MIN MAX: resolve "40", "40%", "+5" or "-5" to a
# clamped integer. Prints nothing and fails if SPEC is malformed.
step_value() {
  local spec=${1%\%} cur=$2 min=$3 max=$4 v
  [[ $spec =~ ^[+-]?[0-9]{1,4}$ ]] || return 1
  case $spec in
    +*) v=$(( cur + 10#${spec#+} )) ;;
    -*) v=$(( cur - 10#${spec#-} )) ;;
    *) v=$(( 10#$spec )) ;;
  esac
  (( v < min )) && v=$min
  (( v > max )) && v=$max
  echo "$v"
}

# json_array ARGS...: print the arguments as a JSON array of strings.
# The "--" keeps jq from reading an argument such as --temp as its own option.
json_array() {
  jq -cn '$ARGS.positional' --args -- "$@"
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
  --window    Open the command in a floating terminal (toggles; needs Wayland)
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
  if (( OPT_WINDOW )); then
    tui_window "$cmd" "$@"
  fi
  "cmd_${cmd//-/_}" "$@"
}
