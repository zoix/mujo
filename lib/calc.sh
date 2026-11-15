# shellcheck shell=bash
# mujo calc: a calculator (qalc). The launcher's "=" mode uses it.

mujo_register calc "Calculate an expression"

help_calc() {
  cat <<EOF
Usage: $MUJO_NAME calc EXPRESSION... [--copy]

Works out the expression with qalc (package libqalculate): arithmetic,
units ("5 km in miles"), percentages ("15% of 80"). --copy puts the result
on the clipboard. In the launcher, type = and then the expression.
EOF
}

cmd_calc() {
  local copy=0
  local -a words=()
  while (( $# )); do
    case $1 in
      --copy) copy=1; shift ;;
      *) words+=("$1"); shift ;;
    esac
  done
  (( ${#words[@]} )) || usage_error "nothing to calculate"
  need qalc
  local expr="${words[*]}" result
  # -t: the result only. Exchange rates are never downloaded from here.
  result=$(qalc -t -- "$expr" 2>/dev/null </dev/null) || result=""
  result=${result##*$'\n'}
  [[ -n $result ]] || die "$EXIT_FAIL" "could not calculate '$expr'"
  if (( copy )); then
    require_wayland
    need wl-copy
    printf '%s' "$result" | wl-copy >/dev/null 2>&1 3>&- 9>&- || die "$EXIT_FAIL" "could not copy the result"
  fi
  say "$result"
  jq -n --arg e "$expr" --arg r "$result" --argjson c "$copy" '{expression: $e, result: $r, copied: ($c == 1)}' | emit
}
