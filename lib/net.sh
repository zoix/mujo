# shellcheck shell=bash
# karma net: Wi-Fi through NetworkManager (nmcli), with its own fzf TUI.

karma_register net "Wi-Fi status, scan, connect, forget (TUI: net tui)"

help_net() {
  cat <<EOF
Usage: $KARMA_NAME net [status]
       $KARMA_NAME net scan [--no-rescan]
       $KARMA_NAME net connect SSID [--password-stdin]
       $KARMA_NAME net disconnect
       $KARMA_NAME net forget SSID --yes
       $KARMA_NAME net wifi [on | off | toggle]
       $KARMA_NAME net tui [--window]

status      Wi-Fi radio, the current network and every active connection.
scan        Networks in range, strongest first.
connect     Join a network. A saved network needs no password. For a new one
            the password is asked on the terminal, or read from stdin with
            --password-stdin (it is then visible to other processes of this
            user while nmcli runs). The password is never journaled.
disconnect  Leave the current Wi-Fi network.
forget      Delete a saved network and its password. Cannot be undone.
wifi        Show or switch the Wi-Fi radio.
tui         Pick a network with fzf: Enter connects, Ctrl-D disconnects,
            Ctrl-X forgets, Ctrl-R rescans, Ctrl-W switches the radio.

connect, disconnect and wifi are journaled and can be undone.
EOF
}

net_running() {
  command -v nmcli >/dev/null 2>&1 || return 1
  [[ $(nmcli -t -f RUNNING general 2>/dev/null) == running ]]
}

net_need() {
  need nmcli
  net_running || die "$EXIT_ENV" "NetworkManager is not running"
}

net_wifi_device() {
  nmcli -t -f DEVICE,TYPE device 2>/dev/null | awk -F: '$2 == "wifi" { print $1; exit }'
}

net_wifi_enabled() {
  if [[ $(nmcli -t -f WIFI radio 2>/dev/null) == enabled ]]; then echo true; else echo false; fi
}

# The SSID the Wi-Fi device is connected to, or nothing.
net_current_ssid() {
  nmcli -t -e no -f ACTIVE,SSID device wifi list --rescan no 2>/dev/null | sed -n 's/^yes://p' | head -n 1
}

net_saved() {
  nmcli -t -e no -f TYPE,NAME connection show 2>/dev/null | sed -n 's/^802-11-wireless://p'
}

# net_state: JSON snapshot. Fails if NetworkManager is not running.
net_state() {
  net_running || return 1
  local dev ssid signal="" ip=""
  dev=$(net_wifi_device)
  ssid=$(net_current_ssid)
  if [[ -n $ssid ]]; then
    signal=$(nmcli -t -e no -f ACTIVE,SIGNAL device wifi list --rescan no 2>/dev/null | sed -n 's/^yes://p' | head -n 1)
  fi
  if [[ -n $dev ]]; then
    ip=$(nmcli -t -e no -f IP4.ADDRESS device show "$dev" 2>/dev/null | sed -n '1s/^[^:]*://p')
  fi
  nmcli -t -e no -f DEVICE,TYPE,STATE,CONNECTION device 2>/dev/null \
    | jq -cRn --arg dev "$dev" --arg ssid "$ssid" --arg signal "$signal" --arg ip "$ip" \
        --argjson wifi "$(net_wifi_enabled)" \
        --arg conn "$(nmcli -t -f CONNECTIVITY general 2>/dev/null)" '
      [inputs | split(":") | {device: .[0], type: .[1], state: .[2], connection: (.[3:] | join(":"))}
       | select(.type != "loopback" and .type != "wifi-p2p" and (.state | startswith("connected")))] as $active
      | {wifi_enabled: $wifi,
         wifi: (if $dev == "" then null else
           {device: $dev, ssid: (if $ssid == "" then null else $ssid end),
            signal: (if $signal == "" then null else ($signal | tonumber) end),
            ip4: (if $ip == "" then null else $ip end)} end),
         connectivity: $conn, connections: $active}'
}

# net_scan_json RESCAN(yes|no|auto): networks in range as a JSON array.
net_scan_json() {
  local saved
  saved=$(net_saved | jq -cRn '[inputs]')
  nmcli -t -e no -f ACTIVE,SIGNAL,SECURITY,SSID device wifi list --rescan "$1" 2>/dev/null \
    | jq -cRn --argjson saved "$saved" '
      [inputs | split(":") | {in_use: (.[0] == "yes"), signal: (.[1] | tonumber? // 0),
         security: (if .[2] == "" or .[2] == "--" then "open" else .[2] end), ssid: (.[3:] | join(":"))}
       | select(.ssid != "")]
      | group_by(.ssid)
      | map((max_by(.signal)) + {in_use: any(.[]; .in_use)})
      | map(. + {saved: (.ssid as $s | $saved | index($s) != null)})
      | sort_by([(if .in_use then 0 else 1 end), -.signal])'
}

cmd_net() {
  local sub=${1:-status}
  (( $# )) && shift
  karma_set_cmd "net $sub"
  case $sub in
    status) net_cmd_status "$@" ;;
    scan) net_cmd_scan "$@" ;;
    connect) net_cmd_connect "$@" ;;
    disconnect) net_cmd_disconnect "$@" ;;
    forget) net_cmd_forget "$@" ;;
    wifi) net_cmd_wifi "$@" ;;
    tui) net_cmd_tui "$@" ;;
    *) usage_error "unknown subcommand '$sub'" ;;
  esac
}

