# shellcheck shell=bash
# Action journal: one JSON object per line in ~/.local/state/mujo/journal.jsonl.
#
# Entry: {schema_version, id, time, command[], summary, before, after,
#         undo: [argv] | null, reversible, undo_of: id | null}
# `mujo undo` runs `mujo <undo argv>` with MUJO_UNDO_OF set, so the undo is
# itself journaled (and can be undone by id, which acts as a redo).

mujo_register log  "List recent actions from the journal"
mujo_register undo "Revert a journaled action (the latest by default)"

journal_new_id() {
  printf '%s-%04x\n' "$(date -u +%Y%m%dT%H%M%SZ)" "$((RANDOM))"
}

# journal_record ID SUMMARY BEFORE-JSON AFTER-JSON UNDO-JSON
journal_record() {
  local id=$1 summary=$2 before=$3 after=$4 undo=$5 argv line
  argv=$(json_array "${MUJO_ARGV[@]}")
  line=$(jq -cn --argjson v "$MUJO_SCHEMA_VERSION" --arg id "$id" \
    --arg time "$(date -u +%FT%TZ)" --argjson cmd "$argv" --arg summary "$summary" \
    --argjson before "$before" --argjson after "$after" --argjson undo "$undo" \
    --arg undo_of "${MUJO_UNDO_OF:-}" \
    '{schema_version: $v, id: $id, time: $time, command: $cmd, summary: $summary,
      before: $before, after: $after, undo: $undo, reversible: ($undo != null),
      undo_of: (if $undo_of == "" then null else $undo_of end)}')
  mkdir -p -- "$MUJO_STATE_DIR"
  {
    flock -w 5 8 || die "$EXIT_FAIL" "journal is locked"
    printf '%s\n' "$line" >&8
  } 8>>"$MUJO_JOURNAL"
}

# All entries as a JSON array, oldest first, each with `undone_by` filled in.
journal_entries() {
  if [[ ! -f $MUJO_JOURNAL ]]; then
    echo '[]'
    return
  fi
  jq -cR 'fromjson? // empty' "$MUJO_JOURNAL" | jq -cs '
    (map(select(.undo_of != null) | {key: .undo_of, value: .id}) | from_entries) as $by
    | map(. + {undone_by: ($by[.id] // null)})'
}

help_log() {
  cat <<EOF
Usage: $MUJO_NAME log [--limit N] [--json]

List recent actions, newest first (default 20). Each row shows the action id,
local time, what changed and whether it can be undone with '$MUJO_NAME undo ID'.
EOF
}

cmd_log() {
  local limit=20
  while (( $# )); do
    case $1 in
      --limit) [[ ${2:-} =~ ^[0-9]+$ ]] || usage_error "--limit needs a number"; limit=$2; shift 2 ;;
      *) usage_error "unexpected argument '$1'" ;;
    esac
  done
  local entries
  entries=$(journal_entries | jq -c --argjson n "$limit" 'reverse | .[:$n]')
  printf '%s' "$entries" | jq '{entries: .}' | emit
  (( OPT_JSON )) && return 0
  if [[ $entries == "[]" ]]; then
    say "No actions recorded yet."
    return 0
  fi
  {
    printf '%-21s  %-16s  %-11s  %s\n' ID WHEN UNDO ACTION
    jq -r '.[] | [.id, (.time | fromdateiso8601 | strflocaltime("%Y-%m-%d %H:%M")),
      (if .undone_by then "undone" elif .reversible then "undoable" else "-" end),
      .summary] | @tsv' <<<"$entries" \
      | while IFS=$'\t' read -r id when state summary; do
          printf '%-21s  %-16s  %-11s  %s\n' "$id" "$when" "$state" "$summary"
        done
  } | say_stream
}

help_undo() {
  cat <<EOF
Usage: $MUJO_NAME undo [ID] [--dry-run] [--json]

Revert one journaled action. Without ID, reverts the most recent action that is
reversible and not already undone (undo entries themselves are skipped, so
repeated '$MUJO_NAME undo' walks back through history). ID may be a unique prefix.
Undoing an undo entry by ID re-applies the original change.
EOF
}

cmd_undo() {
  (( $# <= 1 )) || usage_error "too many arguments"
  local want=${1:-} target
  target=$(journal_entries | jq -c --arg want "$want" '
    if $want == "" then
      [.[] | select(.reversible and .undo_of == null and .undone_by == null)] | last
    else
      [.[] | select(.id | startswith($want))] as $m
      | if ($m | length) > 1 then {ambiguous: ($m | map(.id))} else $m[0] end
    end')
  if [[ $target == null ]]; then
    [[ -n $want ]] && die "$EXIT_FAIL" "no journal entry matches '$want'"
    die "$EXIT_FAIL" "nothing to undo"
  fi
  if jq -e 'has("ambiguous")' <<<"$target" >/dev/null; then
    die "$EXIT_USAGE" "id '$want' is ambiguous: $(jq -r '.ambiguous | join(", ")' <<<"$target")"
  fi
  local id summary
  id=$(jq -r .id <<<"$target")
  summary=$(jq -r .summary <<<"$target")
  jq -e '.reversible' <<<"$target" >/dev/null \
    || die "$EXIT_FAIL" "action $id ($summary) cannot be undone"
  local by
  by=$(jq -r '.undone_by // empty' <<<"$target")
  [[ -z $by ]] || die "$EXIT_FAIL" "action $id was already undone by $by"

  local -a undo_argv flags=()
  mapfile -t undo_argv < <(jq -r '.undo[]' <<<"$target")
  (( OPT_JSON )) && flags+=(--json)
  (( OPT_DRY_RUN )) && flags+=(--dry-run)
  say "Undoing $id: $summary"
  MUJO_UNDO_OF=$id exec "$MUJO_BIN" "${flags[@]}" -- "${undo_argv[@]}"
}
