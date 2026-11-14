# shellcheck shell=bash
# karma sys: processor, memory, temperature, disk and uptime. Read-only; the
# dashboard of the interface shows it.

karma_register sys "Processor, memory, temperature, disk, uptime"

help_sys() {
  cat <<EOF
Usage: $KARMA_NAME sys [--window]

Shows processor load, memory, temperature, disk space and uptime. With
--window inside the desktop it opens the dashboard of the interface.

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

sys_state() {
  local cpu mem_total mem_avail temp disk uptime
  cpu=$(sys_cpu)
  mem_total=$(awk '/^MemTotal:/ { print $2 }' /proc/meminfo)
  mem_avail=$(awk '/^MemAvailable:/ { print $2 }' /proc/meminfo)
  temp=$(sys_temperature) || temp=null
  disk=$(df -kP / 2>/dev/null | awk 'NR == 2 { print $2, $3 }')
  uptime=$(cut -d. -f1 /proc/uptime)
  jq -cn --arg cpu "$cpu" --argjson mt "${mem_total:-0}" --argjson ma "${mem_avail:-0}" --argjson temp "$temp" \
    --arg disk "$disk" --argjson up "${uptime:-0}" --argjson cores "$(nproc 2>/dev/null || echo 1)" '
    ($cpu | split(" ") | map(tonumber)) as $c | ($disk | split(" ") | map(tonumber)) as $d
    | {cpu: {total: $c[0], idle: $c[1], cores: $cores},
       memory: {total_kb: $mt, available_kb: $ma,
                percent: (if $mt > 0 then (($mt - $ma) * 100 / $mt | round) else 0 end)},
       temperature_c: $temp,
       disk: {total_kb: ($d[0] // 0), used_kb: ($d[1] // 0),
              percent: (if ($d[0] // 0) > 0 then ($d[1] * 100 / $d[0] | round) else 0 end)},
       uptime_s: $up}'
}

cmd_sys() {
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
