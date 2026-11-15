# shellcheck shell=bash
# mujo theme: render design/tokens.json into every consumer listed in
# design/consumers.json, check for drift and hardcoded values, and change the
# accent or reduce_motion setting. See docs/tokens.md.

mujo_register theme "Design tokens: build, check, accent, reduce-motion"

THEME_DESIGN=$MUJO_ROOT/design
THEME_TOKENS=$THEME_DESIGN/tokens.json
THEME_CONSUMERS=$THEME_DESIGN/consumers.json
THEME_ALLOW=$THEME_DESIGN/check-allow.txt
THEME_STATE=$MUJO_STATE_DIR/theme
THEME_SNAPSHOTS=$MUJO_STATE_DIR/snapshots
# Palette names that are also ordinary words; the lint ignores them.
THEME_GENERIC_NAMES=(text base red green yellow blue pink)
# Repo directories scanned by a full `theme check`.
THEME_LINT_ROOTS=(bin lib tui config system design/templates)

declare -A C_TEMPLATE=() C_TARGET=() C_SCOPE=() C_COMMENT=() C_COMMENT_END=() C_RELOAD=() C_LINT=()
C_IDS=()
declare -A PLAN_STATUS=() PLAN_DEST=()
PLAN_IDS=()
PLAN_DIR=""

help_theme() {
  cat <<EOF
Usage: $MUJO_NAME theme <subcommand> [arguments]

Subcommands:
  build [ID...]          Render tokens into every consumer (or only the given ones)
  check [ID...]          Fail on drift from the tokens or on hardcoded values
  accent [NAME|auto]     Show the accent, or set it and rebuild (journaled).
                         auto picks the accent closest to the wallpaper's colour
  palette [catppuccin|wallpaper]
                         Show the palette, or set it and rebuild (journaled).
                         wallpaper tints backgrounds, borders and text with the
                         wallpaper's main colour, in light and in dark mode
  mode [dark|light|auto] Show the mode, or set it and rebuild (journaled).
                         auto follows the wallpaper: light for a bright image
  motion [normal|gentle] Show the setting, or set it and rebuild (journaled).
                         gentle is slower, and fades instead of sliding
  glass [on|off]         Show the setting, or set it and rebuild (journaled).
                         on makes the frame and its panels see-through, with
                         the desktop blurred behind them
  reduce-motion [on|off] Show the setting, or set it and rebuild (journaled).
                         on switches every animation off
  list                   List consumers, their targets and whether they are current
  show [PATH]            Print the resolved tokens (optionally one subtree, e.g. color.bg)
  render FILE            Render a template file to stdout (for template authors)
  restore SNAPSHOT       Put back the files saved by a journaled build (used by undo)

Mutating subcommands accept --dry-run (print the diff, change nothing) and --json.
System consumers (scope "system") are rendered into
$THEME_STATE/system/ and installed by the installer.
EOF
}

cmd_theme() {
  local sub=${1:-}
  [[ -n $sub ]] || usage_error "missing subcommand"
  shift
  # shellcheck disable=SC2034  # read by emit/usage_error in core.sh
  MUJO_CMD="theme $sub"
  case $sub in
    build) theme_cmd_build "$@" ;;
    check) theme_cmd_check "$@" ;;
    accent) theme_cmd_accent "$@" ;;
    mode) theme_cmd_mode "$@" ;;
    palette) theme_cmd_palette "$@" ;;
    sync) theme_cmd_sync "$@" ;;
    motion) theme_cmd_motion "$@" ;;
    glass) theme_cmd_glass "$@" ;;
    reduce-motion) theme_cmd_reduce_motion "$@" ;;
    list) theme_cmd_list "$@" ;;
    show) theme_cmd_show "$@" ;;
    render) theme_cmd_render "$@" ;;
    restore) theme_cmd_restore "$@" ;;
    *) usage_error "unknown subcommand '$sub'" ;;
  esac
}

# ---- helpers -----------------------------------------------------------------

# theme_jq OUT ARGS...: run jq with the theme module; OUT is a file or "-".
# jq errors become a clean mujo error (exit 1).
theme_jq() {
  local out=$1 err rc=0 msg
  shift
  err=$(mktemp)
  if [[ $out == - ]]; then
    jq -L "$MUJO_ROOT/lib" "$@" 2>"$err" || rc=$?
  else
    jq -L "$MUJO_ROOT/lib" "$@" >"$out" 2>"$err" || rc=$?
  fi
  if (( rc )); then
    msg=$(sed -E 's/^jq: error \(at [^)]*\): //; s/^jq: error: //' "$err" | head -n 3)
    rm -f -- "$err"
    die "$EXIT_FAIL" "theme: ${msg:-jq failed}"
  fi
  rm -f -- "$err"
}

tilde() {
  printf '%s\n' "${1/#$HOME/\~}"
}

