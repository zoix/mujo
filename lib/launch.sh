# shellcheck shell=bash
# karma launch: application launcher over the XDG desktop entries, with an
# fzf TUI. Apps launched more often sort first.

karma_register launch "Application launcher TUI"

LAUNCH_HISTORY=$KARMA_STATE_DIR/launch-history.tsv

help_launch() {
  cat <<EOF
Usage: $KARMA_NAME launch [pick] [--window]
       $KARMA_NAME launch list
       $KARMA_NAME launch run ID

pick  Choose an application with fzf (the default); the preview shows its
      description and command. Enter starts it.
list  Every application, most used first.
run   Start one by its desktop id (the file name without .desktop).
      Needs a Wayland session; --dry-run prints the command instead.

Entries come from the applications directories in XDG_DATA_HOME and
XDG_DATA_DIRS; hidden entries and those for other desktops are left out.
EOF
}

launch_dirs() {
  local d
  local -a dirs
  IFS=: read -r -a dirs <<<"${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
  printf '%s\n' "${XDG_DATA_HOME:-$HOME/.local/share}/applications"
  for d in "${dirs[@]}"; do
    [[ -n $d ]] && printf '%s\n' "${d%/}/applications"
  done
}

# launch_entries: one line per application, tab-separated:
#   id, name, comment, command, terminal (true|false), file, launch count, icon
# A user entry hides a system entry with the same id, as the spec requires.
launch_entries() {
  local hist=$LAUNCH_HISTORY dir
  [[ -f $hist ]] || hist=/dev/null
  while IFS= read -r dir; do
    [[ -d $dir ]] || continue
    find -L "$dir" -name '*.desktop' -type f -printf '%P\t%p\n' 2>/dev/null | LC_ALL=C sort
  done < <(launch_dirs) | gawk -F'\t' -v hist="$hist" -v desktop="${XDG_CURRENT_DESKTOP:-Hyprland}" '
    BEGIN {
      while ((getline line < hist) > 0) { split(line, h, "\t"); count[h[1]] = h[2] }
      ndesks = split(desktop, desks, ":")
    }
    function clean(s) { gsub(/[\t\r]/, " ", s); return s }
    function listed(list,    i, j, n, parts) {
      n = split(list, parts, ";")
      for (i = 1; i <= n; i++) for (j = 1; j <= ndesks; j++) if (parts[i] == desks[j]) return 1
      return 0
    }
    {
      id = $1; gsub(/\//, "-", id); sub(/\.desktop$/, "", id)
      if (id in seen) next
      seen[id] = 1
      file = $2; in_entry = 0
      delete v
      while ((getline line < file) > 0) {
        if (line ~ /^\[/) { in_entry = (line == "[Desktop Entry]"); continue }
        if (!in_entry) continue
        eq = index(line, "=")
        if (eq == 0) continue
        key = substr(line, 1, eq - 1); sub(/[ \t]+$/, "", key)
        val = substr(line, eq + 1); sub(/^[ \t]+/, "", val)
        if (!(key in v)) v[key] = val
      }
      close(file)
      if (v["Type"] != "Application" || v["NoDisplay"] == "true" || v["Hidden"] == "true") next
      if (v["Exec"] == "" || v["Name"] == "") next
      if (("OnlyShowIn" in v) && !listed(v["OnlyShowIn"])) next
      if (("NotShowIn" in v) && listed(v["NotShowIn"])) next
      cmd = v["Exec"]
      gsub(/%[fFuUdDnNickvm]/, "", cmd); gsub(/%%/, "%", cmd); gsub(/[ \t]+$/, "", cmd)
      printf "%s\t%s\t%s\t%s\t%s\t%s\t%d\t%s\n", id, clean(v["Name"]), clean(v["Comment"]), clean(cmd),
        (v["Terminal"] == "true" ? "true" : "false"), file, count[id] + 0, clean(v["Icon"])
    }' | LC_ALL=C sort -t$'\t' -k7,7nr -k2,2f
}

launch_row_json() {
  jq -cR 'split("\t") | {id: .[0], name: .[1], comment: .[2], exec: .[3],
    terminal: (.[4] == "true"), file: .[5], launches: (.[6] | tonumber), icon: (.[7] // "")}'
}

launch_count() {
  local id=$1
  mkdir -p -- "$KARMA_STATE_DIR"
  [[ -f $LAUNCH_HISTORY ]] || : >"$LAUNCH_HISTORY"
  gawk -F'\t' -v id="$id" 'BEGIN { OFS = "\t" }
    $1 == id { print $1, $2 + 1; found = 1; next } { print }
    END { if (!found) print id, 1 }' "$LAUNCH_HISTORY" | atomic_write "$LAUNCH_HISTORY"
}

# launch_start ROW-JSON: start the application detached from this terminal.
launch_start() {
  local entry=$1 cmd terminal id
  id=$(jq -r .id <<<"$entry")
  cmd=$(jq -r .exec <<<"$entry")
  terminal=$(jq -r .terminal <<<"$entry")
  if (( OPT_DRY_RUN )); then
    say "launch $id (dry run, nothing started)"
    say "Would run: $([[ $terminal == true ]] && echo "kitty -e ")$cmd"
    jq '{id, name, exec, terminal, started: false}' <<<"$entry" | emit
    return 0
  fi
  require_wayland
  need setsid
  launch_count "$id" || warn "could not update the launch history"
  cd -- "$HOME" || true
  if [[ $terminal == true ]]; then
    need kitty
    tui_detach kitty -e sh -c "$cmd"
  else
    tui_detach sh -c "$cmd"
  fi
  say "Started $(jq -r .name <<<"$entry")"
  jq '{id, name, exec, terminal, started: true}' <<<"$entry" | emit
}

cmd_launch() {
  local sub=${1:-pick}
  (( $# )) && shift
  karma_set_cmd "launch $sub"
  need gawk
  case $sub in
    list)
      (( $# == 0 )) || usage_error "unexpected argument '$1'"
      local apps
      apps=$(launch_entries | launch_row_json | jq -cs .)
      launch_entries | gawk -F'\t' '{ printf "%-32s %s\n", $1, $2 }' | say_stream
      jq -n --argjson a "$apps" '{apps: $a}' | emit
      ;;
    run)
      (( $# == 1 )) || usage_error "run needs exactly one desktop id (see '$KARMA_NAME launch list')"
      local row
      row=$(launch_entries | gawk -F'\t' -v id="$1" '$1 == id && !found { print; found = 1 }')
      [[ -n $row ]] || die "$EXIT_FAIL" "no application with the id '$1'"
      launch_start "$(launch_row_json <<<"$row")"
      ;;
    pick)
      (( $# == 0 )) || usage_error "unexpected argument '$1'"
      tui_require
      local row
      row=$(launch_entries | tui_pick --delimiter '\t' --with-nth 2 --prompt 'Launch > ' \
        --preview 'printf "%s\n\n%s\n\n$ %s\n\n%s\n" {2} {3} {4} {6}' \
        --preview-window 'right,45%,wrap') || return 0
      launch_start "$(launch_row_json <<<"$row")"
      ;;
    *) usage_error "unknown subcommand '$sub'" ;;
  esac
}
