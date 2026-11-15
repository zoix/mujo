# shellcheck shell=bash
# Core of the mujo CLI: name, paths, global flags, the output contract and errors.
#
# Output contract (docs/cli.md):
#   - Human text by default. With --json, exactly one JSON object on stdout:
#       {"schema_version":1,"ok":true,"command":"...","dry_run":false,"data":{...}}
#       {"schema_version":1,"ok":false,"command":"...","error":{"code":N,"message":"..."}}
#   - Exit codes: 0 ok, 1 failure, 2 usage error, 3 unsupported environment.
#   - Final output goes to fd 3 (a copy of the real stdout) so `die` and `emit`
#     still reach the user when called inside a command substitution.

MUJO_NAME=mujo
MUJO_VERSION=0.1.0
MUJO_SCHEMA_VERSION=1

EXIT_OK=0
EXIT_FAIL=1
EXIT_USAGE=2
EXIT_ENV=3

MUJO_CONFIG_HOME=${XDG_CONFIG_HOME:-$HOME/.config}
MUJO_STATE_HOME=${XDG_STATE_HOME:-$HOME/.local/state}
MUJO_CONFIG_DIR=$MUJO_CONFIG_HOME/$MUJO_NAME
MUJO_STATE_DIR=$MUJO_STATE_HOME/$MUJO_NAME
# Answers fetched from elsewhere that may be thrown away (weather, pending updates).
# shellcheck disable=SC2034  # used by the files that keep such answers
MUJO_CACHE_DIR=${XDG_CACHE_HOME:-$HOME/.cache}/$MUJO_NAME
# shellcheck disable=SC2034  # used by config.sh and theme.sh
MUJO_CONFIG_FILE=$MUJO_CONFIG_DIR/config.json
# shellcheck disable=SC2034  # used by journal.sh
MUJO_JOURNAL=$MUJO_STATE_DIR/journal.jsonl

OPT_JSON=0
OPT_DRY_RUN=0
OPT_YES=0
OPT_HELP=0
OPT_WINDOW=0
MUJO_ARGS=()   # arguments left after the global flags are removed
MUJO_ARGV=()   # the same, kept intact for the journal
MUJO_CMD=""    # command being run, e.g. "theme accent"
MUJO_CLEANUP=()

declare -A MUJO_CMD_SUMMARY=()
MUJO_CMD_ORDER=()

# mujo_register NAME SUMMARY: make cmd_NAME / help_NAME reachable from the dispatcher.
mujo_register() {
  MUJO_CMD_ORDER+=("$1")
  MUJO_CMD_SUMMARY[$1]=$2
}

# mujo_set_cmd "NAME SUB": the command name used in JSON output and errors.
mujo_set_cmd() {
  MUJO_CMD=$1
}

# Remove global flags from anywhere in the argument list. `--` stops flag parsing.
mujo_parse_globals() {
  MUJO_ARGS=()
  local passthrough=0 a
  for a in "$@"; do
    if (( passthrough )); then MUJO_ARGS+=("$a"); continue; fi
    # shellcheck disable=SC2034  # OPT_YES is read by commands that cannot be undone (phase 2)
    case $a in
      --json) OPT_JSON=1 ;;
      --dry-run) OPT_DRY_RUN=1 ;;
      --yes|-y) OPT_YES=1 ;;
      --help|-h) OPT_HELP=1 ;;
      --window) OPT_WINDOW=1 ;;
      --) passthrough=1 ;;
      *) MUJO_ARGS+=("$a") ;;
    esac
  done
  # shellcheck disable=SC2034  # used by journal.sh
  MUJO_ARGV=("${MUJO_ARGS[@]}")
}

# Make sure fd 3 exists (bin/mujo opens it; this covers sourcing from tests).
mujo_init_fds() {
  { true >&3; } 2>/dev/null || exec 3>&1
}

mujo_cleanup() {
  local p
  for p in "${MUJO_CLEANUP[@]}"; do rm -rf -- "$p"; done
}

# mujo_tmpdir VAR: create a temporary directory removed on exit.
mujo_tmpdir() {
  local d
  d=$(mktemp -d "${TMPDIR:-/tmp}/$MUJO_NAME.XXXXXX")
  MUJO_CLEANUP+=("$d")
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
  printf '%s: warning: %s\n' "$MUJO_NAME" "$*" >&2
}

