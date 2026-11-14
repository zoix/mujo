# shellcheck shell=bash
# karma status: one snapshot of everything the other commands control.
# A section that cannot be read here (no PipeWire over this SSH session, no
# Bluetooth adapter, ...) is null instead of an error.

karma_register status "One snapshot of audio, network, display, theme, battery"

help_status() {
  cat <<EOF
Usage: $KARMA_NAME status

Audio, network, Bluetooth, display, theme, wallpaper, battery and session in
one view. With --json each section has the same shape as the command that
owns it ('$KARMA_NAME audio --json', ...), or null when it is not available.
EOF
}

status_battery() {
  local d
  for d in /sys/class/power_supply/BAT*; do
    [[ -r $d/capacity ]] || continue
    jq -cn --arg n "${d##*/}" --arg p "$(<"$d/capacity")" --arg s "$(cat "$d/status" 2>/dev/null)" \
      '{name: $n, percent: ($p | tonumber? // null), status: ($s | ascii_downcase)}'
    return 0
  done
  return 1
}

status_session() {
  jq -cn --arg w "${WAYLAND_DISPLAY:-}" --arg h "${HYPRLAND_INSTANCE_SIGNATURE:-}" \
    --arg t "${XDG_SESSION_TYPE:-}" \
    '{wayland: ($w != ""), hyprland: ($h != ""), type: (if $t == "" then null else $t end)}'
}

cmd_status() {
  (( $# == 0 )) || usage_error "unexpected argument '$1'"
  local audio net bt display battery state
  audio=$(audio_state 2>/dev/null) || audio=null
  net=$(net_state 2>/dev/null) || net=null
  bt=$(bt_state 2>/dev/null) || bt=null
  display=$(display_state 2>/dev/null) || display=null
  battery=$(status_battery 2>/dev/null) || battery=null
  state=$(jq -cn --argjson audio "${audio:-null}" --argjson net "${net:-null}" --argjson bt "${bt:-null}" \
    --argjson display "${display:-null}" --argjson battery "${battery:-null}" \
    --argjson theme "$(theme_settings)" --argjson wall "$(wall_state)" --argjson session "$(status_session)" \
    '{audio: $audio, network: $net, bluetooth: $bt, display: $display, theme: $theme,
      wallpaper: $wall.wallpaper, battery: $battery, session: $session}')
  jq -r '
    def na: "not available here";
    "Audio      " + (if .audio == null or .audio.output == null then na
      else "\(.audio.output.volume)%\(if .audio.output.muted then " (muted)" else "" end)  \(.audio.output.device // "")"
        + (if .audio.input then "   mic \(.audio.input.volume)%\(if .audio.input.muted then " (muted)" else "" end)" else "" end) end),
    "Network    " + (if .network == null then na
      elif .network.wifi != null and .network.wifi.ssid != null then "\(.network.wifi.ssid)  \(.network.wifi.signal // "?")%  (\(.network.connectivity))"
      elif (.network.connections | length) > 0 then "\(.network.connections[0].connection) (\(.network.connections[0].type))"
      else "not connected, Wi-Fi \(if .network.wifi_enabled then "on" else "off" end)" end),
    "Bluetooth  " + (if .bluetooth == null then na
      elif .bluetooth.powered then "on, \([.bluetooth.devices[] | select(.connected)] | length) connected"
      else "off" end),
    "Display    " + (if .display == null then na else
      (if .display.brightness then "brightness \(.display.brightness.percent)%" else "no backlight" end)
      + (if .display.night == null then "" elif .display.night.on then ", night light on (\(.display.night.temperature) K)"
         else ", night light off" end) end),
    "Theme      accent \(.theme.accent), reduce motion \(if .theme.reduce_motion then "on" else "off" end)",
    "Wallpaper  \(.wallpaper // "none")",
    "Battery    " + (if .battery == null then "none" else "\(.battery.percent)% \(.battery.status)" end),
    "Session    " + (if .session.hyprland then "Hyprland (Wayland)" elif .session.wayland then "Wayland"
      else "no graphical session" end)' <<<"$state" | say_stream
  printf '%s' "$state" | emit
}
