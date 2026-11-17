# shellcheck shell=bash
# mujo keyboard: the laptop's own keyboard is switched off while an external
# one is connected (for a keyboard that sits on top of the laptop's).

mujo_register keyboard "Built-in keyboard off while an external one is connected"

help_keyboard() {
  cat <<EOF
Usage: $MUJO_NAME keyboard
       $MUJO_NAME keyboard auto [on | off | toggle]
       $MUJO_NAME keyboard sync
       $MUJO_NAME keyboard watch

(none)  The keyboards that are connected, and whether the built-in one is off.
auto    While it is on, the built-in keyboard is switched off as long as a
        USB or Bluetooth keyboard is connected, and back on the moment the
        last one goes away. Journaled; can be undone.
sync    Check now (what auto does on every plug and unplug).
watch   Wait for keyboards to come and go and sync each time. Hyprland
        starts this with the session; there is no need to run it by hand.

Only Hyprland ignores the keyboard: the login screen and the console still
listen to it, and so does the power button. Anything that presents itself
as a USB keyboard counts as one, which includes the receivers of some
wireless mice (security keys from Yubico are left out). If such a device is
always plugged in, leave auto off.
EOF
}

KEYBOARD_STATE=$MUJO_STATE_DIR/keyboard.lua
KEYBOARD_BOOT_ID=${MUJO_BOOT_ID_FILE:-/proc/sys/kernel/random/boot_id}

# Every real keyboard the system knows, as [{name, bus, external}]. Virtual
# ones (key remappers) are neither built-in nor external and are left out.
keyboard_scan() {
  udevadm info --export-db 2>/dev/null | awk -v RS= -F'\n' '
    /E: ID_INPUT_KEYBOARD=1/ && /E: NAME=/ {
      name = ""; bus = ""; vendor = ""; path = ""
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^P: /) path = substr($i, 4)
        else if ($i ~ /^E: NAME=/) { name = substr($i, 9); gsub(/^"|"$/, "", name) }
        else if ($i ~ /^E: ID_BUS=/) bus = substr($i, 11)
        else if ($i ~ /^E: ID_VENDOR_ID=/) vendor = substr($i, 17)
      }
      if (path ~ /^\/devices\/virtual\// || vendor == "1050" || name == "") next
      printf "%s\t%s\n", bus, name
    }' | jq -Rcs '[split("\n")[] | select(. != "") | split("\t")
      | {name: .[1], bus: .[0], external: (.[0] == "usb" or .[0] == "bluetooth")}] | unique'
}

# The name Hyprland gives a device: lower case, dashes for spaces.
keyboard_hypr_name() {
  local name=${1,,}
  printf '%s\n' "${name// /-}"
}

keyboard_has_hyprland() {
  [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]] && command -v hyprctl >/dev/null 2>&1
}

# Is the built-in keyboard switched off right now (in this boot)?
keyboard_is_off() {
  [[ -f $KEYBOARD_STATE ]] || return 1
  local boot
  boot=$(cat "$KEYBOARD_BOOT_ID" 2>/dev/null) || boot=""
  grep -qF "boot = \"$boot\"" "$KEYBOARD_STATE"
}

keyboard_status_json() {
  local keyboards=$1 auto off=false
  auto=$(config_read | jq -r '.keyboard_auto == true')
  keyboard_is_off && off=true
  jq -cn --argjson k "$keyboards" --argjson a "$auto" --argjson o "$off" \
    '{auto: $a, off: $o,
      builtin: [$k[] | select(.external | not) | .name],
      external: [$k[] | select(.external) | .name]}'
}

