# shellcheck shell=bash
# mujo services: the background services someone switched on (Docker,
# Tailscale, sshd, ...) and whether each one is running. Read-only: starting
# and stopping a system service stays with systemctl.

mujo_register services "Background services you enabled, and their state"

help_services() {
  cat <<EOF
Usage: $MUJO_NAME services

Lists the system services that are enabled on this machine and what each is
doing: running, ready (a socket that starts it on first use), stopped or
failed. A service and its socket are one line (docker.socket and
docker.service are 'docker').

What every desktop has and the interface already shows (the network,
Bluetooth, the login screen, systemd's own units) is left out.
EOF
}

# Units that are part of the base desktop, not something to watch.
SERVICES_HIDDEN='^(systemd-|getty@|mujo-|NetworkManager|bluetooth$|greetd$|ly$|.*@$)'

# services_state: {services: [{name, state, description, units}]}, by name.
services_state() {
  command -v systemctl >/dev/null 2>&1 || return 1
  local -a units=()
  local unit base
  local -A seen=()
  while read -r unit _; do
    [[ $unit == *.service || $unit == *.socket ]] || continue
    base=${unit%.*}
    [[ $base =~ $SERVICES_HIDDEN ]] && continue
    [[ -n ${seen[$base]:-} ]] && continue
    seen[$base]=1
    units+=("$base.service" "$base.socket")
  done < <(systemctl list-unit-files --type=service,socket --state=enabled --no-legend --plain 2>/dev/null)
  if (( ${#units[@]} == 0 )); then
    jq -cn '{services: []}'
    return 0
  fi
  # One block of Key=Value lines per unit, with an empty line between them.
  systemctl show --property=Id,LoadState,ActiveState,Description -- "${units[@]}" 2>/dev/null \
    | jq -Rsc '
      [split("\n\n")[] | select(length > 0)
        | [split("\n")[] | select(test("=")) | capture("^(?<key>[^=]+)=(?<value>.*)$")] | from_entries
        | select(.Id != null and .LoadState != "not-found")]
      | group_by(.Id | sub("\\.(service|socket)$"; ""))
      | map(
          (map(select(.Id | endswith(".service"))) | first) as $service
          | (map(select(.Id | endswith(".socket"))) | first) as $socket
          | {
              name: (.[0].Id | sub("\\.(service|socket)$"; "")),
              state: (
                if any(.[]; .ActiveState == "failed") then "failed"
                elif $service != null and ($service.ActiveState == "active" or $service.ActiveState == "activating") then "running"
                elif $socket != null and $socket.ActiveState == "active" then "ready"
                else "stopped" end),
              description: (($service // $socket).Description),
              units: map(.Id)
            })
      | {services: sort_by(.name)}'
}

cmd_services() {
  (( $# == 0 )) || usage_error "unexpected argument '$1'"
  local state
  state=$(services_state) || die "$EXIT_ENV" "systemctl is not available here"
  jq -r '
    if (.services | length) == 0 then "No services are enabled beyond the base desktop"
    else (.services | map(.name | length) | max) as $w
      | .services[]
      | .name + (" " * ($w - (.name | length))) + "  "
        + (if .state == "ready" then "ready (starts on first use)" else .state end)
    end' <<<"$state" | say_stream
  printf '%s' "$state" | emit
}
