# shellcheck shell=bash
# mujo voyager: write a firmware file from Oryx to a ZSA Voyager keyboard.

mujo_register voyager "Flash a ZSA Voyager keyboard with a firmware file"

help_voyager() {
  cat <<EOF
Usage: $MUJO_NAME voyager flash [FILE] [--wait SECONDS]

flash  Write FILE to the keyboard. Without FILE: the newest
       zsa_voyager_*.bin in the downloads folder (the name Oryx gives it).
       It then waits (60 seconds, or --wait) for the keyboard's reset button
       to be pressed; that puts the Voyager in its bootloader, where it is
       written and started again. With --dry-run it only says which file.

The file is checked first: it has to look like firmware built for the
Voyager. The bootloader itself is never written, so a layout that turns
out wrong is fixed by flashing another one. Not journaled.

Uses dfu-util. Writing without a password needs the rule that install.sh
puts in /etc/udev/rules.d (exit 3 without it).
EOF
}

VOYAGER_VENDOR=3297
VOYAGER_BOOT=0791      # product id while in the bootloader
VOYAGER_ADDRESS=$(( 0x8000000 + 0x2000 ))   # the firmware starts after the bootloader
VOYAGER_MAX=$(( 0x40000 - 0x2000 ))   # the chip's flash without the bootloader

# The sysfs folder of the first USB device with that product id.
voyager_device() {
  local dir
  for dir in "${MUJO_SYSROOT:-}"/sys/bus/usb/devices/*/; do
    [[ -r ${dir}idVendor && -r ${dir}idProduct ]] || continue
    if [[ $(<"${dir}idVendor") == "$VOYAGER_VENDOR" && $(<"${dir}idProduct") == "$1" ]]; then
      printf '%s\n' "${dir%/}"
      return 0
    fi
  done
  return 1
}

# Is the keyboard there, in normal use (any product id but the bootloader's)?
voyager_typing() {
  local dir
  for dir in "${MUJO_SYSROOT:-}"/sys/bus/usb/devices/*/; do
    [[ -r ${dir}idVendor && -r ${dir}idProduct ]] || continue
    [[ $(<"${dir}idVendor") == "$VOYAGER_VENDOR" && $(<"${dir}idProduct") != "$VOYAGER_BOOT" ]] && return 0
  done
  return 1
}

voyager_newest() {
  local dir=${XDG_DOWNLOAD_DIR:-} file
  [[ -n $dir ]] || dir=$(xdg-user-dir DOWNLOAD 2>/dev/null) || dir=""
  [[ -n $dir && $dir != "$HOME" ]] || dir=$HOME/Downloads
  # shellcheck disable=SC2012  # the names come from Oryx: no odd characters
  file=$(ls -t -- "$dir"/zsa_voyager_*.bin 2>/dev/null | head -n 1)
  [[ -n $file ]] || die "$EXIT_FAIL" "no zsa_voyager_*.bin in $dir; name the file to flash"
  printf '%s\n' "$file"
}

# Firmware for this chip starts with where its stack lies (in memory, 0x20...)
# and where it starts running (in the flash, after the bootloader).
voyager_check() {
  local file=$1 size head start
  [[ -f $file && -r $file ]] || die "$EXIT_FAIL" "cannot read $file"
  size=$(stat -c %s -- "$file")
  (( size >= 1024 && size <= VOYAGER_MAX )) \
    || die "$EXIT_FAIL" "$file is $size bytes; Voyager firmware is between 1024 and $VOYAGER_MAX"
  head=$(od -An -tx1 -N8 -- "$file" | tr -d ' \n')
  start=$(( 16#${head:14:2}${head:12:2}${head:10:2}${head:8:2} ))
  if [[ ${head:6:2} != 20 ]] || (( start < VOYAGER_ADDRESS || start >= VOYAGER_ADDRESS + VOYAGER_MAX )); then
    die "$EXIT_FAIL" "$file does not look like Voyager firmware"
  fi
}

voyager_cmd_flash() {
  local file="" wait=${MUJO_VOYAGER_WAIT:-60}
  while (( $# )); do
    case $1 in
      --wait)
        [[ ${2:-} =~ ^[0-9]+$ ]] || usage_error "--wait needs a number of seconds"
        wait=$2; shift 2 ;;
      -*) usage_error "unknown option '$1'" ;;
      *)
        [[ -z $file ]] || usage_error "unexpected argument '$1'"
        file=$1; shift ;;
    esac
  done
  need dfu-util
  [[ -n $file ]] || file=$(voyager_newest)
  voyager_check "$file"
  local size
  size=$(stat -c %s -- "$file")
  say "Firmware: $file ($size bytes, $(date -r "$file" +'%Y-%m-%d %H:%M'))"
  if (( OPT_DRY_RUN )); then
    say "Would be written to the Voyager."
    jq -n --arg f "$file" --argjson s "$size" '{file: $f, bytes: $s, flashed: false}' | emit
    return 0
  fi

  local device left=$wait
  if ! device=$(voyager_device "$VOYAGER_BOOT"); then
    say "Press the reset button on the Voyager (waiting $wait seconds) ..."
    until device=$(voyager_device "$VOYAGER_BOOT"); do
      (( left-- > 0 )) || die "$EXIT_FAIL" "no Voyager in its bootloader after $wait seconds; nothing was written"
      sleep 1
    done
    sleep 1   # udev sets who may write to it just after it shows up
  fi
  local node
  node=$(printf '%s/dev/bus/usb/%03d/%03d' "${MUJO_SYSROOT:-}" "$(<"$device/busnum")" "$(<"$device/devnum")")
  [[ -w $node ]] \
    || die "$EXIT_ENV" "not allowed to write to the keyboard; run ./install.sh once to install the rule for it, then press reset again"

  say "Writing ..."
  local out rc=0
  out=$(dfu-util -d "$VOYAGER_VENDOR:$VOYAGER_BOOT" -a 0 -s "$(printf '0x%08x' "$VOYAGER_ADDRESS"):leave" -D "$file" 2>&1) || rc=$?
  # The keyboard starts again at once, which dfu-util may report as an error
  # although every byte arrived.
  if (( rc != 0 )) && [[ $out != *"File downloaded successfully"* ]]; then
    tail -n 5 <<<"$out" >&2
    die "$EXIT_FAIL" "dfu-util could not write the firmware; press reset and flash again"
  fi

  local back=false
  for (( left = 15; left > 0; left-- )); do
    if voyager_typing; then back=true; break; fi
    sleep 1
  done
  if [[ $back == true ]]; then
    say "Done: the Voyager runs the new firmware."
  else
    warn "written, but the keyboard has not come back yet; unplug it and plug it in again"
  fi
  jq -n --arg f "$file" --argjson s "$size" --argjson b "$back" '{file: $f, bytes: $s, flashed: true, back: $b}' | emit
}

cmd_voyager() {
  local action=${1:-}
  (( $# )) && shift
  case $action in
    flash) mujo_set_cmd "voyager flash"; voyager_cmd_flash "$@" ;;
    "") usage_error "expected an action: flash" ;;
    *) usage_error "unknown action '$action' (expected flash)" ;;
  esac
}
