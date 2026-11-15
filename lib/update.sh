# shellcheck shell=bash
# mujo update: update mujo itself (git) and the system (pacman), and say
# what changed.

mujo_register update "System and mujo update with a summary"

help_update() {
  cat <<EOF
Usage: $MUJO_NAME update [--mujo-only | --system-only] [--no-snapshot] [--yes]
       $MUJO_NAME update check [--refresh]
       $MUJO_NAME update snapshots
       $MUJO_NAME update rollback [BEFORE..AFTER] --yes

mujo   'git pull --ff-only' in $(tilde "$MUJO_ROOT"), then the new config files
        are linked and the theme is rebuilt. Skipped if the checkout has no
        upstream branch.
system  'sudo pacman -Syu', then the AUR packages with yay or paru if one is
        installed ('yay -Sua'). In a terminal they ask before installing;
        with --yes they do not ask (needed when there is no terminal).

--dry-run lists what would be updated: pending packages (checkupdates if
pacman-contrib is installed, otherwise the last synced database) and the
commits already fetched but not merged. Only the AUR is asked over the
network; the official repositories are read from the last sync.

check counts the packages waiting to be upgraded and changes nothing. The
answer is kept for an hour (--refresh asks again); the interface shows the
count in the bar. With pacman-contrib installed the official repositories
are asked over the network (checkupdates); without it the last synced
database is read.

If snapper has a configuration for / (btrfs), a snapshot is taken before
the system update and another after it (--no-snapshot skips them). They are
numbered and removed by snapper's own clean-up. snapshots lists the pairs.

rollback puts back every system file the last update changed (or the update
between the two snapshot numbers given): 'snapper undochange', then the
kernel image in /boot is made to match again. Your home directory is not
touched. Reboot afterwards. It needs --yes; --dry-run shows the steps.

'$MUJO_NAME undo' cannot undo an update; rollback is the way. If the kernel
or Hyprland was upgraded the summary says to reboot or log out.
EOF
}

update_has_upstream() {
  git -C "$MUJO_ROOT" rev-parse --abbrev-ref '@{upstream}' >/dev/null 2>&1
}

# The packages pacman would upgrade, one "name old -> new" per line.
update_pending() {
  if command -v checkupdates >/dev/null 2>&1; then
    checkupdates 2>/dev/null || true
  else
    pacman -Qu 2>/dev/null || true
  fi
}

UPDATE_CACHE=$MUJO_CACHE_DIR/updates.json
# The snapshots around the last system update: {config, pre, post, time, packages}.
UPDATE_SNAPSHOT_FILE=$MUJO_STATE_DIR/update-snapshot.json

# The name of the snapper configuration that covers /, if there is one.
update_snapper_config() {
  command -v snapper >/dev/null 2>&1 || return 1
  local f
  for f in "${MUJO_SYSROOT:-}"/etc/snapper/configs/*; do
    [[ -r $f ]] || continue
    if grep -qE '^SUBVOLUME="?/"?[[:space:]]*$' "$f"; then
      printf '%s\n' "${f##*/}"
      return 0
    fi
  done
  return 1
}