net_cmd_status() {
  (( $# == 0 )) || usage_error "unexpected argument '$1'"
  net_need
  local state
  state=$(net_state)
  jq -r '
    "Wi-Fi radio   \(if .wifi_enabled then "on" else "off" end)",
    (if .wifi == null then "Wi-Fi         no Wi-Fi device"
     elif .wifi.ssid == null then "Wi-Fi         not connected (\(.wifi.device))"
     else "Wi-Fi         \(.wifi.ssid)  \(.wifi.signal // "?")%  \(.wifi.ip4 // "no address")  (\(.wifi.device))" end),
    "Internet      \(.connectivity)",
    (.connections[] | select(.type != "wifi") | "Also active   \(.connection) (\(.type), \(.device))")' <<<"$state" | say_stream
  printf '%s' "$state" | emit
}

net_cmd_scan() {
  local rescan=yes
  while (( $# )); do
    case $1 in
      --no-rescan) rescan=no; shift ;;
      *) usage_error "unexpected argument '$1'" ;;
    esac
  done
  net_need
  local nets
  nets=$(net_scan_json "$rescan")
  if [[ $nets == "[]" ]]; then
    say "No networks found$([[ $(net_wifi_enabled) == false ]] && echo " (the Wi-Fi radio is off)" || true)."
  else
    jq -r '.[] | [(if .in_use then "*" else " " end), "\(.signal)%", .security,
      (if .saved then "saved" else "-" end), .ssid] | @tsv' <<<"$nets" \
      | while IFS=$'\t' read -r use signal security saved ssid; do
          printf '%s %5s  %-14s %-6s %s\n' "$use" "$signal" "$security" "$saved" "$ssid"
        done | say_stream
  fi
  jq -n --argjson n "$nets" '{networks: $n}' | emit
}

net_cmd_connect() {
  local ssid="" from_stdin=0
  while (( $# )); do
    case $1 in
      --password-stdin) from_stdin=1; shift ;;
      --*) usage_error "unknown option '$1'" ;;
      *)
        [[ -z $ssid ]] || usage_error "too many arguments (quote an SSID that contains spaces)"
        ssid=$1
        shift
        ;;
    esac
  done
  [[ -n $ssid ]] || usage_error "missing SSID"
  net_need
  local cur before after undo
  cur=$(net_current_ssid)
  before=$(jq -cn --arg s "$cur" '{ssid: (if $s == "" then null else $s end)}')
  after=$(jq -cn --arg s "$ssid" '{ssid: $s}')
  change_begin "net connect: ${cur:-not connected} -> $ssid" "$before" "$after" || return 0

  local out rc=0
  if net_saved | grep -Fxq -- "$ssid"; then
    out=$(nmcli -w 30 connection up id "$ssid" 2>&1) || rc=$?
  elif (( from_stdin )); then
    local password
    IFS= read -r password || true
    out=$(nmcli -w 30 device wifi connect "$ssid" password "$password" 2>&1) || rc=$?
  elif [[ -t 0 ]] && (( ! OPT_JSON )); then
    nmcli -w 60 --ask device wifi connect "$ssid" >&2 || rc=$?
    out="see the message above"
  else
    out=$(nmcli -w 30 device wifi connect "$ssid" 2>&1) || rc=$?
  fi
  if (( rc != 0 )); then
    ui_notify "Wi-Fi" "Could not connect to $ssid"
    die "$EXIT_FAIL" "could not connect to '$ssid': $out"
  fi
  ui_notify "Wi-Fi" "Connected to $ssid"

  if [[ -n $cur ]]; then undo=$(json_array net connect "$cur"); else undo=$(json_array net disconnect); fi
  change_end "net connect: ${cur:-not connected} -> $ssid" "$before" "$after" "$undo"
}

