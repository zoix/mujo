# shellcheck shell=bash
# karma update: update karma itself (git) and the system (pacman), and say
# what changed.

karma_register update "System and karma update with a summary"

help_update() {
  cat <<EOF
Usage: $KARMA_NAME update [--karma-only | --system-only] [--yes]
       $KARMA_NAME update check [--refresh]

karma   'git pull --ff-only' in $(tilde "$KARMA_ROOT"), then the new config files
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

An update cannot be undone; it is recorded in the journal. If the kernel
or Hyprland was upgraded the summary says to reboot or log out.
EOF
}

update_has_upstream() {
  git -C "$KARMA_ROOT" rev-parse --abbrev-ref '@{upstream}' >/dev/null 2>&1
}

# The packages pacman would upgrade, one "name old -> new" per line.
update_pending() {
  if command -v checkupdates >/dev/null 2>&1; then
    checkupdates 2>/dev/null || true
  else
    pacman -Qu 2>/dev/null || true
  fi
}

UPDATE_CACHE=$KARMA_CACHE_DIR/updates.json

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
    karma_set_cmd "update check"
    update_cmd_check "$@"
    return 0
  fi
  local do_karma=1 do_system=1
  while (( $# )); do
    case $1 in
      --karma-only) do_system=0; shift ;;
      --system-only) do_karma=0; shift ;;
      *) usage_error "unexpected argument '$1'" ;;
    esac
  done
  (( do_karma || do_system )) || usage_error "--karma-only and --system-only together leave nothing to do"

  local karma_state="skipped" commits=0 from="" to=""
  local -a upgraded=()
  local pending=""

  if (( OPT_DRY_RUN )); then
    say "$KARMA_NAME update (dry run, nothing changed)"
    if (( do_karma )); then
      if command -v git >/dev/null 2>&1 && update_has_upstream; then
        commits=$(git -C "$KARMA_ROOT" rev-list --count 'HEAD..@{upstream}' 2>/dev/null) || commits=0
        say "$KARMA_NAME: $commits commit(s) fetched and not yet merged (git fetch was not run)"
        karma_state="pending"
      else
        say "$KARMA_NAME: the checkout has no upstream branch; nothing to pull"
        karma_state="no-upstream"
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
    jq -n --arg ks "$karma_state" --argjson c "$commits" --arg p "$pending" \
      '{journal_id: null, karma: {state: $ks, commits: $c},
        system: {packages: ($p | split("\n") | map(select(length > 0)))}, reboot_recommended: false}' | emit
    return 0
  fi

  if (( do_system )) && (( ! OPT_YES )) && [[ ! -t 0 ]]; then
    die "$EXIT_USAGE" "a system update without a terminal needs --yes (or use --karma-only)"
  fi
  karma_lock

  if (( do_karma )); then
    if ! command -v git >/dev/null 2>&1 || ! update_has_upstream; then
      say "$KARMA_NAME: the checkout has no upstream branch; nothing to pull"
      karma_state="no-upstream"
    else
      from=$(git -C "$KARMA_ROOT" rev-parse --short HEAD)
      say "$KARMA_NAME: git pull --ff-only"
      if git -C "$KARMA_ROOT" pull --ff-only >&2; then
        to=$(git -C "$KARMA_ROOT" rev-parse --short HEAD)
        commits=$(git -C "$KARMA_ROOT" rev-list --count "$from..$to")
        karma_state="current"
        if (( commits > 0 )); then
          karma_state="updated"
          # New config files need links, and new tokens a rebuild. The
          # installer does both and nothing else when run this way.
          flock -u 9 2>/dev/null || true
          "$KARMA_ROOT/install.sh" --yes --skip-system >/dev/null 2>&1 \
            || warn "linking the new config failed; run $KARMA_ROOT/install.sh --skip-system"
          "$KARMA_BIN" theme build >/dev/null 2>&1 3>&1 || warn "'$KARMA_NAME theme build' failed"
        fi
      else
        warn "git pull failed (local changes or a diverged branch?); $KARMA_NAME was not updated"
        karma_state="failed"
      fi
    fi
  fi

  local system_ok=true
  if (( do_system )); then
    need pacman sudo
    local before after
    before=$(pacman -Q 2>/dev/null | sort)
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
    mapfile -t upgraded < <(comm -13 <(printf '%s\n' "$before") <(printf '%s\n' "$after") | awk '{ print $1 }')
    [[ $system_ok == true ]] || warn "pacman reported an error; see its output above"
  fi

  local reboot=false name
  for name in "${upgraded[@]}"; do
    case $name in
      linux|linux-lts|linux-zen|linux-hardened|hyprland|systemd|mesa) reboot=true ;;
    esac
  done

  local jid summary
  summary="update: $KARMA_NAME $karma_state"
  (( commits > 0 )) && summary+=" ($commits commit(s), $from..$to)"
  (( do_system )) && summary+=", ${#upgraded[@]} package(s) upgraded"
  jid=$(journal_new_id)
  journal_record "$jid" "$summary" '{}' \
    "$(jq -cn --arg ks "$karma_state" --argjson c "$commits" --argjson p "$(json_array "${upgraded[@]}")" \
      '{karma: $ks, commits: $c, packages: $p}')" null

  say ""
  say "Summary"
  case $karma_state in
    updated) say "  $KARMA_NAME: $commits new commit(s), $from -> $to; config linked and theme rebuilt" ;;
    current) say "  $KARMA_NAME: already up to date" ;;
    no-upstream) say "  $KARMA_NAME: not updated (no upstream branch)" ;;
    failed) say "  $KARMA_NAME: update failed" ;;
  esac
  if (( do_system )); then
    if (( ${#upgraded[@]} )); then
      say "  System: ${#upgraded[@]} package(s) upgraded: ${upgraded[*]}"
    else
      say "  System: nothing was upgraded"
    fi
    [[ $reboot == true ]] && say "  The kernel, Hyprland or a core library changed: reboot (or at least log out) to use it."
  fi
  say "  Journal: $jid (cannot be undone)"
  jq -n --arg j "$jid" --arg ks "$karma_state" --argjson c "$commits" --argjson p "$(json_array "${upgraded[@]}")" \
    --argjson r "$reboot" \
    '{journal_id: $j, karma: {state: $ks, commits: $c}, system: {packages: $p}, reboot_recommended: $r}' | emit
  [[ $system_ok == true && $karma_state != failed ]] || exit "$EXIT_FAIL"
}
