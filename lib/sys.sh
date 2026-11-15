# shellcheck shell=bash
# mujo sys: processor, memory, temperature, disk and uptime. Read-only; the
# dashboard of the interface shows it.

mujo_register sys "Processor, memory, temperature, disk, uptime"

help_sys() {
  cat <<EOF
Usage: $MUJO_NAME sys [--window]
       $MUJO_NAME sys workspaces [--window]
       $MUJO_NAME sys activity [--window]

Shows processor load, memory, temperature, disk space and uptime. With
--window inside the desktop it opens the dashboard of the interface.

workspaces lists the Hyprland workspaces and the windows on each; with
--window it opens the dashboard's page of workspace miniatures.

activity gathers what the dashboard's Activity page shows: the latest
changes from the journal, the battery's charge over the last day and the
newest screenshots and recordings. With --window it opens that page.

With --json the processor is reported as raw counters (total and idle time
since boot), so that a program can take two readings and work out the load
between them.
EOF
}

# The CPU temperature in whole degrees, from the first sensor that has one.
sys_temperature() {
  local dir name
  for name in k10temp coretemp zenpower cpu_thermal acpitz; do
    for dir in /sys/class/hwmon/hwmon*; do
      [[ -r $dir/name && $(<"$dir/name") == "$name" && -r $dir/temp1_input ]] || continue
      echo $(( $(<"$dir/temp1_input") / 1000 ))
      return 0
    done
  done
  return 1
}

# sys_cpu: print "TOTAL IDLE" jiffies since boot.
sys_cpu() {
  awk '/^cpu / { total = 0; for (i = 2; i <= NF; i++) total += $i; print total, $5 + $6; exit }' /proc/stat
}

# sys_net: the interface that carries the default route, its address and
# the bytes received and sent since it came up, as JSON (null without one).
sys_net() {
  local root=${MUJO_SYSROOT:-} iface="" address="" rx tx
  iface=$(awk '$2 == "00000000" && $1 != "Iface" { print $1; exit }' "$root/proc/net/route" 2>/dev/null)
  if [[ -z $iface || ! -r $root/sys/class/net/$iface/statistics/rx_bytes ]]; then
    echo null
    return 0
  fi
  rx=$(<"$root/sys/class/net/$iface/statistics/rx_bytes")
  tx=$(<"$root/sys/class/net/$iface/statistics/tx_bytes")
  if command -v ip >/dev/null 2>&1; then
    address=$(ip -4 -o addr show dev "$iface" 2>/dev/null | awk '{ sub(/\/.*/, "", $4); print $4; exit }')
  fi
  jq -cn --arg i "$iface" --arg a "$address" --argjson rx "${rx:-0}" --argjson tx "${tx:-0}" \
    '{interface: $i, address: (if $a == "" then null else $a end), rx_bytes: $rx, tx_bytes: $tx}'
}

# sys_battery_history: the battery's charge over the last 24 hours as
# [[seconds ago, percent], ...], oldest first, at most about 100 points.
# UPower keeps the record; an empty list without it.
sys_battery_history() {
  local root=${MUJO_SYSROOT:-} file="" f now
  for f in "$root"/var/lib/upower/history-charge-*.dat; do
    [[ -r $f && $f != *generic_id* ]] || continue
    file=$f
    break
  done
  if [[ -z $file ]]; then
    echo '[]'
    return 0
  fi
  now=$(date +%s)
  awk -v now="$now" '$1 > now - 86400 && $2 > 0 { print now - $1, $2 + 0 }' "$file" \
    | jq -cRs 'split("\n") | map(select(length > 0) | split(" ") | map(tonumber))
        | (length / 100 | ceil) as $step | if $step > 1 then [.[range(0; length; $step)]] + [.[-1]] else . end'
}

# sys_captures: the newest screenshots and recordings, newest first.
sys_captures() {
  local shots videos
  shots=$(shot_dir)
  videos=$(record_dir)
  {
    [[ -d $shots ]] && find "$shots" -maxdepth 1 -type f \( -name '*.png' -o -name '*.jpg' \) -printf '%T@\tscreenshot\t%p\n' 2>/dev/null
    [[ -d $videos ]] && find "$videos" -maxdepth 1 -type f \( -name '*.mp4' -o -name '*.mkv' -o -name '*.webm' \) -printf '%T@\trecording\t%p\n' 2>/dev/null
  } | sort -rn | head -n 6 \
    | jq -cRs 'split("\n") | map(select(length > 0) | split("\t") | {time: (.[0] | tonumber | floor), kind: .[1], path: .[2]})'
}