update_cmd_snapshots() {
  (( $# )) && usage_error "unexpected argument '$1'"
  local config listing
  config=$(update_snapper_config) || die "$EXIT_ENV" "snapper has no configuration for / (see 'snapper create-config')"
  need sudo
  listing=$(sudo snapper -c "$config" list --type pre-post) || die "$EXIT_FAIL" "snapper could not list the snapshots"
  say "$listing"
  jq -n --arg c "$config" --arg l "$listing" --slurpfile last <(cat -- "$UPDATE_SNAPSHOT_FILE" 2>/dev/null || echo null) \
    '{config: $c, last_update: $last[0], lines: ($l | split("\n"))}' | emit
}

update_cmd_rollback() {
  local range=""
  while (( $# )); do
    case $1 in
      -*) usage_error "unknown option '$1'" ;;
      *) [[ -z $range ]] || usage_error "unexpected argument '$1'"; range=$1; shift ;;
    esac
  done
  local config pre post
  config=$(update_snapper_config) || die "$EXIT_ENV" "snapper has no configuration for / (see 'snapper create-config')"
  if [[ -n $range ]]; then
    [[ $range =~ ^([0-9]+)\.\.([0-9]+)$ ]] || usage_error "give the two snapshot numbers as BEFORE..AFTER, e.g. 41..42 (see '$MUJO_NAME update snapshots')"
    pre=${BASH_REMATCH[1]} post=${BASH_REMATCH[2]}
    (( pre < post )) || usage_error "the first number must be the snapshot taken before the update"
  else
    [[ -f $UPDATE_SNAPSHOT_FILE ]] || die "$EXIT_FAIL" "no update with snapshots is on record; name them: $MUJO_NAME update rollback BEFORE..AFTER"
    pre=$(jq -r '.pre // empty' "$UPDATE_SNAPSHOT_FILE") post=$(jq -r '.post // empty' "$UPDATE_SNAPSHOT_FILE")
    config=$(jq -r --arg c "$config" '.config // $c' "$UPDATE_SNAPSHOT_FILE")
    [[ $pre =~ ^[0-9]+$ && $post =~ ^[0-9]+$ ]] || die "$EXIT_FAIL" "the last update has no finished pair of snapshots; name them: $MUJO_NAME update rollback BEFORE..AFTER"
  fi
  local modules=${MUJO_SYSROOT:-}/usr/lib/modules boot=${MUJO_SYSROOT:-}/boot
  if (( OPT_DRY_RUN )); then
    say "$MUJO_NAME update rollback (dry run, nothing changed)"
    say "  sudo snapper -c $config undochange $pre..$post"
    say "  copy each kernel in $modules to $boot if it differs, then sudo mkinitcpio -P"
    say "  then reboot"
    jq -n --arg c "$config" --argjson a "$pre" --argjson b "$post" \
      '{journal_id: null, config: $c, pre: $a, post: $b, kernels: [], reboot_recommended: true}' | emit
    return 0
  fi
  confirm_irreversible "rolling back the update between snapshots $pre and $post"
  need sudo
  mujo_lock
  say "Rollback: sudo snapper -c $config undochange $pre..$post"
  if (( OPT_JSON )); then
    sudo snapper -c "$config" undochange "$pre..$post" >&2 || die "$EXIT_FAIL" "snapper could not undo the changes; nothing else was done"
  else
    sudo snapper -c "$config" undochange "$pre..$post" || die "$EXIT_FAIL" "snapper could not undo the changes; nothing else was done"
  fi
  # /boot is not part of the snapshot. Put the kernel images that belong to
  # the restored modules back, and rebuild the initramfs for them.
  local dir base
  local -a kernels=()
  for dir in "$modules"/*/; do
    [[ -f ${dir}vmlinuz && -f ${dir}pkgbase ]] || continue
    base=$(<"${dir}pkgbase")
    if ! sudo cmp -s -- "${dir}vmlinuz" "$boot/vmlinuz-$base"; then
      say "Kernel: $boot/vmlinuz-$base <- ${dir}vmlinuz"
      sudo install -Dm644 -- "${dir}vmlinuz" "$boot/vmlinuz-$base" || warn "could not copy the kernel image to $boot/vmlinuz-$base"
      kernels+=("$base")
    fi
  done
  if (( ${#kernels[@]} )) && command -v mkinitcpio >/dev/null 2>&1; then
    say "Kernel: sudo mkinitcpio -P"
    sudo mkinitcpio -P >&2 || warn "mkinitcpio failed; run 'sudo mkinitcpio -P' before rebooting"
  fi
  rm -f -- "$UPDATE_CACHE" "$UPDATE_SNAPSHOT_FILE"
  ui_ipc updates refresh
  local jid
  jid=$(journal_new_id)
  journal_record "$jid" "update rollback: system files back to snapshot $pre (undid $pre..$post)" '{}' \
    "$(jq -cn --arg c "$config" --argjson a "$pre" --argjson b "$post" --argjson k "$(json_array "${kernels[@]}")" \
      '{config: $c, pre: $a, post: $b, kernels: $k}')" null
  say ""
  say "The system files are back as they were before the update. Reboot now."
  say "  Journal: $jid (cannot be undone)"
  jq -n --arg j "$jid" --arg c "$config" --argjson a "$pre" --argjson b "$post" --argjson k "$(json_array "${kernels[@]}")" \
    '{journal_id: $j, config: $c, pre: $a, post: $b, kernels: $k, reboot_recommended: true}' | emit
}

update_cmd_check() {
  local refresh=0
  while (( $# )); do
    case $1 in
      --refresh) refresh=1; shift ;;
      *) usage_error "unexpected argument '$1'" ;;
    esac
  done
  local now result="" repo aur="" helper
  now=$(date +%s)
  if (( ! refresh )) && [[ -f $UPDATE_CACHE ]]; then
    result=$(jq -c --argjson now "$now" 'select(.checked > $now - 3600)' "$UPDATE_CACHE" 2>/dev/null) || result=""
  fi
  if [[ -z $result ]]; then
    need pacman
    repo=$(update_pending)
    if helper=$(pkg_helper); then aur=$(timeout 30 "$helper" -Qua 2>/dev/null || true); fi
    result=$(jq -cn --arg r "$repo" --arg a "$aur" --argjson now "$now" '
      def names: split("\n") | map(select(length > 0) | split(" ")[0]);
      {repo: ($r | names), aur: ($a | names), checked: $now} | .count = (.repo + .aur | length)')
    printf '%s\n' "$result" | atomic_write "$UPDATE_CACHE"
  fi
  local count
  count=$(jq -r .count <<<"$result")
  if (( count == 0 )); then say "Everything is up to date."
  else say "$count package(s) can be upgraded: $(jq -r '.repo + .aur | join(" ")' <<<"$result")"; fi
  printf '%s' "$result" | emit
}

cmd_update() {
  if [[ ${1:-} == check ]]; then
    shift
    mujo_set_cmd "update check"
    update_cmd_check "$@"
    return 0
  fi
  case ${1:-} in
    snapshots) shift; mujo_set_cmd "update snapshots"; update_cmd_snapshots "$@"; return 0 ;;
    rollback) shift; mujo_set_cmd "update rollback"; update_cmd_rollback "$@"; return 0 ;;
  esac
  local do_mujo=1 do_system=1 do_snapshot=1
  while (( $# )); do
    case $1 in
      --no-snapshot) do_snapshot=0; shift ;;
      --mujo-only) do_system=0; shift ;;
      --system-only) do_mujo=0; shift ;;
      *) usage_error "unexpected argument '$1'" ;;
    esac
  done
  (( do_mujo || do_system )) || usage_error "--mujo-only and --system-only together leave nothing to do"

  local mujo_state="skipped" commits=0 from="" to=""
  local -a upgraded=()
  local pending=""

  if (( OPT_DRY_RUN )); then
    say "$MUJO_NAME update (dry run, nothing changed)"
    if (( do_mujo )); then
      if command -v git >/dev/null 2>&1 && update_has_upstream; then
        commits=$(git -C "$MUJO_ROOT" rev-list --count 'HEAD..@{upstream}' 2>/dev/null) || commits=0
        say "$MUJO_NAME: $commits commit(s) fetched and not yet merged (git fetch was not run)"
        mujo_state="pending"
      else
        say "$MUJO_NAME: the checkout has no upstream branch; nothing to pull"
        mujo_state="no-upstream"
      fi
    fi
    if (( do_system )); then
      need pacman
      pending=$(update_pending)
      if [[ -n $pending ]]; then
        say "System: $(grep -c . <<<"$pending") package(s) would be upgraded:"
        say "  ${pending//$'\n'/$'\n'  }"
      else
        say "System: no pending packages in the synced database"
      fi
      local dry_config
      if (( do_snapshot )) && dry_config=$(update_snapper_config); then
        say "Snapshot: one before and one after the update (snapper configuration '$dry_config')"
      else
        say "Snapshot: none"
      fi
      local helper aur_pending
      if helper=$(pkg_helper); then
        aur_pending=$("$helper" -Qua 2>/dev/null || true)
        if [[ -n $aur_pending ]]; then
          say "AUR: $(grep -c . <<<"$aur_pending") package(s) would be upgraded:"
          say "  ${aur_pending//$'\n'/$'\n'  }"
          pending+=${pending:+$'\n'}$aur_pending
        else
          say "AUR: nothing to upgrade"
        fi
      fi
    fi
    jq -n --arg ks "$mujo_state" --argjson c "$commits" --arg p "$pending" \
      '{journal_id: null, mujo: {state: $ks, commits: $c},
        system: {packages: ($p | split("\n") | map(select(length > 0)))}, reboot_recommended: false}' | emit
    return 0
  fi

  if (( do_system )) && (( ! OPT_YES )) && [[ ! -t 0 ]]; then
    die "$EXIT_USAGE" "a system update without a terminal needs --yes (or use --mujo-only)"
  fi
  mujo_lock

  if (( do_mujo )); then
    if ! command -v git >/dev/null 2>&1 || ! update_has_upstream; then
      say "$MUJO_NAME: the checkout has no upstream branch; nothing to pull"
      mujo_state="no-upstream"
    else
      from=$(git -C "$MUJO_ROOT" rev-parse --short HEAD)
      say "$MUJO_NAME: git pull --ff-only"
      if git -C "$MUJO_ROOT" pull --ff-only >&2; then
        to=$(git -C "$MUJO_ROOT" rev-parse --short HEAD)
        commits=$(git -C "$MUJO_ROOT" rev-list --count "$from..$to")
        mujo_state="current"
        if (( commits > 0 )); then
          mujo_state="updated"
          # New config files need links, and new tokens a rebuild. The
          # installer does both and nothing else when run this way.
          flock -u 9 2>/dev/null || true
          "$MUJO_ROOT/install.sh" --yes --skip-system >/dev/null 2>&1 \
            || warn "linking the new config failed; run $MUJO_ROOT/install.sh --skip-system"
          "$MUJO_BIN" theme build >/dev/null 2>&1 3>&1 || warn "'$MUJO_NAME theme build' failed"
        fi
      else
        warn "git pull failed (local changes or a diverged branch?); $MUJO_NAME was not updated"
        mujo_state="failed"
      fi
    fi
  fi

  local system_ok=true snap_config="" snap_pre="" snap_post="" snapshot=null
  if (( do_system )); then
    need pacman sudo
    local before after
    before=$(pacman -Q 2>/dev/null | sort)
    if (( do_snapshot )) && snap_config=$(update_snapper_config); then
      say "Snapshot: sudo snapper -c $snap_config create (before the update)"
      snap_pre=$(sudo snapper -c "$snap_config" create --type pre --cleanup-algorithm number \
        --print-number --description "$MUJO_NAME update") || snap_pre=""
      if [[ ! $snap_pre =~ ^[0-9]+$ ]]; then
        warn "the snapshot could not be taken; updating without one"
        snap_pre=""
      fi
    elif (( do_snapshot )); then
      say "Snapshot: none (snapper has no configuration for /)"
    fi
    say "System: sudo pacman -Syu"
    local -a flags=(-Syu)
    (( OPT_YES )) && flags+=(--noconfirm)
    if (( OPT_JSON )); then
      sudo pacman "${flags[@]}" >&2 || system_ok=false
    else
      sudo pacman "${flags[@]}" || system_ok=false
    fi
    # AUR packages, with the helper if there is one. It asks for sudo itself.
    local helper
    if helper=$(pkg_helper); then
      say "AUR: $helper -Sua"
      local -a aur_flags=(-Sua)
      (( OPT_YES )) && aur_flags+=(--noconfirm)
      if (( OPT_JSON )); then
        "$helper" "${aur_flags[@]}" >&2 || system_ok=false
      else
        "$helper" "${aur_flags[@]}" || system_ok=false
      fi
    fi
    after=$(pacman -Q 2>/dev/null | sort)
    rm -f -- "$UPDATE_CACHE"
    # The bar shows the old count until it looks again.
    ui_ipc updates refresh
    mapfile -t upgraded < <(comm -13 <(printf '%s\n' "$before") <(printf '%s\n' "$after") | awk '{ print $1 }')
    if [[ -n $snap_pre ]]; then
      snap_post=$(sudo snapper -c "$snap_config" create --type post --pre-number "$snap_pre" \
        --cleanup-algorithm number --print-number \
        --description "$MUJO_NAME update: ${#upgraded[@]} package(s)") || snap_post=""
      [[ $snap_post =~ ^[0-9]+$ ]] || { warn "the snapshot after the update could not be taken"; snap_post=""; }
      snapshot=$(jq -cn --arg c "$snap_config" --arg a "$snap_pre" --arg b "$snap_post" \
        --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --argjson p "$(json_array "${upgraded[@]}")" \
        '{config: $c, pre: ($a | tonumber), post: (if $b == "" then null else ($b | tonumber) end), time: $t, packages: $p}')
      printf '%s\n' "$snapshot" | atomic_write "$UPDATE_SNAPSHOT_FILE"
    fi
    [[ $system_ok == true ]] || warn "pacman reported an error; see its output above"
  fi

  local reboot=false name
  for name in "${upgraded[@]}"; do
    case $name in
      linux|linux-lts|linux-zen|linux-hardened|hyprland|systemd|mesa) reboot=true ;;
    esac
  done

  local jid summary
  summary="update: $MUJO_NAME $mujo_state"
  (( commits > 0 )) && summary+=" ($commits commit(s), $from..$to)"
  (( do_system )) && summary+=", ${#upgraded[@]} package(s) upgraded"
  jid=$(journal_new_id)
  journal_record "$jid" "$summary" '{}' \
    "$(jq -cn --arg ks "$mujo_state" --argjson c "$commits" --argjson p "$(json_array "${upgraded[@]}")" \
      --argjson s "$snapshot" '{mujo: $ks, commits: $c, packages: $p, snapshot: $s}')" null

  say ""
  say "Summary"
  case $mujo_state in
    updated) say "  $MUJO_NAME: $commits new commit(s), $from -> $to; config linked and theme rebuilt" ;;
    current) say "  $MUJO_NAME: already up to date" ;;
    no-upstream) say "  $MUJO_NAME: not updated (no upstream branch)" ;;
    failed) say "  $MUJO_NAME: update failed" ;;
  esac
  if (( do_system )); then
    if (( ${#upgraded[@]} )); then
      say "  System: ${#upgraded[@]} package(s) upgraded: ${upgraded[*]}"
    else
      say "  System: nothing was upgraded"
    fi
    [[ $reboot == true ]] && say "  The kernel, Hyprland or a core library changed: reboot (or at least log out) to use it."
    if [[ -n $snap_pre && -n $snap_post ]]; then
      say "  Snapshots: $snap_pre before, $snap_post after. If something broke: $MUJO_NAME update rollback --yes"
    elif [[ -n $snap_pre ]]; then
      say "  Snapshot: $snap_pre before the update (the one after it failed)"
    fi
  fi
  say "  Journal: $jid (cannot be undone)"
  jq -n --arg j "$jid" --arg ks "$mujo_state" --argjson c "$commits" --argjson p "$(json_array "${upgraded[@]}")" \
    --argjson r "$reboot" --argjson s "$snapshot" \
    '{journal_id: $j, mujo: {state: $ks, commits: $c}, system: {packages: $p}, snapshot: $s, reboot_recommended: $r}' | emit
  [[ $system_ok == true && $mujo_state != failed ]] || exit "$EXIT_FAIL"
}
