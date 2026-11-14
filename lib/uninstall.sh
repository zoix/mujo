# shellcheck shell=bash
# karma uninstall: put the system back the way install.sh found it, from
# the manifests in ~/.local/state/karma/backups/<time>/manifest.json.

karma_register uninstall "Remove karma's links and restore the backups"

help_uninstall() {
  cat <<EOF
Usage: $KARMA_NAME uninstall [--skip-system] --yes

Reverses install.sh:
  1. removes the links from config/ in your home directory
  2. moves what karma generated or wrote there (theme files, host.lua,
     local.zsh, ~/.config/$KARMA_NAME) to
     ~/.local/state/$KARMA_NAME/uninstalled/<time>/  (nothing is deleted)
  3. puts back every file from the backups, restows the dotfile packages
     that were unstowed and folds directories that were unfolded
  4. with sudo: restores the files in /etc, the previous login screen and
     the previous locale, and disables the console palette service

--skip-system leaves out step 4. --dry-run prints the plan and changes
nothing. Without --yes nothing happens.

Not reversed: installed packages stay installed, packages you let the
installer remove are only listed, and the login shell is left alone. The
checkout, the backups and the journal stay where they are, so running
install.sh again brings karma back.
EOF
}

UNINSTALL_STEPS=()
UNINSTALL_NOTES=()
UNINSTALL_ATTIC=""

# un_act DESCRIPTION COMMAND...: one step of the plan. Runs unless --dry-run.
un_act() {
  local what=$1
  shift
  UNINSTALL_STEPS+=("$what")
  say "   + $what"
  (( OPT_DRY_RUN )) && return 0
  "$@" || { warn "failed: $what"; UNINSTALL_NOTES+=("failed: $what"); }
}

un_note() {
  UNINSTALL_NOTES+=("$1")
  say "   ! $1"
}

