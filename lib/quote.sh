# shellcheck shell=bash
# karma quote: a line from the Stoics, the Tao Te Ching or the Dhammapada.
# One quote is current for each hour; the interface shows it on the lock
# screen and the dashboard, and lets it slide out of the top edge on the hour.

karma_register quote "The quote of the hour (Stoic, Taoist, Buddhist)"

QUOTE_STATE=$KARMA_STATE_DIR/quote-offset

help_quote() {
  cat <<EOF
Usage: $KARMA_NAME quote [show]
       $KARMA_NAME quote next
       $KARMA_NAME quote list
       $KARMA_NAME quote hourly [on | off | toggle]

show    The current quote (the default). It changes every hour.
next    Move on to another quote now; the interface shows it at once.
list    Every quote in the list.
hourly  Whether the quote slides out of the top edge of the screen for a
        few seconds on the hour (on unless you switch it off). It never does
        while do-not-disturb is on. Journaled; can be undone.

The list is $(tilde "$KARMA_ROOT/data/quotes.txt"). To use your own, copy it to
$(tilde "$KARMA_CONFIG_DIR/quotes.txt") and edit that: one quote per line,
as text, author and source separated by tabs.
EOF
}

quote_file() {
  if [[ -s $KARMA_CONFIG_DIR/quotes.txt ]]; then
    echo "$KARMA_CONFIG_DIR/quotes.txt"
  else
    echo "$KARMA_ROOT/data/quotes.txt"
  fi
}

# All quotes as a JSON array of {text, author, source}.
quote_all() {
  grep -v '^[[:space:]]*#' "$(quote_file)" 2>/dev/null | grep -v '^[[:space:]]*$' \
    | jq -cRn '[inputs | split("\t") | select(length >= 1 and .[0] != "")
        | {text: .[0], author: (.[1] // ""), source: (.[2] // "")}]'
}

quote_offset() {
  local n=0
  [[ -f $QUOTE_STATE ]] && n=$(<"$QUOTE_STATE")
  [[ $n =~ ^[0-9]+$ ]] || n=0
  echo "$n"
}

# The quote for this hour: the hour picks a place in the list, in an order
# that does not simply run from top to bottom; `next` shifts it by one.
quote_current() {
  local all=$1 hour
  hour=$(( $(date +%s) / 3600 ))
  jq -c --argjson h "$hour" --argjson o "$(quote_offset)" '
    length as $n | if $n == 0 then null
    else ((($h * 7919) + $o) % $n) as $i | .[$i] + {index: $i, total: $n} end' <<<"$all"
}

cmd_quote() {
  local sub=${1:-show}
  (( $# )) && shift
  karma_set_cmd "quote $sub"
  local all current
  case $sub in
    show|next)
      (( $# == 0 )) || usage_error "unexpected argument '$1'"
      all=$(quote_all)
      [[ $all != "[]" ]] || die "$EXIT_FAIL" "no quotes in $(quote_file)"
      if [[ $sub == next ]]; then
        mkdir -p -- "$KARMA_STATE_DIR"
        echo $(( $(quote_offset) + 1 )) >"$QUOTE_STATE"
      fi
      current=$(quote_current "$all")
      jq -r '"\(.text)\n  \(.author)\(if .source != "" then ", \(.source)" else "" end)"' <<<"$current" | say_stream
      printf '%s' "$current" | emit
      [[ $sub == next ]] && ui_ipc quote visit
      return 0
      ;;
    list)
      (( $# == 0 )) || usage_error "unexpected argument '$1'"
      all=$(quote_all)
      jq -r '.[] | "\(.text)  (\(.author))"' <<<"$all" | say_stream
      jq -n --argjson q "$all" '{quotes: $q}' | emit
      ;;
    hourly)
      (( $# <= 1 )) || usage_error "too many arguments"
      local cur new
      cur=$(config_read | jq -r '.quote_hourly != false')
      if (( $# == 0 )); then
        say "Hourly quote: $([[ $cur == true ]] && echo on || echo off)"
        jq -n --argjson h "$cur" '{hourly: $h}' | emit
        return 0
      fi
      new=$(on_off "$1" "$cur") || usage_error "expected on, off or toggle, got '$1'"
      local wc wn before after
      wc=$([[ $cur == true ]] && echo on || echo off)
      wn=$([[ $new == true ]] && echo on || echo off)
      before=$(jq -cn --argjson h "$cur" '{hourly: $h}')
      after=$(jq -cn --argjson h "$new" '{hourly: $h}')
      change_begin "quote hourly: $wc -> $wn" "$before" "$after" || return 0
      karma_lock
      config_set quote_hourly "$new"
      change_end "quote hourly: $wc -> $wn" "$before" "$after" "$(json_array quote hourly "$wc")"
      ;;
    *) usage_error "unknown subcommand '$sub'" ;;
  esac
}