sys_state() {
  local cpu mem_total mem_avail temp disk uptime
  cpu=$(sys_cpu)
  mem_total=$(awk '/^MemTotal:/ { print $2 }' /proc/meminfo)
  mem_avail=$(awk '/^MemAvailable:/ { print $2 }' /proc/meminfo)
  temp=$(sys_temperature) || temp=null
  disk=$(df -kP / 2>/dev/null | awk 'NR == 2 { print $2, $3 }')
  uptime=$(cut -d. -f1 /proc/uptime)
  jq -cn --arg cpu "$cpu" --argjson mt "${mem_total:-0}" --argjson ma "${mem_avail:-0}" --argjson temp "$temp" \
    --arg disk "$disk" --argjson up "${uptime:-0}" --argjson cores "$(nproc 2>/dev/null || echo 1)" \
    --argjson net "$(sys_net)" '
    ($cpu | split(" ") | map(tonumber)) as $c | ($disk | split(" ") | map(tonumber)) as $d
    | {cpu: {total: $c[0], idle: $c[1], cores: $cores},
       memory: {total_kb: $mt, available_kb: $ma,
                percent: (if $mt > 0 then (($mt - $ma) * 100 / $mt | round) else 0 end)},
       temperature_c: $temp,
       disk: {total_kb: ($d[0] // 0), used_kb: ($d[1] // 0),
              percent: (if ($d[0] // 0) > 0 then ($d[1] * 100 / $d[0] | round) else 0 end)},
       net: $net,
       uptime_s: $up}'
}

cmd_sys() {
  if [[ ${1:-} == workspaces ]]; then
    (( $# == 1 )) || usage_error "unexpected argument '$2'"
    mujo_set_cmd "sys workspaces"
    require_hyprland
    local spaces
    spaces=$(hyprctl clients -j 2>/dev/null | jq -c --argjson ws "$(hyprctl workspaces -j 2>/dev/null)" '
      . as $clients | [$ws[] | select(.id > 0) | . as $w
        | {id, name, monitor, windows: [$clients[] | select(.workspace.id == $w.id) | {class, title}]}] | sort_by(.id)') \
      || die "$EXIT_FAIL" "could not read the workspaces from Hyprland"
    jq -r '.[] | "\(.id)  \(.monitor)  \(if (.windows | length) == 0 then "empty" else ([.windows[].class] | join(", ")) end)"' <<<"$spaces" | say_stream
    jq -n --argjson s "$spaces" '{workspaces: $s}' | emit
    return 0
  fi
  if [[ ${1:-} == activity ]]; then
    (( $# == 1 )) || usage_error "unexpected argument '$2'"
    mujo_set_cmd "sys activity"
    local activity
    activity=$(jq -cn --argjson changes "$(journal_entries | jq -c 'reverse | .[:7] | map({id, time, summary, reversible, undone: (.undone_by != null)})')" \
      --argjson battery "$(sys_battery_history)" --argjson captures "$(sys_captures)" \
      '{changes: $changes, battery: $battery, captures: $captures}')
    jq -r '
      "Latest changes:", (if (.changes | length) == 0 then "  none yet" else (.changes[] | "  \(.time | fromdateiso8601 | strflocaltime("%H:%M"))  \(.summary)") end),
      "", "Battery: \(.battery | length) reading(s) from the last 24 hours" + (if (.battery | length) > 0 then ", now \(.battery[-1][1])%" else "" end),
      "", "Screenshots and recordings:", (if (.captures | length) == 0 then "  none yet" else (.captures[] | "  \(.path)") end)' <<<"$activity" | say_stream
    printf '%s' "$activity" | emit
    return 0
  fi
  (( $# == 0 )) || usage_error "unexpected argument '$1'"
  local state
  state=$(sys_state)
  if (( ! OPT_JSON )); then
    # Two readings a moment apart give the load right now.
    local a b load
    a=$(sys_cpu)
    sleep 0.25
    b=$(sys_cpu)
    load=$(awk -v a="$a" -v b="$b" 'BEGIN { split(a, x, " "); split(b, y, " "); t = y[1] - x[1]; i = y[2] - x[2];
      printf "%d", (t > 0 ? (t - i) * 100 / t : 0) }')
    jq -r --arg load "$load" '
      def gib: . / 1048576 * 10 | round / 10;
      "Processor    \($load)% of \(.cpu.cores) cores",
      "Memory       \(.memory.percent)%  (\((.memory.total_kb - .memory.available_kb) | gib) of \(.memory.total_kb | gib) GiB)",
      "Temperature  \(if .temperature_c == null then "no sensor" else "\(.temperature_c) °C" end)",
      "Disk /       \(.disk.percent)%  (\(.disk.used_kb | gib) of \(.disk.total_kb | gib) GiB)",
      "Uptime       \(.uptime_s / 3600 | floor) h \(.uptime_s % 3600 / 60 | floor) min"' <<<"$state" | say_stream
  fi
  printf '%s' "$state" | emit
}