theme_load_consumers() {
  (( ${#C_IDS[@]} )) && return 0
  [[ -f $THEME_CONSUMERS ]] || die "$EXIT_FAIL" "missing $THEME_CONSUMERS"
  local rows id tpl target scope c ce reload lint
  rows=$(theme_jq - -r '
    if .schema_version != 1 then error("consumers.json: unsupported schema_version") else . end
    | .consumers[]
    | [.id, .template, .target, .scope, (.comment // ""), (.comment_end // ""),
       (.reload // ""), ((.lint // []) | join(" "))]
    | join("\u001f")' "$THEME_CONSUMERS")
  while IFS=$'\x1f' read -r id tpl target scope c ce reload lint; do
    [[ $id =~ ^[a-z0-9_-]+$ ]] || die "$EXIT_FAIL" "consumers.json: bad id '$id'"
    case $scope in
      user) [[ $target == @config/* || $target == @state/* ]] \
              || die "$EXIT_FAIL" "consumers.json: user target of '$id' must start with @config/ or @state/" ;;
      system) [[ $target == /etc/* ]] \
              || die "$EXIT_FAIL" "consumers.json: system target of '$id' must be under /etc" ;;
      *) die "$EXIT_FAIL" "consumers.json: '$id' has unknown scope '$scope'" ;;
    esac
    C_IDS+=("$id")
    C_TEMPLATE[$id]=$tpl
    C_TARGET[$id]=$target
    C_SCOPE[$id]=$scope
    C_COMMENT[$id]=$c
    C_COMMENT_END[$id]=$ce
    C_RELOAD[$id]=$reload
    C_LINT[$id]=$lint
  done <<<"$rows"
}

# Where `build` writes a consumer: the real path for user scope, a staging
# path for system scope.
theme_dest() {
  local id=$1 t=${C_TARGET[$1]}
  if [[ ${C_SCOPE[$id]} == system ]]; then
    printf '%s/system/%s/%s\n' "$THEME_STATE" "$id" "${t##*/}"
  else
    t=${t/#@config/$MUJO_CONFIG_HOME}
    t=${t/#@state/$MUJO_STATE_HOME}
    printf '%s\n' "$t"
  fi
}

# Where a system consumer is finally installed (MUJO_SYSROOT is for tests).
theme_installed_path() {
  printf '%s%s\n' "${MUJO_SYSROOT:-}" "${C_TARGET[$1]}"
}

# theme_settings [OVERRIDE-JSON]: the effective settings as JSON.
theme_settings() {
  local cfg
  cfg=$(config_read)
  theme_jq - -c -n --slurpfile tok "$THEME_TOKENS" --argjson cfg "$cfg" --argjson over "${1:-"{}"}" \
    'include "theme"; settings($tok[0]; $cfg; $over)'
}

theme_check_ids() {
  local id
  for id in "$@"; do
    [[ -n ${C_SCOPE[$id]+x} ]] || usage_error "unknown consumer '$id' (known: ${C_IDS[*]})"
  done
}

# theme_plan SETTINGS [ID...]: render into a temp dir and classify each target
# as new, changed or unchanged. Writes nothing outside the temp dir.
theme_plan() {
  local settings=$1 id tpl dest
  shift
  theme_load_consumers
  local -a ids=("$@")
  (( ${#ids[@]} )) || ids=("${C_IDS[@]}")
  theme_check_ids "${ids[@]}"
  mujo_tmpdir PLAN_DIR
  theme_jq "$PLAN_DIR/tokens.resolved.json" -n --slurpfile tok "$THEME_TOKENS" --argjson s "$settings" \
    'include "theme"; $tok[0] | resolve($s)'
  PLAN_IDS=()
  PLAN_STATUS=()
  PLAN_DEST=()
  for id in "${ids[@]}"; do
    tpl=$THEME_DESIGN/templates/${C_TEMPLATE[$id]}
    [[ -f $tpl ]] || die "$EXIT_FAIL" "theme: template for '$id' not found: ${C_TEMPLATE[$id]}"
    theme_jq "$PLAN_DIR/$id" -rj -n --rawfile tpl "$tpl" --slurpfile t "$PLAN_DIR/tokens.resolved.json" \
      --arg name "${C_TEMPLATE[$id]}" --arg c "${C_COMMENT[$id]}" --arg ce "${C_COMMENT_END[$id]}" \
      --arg id "$id" --arg prog "$MUJO_NAME" \
      'include "theme"; header($c; $ce; $id; $prog) + render($tpl; $t[0]; $name)'
    dest=$(theme_dest "$id")
    PLAN_IDS+=("$id")
    PLAN_DEST[$id]=$dest
    if [[ ! -e $dest ]]; then
      PLAN_STATUS[$id]=new
    elif cmp -s -- "$dest" "$PLAN_DIR/$id"; then
      PLAN_STATUS[$id]=unchanged
    else
      PLAN_STATUS[$id]=changed
    fi
  done
}

theme_changed_count() {
  local id n=0
  for id in "${PLAN_IDS[@]}"; do
    [[ ${PLAN_STATUS[$id]} == unchanged ]] || n=$((n + 1))
  done
  echo "$n"
}

# Unified diff between the current target and the planned content.
theme_diff() {
  local id=$1 dest=${PLAN_DEST[$1]} old new
  old=$dest
  new=$PLAN_DIR/$id
  [[ -e $old ]] || old=/dev/null
  [[ ${PLAN_STATUS[$id]} == remove ]] && new=/dev/null
  diff -u --label "$(tilde "$dest")" --label "$(tilde "$dest") (planned)" -- "$old" "$new" || true
}

# The plan as JSON: [{id, scope, path, status, diff?}]
theme_plan_json() {
  local with_diff=${1:-0} id
  for id in "${PLAN_IDS[@]}"; do
    local d=""
    if (( with_diff )) && [[ ${PLAN_STATUS[$id]} != unchanged ]]; then d=$(theme_diff "$id"); fi
    jq -cn --arg id "$id" --arg scope "${C_SCOPE[$id]:-user}" --arg path "${PLAN_DEST[$id]}" \
      --arg status "${PLAN_STATUS[$id]}" --arg diff "$d" --argjson wd "$with_diff" \
      '{id: $id, scope: $scope, path: $path, status: $status}
       + (if $wd == 1 and $diff != "" then {diff: $diff} else {} end)'
  done | jq -cs .
}

theme_print_plan() {
  local id note
  for id in "${PLAN_IDS[@]}"; do
    note=""
    [[ ${C_SCOPE[$id]:-user} == system ]] && note="  (staged; installs to ${C_TARGET[$id]})"
    printf '  %-10s %-14s %s%s\n' "${PLAN_STATUS[$id]}" "$id" "$(tilde "${PLAN_DEST[$id]}")" "$note"
  done | say_stream
}

theme_print_diffs() {
  local id
  for id in "${PLAN_IDS[@]}"; do
    [[ ${PLAN_STATUS[$id]} == unchanged ]] || theme_diff "$id"
  done | say_stream
}

# theme_apply_plan JOURNAL-ID: snapshot what will be replaced, then write.
theme_apply_plan() {
  local jid=$1 snap=$THEME_SNAPSHOTS/$1 id dest
  local -a index=()
  for id in "${PLAN_IDS[@]}"; do
    [[ ${PLAN_STATUS[$id]} == unchanged ]] && continue
    dest=${PLAN_DEST[$id]}
    mkdir -p -- "$snap"
    if [[ -f $dest ]]; then
      cp -p -- "$dest" "$snap/$id"
      index+=("$id" "$dest" true)
    else
      index+=("$id" "$dest" false)
    fi
    if [[ ${PLAN_STATUS[$id]} == remove ]]; then
      rm -f -- "$dest"
    else
      atomic_write "$dest" <"$PLAN_DIR/$id"
    fi
  done
  if (( ${#index[@]} )); then
    jq -n '$ARGS.positional | [range(0; length; 3) as $i
      | {id: .[$i], path: .[$i + 1], existed: (.[$i + 2] == "true")}]' --args "${index[@]}" \
      | atomic_write "$snap/index.json"
  fi
  if [[ -f $PLAN_DIR/tokens.resolved.json ]]; then
    atomic_write "$THEME_STATE/tokens.resolved.json" <"$PLAN_DIR/tokens.resolved.json"
  fi
  theme_update_manifest
}

# Record the sha256 of every file the plan touched in manifest.json.
theme_update_manifest() {
  local manifest=$THEME_STATE/manifest.json id sum cur
  local -a rows=()
  for id in "${PLAN_IDS[@]}"; do
    if [[ -f ${PLAN_DEST[$id]} ]]; then
      sum=$(sha256sum -- "${PLAN_DEST[$id]}" | cut -d' ' -f1)
      rows+=("$id" "${PLAN_DEST[$id]}" "${C_SCOPE[$id]:-user}" "$sum")
    else
      rows+=("$id" "" "" "")
    fi
  done
  cur='{}'
  [[ -f $manifest ]] && cur=$(jq -c 'if type == "object" then . else {} end' "$manifest" 2>/dev/null || echo '{}')
  jq -n --argjson cur "$cur" --argjson v "$MUJO_SCHEMA_VERSION" --arg now "$(date -u +%FT%TZ)" '
    $ARGS.positional as $r
    | reduce range(0; $r | length; 4) as $i ($cur.files // {};
        if $r[$i + 1] == "" then del(.[$r[$i]])
        else .[$r[$i]] = {path: $r[$i + 1], scope: $r[$i + 2], sha256: $r[$i + 3]} end)
    | {schema_version: $v, updated_at: $now, files: .}' --args "${rows[@]}" \
    | atomic_write "$manifest"
}

theme_run_reloads() {
  local id
  local -A done_hooks=()
  for id in "${PLAN_IDS[@]}"; do
    [[ ${PLAN_STATUS[$id]} == unchanged ]] && continue
    local hook=${C_RELOAD[$id]:-}
    [[ -n $hook && -z ${done_hooks[$hook]+x} ]] || continue
    done_hooks[$hook]=1
    [[ $hook == gtk ]] && theme_gtk_sync
    ui_reload "$hook"
  done
}

theme_settings_label() {
  jq -r '"accent \(.accent), mode \(.mode), motion \(.motion), reduce_motion \(if .reduce_motion then "on" else "off" end)"' <<<"$1"
}

# Tell running GTK and libadwaita apps (through GSettings) which scheme the
# new tokens use. Only inside the graphical session; never fatal.
theme_gtk_sync() {
  ui_session || return 0
  command -v gsettings >/dev/null 2>&1 || return 0
  local scheme theme
  scheme=$(jq -r '.gtk.color_scheme' "$PLAN_DIR/tokens.resolved.json")
  theme=$(jq -r '.gtk.theme' "$PLAN_DIR/tokens.resolved.json")
  gsettings set org.gnome.desktop.interface color-scheme "$scheme" >/dev/null 2>&1 || true
  gsettings set org.gnome.desktop.interface gtk-theme "$theme" >/dev/null 2>&1 || true
}

# Shared tail of every mutating subcommand. Uses the current plan.
# theme_commit SUMMARY BEFORE AFTER UNDO-MODE SETTINGS [CONFIG-KEY CONFIG-VALUE]
#   UNDO-MODE: "restore" (undo = theme restore <id>) or a JSON argv array.
theme_commit() {
  local summary=$1 before=$2 after=$3 undo_mode=$4 settings=$5 ckey=${6:-} cval=${7:-}
  local changed jid="" undo
  changed=$(theme_changed_count)

  if (( OPT_DRY_RUN )); then
    say "$summary (dry run, nothing written)"
    say "Tokens: $(theme_settings_label "$settings")"
    if [[ -n $ckey ]]; then
      diff -u --label "$(tilde "$MUJO_CONFIG_FILE")" --label "$(tilde "$MUJO_CONFIG_FILE") (planned)" \
        <(config_read | jq .) <(config_with "$ckey" "$cval") | say_stream || true
    fi
    theme_print_plan
    theme_print_diffs
    theme_plan_json 1 | jq --argjson s "$settings" '{journal_id: null, settings: $s, files: .}' | emit
    return 0
  fi

  jid=$(journal_new_id)
  theme_apply_plan "$jid"
  [[ -n $ckey ]] && config_set "$ckey" "$cval"
  if [[ $undo_mode == restore ]]; then
    if (( changed > 0 )); then undo=$(json_array theme restore "$jid"); else undo=null; fi
  else
    undo=$undo_mode
  fi
  journal_record "$jid" "$summary" "$before" "$after" "$undo"
  theme_run_reloads

  say "$summary"
  say "Tokens: $(theme_settings_label "$settings")"
  theme_print_plan
  say "$changed file(s) written. Journal: $jid$([[ $undo != null ]] && echo " (undo: $MUJO_NAME undo $jid)")"
  theme_plan_json 0 | jq --arg j "$jid" --argjson s "$settings" '{journal_id: $j, settings: $s, files: .}' | emit
}

theme_current_hash() {
  if [[ -f $THEME_STATE/tokens.resolved.json ]]; then
    sha256sum -- "$THEME_STATE/tokens.resolved.json" | cut -c1-16
  else
    echo none
  fi
}

theme_ids_from_args() {
  local a
  THEME_ARG_IDS=()
  for a in "$@"; do
    [[ $a == -* ]] && usage_error "unknown option '$a'"
    THEME_ARG_IDS+=("$a")
  done
}

# ---- subcommands -------------------------------------------------------------

theme_cmd_build() {
  theme_ids_from_args "$@"
  (( OPT_DRY_RUN )) || mujo_lock
  local settings before after
  settings=$(theme_settings)
  before=$(jq -cn --arg h "$(theme_current_hash)" '{tokens_hash: $h}')
  theme_plan "$settings" "${THEME_ARG_IDS[@]}"
  after=$(jq -cn --arg h "$(sha256sum -- "$PLAN_DIR/tokens.resolved.json" | cut -c1-16)" \
    --argjson n "$(theme_changed_count)" '{tokens_hash: $h, files_changed: $n}')
  theme_commit "theme build: $(theme_changed_count) of ${#PLAN_IDS[@]} file(s) changed" \
    "$before" "$after" restore "$settings"
}

# Shared by accent and reduce-motion: KEY NEW-JSON CURRENT-JSON SUMMARY UNDO-ARGV-JSON
theme_set() {
  local key=$1 new=$2 cur=$3 summary=$4 undo=$5 settings
  settings=$(theme_settings "$(jq -cn --arg k "$key" --argjson v "$new" '{($k): $v}')")
  theme_plan "$settings"
  theme_commit "$summary" "$(jq -cn --arg k "$key" --argjson v "$cur" '{($k): $v}')" \
    "$(jq -cn --arg k "$key" --argjson v "$new" '{($k): $v}')" "$undo" "$settings" "$key" "$new"
}

# The palette: catppuccin, or wallpaper (backgrounds and text tinted with
# the wallpaper's hue).
theme_palette_pref() {
  config_read | jq -r '.palette // "catppuccin"'
}

theme_cmd_palette() {
  (( $# <= 1 )) || usage_error "too many arguments"
  local cur
  cur=$(theme_palette_pref)
  if (( $# == 0 )); then
    say "Palette: $cur"
    say "Available: catppuccin wallpaper"
    jq -n --arg p "$cur" --argjson h "$(config_read | jq '.hue // null')" \
      '{palette: $p, hue: $h, available: ["catppuccin", "wallpaper"]}' | emit
    return 0
  fi
  local new=$1
  [[ $new == catppuccin || $new == wallpaper ]] || usage_error "expected catppuccin or wallpaper, got '$new'"
  (( OPT_DRY_RUN )) || mujo_lock
  if [[ $new == "$cur" ]]; then
    say "The palette is already $new; nothing to do."
    jq -n --arg p "$cur" '{journal_id: null, settings: {palette: $p}, files: []}' | emit
    return 0
  fi
  local hue=null accent settings before after
  if [[ $new == wallpaper ]]; then
    hue=$(wall_hue "$(wall_current)") || hue=null
    [[ $hue != null ]] || warn "the wallpaper has no dominant colour (or there is none); the Catppuccin colours stay until one does"
  fi
  # The accent follows, if it is on auto.
  accent=$(theme_settings | jq -r .accent)
  if [[ $(theme_accent_pref) == auto ]]; then
    if [[ $new == wallpaper && $hue != null ]]; then
      accent=wallpaper
    else
      accent=$(wall_accent "$(wall_current)") || accent=$(jq -r .defaults.accent "$THEME_TOKENS")
    fi
  fi
  before=$(jq -cn --arg p "$cur" '{palette: $p}')
  after=$(jq -cn --arg p "$new" --argjson h "$hue" --arg a "$accent" '{palette: $p, hue: $h, accent: $a}')
  settings=$(theme_settings "$after")
  theme_plan "$settings"
  if (( ! OPT_DRY_RUN )); then
    config_set hue "$hue"
    config_set accent "\"$accent\""
  fi
  theme_commit "theme palette: $cur -> $new" "$before" "$after" "$(json_array theme palette "$cur")" "$settings" palette "\"$new\""
}

# The accent preference: a name, or auto (follow the wallpaper).
theme_accent_pref() {
  config_read | jq -r '.accent_pref // "auto"'
}

# theme_accent_wanted PREF: the accent that preference means right now.
# auto picks the accent closest to the wallpaper's dominant colour, and the
# default accent when there is no wallpaper or it has no colour to speak of.
theme_accent_wanted() {
  if [[ $1 == auto ]]; then
    # With the wallpaper palette the accent is a colour of the wallpaper's own hue.
    if [[ $(theme_palette_pref) == wallpaper ]] && wall_hue "$(wall_current)" >/dev/null; then
      echo wallpaper
      return 0
    fi
    wall_accent "$(wall_current)" || jq -r .defaults.accent "$THEME_TOKENS"
  else
    echo "$1"
  fi
}

theme_cmd_accent() {
  (( $# <= 1 )) || usage_error "too many arguments"
  local accents cur pref
  accents=$(jq -r '.accents | join(" ")' "$THEME_TOKENS")
  pref=$(theme_accent_pref)
  if (( $# == 0 )); then
    cur=$(theme_settings | jq -r .accent)
    say "Accent: $cur (preference: $pref)"
    say "Available: $accents auto"
    jq -n --arg a "$cur" --arg p "$pref" --arg l "$accents" \
      '{accent: $a, preference: $p, available: ($l | split(" "))}' | emit
    return 0
  fi
  local want=$1 new
  [[ $want == auto || " $accents " == *" $want "* ]] \
    || usage_error "unknown accent '$want'; choose one of: $accents auto"
  new=$(theme_accent_wanted "$want")
  (( OPT_DRY_RUN )) || mujo_lock
  cur=$(theme_settings | jq -r .accent)
  if [[ $new == "$cur" ]]; then
    if [[ $want == "$pref" ]]; then
      say "Accent is already $new; nothing to do."
      jq -n --arg a "$cur" '{journal_id: null, settings: {accent: $a}, files: []}' | emit
      return 0
    fi
    local before after
    before=$(jq -cn --arg p "$pref" '{accent_pref: $p}')
    after=$(jq -cn --arg p "$want" '{accent_pref: $p}')
    change_begin "theme accent preference: $pref -> $want" "$before" "$after" || return 0
    config_set accent_pref "\"$want\""
    change_end "theme accent preference: $pref -> $want" "$before" "$after" "$(json_array theme accent "$pref")"
    return 0
  fi
  (( OPT_DRY_RUN )) || config_set accent_pref "\"$want\""
  theme_set accent "\"$new\"" "\"$cur\"" \
    "theme accent: $cur -> $new$([[ $want == auto ]] && echo " (auto)" || true)" "$(json_array theme accent "$pref")"
}

# Internal: called after the wallpaper changed. Brings the mode and the
# accent in line with it, for whichever of the two is set to auto, in one
# build. Not reversible on its own, so that `undo` reverts the wallpaper,
# which runs this again.
theme_cmd_sync() {
  (( $# == 0 )) || usage_error "unexpected argument '$1'"
  # Lock first: when wallpapers change in quick succession, each sync must
  # see the wallpaper that is current when its turn comes, not an older one.
  (( OPT_DRY_RUN )) || mujo_lock
  local cur_mode cur_accent new_mode new_accent cur_hue new_hue
  cur_mode=$(theme_settings | jq -r .mode)
  cur_accent=$(theme_settings | jq -r .accent)
  cur_hue=$(theme_settings | jq -r '.hue // "null"')
  new_mode=$(theme_mode_wanted "$(theme_mode_pref)")
  new_accent=$(theme_accent_wanted "$(theme_accent_pref)")
  new_hue=$cur_hue
  if [[ $(theme_palette_pref) == wallpaper ]]; then
    new_hue=$(wall_hue "$(wall_current)") || new_hue=null
  fi
  if [[ $new_mode == "$cur_mode" && $new_accent == "$cur_accent" && $new_hue == "$cur_hue" ]]; then
    say "Mode and accent already match the wallpaper; nothing to do."
    jq -n '{journal_id: null, settings: {}, files: []}' | emit
    return 0
  fi
  local settings before after summary="theme: "
  [[ $new_mode != "$cur_mode" ]] && summary+="mode $cur_mode -> $new_mode, "
  [[ $new_accent != "$cur_accent" ]] && summary+="accent $cur_accent -> $new_accent, "
  [[ $new_hue != "$cur_hue" ]] && summary+="palette hue $cur_hue -> $new_hue, "
  summary="${summary%, } (from the wallpaper)"
  before=$(jq -cn --arg m "$cur_mode" --arg a "$cur_accent" --argjson h "$cur_hue" '{mode: $m, accent: $a, hue: $h}')
  after=$(jq -cn --arg m "$new_mode" --arg a "$new_accent" --argjson h "$new_hue" '{mode: $m, accent: $a, hue: $h}')
  settings=$(theme_settings "$after")
  theme_plan "$settings"
  if (( ! OPT_DRY_RUN )); then
    config_set accent "\"$new_accent\""
    config_set hue "$new_hue"
  fi
  theme_commit "$summary" "$before" "$after" null "$settings" mode "\"$new_mode\""
}

# The mode preference: dark, light, or auto (follow the wallpaper).
theme_mode_pref() {
  config_read | jq -r '.mode_pref // "auto"'
}

# theme_mode_wanted PREF: the mode that preference means right now.
theme_mode_wanted() {
  if [[ $1 == auto ]]; then
    wall_mode "$(wall_current)" || theme_settings | jq -r .mode
  else
    echo "$1"
  fi
}

theme_cmd_mode() {
  (( $# <= 1 )) || usage_error "too many arguments"
  local cur pref
  cur=$(theme_settings | jq -r .mode)
  pref=$(theme_mode_pref)
  if (( $# == 0 )); then
    say "Mode: $cur (preference: $pref)"
    say "Available: dark light auto"
    jq -n --arg m "$cur" --arg p "$pref" '{mode: $m, preference: $p, available: ["dark", "light", "auto"]}' | emit
    return 0
  fi
  local want=$1 new summary undo
  case $want in
    dark|light|auto) ;;
    *) usage_error "expected dark, light or auto, got '$want'" ;;
  esac
  new=$(theme_mode_wanted "$want")
  (( OPT_DRY_RUN )) || mujo_lock
  if [[ $new == "$cur" ]]; then
    if [[ $want == "$pref" ]]; then
      say "Mode is already $cur (preference: $pref); nothing to do."
      jq -n --arg m "$cur" '{journal_id: null, settings: {mode: $m}, files: []}' | emit
      return 0
    fi
    # Only the preference changes; the colours stay.
    local before after
    before=$(jq -cn --arg p "$pref" '{mode_pref: $p}')
    after=$(jq -cn --arg p "$want" '{mode_pref: $p}')
    change_begin "theme mode preference: $pref -> $want" "$before" "$after" || return 0
    config_set mode_pref "\"$want\""
    change_end "theme mode preference: $pref -> $want" "$before" "$after" "$(json_array theme mode "$pref")"
    return 0
  fi
  summary="theme mode: $cur -> $new$([[ $want == auto ]] && echo " (auto)" || true)"
  undo=$(json_array theme mode "$pref")
  (( OPT_DRY_RUN )) || config_set mode_pref "\"$want\""
  theme_set mode "\"$new\"" "\"$cur\"" "$summary" "$undo"
}

theme_cmd_glass() {
  (( $# <= 1 )) || usage_error "too many arguments"
  local cur new word
  cur=$(theme_settings | jq -r .glass)
  if (( $# == 0 )); then
    say "Glass: $([[ $cur == true ]] && echo on || echo off)"
    jq -n --argjson g "$cur" '{glass: $g}' | emit
    return 0
  fi
  new=$(on_off "$1" "$cur") || usage_error "expected on, off or toggle, got '$1'"
  (( OPT_DRY_RUN )) || mujo_lock
  if [[ $new == "$cur" ]]; then
    say "Glass is already $1; nothing to do."
    jq -n --argjson g "$cur" '{journal_id: null, settings: {glass: $g}, files: []}' | emit
    return 0
  fi
  word=$([[ $cur == true ]] && echo on || echo off)
  theme_set glass "$new" "$cur" "theme glass: $word -> $([[ $new == true ]] && echo on || echo off)" \
    "$(json_array theme glass "$word")"
}

theme_cmd_motion() {
  (( $# <= 1 )) || usage_error "too many arguments"
  local cur off
  cur=$(theme_settings | jq -r .motion)
  off=$(theme_settings | jq -r .reduce_motion)
  if (( $# == 0 )); then
    say "Motion: $cur$([[ $off == true ]] && echo " (but reduce-motion is on, so animations are off)" || true)"
    say "Available: normal gentle"
    jq -n --arg m "$cur" --argjson r "$off" '{motion: $m, reduce_motion: $r, available: ["normal", "gentle"]}' | emit
    return 0
  fi
  local new=$1
  [[ $new == normal || $new == gentle ]] || usage_error "expected normal or gentle, got '$new'"
  (( OPT_DRY_RUN )) || mujo_lock
  if [[ $new == "$cur" ]]; then
    say "Motion is already $new; nothing to do."
    jq -n --arg m "$cur" '{journal_id: null, settings: {motion: $m}, files: []}' | emit
    return 0
  fi
  [[ $off == true ]] && warn "reduce-motion is on, so nothing will move until '$MUJO_NAME theme reduce-motion off'"
  theme_set motion "\"$new\"" "\"$cur\"" "theme motion: $cur -> $new" "$(json_array theme motion "$cur")"
}

theme_cmd_reduce_motion() {
  (( $# <= 1 )) || usage_error "too many arguments"
  local cur new
  cur=$(theme_settings | jq -r .reduce_motion)
  if (( $# == 0 )); then
    say "reduce_motion: $([[ $cur == true ]] && echo on || echo off)"
    jq -n --argjson v "$cur" '{reduce_motion: $v}' | emit
    return 0
  fi
  case $1 in
    on|true) new=true ;;
    off|false) new=false ;;
    *) usage_error "expected 'on' or 'off', got '$1'" ;;
  esac
  (( OPT_DRY_RUN )) || mujo_lock
  cur=$(theme_settings | jq -r .reduce_motion)
  if [[ $new == "$cur" ]]; then
    say "reduce_motion is already $1; nothing to do."
    jq -n --argjson v "$cur" '{journal_id: null, settings: {reduce_motion: $v}, files: []}' | emit
    return 0
  fi
  local undo_word
  undo_word=$([[ $cur == true ]] && echo on || echo off)
  theme_set reduce_motion "$new" "$cur" "theme reduce-motion: $undo_word -> $1" \
    "$(json_array theme reduce-motion "$undo_word")"
}

theme_cmd_restore() {
  (( $# == 1 )) || usage_error "restore needs exactly one snapshot id"
  local sid=$1 src=$THEME_SNAPSHOTS/$1 rows id path existed
  [[ $sid =~ ^[0-9A-Za-z-]+$ && -f $src/index.json ]] || die "$EXIT_FAIL" "no snapshot '$sid'"
  (( OPT_DRY_RUN )) || mujo_lock
  theme_load_consumers
  mujo_tmpdir PLAN_DIR
  PLAN_IDS=()
  PLAN_STATUS=()
  PLAN_DEST=()
  rows=$(jq -r '.[] | [.id, .path, (.existed | tostring)] | join("\u001f")' "$src/index.json")
  while IFS=$'\x1f' read -r id path existed; do
    [[ -n $id ]] || continue
    PLAN_IDS+=("$id")
    PLAN_DEST[$id]=$path
    if [[ $existed == true ]]; then
      cp -- "$src/$id" "$PLAN_DIR/$id"
      if [[ ! -e $path ]]; then PLAN_STATUS[$id]=new
      elif cmp -s -- "$path" "$PLAN_DIR/$id"; then PLAN_STATUS[$id]=unchanged
      else PLAN_STATUS[$id]=changed; fi
    else
      if [[ -e $path ]]; then PLAN_STATUS[$id]=remove; else PLAN_STATUS[$id]=unchanged; fi
    fi
  done <<<"$rows"
  local settings
  settings=$(theme_settings)
  theme_commit "theme restore: snapshot $sid ($(theme_changed_count) file(s))" \
    "$(jq -cn --arg s "$sid" '{snapshot: $s}')" '{}' restore "$settings"
}

theme_cmd_list() {
  (( $# == 0 )) || usage_error "list takes no arguments"
  theme_plan "$(theme_settings)"
  theme_print_plan
  theme_plan_json 0 | jq '{consumers: .}' | emit
}

theme_cmd_show() {
  (( $# <= 1 )) || usage_error "too many arguments"
  local path=${1:-} out
  theme_load_consumers
  mujo_tmpdir PLAN_DIR
  theme_jq "$PLAN_DIR/r.json" -n --slurpfile tok "$THEME_TOKENS" --argjson s "$(theme_settings)" \
    'include "theme"; $tok[0] | resolve($s)'
  out=$(theme_jq - -c --arg p "$path" '
    if $p == "" then . else
      (try getpath($p | split(".") | map(if test("^[0-9]+$") then tonumber else . end)) catch null)
      // error("unknown token path \($p)") end' "$PLAN_DIR/r.json")
  (( OPT_JSON )) || jq . <<<"$out" | say_stream
  jq --arg p "$path" '{path: $p, value: .}' <<<"$out" | emit
}

theme_cmd_render() {
  (( $# == 1 )) || usage_error "render needs one template file"
  [[ -f $1 ]] || die "$EXIT_FAIL" "no such file: $1"
  mujo_tmpdir PLAN_DIR
  theme_jq "$PLAN_DIR/r.json" -n --slurpfile tok "$THEME_TOKENS" --argjson s "$(theme_settings)" \
    'include "theme"; $tok[0] | resolve($s)'
  theme_jq "$PLAN_DIR/out" -rj -n --rawfile tpl "$1" --slurpfile t "$PLAN_DIR/r.json" --arg name "$1" \
    'include "theme"; render($tpl; $t[0]; $name)'
  if (( OPT_JSON )); then
    jq -Rs '{output: .}' "$PLAN_DIR/out" | emit
  else
    cat -- "$PLAN_DIR/out" >&3
  fi
}

# ---- check -------------------------------------------------------------------

# Print lint findings as "file<TAB>line<TAB>rule<TAB>text", paths relative to the repo.
theme_lint() {
  local -a roots=() files=() id names
  if (( $# )); then
    for id in "$@"; do
      # shellcheck disable=SC2206 # space-separated list of repo paths
      roots+=(${C_LINT[$id]} "design/templates/$(dirname -- "${C_TEMPLATE[$id]}")")
    done
  else
    roots=("${THEME_LINT_ROOTS[@]}")
  fi
  mapfile -t files < <(cd -- "$MUJO_ROOT" && for r in "${roots[@]}"; do
    [[ -e $r ]] && find "$r" -type f ! -name '*.md'
  done | sort -u)
  (( ${#files[@]} )) || return 0

  names=$(jq -r '.palette | keys - $ARGS.positional | join("|")' "$THEME_TOKENS" --args "${THEME_GENERIC_NAMES[@]}")
  [[ -n $names ]] || die "$EXIT_FAIL" "theme: could not read palette names from tokens.json"
  local -a rules=(
    "hex-colour|#[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?([^0-9A-Za-z_]|\$)"
    "colour-function|(^|[^A-Za-z_])(rgba?|hsla?)\\("
    "hex-int-colour|0x[0-9A-Fa-f]{8}([^0-9A-Za-z_]|\$)"
    "palette-name|(^|[^A-Za-z0-9_])($names)([^A-Za-z0-9_]|\$)"
  )
  local rule name re
  (
    cd -- "$MUJO_ROOT" || exit "$EXIT_FAIL"
    for rule in "${rules[@]}"; do
      name=${rule%%|*}
      re=${rule#*|}
      grep -nHE -- "$re" "${files[@]}" 2>/dev/null | sed -E "s/^([^:]*):([0-9]+):/\\1\t\\2\t$name\t/" || true
    done
    local -a qml=()
    local f
    for f in "${files[@]}"; do [[ $f == *.qml ]] && qml+=("$f"); done
    if (( ${#qml[@]} )); then
      grep -nHE '^[[:space:]]*[A-Za-z.]*([Ww]idth|[Hh]eight|[Rr]adius|[Ss]pacing|[Mm]argins?|[Pp]adding|[Dd]uration|[Pp]ixelSize|[Ss]ize)[[:space:]]*:[[:space:]]*-?[0-9.]+[[:space:]]*(//.*)?$' \
        "${qml[@]}" 2>/dev/null \
        | grep -vE ':[[:space:]]*-?(0|1)[[:space:]]*(//.*)?$' \
        | sed -E "s/^([^:]*):([0-9]+):/\\1\t\\2\tqml-literal\t/" || true
    fi
  ) | theme_lint_filter_allowed
}

# Drop findings matched by design/check-allow.txt ("glob|ERE|reason" per line).
theme_lint_filter_allowed() {
  local -a globs=() res=()
  local line glob re rest file lineno rule text i allowed
  if [[ -f $THEME_ALLOW ]]; then
    while IFS= read -r line; do
      [[ -z $line || $line == \#* ]] && continue
      glob=${line%%|*}
      rest=${line#*|}
      re=${rest%%|*}
      globs+=("$glob")
      res+=("$re")
    done <"$THEME_ALLOW"
  fi
  while IFS=$'\t' read -r file lineno rule text; do
    allowed=0
    for i in "${!globs[@]}"; do
      # shellcheck disable=SC2053 # glob match is intended
      if [[ $file == ${globs[$i]} ]] && grep -qE -- "${res[$i]}" <<<"$text"; then allowed=1; break; fi
    done
    (( allowed )) || printf '%s\t%s\t%s\t%s\n' "$file" "$lineno" "$rule" "$text"
  done
}

theme_cmd_check() {
  theme_ids_from_args "$@"
  theme_plan "$(theme_settings)" "${THEME_ARG_IDS[@]}"
  local id problems='[]' notes='[]' p findings inst
  for id in "${PLAN_IDS[@]}"; do
    case ${PLAN_STATUS[$id]} in
      new) p="not built: run '$MUJO_NAME theme build'" ;;
      changed) p="out of date or edited by hand: differs from a fresh render" ;;
      *) p="" ;;
    esac
    if [[ -n $p ]]; then
      problems=$(jq -c --arg id "$id" --arg path "${PLAN_DEST[$id]}" --arg m "$p" --arg d "$(theme_diff "$id")" \
        '. + [{kind: "drift", consumer: $id, path: $path, message: $m, diff: $d}]' <<<"$problems")
    fi
    if [[ ${C_SCOPE[$id]} == system ]]; then
      inst=$(theme_installed_path "$id")
      if ! cmp -s -- "$inst" "$PLAN_DIR/$id" 2>/dev/null; then
        notes=$(jq -c --arg id "$id" --arg path "$inst" \
          '. + [{consumer: $id, path: $path, message: "system file not installed or out of date (the installer installs it)"}]' <<<"$notes")
      fi
    fi
  done
  findings=$(theme_lint "${THEME_ARG_IDS[@]}" | jq -cR 'split("\t") | {kind: "hardcoded", file: .[0], line: (.[1] | tonumber), rule: .[2], text: .[3]}' | jq -cs .)
  problems=$(jq -c --argjson f "$findings" '. + $f' <<<"$problems")

  if (( ! OPT_JSON )); then
    local n
    n=$(jq length <<<"$problems")
    jq -r '.[] | if .kind == "drift" then "drift      \(.consumer): \(.path | sub("^'"$HOME"'"; "~")): \(.message)"
                 else "hardcoded  \(.file):\(.line): \(.rule): \(.text | gsub("^\\s+"; ""))" end' <<<"$problems" | say_stream
    jq -r '.[] | "note       \(.consumer): \(.path): \(.message)"' <<<"$notes" | say_stream
    if (( n == 0 )); then
      say "theme check: ok (${#PLAN_IDS[@]} consumer(s) current, no hardcoded values)"
    else
      say "theme check: $n problem(s)"
    fi
  fi
  jq -n --argjson p "$problems" --argjson n "$notes" '{ok: ($p | length == 0), problems: $p, notes: $n}' | emit
  [[ $problems == "[]" ]] || exit "$EXIT_FAIL"
}
