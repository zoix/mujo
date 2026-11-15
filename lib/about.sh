# shellcheck shell=bash
# mujo about: what this machine is and whether mujo is in good shape.
# Read-only; the card behind the logo in the bar shows it.

mujo_register about "This machine, and mujo's health at a glance"

help_about() {
  cat <<EOF
Usage: $MUJO_NAME about [--window]

Shows the machine (model, system, kernel, Hyprland, processor, graphics,
memory, packages, uptime) and how $MUJO_NAME is doing: the result of
'$MUJO_NAME doctor', pending updates as last counted, the snapshots of the
last update and the latest changes from the journal.

Changes nothing. With --window inside the desktop it opens the card behind
the logo in the bar.
EOF
}

# about_first FILE: the first line of a file, or nothing.
about_first() {
  [[ -r $1 ]] && head -n 1 -- "$1" 2>/dev/null
}

about_state() {
  local root=${MUJO_SYSROOT:-} host os kernel hypr="" cpu gpu="" packages=null commit=""
  host=$(printf '%s %s' "$(about_first "$root/sys/class/dmi/id/sys_vendor")" "$(about_first "$root/sys/class/dmi/id/product_name")")
  host=${host# } host=${host% }
  # shellcheck source=/dev/null
  os=$(. "$root/etc/os-release" 2>/dev/null && printf '%s' "${PRETTY_NAME:-${NAME:-}}")
  kernel=$(uname -r)
  if [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]] && command -v hyprctl >/dev/null 2>&1; then
    hypr=$(timeout 2 hyprctl version -j 2>/dev/null | jq -r '.version // empty' 2>/dev/null) || hypr=""
  fi
  cpu=$(awk -F': ' '/^model name/ { print $2; exit }' /proc/cpuinfo 2>/dev/null)
  if command -v lspci >/dev/null 2>&1; then
    # "Strix [Radeon 880M / 890M]" -> "Radeon 880M / 890M"
    gpu=$(lspci -mm 2>/dev/null | awk -F'"' '$2 ~ /VGA|3D|Display/ { print $6; exit }' | sed -E 's/^.*\[(.*)\]$/\1/')
  fi
  if command -v pacman >/dev/null 2>&1; then
    packages=$(pacman -Qq 2>/dev/null | wc -l) || packages=null
  fi
  if command -v git >/dev/null 2>&1; then
    commit=$(git -C "$MUJO_ROOT" rev-parse --short HEAD 2>/dev/null) || commit=""
  fi

  local doctor updates=null snapshot=null recent
  doctor=$("$MUJO_BIN" doctor --json 2>/dev/null 3>/dev/null | jq -c '.data | {ok, failed, warnings}' 2>/dev/null) || true
  [[ -n $doctor ]] || doctor=null
  [[ -f $UPDATE_CACHE ]] && updates=$(jq -c '{count, checked}' "$UPDATE_CACHE" 2>/dev/null || echo null)
  [[ -f $UPDATE_SNAPSHOT_FILE ]] && snapshot=$(jq -c . "$UPDATE_SNAPSHOT_FILE" 2>/dev/null || echo null)
  recent=$(journal_entries | jq -c 'reverse | .[:3] | map({id, time, summary, reversible, undone: (.undone_by != null)})')

  jq -cn --arg v "$MUJO_VERSION" --arg commit "$commit" --arg host "$host" --arg os "$os" --arg kernel "$kernel" \
    --arg hypr "$hypr" --arg cpu "$cpu" --arg gpu "$gpu" --argjson packages "${packages:-null}" \
    --argjson sys "$(sys_state)" --argjson doctor "$doctor" --argjson updates "${updates:-null}" \
    --argjson snapshot "${snapshot:-null}" --argjson recent "$recent" '
    def text: if . == "" then null else . end;
    {mujo: {version: $v, commit: ($commit | text)},
     host: ($host | text), os: ($os | text), kernel: $kernel, hyprland: ($hypr | text),
     cpu: ($cpu | text), gpu: ($gpu | text),
     memory_kb: $sys.memory.total_kb, disk: $sys.disk, uptime_s: $sys.uptime_s, packages: $packages,
     doctor: $doctor, updates: $updates, snapshot: $snapshot, recent: $recent}'
}

cmd_about() {
  (( $# == 0 )) || usage_error "unexpected argument '$1'"
  local state
  state=$(about_state)
  jq -r --arg name "$MUJO_NAME" '
    def gib: . / 1048576 | round;
    def row(k; v): if v == null then empty else "\(k)\(" " * (10 - (k | length)))  \(v)" end;
    "\($name) \(.mujo.version)\(if .mujo.commit then " (\(.mujo.commit))" else "" end)",
    "",
    row("Machine"; .host), row("System"; .os), row("Kernel"; .kernel), row("Hyprland"; .hyprland),
    row("Processor"; .cpu), row("Graphics"; .gpu),
    row("Memory"; "\(.memory_kb | gib) GiB"),
    row("Disk /"; "\(.disk.percent)% of \(.disk.total_kb | gib) GiB"),
    row("Packages"; .packages),
    row("Uptime"; "\(.uptime_s / 3600 | floor) h \(.uptime_s % 3600 / 60 | floor) min"),
    "",
    row("Health"; (.doctor | if . == null then "not checked" elif .failed > 0 then "\(.failed) problem(s), \(.warnings) warning(s)"
      elif .warnings > 0 then "no problems, \(.warnings) warning(s)" else "everything is in order" end)),
    row("Updates"; (.updates | if . == null then "not counted yet (\($name) update check)" elif .count == 0 then "up to date"
      else "\(.count) package(s) waiting" end)),
    row("Snapshots"; (.snapshot | if . == null then "none on record" else "\(.pre)..\(.post // "?") from the last update (\(.packages | length) package(s))" end)),
    (if (.recent | length) > 0 then "", "Latest changes:", (.recent[] | "  \(.summary)") else empty end)' <<<"$state" | say_stream
  printf '%s' "$state" | emit
}
