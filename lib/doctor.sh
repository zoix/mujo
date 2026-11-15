# shellcheck shell=bash
# mujo doctor: check that everything mujo needs is in place. Read-only.

mujo_register doctor "Check dependencies, services, links and tokens"

help_doctor() {
  cat <<EOF
Usage: $MUJO_NAME doctor

Checks, and for each problem says how to fix it:
  packages   every package in packages/pacman.txt is installed
  links      every file in config/ is linked into your home directory
  theme      generated files match the tokens ('$MUJO_NAME theme check')
  settings   config.json and the journal are readable
  services   NetworkManager, Bluetooth, the login screen, PipeWire
  session    Hyprland config errors, the interface, idle locking
             (skipped outside the graphical session)

Changes nothing. Exit code 0 if nothing failed (warnings are allowed), 1 otherwise.
EOF
}

DOCTOR_ROWS=()

# doctor_add GROUP STATUS(ok|warn|fail|skip) MESSAGE [FIX]
doctor_add() {
  DOCTOR_ROWS+=("$(jq -cn --arg g "$1" --arg s "$2" --arg m "$3" --arg f "${4:-}" \
    '{group: $g, status: $s, message: $m, fix: (if $f == "" then null else $f end)}')")
}

doctor_packages() {
  local list=$MUJO_ROOT/packages/pacman.txt
  if ! command -v pacman >/dev/null 2>&1; then
    doctor_add packages skip "pacman is not available here"
    return 0
  fi
  local -a wanted missing=()
  local pkg
  mapfile -t wanted < <(sed -E 's/#.*//; s/[[:space:]]+$//' "$list" | grep -v '^$')
  for pkg in "${wanted[@]}"; do
    pacman -Q "$pkg" >/dev/null 2>&1 || missing+=("$pkg")
  done
  if (( ${#missing[@]} )); then
    doctor_add packages fail "${#missing[@]} package(s) missing: ${missing[*]}" "sudo pacman -S --needed ${missing[*]}"
  else
    doctor_add packages ok "all ${#wanted[@]} packages are installed"
  fi
}

doctor_links() {
  local root=$MUJO_ROOT/config pkg file rel dest total=0
  local -a broken=()
  while IFS= read -r -d '' file; do
    pkg=${file#"$root"/}
    rel=${pkg#*/}
    dest=$HOME/$rel
    total=$(( total + 1 ))
    if [[ ! -L $dest || $(readlink -f -- "$dest") != "$(readlink -f -- "$file")" ]]; then
      broken+=("$(tilde "$dest")")
    fi
  done < <(find "$root" -mindepth 2 \( -type f -o -type l \) -print0 2>/dev/null)
  if (( ${#broken[@]} )); then
    local shown="${broken[*]:0:4}"
    (( ${#broken[@]} > 4 )) && shown+=" and $(( ${#broken[@]} - 4 )) more"
    doctor_add links fail "${#broken[@]} of $total config file(s) are not linked: $shown" "$MUJO_ROOT/install.sh --skip-system"
  else
    doctor_add links ok "all $total config files are linked"
  fi
}

doctor_theme() {
  local out problems
  out=$("$MUJO_BIN" theme check --json 2>/dev/null) || true
  problems=$(jq -r '.data.problems // [] | length' <<<"$out" 2>/dev/null) || problems=""
  if [[ -z $problems ]]; then
    doctor_add theme fail "'$MUJO_NAME theme check' did not run" "$MUJO_NAME theme check"
  elif (( problems > 0 )); then
    doctor_add theme fail "$problems generated file(s) are missing or out of date" "$MUJO_NAME theme build"
  else
    doctor_add theme ok "generated theme files match the tokens"
  fi
}

doctor_settings() {
  if [[ -f $MUJO_CONFIG_FILE ]] && ! jq -e 'type == "object"' "$MUJO_CONFIG_FILE" >/dev/null 2>&1; then
    doctor_add settings fail "$(tilde "$MUJO_CONFIG_FILE") is not a JSON object" "fix or remove the file"
  else
    doctor_add settings ok "config.json is readable"
  fi
  if [[ -f $MUJO_JOURNAL ]]; then
    local bad
    bad=$(jq -cR 'fromjson? // "bad"' "$MUJO_JOURNAL" 2>/dev/null | grep -c '^"bad"$' || true)
    if (( bad > 0 )); then
      doctor_add settings warn "$bad line(s) of the journal are not valid JSON and are ignored"
    else
      doctor_add settings ok "the journal is readable ($(wc -l <"$MUJO_JOURNAL") entries)"
    fi
  fi
  local wall
  wall=$(config_read | jq -r '.wallpaper // empty')
  if [[ -n $wall && ! -f $wall ]]; then
    doctor_add settings warn "the wallpaper $wall no longer exists" "$MUJO_NAME wall clear"
  fi
}

doctor_services() {
  if ! command -v systemctl >/dev/null 2>&1; then
    doctor_add services skip "systemctl is not available here"
    return 0
  fi
  local unit
  for unit in NetworkManager.service bluetooth.service; do
    if systemctl is-enabled -q "$unit" 2>/dev/null; then
      doctor_add services ok "$unit is enabled"
    else
      doctor_add services warn "$unit is not enabled" "sudo systemctl enable --now $unit"
    fi
  done
  if systemctl is-enabled -q greetd.service 2>/dev/null; then
    doctor_add services ok "greetd.service (the login screen) is enabled"
  else
    doctor_add services warn "greetd.service is not enabled; another login screen is in use" "$MUJO_ROOT/install.sh"
  fi
  if systemctl --user is-active -q pipewire.service 2>/dev/null && systemctl --user is-active -q wireplumber.service 2>/dev/null; then
    doctor_add services ok "PipeWire and WirePlumber are running"
  else
    doctor_add services warn "PipeWire or WirePlumber is not running for this user (normal over SSH without a session)" \
      "systemctl --user enable --now pipewire wireplumber"
  fi
  [[ ${SHELL:-} == */zsh ]] || doctor_add services warn "the login shell is ${SHELL:-unknown}, not zsh" "chsh -s /bin/zsh"
}

doctor_session() {
  if [[ -z ${WAYLAND_DISPLAY:-} || -z ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; then
    doctor_add session skip "not inside the graphical session; session checks skipped"
    return 0
  fi
  local errors
  errors=$(hyprctl configerrors 2>/dev/null | grep -c . || true)
  if (( errors > 0 )); then
    doctor_add session fail "Hyprland reports config errors" "hyprctl configerrors"
  else
    doctor_add session ok "Hyprland has no config errors"
  fi
  if command -v qs >/dev/null 2>&1 && timeout 2 qs -c "$MUJO_NAME" ipc show >/dev/null 2>&1; then
    doctor_add session ok "the interface (qs -c $MUJO_NAME) is running"
  else
    doctor_add session fail "the interface is not running" "systemctl --user restart $MUJO_NAME-ui.service"
  fi
  if pgrep -x dunst >/dev/null 2>&1 || pgrep -x mako >/dev/null 2>&1; then
    doctor_add session warn "another notification daemon is running and may take notifications from the interface" \
      "systemctl --user stop dunst (and consider removing it)"
  fi
  if pgrep -x hypridle >/dev/null 2>&1; then
    doctor_add session ok "hypridle is running (locks after 10 minutes without input)"
  else
    doctor_add session warn "hypridle is not running; the screen will not lock by itself" "it starts at the next login, or run: hypridle &"
  fi
}

cmd_doctor() {
  (( $# == 0 )) || usage_error "unexpected argument '$1'"
  DOCTOR_ROWS=()
  doctor_packages
  doctor_links
  doctor_theme
  doctor_settings
  doctor_services
  doctor_session

  local checks failed warned
  checks=$(printf '%s\n' "${DOCTOR_ROWS[@]}" | jq -cs .)
  failed=$(jq '[.[] | select(.status == "fail")] | length' <<<"$checks")
  warned=$(jq '[.[] | select(.status == "warn")] | length' <<<"$checks")
  jq -r '.[] | (if .status == "ok" then "  ok    " elif .status == "warn" then "  WARN  " elif .status == "fail" then "  FAIL  " else "  skip  " end)
    + "\(.group): \(.message)" + (if .fix then "\n          fix: \(.fix)" else "" end)' <<<"$checks" | say_stream
  if (( failed > 0 )); then
    say "$failed problem(s), $warned warning(s)."
  elif (( warned > 0 )); then
    say "No problems, $warned warning(s)."
  else
    say "Everything is in order."
  fi
  jq -n --argjson c "$checks" --argjson f "$failed" --argjson w "$warned" \
    '{ok: ($f == 0), failed: $f, warnings: $w, checks: $c}' | emit
  (( failed == 0 )) || exit "$EXIT_FAIL"
}
