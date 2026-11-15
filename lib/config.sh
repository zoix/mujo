# shellcheck shell=bash
# User settings in ~/.config/mujo/config.json (a JSON object; missing file = {}).

config_read() {
  if [[ ! -f $MUJO_CONFIG_FILE ]]; then
    echo '{}'
    return
  fi
  jq -c 'if type == "object" then . else error("not an object") end' "$MUJO_CONFIG_FILE" 2>/dev/null \
    || die "$EXIT_FAIL" "$MUJO_CONFIG_FILE is not a valid JSON object"
}

# config_with KEY JSON-VALUE: print the config with KEY set, without writing it.
config_with() {
  config_read | jq --arg k "$1" --argjson v "$2" '.[$k] = $v'
}

# config_set KEY JSON-VALUE: write KEY to the config file.
config_set() {
  local new
  new=$(config_with "$1" "$2")
  printf '%s\n' "$new" | atomic_write "$MUJO_CONFIG_FILE"
  # The interface shows several of these settings; tell it to read them again.
  # (The installer uses this file without the rest of the CLI.)
  if declare -F ui_ipc >/dev/null; then ui_ipc notify reload; fi
}