# die CODE MESSAGE: report an error in the right format and exit.
die() {
  local code=$1
  shift
  if (( OPT_JSON )); then
    jq -cn --argjson v "$MUJO_SCHEMA_VERSION" --arg cmd "$MUJO_CMD" \
      --argjson code "$code" --arg msg "$*" \
      '{schema_version: $v, ok: false, command: $cmd, error: {code: $code, message: $msg}}' >&3
  else
    printf '%s: %s\n' "$MUJO_NAME" "$*" >&2
  fi
  exit "$code"
}

usage_error() {
  die "$EXIT_USAGE" "$* (see '$MUJO_NAME ${MUJO_CMD:+$MUJO_CMD }--help')"
}

# emit: wrap the JSON on stdin in the success envelope (JSON mode only).
emit() {
  if (( OPT_JSON )); then
    jq -c --argjson v "$MUJO_SCHEMA_VERSION" --arg cmd "$MUJO_CMD" \
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
    || die "$EXIT_ENV" "'$MUJO_NAME $MUJO_CMD' needs a Wayland session (WAYLAND_DISPLAY is not set)"
}

# Commands that talk to the compositor call this first.
require_hyprland() {
  [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]] \
    || die "$EXIT_ENV" "'$MUJO_NAME $MUJO_CMD' needs a running Hyprland session"
  need hyprctl
}

# atomic_write DEST: write stdin to DEST via a temporary file and rename.
atomic_write() {
  local dest=$1 dir tmp
  dir=$(dirname -- "$dest")
  mkdir -p -- "$dir"
  tmp=$(mktemp "$dir/.$MUJO_NAME.XXXXXX")
  if ! cat >"$tmp"; then rm -f -- "$tmp"; return 1; fi
  chmod 644 -- "$tmp"
  mv -f -- "$tmp" "$dest"
}

# Serialise mutating commands. The lock is released when the process exits.
mujo_lock() {
  mkdir -p -- "$MUJO_STATE_DIR"
  exec 9>"$MUJO_STATE_DIR/.lock"
  flock -w 10 9 || die "$EXIT_FAIL" "another $MUJO_NAME action is still running"
}

# ---- mutating commands: plan, apply, record --------------------------------
#
# Every simple state change uses the same three steps:
#   change_begin SUMMARY BEFORE PLANNED   || return 0   # no-op or dry run: reported, stop
#   <apply the change>
#   change_end SUMMARY BEFORE AFTER UNDO                # journal, report
# BEFORE, PLANNED and AFTER are JSON objects describing the state; UNDO is a
# JSON argv array for `mujo undo`, or null if the change cannot be reverted.
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
    say "Journal: $jid (undo: $MUJO_NAME undo $jid)"
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

mujo_help() {
  local name
  cat <<EOF
$MUJO_NAME $MUJO_VERSION: control plane for the $MUJO_NAME desktop

Usage: $MUJO_NAME [global flags] <command> [arguments]

Commands:
EOF
  for name in "${MUJO_CMD_ORDER[@]}"; do
    printf '  %-10s %s\n' "$name" "${MUJO_CMD_SUMMARY[$name]}"
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

mujo_main() {
  mujo_init_fds
  trap mujo_cleanup EXIT
  mujo_parse_globals "$@"
  need jq flock
  set -- "${MUJO_ARGS[@]}"

  local cmd=${1:-}
  case $cmd in
    "")
      if (( OPT_HELP )); then mujo_help >&3; exit "$EXIT_OK"; fi
      mujo_help >&2
      exit "$EXIT_USAGE"
      ;;
    help)
      shift
      if (( $# == 0 )); then mujo_help >&3; exit "$EXIT_OK"; fi
      OPT_HELP=1
      cmd=$1
      ;;
    version)
      MUJO_CMD=version
      say "$MUJO_NAME $MUJO_VERSION"
      jq -n --arg v "$MUJO_VERSION" '{version: $v}' | emit
      exit "$EXIT_OK"
      ;;
  esac
  [[ $cmd == help ]] || shift

  if [[ -z ${MUJO_CMD_SUMMARY[$cmd]+x} ]]; then
    die "$EXIT_USAGE" "unknown command '$cmd' (see '$MUJO_NAME --help')"
  fi
  MUJO_CMD=$cmd
  if (( OPT_HELP )); then
    "help_${cmd//-/_}" "$@" >&3
    exit "$EXIT_OK"
  fi
  if (( OPT_WINDOW )); then
    tui_window "$cmd" "$@"
  fi
  "cmd_${cmd//-/_}" "$@"
}