net_cmd_disconnect() {
  (( $# == 0 )) || usage_error "unexpected argument '$1'"
  net_need
  local dev cur before
  dev=$(net_wifi_device)
  [[ -n $dev ]] || die "$EXIT_ENV" "no Wi-Fi device"
  cur=$(net_current_ssid)
  before=$(jq -cn --arg s "$cur" '{ssid: (if $s == "" then null else $s end)}')
  change_begin "net disconnect: $cur -> not connected" "$before" '{"ssid":null}' || return 0
  nmcli device disconnect "$dev" >/dev/null 2>&1 || die "$EXIT_FAIL" "could not disconnect $dev"
  change_end "net disconnect: $cur -> not connected" "$before" '{"ssid":null}' "$(json_array net connect "$cur")"
}

net_cmd_forget() {
  (( $# == 1 )) || usage_error "forget needs exactly one SSID"
  local ssid=$1
  net_need
  net_saved | grep -Fxq -- "$ssid" || die "$EXIT_FAIL" "no saved network '$ssid'"
  confirm_irreversible "Forgetting '$ssid' (its password is deleted)"
  local before
  before=$(jq -cn --arg s "$ssid" '{saved: $s}')
  change_begin "net forget: $ssid" "$before" '{"saved":null}' || return 0
  nmcli connection delete id "$ssid" >/dev/null 2>&1 || die "$EXIT_FAIL" "could not delete '$ssid'"
  change_end "net forget: $ssid" "$before" '{"saved":null}' null
}

net_cmd_wifi() {
  (( $# <= 1 )) || usage_error "too many arguments"
  net_need
  local cur new
  cur=$(net_wifi_enabled)
  if (( $# == 0 )); then
    say "Wi-Fi radio: $([[ $cur == true ]] && echo on || echo off)"
    jq -n --argjson w "$cur" '{wifi_enabled: $w}' | emit
    return 0
  fi
  new=$(on_off "$1" "$cur") || usage_error "expected on, off or toggle, got '$1'"
  local word_cur word_new before after
  word_cur=$([[ $cur == true ]] && echo on || echo off)
  word_new=$([[ $new == true ]] && echo on || echo off)
  before=$(jq -cn --argjson w "$cur" '{wifi_enabled: $w}')
  after=$(jq -cn --argjson w "$new" '{wifi_enabled: $w}')
  change_begin "net wifi: $word_cur -> $word_new" "$before" "$after" || return 0
  nmcli radio wifi "$word_new" >/dev/null 2>&1 || die "$EXIT_FAIL" "could not switch the Wi-Fi radio"
  change_end "net wifi: $word_cur -> $word_new" "$before" "$after" "$(json_array net wifi "$word_cur")"
}

# Signal strength as four bars.
net_bars() {
  local s=$1
  if (( s >= 75 )); then echo "▂▄▆█"
  elif (( s >= 50 )); then echo "▂▄▆ "
  elif (( s >= 25 )); then echo "▂▄  "
  else echo "▂   "
  fi
}

net_cmd_tui() {
  (( $# == 0 )) || usage_error "unexpected argument '$1'"
  tui_require
  net_need
  # "auto" lets NetworkManager reuse a scan that is less than 30 seconds old.
  local rescan=auto nets out key row ssid header
  while true; do
    [[ $rescan == no ]] || printf '%s\n' "Scanning for networks..." >&2
    nets=$(net_scan_json "$rescan")
    rescan=no
    header="Wi-Fi $([[ $(net_wifi_enabled) == true ]] && echo on || echo off)"
    header+=$'\n'"Enter connect   Ctrl-D disconnect   Ctrl-X forget"
    header+=$'\n'"Ctrl-R rescan   Ctrl-W radio on/off"
    out=$(jq -r '.[] | [.ssid, (.signal | tostring), .security,
        (if .in_use then "connected" elif .saved then "saved" else "" end)] | @tsv' <<<"$nets" \
      | while IFS=$'\t' read -r ssid signal security note; do
          printf '%s\t%s %3s%%  %-28s %-12s %s\n' "$ssid" "$(net_bars "$signal")" "$signal" "$ssid" "$security" "$note"
        done \
      | tui_pick --delimiter '\t' --with-nth 2 --prompt 'Wi-Fi > ' --header "$header" \
          --expect=ctrl-d,ctrl-x,ctrl-r,ctrl-w) || return 0
    key=$(sed -n 1p <<<"$out")
    row=$(sed -n 2p <<<"$out")
    ssid=${row%%$'\t'*}
    case $key in
      ctrl-r) rescan=yes; continue ;;
      ctrl-w) "$KARMA_BIN" net wifi toggle || true; sleep 1; rescan=yes ;;
      ctrl-d) "$KARMA_BIN" net disconnect || true ;;
      ctrl-x)
        [[ -n $ssid ]] || continue
        printf 'Forget "%s" and its password? This cannot be undone. [y/N] ' "$ssid" >&2
        local answer
        read -r answer || answer=""
        [[ $answer == [yY]* ]] && { "$KARMA_BIN" net forget "$ssid" --yes || true; }
        ;;
      *)
        [[ -n $ssid ]] || continue
        "$KARMA_BIN" net connect "$ssid" || true
        ;;
    esac
    tui_pause
  done
}