# un_stash PATH: move a file karma wrote into the attic, keeping its path.
un_stash() {
  local path=$1 dest
  dest=$UNINSTALL_ATTIC/${path#"$HOME"/}
  mkdir -p -- "$(dirname -- "$dest")"
  mv -- "$path" "$dest"
}

un_rmdir_empty() {
  local dir=$1
  while [[ $dir == "$HOME"/* ]]; do
    rmdir -- "$dir" 2>/dev/null || return 0
    dir=$(dirname -- "$dir")
  done
}

un_remove_link() {
  rm -f -- "$1"
  un_rmdir_empty "$(dirname -- "$1")"
}

# Fold a directory back into the single link it was before the install, if
# all that is left in it are links into the stow package it came from.
un_refold() {
  local path=$1 link=$2 entry target points
  target=$link
  [[ $target == /* ]] || target=$(dirname -- "$path")/$target
  target=$(realpath -m -- "$target")
  shopt -s dotglob nullglob
  for entry in "$path"/*; do
    # Where the entry points, one step only: what it points at may itself
    # be a link to somewhere else, and that is none of our business.
    points=$(readlink -- "$entry" 2>/dev/null) || points=""
    [[ $points == /* ]] || points=$path/$points
    if [[ ! -L $entry || $(realpath -m -- "$(dirname -- "$points")") != "$target" ]]; then
      shopt -u dotglob nullglob
      warn "$(tilde "$path") has entries that are not from your dotfiles; left as a directory"
      return 0
    fi
  done
  shopt -u dotglob nullglob
  rm -rf -- "$path"
  ln -s -- "$link" "$path"
}

un_restore_path() {
  local backup=$1 path=$2
  mkdir -p -- "$(dirname -- "$path")"
  cp -P -- "$backup" "$path"
}

un_home() {
  local root=$KARMA_ROOT/config file rel dest count=0
  say "1. Links from config/"
  local -a links=()
  while IFS= read -r -d '' file; do
    rel=${file#"$root"/}
    rel=${rel#*/}
    dest=$HOME/$rel
    if [[ -L $dest && $(readlink -f -- "$dest") == "$(readlink -f -- "$file")" ]]; then
      links+=("$dest")
    fi
  done < <(find "$root" -mindepth 2 \( -type f -o -type l \) -print0 2>/dev/null)
  count=${#links[@]}
  if (( count )); then
    UNINSTALL_STEPS+=("remove $count link(s) into $(tilde "$KARMA_ROOT")/config")
    say "   + remove $count link(s) into $(tilde "$KARMA_ROOT")/config"
    if (( ! OPT_DRY_RUN )); then
      for dest in "${links[@]}"; do un_remove_link "$dest"; done
    fi
  else
    say "   = none found"
  fi
  local checkout=${XDG_DATA_HOME:-$HOME/.local/share}/$KARMA_NAME
  [[ -L $checkout ]] && un_act "remove the link $(tilde "$checkout")" un_remove_link "$checkout"

  say "2. Files karma generated or wrote (moved to $(tilde "$UNINSTALL_ATTIC"))"
  theme_load_consumers
  local id path
  local -a written=()
  for id in "${C_IDS[@]}"; do
    [[ ${C_SCOPE[$id]} == user ]] || continue
    path=$(theme_dest "$id")
    [[ -e $path ]] && written+=("$path")
  done
  for path in "$KARMA_CONFIG_HOME/hypr/host.lua" "$KARMA_CONFIG_HOME/zsh/local.zsh" "$KARMA_CONFIG_DIR"; do
    [[ -e $path ]] && written+=("$path")
  done
  if (( ${#written[@]} )); then
    for path in "${written[@]}"; do
      UNINSTALL_STEPS+=("move $(tilde "$path") away")
      say "   + move $(tilde "$path") away"
      if (( ! OPT_DRY_RUN )); then
        un_stash "$path"
        un_rmdir_empty "$(dirname -- "$path")"
      fi
    done
  else
    say "   = none found"
  fi

  say "3. Backups"
  local manifest dir entry kind p
  local -a manifests=()
  mapfile -t manifests < <(find "$KARMA_STATE_DIR/backups" -mindepth 2 -maxdepth 2 -name manifest.json 2>/dev/null | sort -r)
  if (( ${#manifests[@]} == 0 )); then
    say "   = no backup manifests in $(tilde "$KARMA_STATE_DIR")/backups"
    return 0
  fi
  # A backup without a manifest is from an install that stopped half-way.
  for dir in "$KARMA_STATE_DIR"/backups/*/; do
    [[ -f ${dir}manifest.json ]] \
      || un_note "$(tilde "${dir%/}") has no manifest (an interrupted install); its files are kept there, not restored"
  done
  for manifest in "${manifests[@]}"; do
    dir=$(dirname -- "$manifest")
    while IFS= read -r entry; do
      if p=$(jq -er '.path // empty' <<<"$entry"); then
        if [[ -e $p || -L $p ]] && (( ! OPT_DRY_RUN )); then
          un_note "$(tilde "$p") exists and is not karma's; the backup in $(tilde "$dir") was not restored"
        else
          un_act "restore $(tilde "$p")" un_restore_path "$dir/home/${p#"$HOME"/}" "$p"
        fi
      elif jq -e 'has("unstowed")' <<<"$entry" >/dev/null; then
        local sdir spkg
        sdir=$(jq -r .unstowed.stow_dir <<<"$entry")
        spkg=$(jq -r .unstowed.package <<<"$entry")
        if [[ -d $sdir/$spkg ]] && command -v stow >/dev/null 2>&1; then
          un_act "stow package '$spkg' from $(tilde "$sdir") again" stow -d "$sdir" -t "$HOME" -S "$spkg"
        else
          un_note "cannot restow '$spkg': $(tilde "$sdir/$spkg") or stow is missing"
        fi
      elif jq -e 'has("unfolded")' <<<"$entry" >/dev/null; then
        local upath ulink
        upath=$(jq -r .unfolded.path <<<"$entry")
        ulink=$(jq -r .unfolded.link <<<"$entry")
        if [[ -d $upath && ! -L $upath ]]; then
          un_act "fold $(tilde "$upath") back into a link to $ulink" un_refold "$upath" "$ulink"
        fi
      elif kind=$(jq -er '.packages_removed // empty | join(" ")' <<<"$entry"); then
        un_note "packages the installer removed are not reinstalled: $kind"
      fi
    done < <(jq -c '.entries | reverse | .[]' "$manifest")
  done
}

un_system() {
  say "4. System (sudo)"
  local manifest dir entry p kind unit locale any=0
  local -a manifests=()
  mapfile -t manifests < <(find "$KARMA_STATE_DIR/backups" -mindepth 2 -maxdepth 2 -name manifest.json 2>/dev/null | sort -r)
  if systemctl is-enabled -q "$KARMA_NAME-vtrgb.service" 2>/dev/null; then
    any=1
    un_act "disable $KARMA_NAME-vtrgb.service (the console palette)" sudo systemctl disable "$KARMA_NAME-vtrgb.service"
  fi
  for manifest in "${manifests[@]}"; do
    dir=$(dirname -- "$manifest")
    while IFS= read -r entry; do
      if p=$(jq -er '.etc // empty' <<<"$entry"); then
        any=1
        kind=$(jq -r .kind <<<"$entry")
        if [[ $kind == file ]]; then
          un_act "restore $p" sudo install -D -m 0644 -- "$dir/etc/${p#/etc/}" "$p"
        else
          un_act "remove $p" sudo rm -f -- "$p"
        fi
      elif unit=$(jq -er '.display_manager_disabled // empty' <<<"$entry"); then
        any=1
        un_act "disable greetd.service and enable $unit again (takes effect at the next boot)" \
          sh -c 'sudo systemctl disable greetd.service; sudo systemctl enable "$1"' sh "$unit"
      elif locale=$(jq -er '.locale_before // empty' <<<"$entry"); then
        any=1
        [[ -f $dir/etc/locale.gen ]] && un_act "restore /etc/locale.gen" sudo install -m 0644 -- "$dir/etc/locale.gen" /etc/locale.gen
        if [[ $locale == LANG=* ]]; then
          un_act "set the system locale back to $locale" sh -c 'sudo locale-gen >/dev/null; sudo localectl set-locale "$1"' sh "$locale"
        fi
      fi
    done < <(jq -c '.entries | reverse | .[]' "$manifest")
  done
  (( any )) || say "   = nothing recorded"
}

cmd_uninstall() {
  local skip_system=0
  while (( $# )); do
    case $1 in
      --skip-system) skip_system=1; shift ;;
      *) usage_error "unexpected argument '$1'" ;;
    esac
  done
  confirm_irreversible "Uninstalling $KARMA_NAME"
  (( OPT_DRY_RUN )) || karma_lock
  UNINSTALL_STEPS=()
  UNINSTALL_NOTES=()
  UNINSTALL_ATTIC=$KARMA_STATE_DIR/uninstalled/$(date -u +%Y%m%dT%H%M%SZ)
  (( OPT_DRY_RUN )) && say "$KARMA_NAME uninstall: dry run, nothing will change"

  un_home
  if (( skip_system )); then
    say "4. System: skipped (--skip-system)"
  else
    if (( ! OPT_DRY_RUN )); then
      need sudo
      sudo -v || die "$EXIT_FAIL" "sudo is needed for the system part (or use --skip-system)"
    fi
    un_system
  fi

  local jid=null
  if (( ! OPT_DRY_RUN )); then
    jid=$(journal_new_id)
    journal_record "$jid" "uninstall: ${#UNINSTALL_STEPS[@]} step(s)" '{}' \
      "$(jq -cn --arg a "$UNINSTALL_ATTIC" '{moved_to: $a}')" null
    jid="\"$jid\""
    say "Done: ${#UNINSTALL_STEPS[@]} step(s). Log out (or reboot) to leave the $KARMA_NAME session."
    say "To install again: $KARMA_ROOT/install.sh"
  else
    say "Dry run: ${#UNINSTALL_STEPS[@]} step(s) planned, none made."
  fi
  jq -n --argjson j "$jid" --arg attic "$UNINSTALL_ATTIC" \
    --argjson steps "$(json_array "${UNINSTALL_STEPS[@]}")" --argjson notes "$(json_array "${UNINSTALL_NOTES[@]}")" \
    '{journal_id: $j, moved_to: $attic, steps: $steps, notes: $notes}' | emit
}