keyboard_cmd_show() {
  (( $# == 0 )) || usage_error "unexpected argument '$1'"
  need udevadm
  local status
  status=$(keyboard_status_json "$(keyboard_scan)")
  say "Built-in keyboard: $(jq -r 'if (.builtin | length) == 0 then "none found" else (.builtin | join(", ")) + (if .off then " (off)" else "" end) end' <<<"$status")"
  say "External keyboards: $(jq -r 'if (.external | length) == 0 then "none" else .external | join(", ") end' <<<"$status")"
  say "Off while an external one is connected: $(jq -r 'if .auto then "on" else "off" end' <<<"$status")"
  emit <<<"$status"
}

# Not journaled: it only carries out the "auto" setting, which is.
keyboard_cmd_sync() {
  (( $# == 0 )) || usage_error "unexpected argument '$1'"
  need udevadm
  local keyboards auto names="" want="" now="" changed=false name boot
  keyboards=$(keyboard_scan)
  auto=$(config_read | jq -r '.keyboard_auto == true')
  if [[ $auto == true && $(jq -r 'any(.[]; .external)' <<<"$keyboards") == true ]]; then
    while IFS= read -r name; do
      [[ -n $name ]] || continue
      names+="${names:+, }$(jq -Rc . <<<"$(keyboard_hypr_name "$name")")"
    done < <(jq -r '.[] | select(.external | not) | .name' <<<"$keyboards")
  fi
  if [[ -n $names ]]; then
    boot=$(cat "$KEYBOARD_BOOT_ID" 2>/dev/null) || boot=""
    want="return { boot = \"$boot\", off = { $names } }"
  fi
  [[ -f $KEYBOARD_STATE ]] && now=$(cat "$KEYBOARD_STATE")
  if [[ $want != "$now" ]] && (( ! OPT_DRY_RUN )); then
    changed=true
    if [[ -z $want ]]; then
      rm -f -- "$KEYBOARD_STATE"
    else
      printf '%s\n' "$want" | atomic_write "$KEYBOARD_STATE"
    fi
    if keyboard_has_hyprland; then hyprctl reload >/dev/null 2>&1 || true; fi
    if [[ -n $want ]]; then
      say "Built-in keyboard: off ($(jq -r '[.[] | select(.external) | .name][0]' <<<"$keyboards") is connected)"
      ui_notify "Keyboard" "Built-in keyboard off while $(jq -r '[.[] | select(.external) | .name][0]' <<<"$keyboards") is connected"
    else
      say "Built-in keyboard: on"
      ui_notify "Keyboard" "Built-in keyboard on again"
    fi
  elif (( ! OPT_DRY_RUN )) || [[ $want == "$now" ]]; then
    say "Built-in keyboard: $([[ -n $now ]] && echo off || echo on) (nothing to change)"
  else
    say "Built-in keyboard: would be switched $([[ -n $want ]] && echo off || echo on)"
  fi
  keyboard_status_json "$keyboards" | jq -c --argjson c "$changed" '. + {changed: $c}' | emit
}

# Sync now, then after every keyboard that comes or goes. A device shows up
# as several events, so the sync waits until a second has passed without one.
keyboard_cmd_watch() {
  (( $# == 0 )) || usage_error "unexpected argument '$1'"
  need udevadm
  "$MUJO_BIN" keyboard sync >/dev/null 2>&1 3>&1 || true
  local line
  udevadm monitor --udev --subsystem-match=input 2>/dev/null | while IFS= read -r line; do
    [[ $line == *" add "* || $line == *" remove "* ]] || continue
    while IFS= read -r -t 1 line; do :; done
    "$MUJO_BIN" keyboard sync >/dev/null 2>&1 3>&1 || true
  done
}

keyboard_cmd_auto() {
  (( $# <= 1 )) || usage_error "too many arguments"
  local cur new
  cur=$(config_read | jq -r '.keyboard_auto == true')
  if (( $# == 0 )); then
    say "Built-in keyboard off while an external one is connected: $([[ $cur == true ]] && echo on || echo off)"
    jq -n --argjson a "$cur" '{auto: $a}' | emit
    return 0
  fi
  new=$(on_off "$1" "$cur") || usage_error "expected on, off or toggle, got '$1'"
  local wc wn before after
  wc=$([[ $cur == true ]] && echo on || echo off)
  wn=$([[ $new == true ]] && echo on || echo off)
  before=$(jq -cn --argjson a "$cur" '{auto: $a}')
  after=$(jq -cn --argjson a "$new" '{auto: $a}')
  change_begin "keyboard auto: $wc -> $wn" "$before" "$after" || return 0
  mujo_lock
  config_set keyboard_auto "$new"
  change_end "keyboard auto: $wc -> $wn" "$before" "$after" "$(json_array keyboard auto "$wc")"
  # Off as well: the built-in keyboard has to come back.
  flock -u 9 2>/dev/null || true
  "$MUJO_BIN" keyboard sync >/dev/null 2>&1 3>&1 || true
}

cmd_keyboard() {
  local action=${1:-show}
  (( $# )) && shift
  case $action in
    show) keyboard_cmd_show "$@" ;;
    auto) mujo_set_cmd "keyboard auto"; keyboard_cmd_auto "$@" ;;
    sync) mujo_set_cmd "keyboard sync"; keyboard_cmd_sync "$@" ;;
    watch) mujo_set_cmd "keyboard watch"; keyboard_cmd_watch "$@" ;;
    *) usage_error "unknown action '$action' (expected auto, sync or watch)" ;;
  esac
}
