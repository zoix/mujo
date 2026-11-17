#!/usr/bin/env bash
# install.sh: install or update mujo on Arch Linux. Safe to run again: a
# second run with the same answers changes nothing.
#
#   ./install.sh               ask a few questions, show the plan, then apply it
#   ./install.sh --dry-run     show the plan and change nothing
#   ./install.sh --yes         use the defaults, no questions (see --help)
#
# Everything it changes is listed in the plan first. Files it replaces are
# backed up to ~/.local/state/mujo/backups/<time>/ with a manifest.json.
set -euo pipefail

if (( BASH_VERSINFO[0] < 5 )); then
  echo "install.sh: needs bash 5 or newer" >&2
  exit 3
fi

REPO=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)
export MUJO_ROOT=$REPO

exec 3>&1
# shellcheck source=lib/core.sh
source "$REPO/lib/core.sh"
# shellcheck source=lib/config.sh
source "$REPO/lib/config.sh"
MUJO_CMD=install

SYSROOT=${MUJO_SYSROOT:-}
CHECKOUT=${XDG_DATA_HOME:-$HOME/.local/share}/$MUJO_NAME
LOG=$MUJO_STATE_DIR/install.log
MIN_FREE_GIB=3

DRY=0
ASSUME_YES=0
SKIP_SYSTEM=0
RETIRE_FLAG=0

usage() {
  cat <<EOF
Usage: ./install.sh [--dry-run] [--yes] [--skip-system] [--retire-old-config]

Installs $MUJO_NAME for the current user. Run it as yourself, not as root;
it uses sudo for the system part and shows every file it writes under /etc.

  --dry-run            Show the plan and change nothing
  --yes, -y            Ask no questions: take every default. Defaults never
                       remove packages and never retire an old hyprland.conf
  --skip-system        Only link configs and generate files in \$HOME; no sudo,
                       no packages, no /etc, no services
  --retire-old-config  With --yes: also retire ~/.config/hypr/hyprland.conf
                       (normally a question; see docs/install.md)
  --help, -h           Show this help

Log: ~/.local/state/$MUJO_NAME/install.log
EOF
}

while (( $# )); do
  case $1 in
    --dry-run) DRY=1 ;;
    --yes|-y) ASSUME_YES=1 ;;
    --skip-system) SKIP_SYSTEM=1 ;;
    --retire-old-config) RETIRE_FLAG=1 ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'install.sh: unknown option %s (see --help)\n' "$1" >&2; exit 2 ;;
  esac
  shift
done

# ---------------------------------------------------------------- output

STEP_N=0
CHANGES=0

step() {
  STEP_N=$((STEP_N + 1))
  printf '\n\033[1m%d. %s\033[0m\n' "$STEP_N" "$*"
}
info() { printf '   %s\n' "$*"; }
ok() { printf '   = %s\n' "$*"; }

# act DESCRIPTION CMD...: print a change and run it unless this is a dry run.
act() {
  local desc=$1
  shift
  CHANGES=$((CHANGES + 1))
  if (( DRY )); then
    printf '   + %s (dry run)\n' "$desc"
  else
    printf '   + %s\n' "$desc"
    "$@"
  fi
}

fail() {
  printf '\ninstall.sh: %s\n' "$*" >&2
  exit 1
}

is_interactive() {
  (( ! ASSUME_YES )) && [[ -t 0 ]] && [[ -r /dev/tty ]]
}

# ask VAR PROMPT DEFAULT: read an answer (the default with --yes).
ask() {
  local var=$1 prompt=$2 def=$3 reply=''
  if is_interactive; then
    read -r -p "   $prompt [$def]: " reply </dev/tty || true
  fi
  printf -v "$var" '%s' "${reply:-$def}"
}

# confirm VAR QUESTION DEFAULT(y|n): set VAR to 1 or 0.
confirm() {
  local var=$1 q=$2 def=$3 reply='' hint='y/N'
  [[ $def == y ]] && hint='Y/n'
  if is_interactive; then
    read -r -p "   $q [$hint]: " reply </dev/tty || true
  fi
  reply=${reply:-$def}
  if [[ ${reply,,} == y || ${reply,,} == yes ]]; then
    printf -v "$var" 1
  else
    printf -v "$var" 0
  fi
}

tilde() {
  local p=$1
  [[ $p == "$HOME"/* ]] && p="~${p#"$HOME"}"
  printf '%s' "$p"
}

# Strip comments and blanks from a package list.
read_list() {
  sed -e 's/#.*//' -e 's/[[:space:]]*$//' -e '/^[[:space:]]*$/d' -e 's/^[[:space:]]*//' "$1"
}

# ---------------------------------------------------------------- preflight

preflight() {
  step "Preflight"
  local problems=0
  local os=$SYSROOT/etc/os-release id=''
  # shellcheck disable=SC1090
  [[ -r $os ]] && id=$(. "$os" && echo "${ID:-}")
  if [[ $id == arch ]]; then ok "Arch Linux"; else info "x not Arch Linux ($os says '${id:-unknown}')"; problems=1; fi
  if (( EUID == 0 )); then info "x running as root: run install.sh as your own user"; problems=1; else ok "running as $USER"; fi

  local c
  for c in jq stow flock diff cmp sed find; do
    command -v "$c" >/dev/null 2>&1 || { info "x missing command: $c (sudo pacman -S --needed jq stow util-linux diffutils)"; problems=1; }
  done

  local free_kib
  free_kib=$(df --output=avail -k "$HOME" | tail -n 1 | tr -d ' ')
  if (( free_kib >= MIN_FREE_GIB * 1024 * 1024 )); then
    ok "$(( free_kib / 1024 / 1024 )) GiB free"
  else
    info "x less than $MIN_FREE_GIB GiB free in $HOME"; problems=1
  fi

  if (( ! SKIP_SYSTEM )); then
    if getent ahosts archlinux.org >/dev/null 2>&1; then ok "network is up"; else info "x network: cannot resolve archlinux.org"; problems=1; fi
    if (( DRY )); then
      ok "sudo is checked when the plan is applied"
    elif sudo -v; then
      ok "sudo works"
    else
      info "x sudo does not work for $USER"; problems=1
    fi
  fi

  if (( problems )); then
    (( DRY )) && { info "(dry run: continuing to show the plan)"; return 0; }
    fail "preflight failed; fix the items marked x and run again"
  fi
}

# ---------------------------------------------------------------- old config

OLD_CONF=$HOME/.config/hypr/hyprland.conf

# Value of a simple "key = value" line in the old hyprland.conf.
old_conf_value() {
  [[ -r $OLD_CONF ]] || return 0
  sed -n -E "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*([^#]*[^#[:space:]])?[[:space:]]*(#.*)?$/\\1/p" "$OLD_CONF" | head -n 1
}

lua_q() {
  jq -Rn --arg s "$1" '$s'
}

# Print host.lua: this machine's monitors, keyboard and lid switch, ported
# from the old hyprland.conf when there is one.
render_host_lua() {
  local layout=$1 variant=$2 options=$3
  local -a monitors=() lids=() wsrules=()
  local sens=''
  if [[ -r $OLD_CONF ]]; then
    local line name mode pos scale rest
    while IFS= read -r line; do
      line=${line%%#*}
      if [[ $line =~ ^[[:space:]]*monitor[[:space:]]*=[[:space:]]*(.*)$ ]]; then
        IFS=, read -r name mode pos scale rest <<<"${BASH_REMATCH[1]}"
        name=${name//[[:space:]]/}; mode=${mode//[[:space:]]/}
        pos=${pos//[[:space:]]/}; scale=${scale//[[:space:]]/}
        if [[ $mode == disable || $mode == disabled ]]; then
          monitors+=("hl.monitor({ output = $(lua_q "$name"), disabled = true })")
        else
          monitors+=("hl.monitor({ output = $(lua_q "$name"), mode = $(lua_q "${mode:-preferred}"), position = $(lua_q "${pos:-auto}"), scale = $(lua_q "${scale:-auto}") })${rest:+ -- not ported: ,$rest}")
        fi
      elif [[ $line =~ switch:(on|off):([^,]+),[[:space:]]*exec,[[:space:]]*hyprctl[[:space:]]+dispatch[[:space:]]+dpms[[:space:]]+(on|off)[[:space:]]+([A-Za-z0-9_-]+) ]]; then
        local state=${BASH_REMATCH[1]} sw=${BASH_REMATCH[2]} act=${BASH_REMATCH[3]} mon=${BASH_REMATCH[4]}
        sw=${sw%"${sw##*[![:space:]]}"}
        local what='opened'
        [[ $state == on ]] && what='closed'
        lids+=("hl.bind($(lua_q "switch:$state:$sw"), function() hl.dispatch(hl.dsp.dpms({ monitor = $(lua_q "$mon"), action = \"$act\" })) end, { locked = true, description = $(lua_q "Lid $what: turn $mon $act") })")
      elif [[ $line =~ moveworkspacetomonitor[[:space:]]+([0-9]+)[[:space:]]+([A-Za-z0-9_-]+) ]]; then
        wsrules+=("hl.workspace_rule({ workspace = $(lua_q "${BASH_REMATCH[1]}"), monitor = $(lua_q "${BASH_REMATCH[2]}") })")
      fi
    done <"$OLD_CONF"
    sens=$(old_conf_value sensitivity)
    [[ $sens =~ ^-?[0-9]+(\.[0-9]+)?$ ]] || sens=''
  fi
  (( ${#monitors[@]} )) || monitors=('hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })')

  cat <<EOF
-- host.lua: settings for this machine only. Written once by install.sh
-- and never overwritten; edit freely. hyprland.lua loads it last.
$( [[ -r $OLD_CONF ]] && printf -- '-- Monitor, lid and workspace lines were ported from %s.\n' "$(tilde "$OLD_CONF")" )
-- Monitors: hyprctl monitors lists names and modes.
$(printf '%s\n' "${monitors[@]}")

-- Keyboard (asked during install).
hl.config({
    input = {
        kb_layout  = $(lua_q "$layout"),
        kb_variant = $(lua_q "$variant"),
        kb_options = $(lua_q "$options"),$( [[ -n $sens ]] && printf '\n        sensitivity = %s,' "$sens" )
    },
})
EOF
  if (( ${#lids[@]} )); then
    printf '\n-- Lid switch (hyprctl devices lists switches).\n'
    printf '%s\n' "${lids[@]}"
  fi
  if (( ${#wsrules[@]} )); then
    printf '\n-- Workspaces pinned to a monitor.\n'
    printf '%s\n' "${wsrules[@]}"
  fi
}

# The lines of the old hyprland.conf and where each one went.
print_port_table() {
  [[ -r $OLD_CONF ]] || return 0
  info "What happens to each setting in $(tilde "$OLD_CONF"):"
  local line
  while IFS= read -r line; do
    local l=${line%%#*}
    [[ $l =~ [^[:space:]] ]] || continue
    local where
    case $l in
      *force_zero_scaling*|*ELECTRON_OZONE*|*OZONE_PLATFORM*|*CURSOR_SIZE*|*gnome-keyring*) where="compat.lua" ;;
      *xrdb*) where="dropped: ~/.Xresources does not exist" ;;
      *monitor*=*|*switch:*|*moveworkspacetomonitor*) where="host.lua" ;;
      *kb_layout*|*kb_variant*|*kb_options*|*sensitivity*) where="host.lua (keyboard question)" ;;
      *waybar*|*hyprpaper*|*nm-applet*|*swaync*) where="replaced by the mujo UI (phase 3)" ;;
      *'vicinae server'*) where="dropped: mujo launch replaced the Vicinae server (Vicinae itself stays installed)" ;;
      *vicinae*|*'$menu'*) where="binds.lua: SUPER+SPACE opens mujo launch" ;;
      *browser*) where="not bound; the browser question can install one" ;;
      *fileManager*) where="binds.lua: SUPER+E opens yazi in Ghostty" ;;
      *TERMINAL*|*terminal*) where="binds.lua / autostart.lua: ghostty" ;;
      *hyprshot*) where="binds.lua: mujo shot" ;;
      *bind*|*'$mainMod'*) where="binds.lua" ;;
      *bezier*|*animation*) where="animations.lua (from tokens)" ;;
      *pseudotile*) where="dropped: no longer a Hyprland option" ;;
      *gaps*|*border*|*col.*|*rounding*|*opacity*|*shadow*|*blur*|*range*|*render_power*|*color*|*size*|*passes*|*vibrancy*|*layout*|*tearing*|*preserve_split*|*wallpaper*|*logo*|*enabled*) where="look.lua (from tokens)" ;;
      *follow_mouse*|*natural_scroll*|*kb_*) where="input.lua" ;;
      *'{'*|*'}'*) continue ;;
      *) where="not ported" ;;
    esac
    printf '     %-58.58s -> %s\n' "${line#"${line%%[![:space:]]*}"}" "$where"
  done <"$OLD_CONF"
}

render_local_zsh() {
  local editor=$1
  cat <<EOF
# local.zsh: your own zsh settings. Written once by install.sh and never
# overwritten; mujo's .zshrc sources it near the end. Edit freely.

export EDITOR=$(printf '%q' "$editor")
export VISUAL=\$EDITOR
EOF
  if [[ -e $HOME/.aliases ]]; then
    printf '\n# Your aliases, kept where they were.\n[[ -r ~/.aliases ]] && source ~/.aliases\n'
  fi
  if [[ -d $HOME/.zfunc ]]; then
    printf '\n# Your completion functions.\nfpath+=(~/.zfunc)\n'
  fi
  cat <<'EOF'

# Tool hooks: each runs only if the tool is installed.
(( $+commands[zoxide] )) && eval "$(zoxide init zsh)"
(( $+commands[direnv] )) && eval "$(direnv hook zsh)"
(( $+commands[mise] ))   && eval "$(mise activate zsh)"
EOF
  local old
  old=$(readlink -f -- "$HOME/.zshrc" 2>/dev/null || true)
  if [[ -n $old && -f $old ]]; then
    printf '\n# Your previous ~/.zshrc is still at %s.\n# Copy anything else you need from it into this file.\n' "$(tilde "$old")"
  fi
}

# ---------------------------------------------------------------- questions

ANS_LAYOUT='' ANS_VARIANT='' ANS_OPTIONS='' ANS_TZ='' ANS_EDITOR='' ANS_BROWSER=''
DO_DM=0 DO_LOCALE=0 DO_RETIRE=0 DO_REMOVE=0 DO_VICINAE=0 DO_FPRINT=0
DM_CURRENT=''
REPLACED_PRESENT=()

cfg_get() {
  config_read | jq -r "$1 // empty"
}

canonical_tz() {
  local tz=$1 zi=$SYSROOT/usr/share/zoneinfo/tzdata.zi target
  if [[ -r $zi ]]; then
    target=$(awk -v n="$tz" '$1 == "L" && $3 == n { print $2; exit }' "$zi")
    [[ -n $target ]] && tz=$target
  fi
  printf '%s' "$tz"
}

detect_dm() {
  local u
  for u in ly@tty1.service ly.service gdm.service sddm.service lightdm.service lxdm.service emptty.service; do
    if systemctl is-enabled -q "$u" 2>/dev/null; then
      DM_CURRENT=$u
      return
    fi
  done
}

questions() {
  step "Questions"
  if (( ! ASSUME_YES && ! DRY )) && [[ ! -t 0 ]]; then
    fail "no terminal to ask questions on; run it in a terminal, or pass --yes to take every default"
  fi
  local def
  def=$(cfg_get '.install.keyboard.layout')
  [[ -n $def ]] || def=$(old_conf_value kb_layout)
  [[ -n $def ]] || def=$(localectl status 2>/dev/null | sed -n 's/^ *X11 Layout: //p')
  ask ANS_LAYOUT "Keyboard layout (xkb, e.g. us, de, fr)" "${def:-us}"

  def=$(cfg_get '.install.keyboard.variant')
  [[ -n $def ]] || def=$(old_conf_value kb_variant)
  ask ANS_VARIANT "Keyboard variant (empty for none, e.g. altgr-intl)" "$def"
  ANS_OPTIONS=$(cfg_get '.install.keyboard.options')
  [[ -n $ANS_OPTIONS ]] || ANS_OPTIONS=$(old_conf_value kb_options)

  def=$(cfg_get '.install.timezone')
  [[ -n $def ]] || def=$(timedatectl show -p Timezone --value 2>/dev/null || true)
  def=$(canonical_tz "${def:-UTC}")
  while :; do
    ask ANS_TZ "Time zone" "$def"
    [[ -f $SYSROOT/usr/share/zoneinfo/$ANS_TZ ]] && break
    info "unknown time zone '$ANS_TZ' (see timedatectl list-timezones)"
    is_interactive || fail "unknown time zone '$ANS_TZ'"
  done

  def=$(cfg_get '.install.editor')
  [[ -n $def ]] || def=${EDITOR:-}
  [[ -n $def ]] || { command -v nvim >/dev/null && def=nvim; }
  ask ANS_EDITOR "Editor command (nvim, helix, vim, nano, ...)" "${def:-nano}"

  def=$(cfg_get '.install.browser')
  ask ANS_BROWSER "Browser package to install (firefox, chromium, or none)" "${def:-none}"

  if (( ! SKIP_SYSTEM )); then
    detect_dm
    if [[ -n $DM_CURRENT ]]; then
      info "The login screen is $DM_CURRENT. mujo uses greetd with tuigreet."
      confirm DO_DM "Replace $DM_CURRENT with greetd at the next boot?" y
    fi
    local lang
    lang=$(localectl status 2>/dev/null | sed -n 's/^ *System Locale: LANG=//p')
    if [[ $lang != en_US.UTF-8 ]]; then
      confirm DO_LOCALE "Set the system locale to en_US.UTF-8 (now ${lang:-unset})?" y
    fi
    local p
    while IFS= read -r p; do
      pacman -Q "$p" >/dev/null 2>&1 && REPLACED_PRESENT+=("$p")
    done < <(read_list "$REPO/packages/replaced.txt")
    if (( ${#REPLACED_PRESENT[@]} )); then
      info "Installed packages that mujo replaces: ${REPLACED_PRESENT[*]}"
      confirm DO_REMOVE "Remove them (pacman -Rns)?" n
    fi
    # A fingerprint reader that sudo does not use yet. Asked, never assumed:
    # this changes how sudo checks who you are.
    if has_fingerprint_reader && ! grep -qs 'pam_fprintd' /etc/pam.d/sudo; then
      info "This machine has a fingerprint reader."
      confirm DO_FPRINT "Let sudo accept your fingerprint (the password stays as the fallback)?" n
    fi
    if pacman -Q vicinae-bin >/dev/null 2>&1 || pacman -Q vicinae >/dev/null 2>&1; then
      info "SUPER+SPACE opens mujo's launcher; Vicinae is no longer bound to a key."
      confirm DO_VICINAE "Remove Vicinae now?" n
    fi
  fi

  if [[ -e $OLD_CONF || -L $OLD_CONF ]]; then
    print_port_table
    info "Hyprland 0.57 no longer reads hyprland.conf; mujo's hyprland.lua replaces it."
    info "Retiring it removes the link (or file) after a backup; the original stays in your dotfiles."
    local owner
    if owner=$(owner_of "$OLD_CONF") && has_abs_links "${owner%%$'\t'*}" "${owner#*$'\t'}"; then
      info "It comes from stow package '${owner#*$'\t'}', which stow cannot unstow (it has absolute symlinks); only this link is removed."
    elif [[ -n $owner ]]; then
      info "It comes from stow package '${owner#*$'\t'}' in $(tilde "${owner%%$'\t'*}"); retiring unstows the whole package:"
      stow -n -v -d "${owner%%$'\t'*}" -t "$HOME" -D "${owner#*$'\t'}" 2>&1 | sed -n 's/^UNLINK: /     - ~\//p'
    fi
    if (( RETIRE_FLAG )); then
      DO_RETIRE=1
      ok "retiring it (--retire-old-config)"
    else
      confirm DO_RETIRE "Retire $(tilde "$OLD_CONF") now?" n
    fi
  fi
}

# ---------------------------------------------------------------- link plan

declare -a PKGS=()
declare -a LINK_NEW=() LINK_OK=() FILE_CONFLICT=()
declare -A UNSTOW=() UNFOLD=()
declare -a BACKUP_PATHS=()

# owner_of PATH: print "stowdir<TAB>package" if PATH (or what it resolves to)
# is a link into a stow package, mirroring PATH's place under $HOME.
owner_of() {
  local path=$1 rel resolved root
  rel=${path#"$HOME"/}
  resolved=$(readlink -f -- "$path" 2>/dev/null) || return 1
  [[ $resolved == */"$rel" ]] || return 1
  root=${resolved%/"$rel"}
  [[ -d $root ]] || return 1
  printf '%s\t%s\n' "$(dirname -- "$root")" "$(basename -- "$root")"
}

# check_ancestors PATH: find symlinked parent directories (folded by another
# stow tree) between $HOME and PATH.
check_ancestors() {
  local path=$1 rel dir='' part owner
  [[ $path == "$HOME"/* ]] || return 0
  rel=${path#"$HOME"/}
  local -a parts
  IFS=/ read -r -a parts <<<"$rel"
  unset 'parts[-1]'
  for part in "${parts[@]}"; do
    dir=${dir:+$dir/}$part
    if [[ -L $HOME/$dir ]]; then
      if owner=$(owner_of "$HOME/$dir"); then
        UNFOLD[$owner]=$HOME/$dir
      else
        fail "$(tilde "$HOME/$dir") is a symlink to $(readlink -- "$HOME/$dir") that stow does not manage. Move it aside and run again."
      fi
      return
    fi
  done
}

plan_links() {
  step "Configs to link (stow --no-folding from $(tilde "$CHECKOUT")/config)"
  local pkgdir pkg rel target src owner
  for pkgdir in "$REPO"/config/*/; do
    pkg=$(basename -- "$pkgdir")
    PKGS+=("$pkg")
    while IFS= read -r rel; do
      target=$HOME/$rel
      src=$REPO/config/$pkg/$rel
      check_ancestors "$target"
      if [[ -e $target && $(readlink -f -- "$target") == "$(readlink -f -- "$src")" ]]; then
        LINK_OK+=("$target")
      elif [[ -L $target ]]; then
        if owner=$(owner_of "$target"); then
          UNSTOW[$owner]=1
        else
          FILE_CONFLICT+=("$target")
        fi
        BACKUP_PATHS+=("$target")
        LINK_NEW+=("$target")
      elif [[ -d $target ]]; then
        fail "$(tilde "$target") is a directory where mujo links a file. Move it aside and run again."
      elif [[ -e $target ]]; then
        FILE_CONFLICT+=("$target")
        BACKUP_PATHS+=("$target")
        LINK_NEW+=("$target")
      else
        LINK_NEW+=("$target")
      fi
    done < <(cd -- "$pkgdir" && find . \( -type f -o -type l \) -printf '%P\n' | sort)
  done
  check_ancestors "$CHECKOUT"
  check_ancestors "$MUJO_STATE_DIR/x"

  ok "${#LINK_OK[@]} already linked"
  local t
  for t in "${LINK_NEW[@]}"; do info "link $(tilde "$t")"; done
  for t in "${FILE_CONFLICT[@]}"; do info "existing $(tilde "$t") will be backed up and replaced"; done
  local o
  for o in "${!UNFOLD[@]}"; do
    info "$(tilde "${UNFOLD[$o]}") is a folded link from stow package '${o#*$'\t'}' in $(tilde "${o%%$'\t'*}"):"
    info "  it becomes a real directory with one link per file (the same files stay reachable)"
  done
  for o in "${!UNSTOW[@]}"; do
    if has_abs_links "${o%%$'\t'*}" "${o#*$'\t'}"; then
      fail "stow package '${o#*$'\t'}' in $(tilde "${o%%$'\t'*}") conflicts with mujo but contains absolute symlinks, so stow cannot unstow it. Remove the conflicting links by hand and run again."
    fi
    info "stow package '${o#*$'\t'}' in $(tilde "${o%%$'\t'*}") conflicts and will be unstowed; it links:"
    stow -n -v -d "${o%%$'\t'*}" -t "$HOME" -D "${o#*$'\t'}" 2>&1 | sed -n 's/^UNLINK: /     - ~\//p'
  done
}

# Generated theme files that exist but were not written by mujo.
plan_generated_backups() {
  local id target
  while IFS=$'\t' read -r id target; do
    target=${target/#@config/${XDG_CONFIG_HOME:-$HOME/.config}}
    if [[ -e $target ]] && ! head -n 3 -- "$target" | grep -qF "Generated by '$MUJO_NAME theme build'"; then
      BACKUP_PATHS+=("$target")
      info "existing $(tilde "$target") will be backed up and replaced by the generated $id file"
    fi
  done < <(jq -r '.consumers[] | select(.scope == "user") | [.id, .target] | @tsv' "$REPO/design/consumers.json")
}

# ---------------------------------------------------------------- user steps

BACKUP_DIR=''
declare -a MANIFEST_ENTRIES=()

backup_dir() {
  if [[ -z $BACKUP_DIR ]]; then
    BACKUP_DIR=$MUJO_STATE_DIR/backups/$(date -u +%Y%m%dT%H%M%SZ)
    mkdir -p -- "$BACKUP_DIR"
  fi
}

# backup_path PATH: copy a file or symlink (as a symlink) into the backup.
backup_path() {
  local p=$1 kind dest
  backup_dir
  dest=$BACKUP_DIR/home/${p#"$HOME"/}
  mkdir -p -- "$(dirname -- "$dest")"
  if [[ -L $p ]]; then kind='symlink'; else kind='file'; fi
  cp -P -- "$p" "$dest"
  MANIFEST_ENTRIES+=("$(jq -cn --arg path "$p" --arg kind "$kind" --arg link "$(readlink -- "$p" 2>/dev/null || true)" \
    '{path: $path, kind: $kind} + (if $kind == "symlink" then {link: $link} else {} end)')")
}

backup_stow_dir() {
  local dir=$1 name
  backup_dir
  name=$(basename -- "$dir")
  [[ -e $BACKUP_DIR/stow-$name.tar ]] && return 0
  tar -C "$(dirname -- "$dir")" -cf "$BACKUP_DIR/stow-$name.tar" "$name"
  MANIFEST_ENTRIES+=("$(jq -cn --arg dir "$dir" --arg tar "stow-$name.tar" '{stow_dir: $dir, tar: $tar}')")
}

record() {
  backup_dir
  MANIFEST_ENTRIES+=("$1")
}

write_manifest() {
  [[ -n $BACKUP_DIR ]] || return 0
  printf '%s\n' "${MANIFEST_ENTRIES[@]}" | jq -s --arg time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg version "$MUJO_VERSION" '{schema_version: 1, time: $time, mujo_version: $version, entries: .}' \
    >"$BACKUP_DIR/manifest.json"
}

# do_unfold STOWDIR PACKAGE PATH: replace the folded directory link PATH with
# a real directory holding one relative link per entry, which is what stow
# itself does when it unfolds. Done by hand because stow refuses packages that
# contain absolute symlinks (installers that wrote into the folded directory
# leave those behind). The new directory is built next to PATH and swapped in,
# so a failure leaves PATH untouched.
do_unfold() {
  local dir=$1 pkg=$2 path=$3 link target tmp entry name
  backup_stow_dir "$dir"
  link=$(readlink -- "$path")
  target=$link
  [[ $target == /* ]] || target=$(dirname -- "$path")/$target
  tmp=$(mktemp -d "$(dirname -- "$path")/.mujo-unfold.XXXXXX")
  shopt -s dotglob nullglob
  for entry in "$target"/*; do
    name=$(basename -- "$entry")
    ln -s -- "$(realpath -s --relative-to="$path" -- "$entry")" "$tmp/$name"
  done
  shopt -u dotglob nullglob
  record "$(jq -cn --arg d "$dir" --arg p "$pkg" --arg path "$path" --arg link "$link" \
    '{unfolded: {stow_dir: $d, package: $p, path: $path, link: $link}}')"
  rm -f -- "$path"
  mv -T -- "$tmp" "$path"
}

# has_abs_links STOWDIR PACKAGE: true if the package contains absolute
# symlinks, which make stow refuse to touch it.
has_abs_links() {
  [[ -n $(find "$1/$2" -type l -lname '/*' -print -quit 2>/dev/null) ]]
}

do_unstow() {
  local dir=$1 pkg=$2 links
  backup_stow_dir "$dir"
  links=$(stow -n -v -d "$dir" -t "$HOME" -D "$pkg" 2>&1 | sed -n 's/^UNLINK: //p' | jq -Rsc 'split("\n") | map(select(length > 0))')
  record "$(jq -cn --arg d "$dir" --arg p "$pkg" --argjson l "$links" '{unstowed: {stow_dir: $d, package: $p, links: $l}}')"
  stow -d "$dir" -t "$HOME" -D "$pkg"
}

do_checkout_link() {
  mkdir -p -- "$(dirname -- "$CHECKOUT")"
  ln -s -- "$REPO" "$CHECKOUT"
}

do_stow() {
  stow -d "$CHECKOUT/config" -t "$HOME" --no-folding -S "${PKGS[@]}"
}

do_write_new() {
  local dest=$1 content=$2
  mkdir -p -- "$(dirname -- "$dest")"
  printf '%s\n' "$content" >"$dest"
}

# do_mime_defaults APP TYPE...: make APP the program for the file types, and
# write down which ones, so that uninstall can take exactly these back.
do_mime_defaults() {
  local app=$1
  shift
  xdg-mime default "$app" "$@"
  record "$(jq -cn --arg a "$app" '{mime_defaults: {app: $a, types: $ARGS.positional}}' --args "$@")"
}

do_retire() {
  local owner
  backup_path "$OLD_CONF"
  if owner=$(owner_of "$OLD_CONF") && ! has_abs_links "${owner%%$'\t'*}" "${owner#*$'\t'}"; then
    do_unstow "${owner%%$'\t'*}" "${owner#*$'\t'}"
  else
    rm -f -- "$OLD_CONF"
    record "$(jq -cn --arg p "$OLD_CONF" '{retired: $p}')"
  fi
}

user_steps() {
  step "Your home directory"

  # The installed checkout.
  if [[ $REPO == "$(readlink -f -- "$CHECKOUT" 2>/dev/null || true)" ]]; then
    ok "$(tilde "$CHECKOUT") is this checkout"
  elif [[ -e $CHECKOUT || -L $CHECKOUT ]]; then
    fail "$(tilde "$CHECKOUT") exists and is not this checkout ($REPO). Move it aside or run install.sh from there."
  fi

  # Unfold first: later steps write under these directories.
  local o
  for o in "${!UNFOLD[@]}"; do
    act "unfold $(tilde "${UNFOLD[$o]}") into a real directory (links into stow package '${o#*$'\t'}')" do_unfold "${o%%$'\t'*}" "${o#*$'\t'}" "${UNFOLD[$o]}"
  done
  [[ -e $CHECKOUT || -L $CHECKOUT ]] || act "link $(tilde "$CHECKOUT") -> $REPO" do_checkout_link

  # Back up everything that is about to be replaced, before anything moves.
  local p
  for p in "${BACKUP_PATHS[@]}"; do
    [[ -e $p || -L $p ]] && act "back up $(tilde "$p")" backup_path "$p"
  done
  for o in "${!UNSTOW[@]}"; do
    act "unstow conflicting package '${o#*$'\t'}' from $(tilde "${o%%$'\t'*}")" do_unstow "${o%%$'\t'*}" "${o#*$'\t'}"
  done
  local t
  for t in "${FILE_CONFLICT[@]}"; do
    act "remove $(tilde "$t") (backed up)" rm -f -- "$t"
  done
  if (( DO_RETIRE )) && [[ -e $OLD_CONF || -L $OLD_CONF ]]; then
    act "retire $(tilde "$OLD_CONF") (backed up first)" do_retire
  fi

  if (( ${#LINK_NEW[@]} )); then
    act "stow ${#LINK_NEW[@]} link(s) from packages: ${PKGS[*]}" do_stow
  else
    ok "all ${#LINK_OK[@]} config links are in place"
  fi

  # Files written once and then owned by the user.
  local host=$HOME/.config/hypr/host.lua
  if [[ -e $host ]]; then
    ok "$(tilde "$host") exists (yours; not touched)"
  else
    local content
    content=$(render_host_lua "$ANS_LAYOUT" "$ANS_VARIANT" "$ANS_OPTIONS")
    act "write $(tilde "$host") (monitors, keyboard$( [[ -r $OLD_CONF ]] && echo ', ported lines'))" do_write_new "$host" "$content"
    (( DRY )) && printf '       | %s\n' "${content//$'\n'/$'\n'       | }"
  fi
  local lz=${XDG_CONFIG_HOME:-$HOME/.config}/zsh/local.zsh
  if [[ -e $lz ]]; then
    ok "$(tilde "$lz") exists (yours; not touched)"
  else
    act "write $(tilde "$lz") (editor, your aliases, tool hooks)" do_write_new "$lz" "$(render_local_zsh "$ANS_EDITOR")"
  fi

  # Answers, kept for the next run.
  local want have
  want=$(jq -cn --arg l "$ANS_LAYOUT" --arg v "$ANS_VARIANT" --arg o "$ANS_OPTIONS" --arg tz "$ANS_TZ" \
    --arg e "$ANS_EDITOR" --arg b "$ANS_BROWSER" \
    '{keyboard: {layout: $l, variant: $v, options: $o}, timezone: $tz, editor: $e, browser: $b}')
  have=$(config_read | jq -c '.install // null')
  if [[ $want == "$have" ]]; then
    ok "answers already saved in $(tilde "$MUJO_CONFIG_FILE")"
  else
    act "save answers to $(tilde "$MUJO_CONFIG_FILE")" config_set install "$want"
  fi

  # Generated theme files.
  local pending
  pending=$("$REPO/bin/mujo" theme list --json | jq '[.data.consumers[] | select(.status != "unchanged")] | length')
  if (( pending )); then
    # No Hyprland reload: the running session may be an older Hyprland that
    # still reads hyprland.conf. The new config starts with the next login.
    act "generate $pending theme file(s): mujo theme build" env -u HYPRLAND_INSTANCE_SIGNATURE "$REPO/bin/mujo" theme build
  else
    ok "theme files are current"
  fi

  # GTK colour scheme for apps that read GSettings (libadwaita, portals).
  if command -v gsettings >/dev/null 2>&1 && [[ -S ${XDG_RUNTIME_DIR:-/run/user/$UID}/bus ]]; then
    local k v cur
    # The values follow the current mode (dark or light) from the tokens.
    local scheme gtk_theme
    scheme=$("$REPO/bin/mujo" theme show gtk.color_scheme --json 2>/dev/null | jq -r '.data.value // "prefer-dark"')
    gtk_theme=$("$REPO/bin/mujo" theme show gtk.theme --json 2>/dev/null | jq -r '.data.value // "adw-gtk3-dark"')
    for k in "color-scheme $scheme" "gtk-theme $gtk_theme"; do
      v=${k#* }
      k=${k%% *}
      cur=$(gsettings get org.gnome.desktop.interface "$k" 2>/dev/null | tr -d "'")
      if [[ $cur == "$v" ]]; then
        ok "gsettings $k is $v"
      else
        act "gsettings: $k ${cur:-unset} -> $v" gsettings set org.gnome.desktop.interface "$k" "$v"
      fi
    done
  else
    info "gsettings skipped (no session bus); settings.ini covers GTK apps"
  fi

  # Pictures open in imv and videos in mpv, instead of in the browser. Only
  # types without a choice of yours in mimeapps.list are set.
  local apps=${MUJO_SYSROOT:-}/usr/share/applications mimeapps=${XDG_CONFIG_HOME:-$HOME/.config}/mimeapps.list
  local entry app type
  local -a unset_types
  for entry in \
    "imv-dir.desktop image/png image/jpeg image/webp image/gif image/bmp image/tiff image/avif" \
    "mpv.desktop video/mp4 video/x-matroska video/webm video/quicktime video/x-msvideo video/mpeg audio/mpeg audio/flac audio/ogg audio/x-wav"; do
    app=${entry%% *}
    if [[ ! -f $apps/$app ]] || ! command -v xdg-mime >/dev/null 2>&1; then
      info "file types for ${app%.desktop} skipped (it is not installed)"
      continue
    fi
    unset_types=()
    for type in ${entry#* }; do
      grep -qs "^${type//+/\\+}=" "$mimeapps" || unset_types+=("$type")
    done
    if (( ${#unset_types[@]} )); then
      act "open ${#unset_types[@]} file type(s) with ${app%.desktop}: ${unset_types[*]}" do_mime_defaults "$app" "${unset_types[@]}"
    else
      ok "file types for ${app%.desktop} are set"
    fi
  done
}

# ---------------------------------------------------------------- system steps

SUDO_KEEPALIVE=''

sudo_keepalive() {
  (( DRY )) && return 0
  sudo -v
  ( while kill -0 "$$" 2>/dev/null; do sudo -n true 2>/dev/null; sleep 50; done ) &
  SUDO_KEEPALIVE=$!
}

stop_keepalive() {
  [[ -n $SUDO_KEEPALIVE ]] && kill "$SUDO_KEEPALIVE" 2>/dev/null || true
}

editor_package() {
  case $1 in
    nvim) echo neovim ;;
    hx|helix) echo helix ;;
    vim) echo vim ;;
    nano) echo nano ;;
    micro) echo micro ;;
    emacs) echo emacs ;;
    *) echo '' ;;
  esac
}

do_pacman_install() {
  sudo pacman -S --needed --noconfirm "$@"
}

system_packages() {
  step "Packages (official repos)"
  local -a want missing=()
  mapfile -t want < <(read_list "$REPO/packages/pacman.txt")
  local ep
  ep=$(editor_package "$ANS_EDITOR")
  [[ -n $ep ]] && want+=("$ep")
  [[ $ANS_BROWSER != none && -n $ANS_BROWSER ]] && want+=("$ANS_BROWSER")
  local p
  for p in "${want[@]}"; do
    pacman -Q "$p" >/dev/null 2>&1 || missing+=("$p")
  done
  if (( ${#missing[@]} )); then
    for p in "${missing[@]}"; do
      pacman -Si "$p" >/dev/null 2>&1 || fail "package '$p' is not in the official repos"
    done
    act "pacman -S --needed ${missing[*]}" do_pacman_install "${missing[@]}"
  else
    ok "all ${#want[@]} packages are installed"
  fi
  # Packages on mujo's list that are only installed as a dependency of
  # something else would be removed together with that something
  # (`pacman -Rns`). Marking them as explicitly installed prevents that.
  local -a asdeps=()
  for p in "${want[@]}"; do
    pacman -Qqd "$p" >/dev/null 2>&1 && asdeps+=("$p")
  done
  if (( ${#asdeps[@]} )); then
    act "mark as explicitly installed: ${asdeps[*]}" sudo pacman -D --asexplicit "${asdeps[@]}"
  else
    ok "mujo's packages are all marked as explicitly installed"
  fi
  if [[ -n $(read_list "$REPO/packages/aur.txt") ]]; then
    fail "packages/aur.txt lists packages, but the AUR bootstrap is not part of this installer yet"
  fi
}

# install_etc SRC DEST: install a file under /etc if it differs, showing the diff.
install_etc() {
  local src=$1 dest=$2 real=$SYSROOT$2
  # A folder only root may look into (polkit's rules) is read through sudo.
  local closed=0
  [[ -d ${real%/*} && ! -x ${real%/*} ]] && closed=1
  if (( closed )); then
    if sudo cmp -s -- "$src" "$real"; then
      ok "$dest is current"
      return 0
    fi
  elif [[ -r $real ]] && cmp -s -- "$src" "$real"; then
    ok "$dest is current"
    return 0
  fi
  if [[ -e $real ]] || { (( closed )) && sudo test -e "$real"; }; then
    info "changes to $dest:"
    sudo_or_cat "$real" | diff -u --label "$dest" --label "$dest (mujo)" - "$src" | sed 's/^/       /' || true
    act "install $dest (previous version backed up)" do_install_etc "$src" "$dest" 1
  else
    info "new file $dest:"
    sed 's/^/       | /' "$src"
    act "install $dest" do_install_etc "$src" "$dest" 0
  fi
}

sudo_or_cat() {
  if [[ -r $1 ]]; then cat -- "$1"; else sudo cat -- "$1"; fi
}

do_install_etc() {
  local src=$1 dest=$2 had=$3
  if (( had )); then
    backup_dir
    mkdir -p -- "$BACKUP_DIR/etc/$(dirname -- "${dest#/etc/}")"
    sudo_or_cat "$SYSROOT$dest" >"$BACKUP_DIR/etc/${dest#/etc/}"
    record "$(jq -cn --arg p "$dest" '{etc: $p, kind: "file"}')"
  else
    record "$(jq -cn --arg p "$dest" '{etc: $p, kind: "absent"}')"
  fi
  sudo install -D -m 0644 -- "$src" "$SYSROOT$dest"
}

system_files() {
  step "System files (/etc)"
  local staged=$MUJO_STATE_DIR/theme/system
  if (( DRY )) && [[ ! -f $staged/greetd/config.toml ]]; then
    info "the greetd and console palette files are generated by mujo theme build; run without --dry-run to see their diffs"
  else
    [[ -f $staged/greetd/config.toml ]] && install_etc "$staged/greetd/config.toml" /etc/greetd/config.toml
    [[ -f $staged/vtrgb/palette.vtrgb ]] && install_etc "$staged/vtrgb/palette.vtrgb" /etc/mujo/palette.vtrgb
  fi
  local before=$CHANGES
  install_etc "$REPO/system/vtrgb/mujo-vtrgb.service" /etc/systemd/system/mujo-vtrgb.service
  # Lets `mujo time auto` change the time zone without a password prompt.
  install_etc "$REPO/system/polkit/49-mujo-timezone.rules" /etc/polkit-1/rules.d/49-mujo-timezone.rules
  if (( CHANGES > before )); then
    act "systemctl daemon-reload" sudo systemctl daemon-reload
  fi
  # Lets `mujo voyager flash` write to the keyboard without a password.
  before=$CHANGES
  install_etc "$REPO/system/udev/70-mujo-voyager.rules" /etc/udev/rules.d/70-mujo-voyager.rules
  if (( CHANGES > before )); then
    act "udevadm control --reload" sudo udevadm control --reload
  fi
}

do_switch_dm() {
  sudo systemctl disable "$DM_CURRENT"
  record "$(jq -cn --arg u "$DM_CURRENT" '{display_manager_disabled: $u}')"
  sudo systemctl enable greetd.service
}

system_services() {
  step "Services"
  local u
  for u in NetworkManager.service bluetooth.service; do
    if systemctl is-enabled -q "$u" 2>/dev/null; then ok "$u is enabled"; else act "enable and start $u" sudo systemctl enable --now "$u"; fi
  done
  if systemctl is-enabled -q mujo-vtrgb.service 2>/dev/null; then
    ok "mujo-vtrgb.service is enabled"
  else
    act "enable mujo-vtrgb.service and load the console palette now" sudo systemctl enable --now mujo-vtrgb.service
  fi

  if systemctl is-enabled -q greetd.service 2>/dev/null; then
    ok "greetd.service is enabled"
  elif [[ -n $DM_CURRENT ]]; then
    if (( DO_DM )); then
      act "disable $DM_CURRENT and enable greetd.service (takes effect at the next boot)" do_switch_dm
    else
      info "kept $DM_CURRENT; greetd is installed but not enabled (two login screens cannot share tty1)"
    fi
  else
    act "enable greetd.service (takes effect at the next boot)" sudo systemctl enable greetd.service
  fi

  # NetworkManager and iwd must agree on who drives Wi-Fi.
  if systemctl is-enabled -q iwd.service 2>/dev/null \
     && ! grep -rqs '^[[:space:]]*wifi.backend[[:space:]]*=[[:space:]]*iwd' /etc/NetworkManager/; then
    info "warning: iwd.service is enabled but NetworkManager does not use the iwd backend;"
    info "         they will fight over Wi-Fi. Disable iwd or set wifi.backend=iwd."
  else
    ok "NetworkManager owns Wi-Fi (iwd is not competing)"
  fi
}

do_locale() {
  backup_dir
  mkdir -p -- "$BACKUP_DIR/etc"
  sudo_or_cat /etc/locale.gen >"$BACKUP_DIR/etc/locale.gen"
  [[ -r /etc/locale.conf ]] && cp -- /etc/locale.conf "$BACKUP_DIR/etc/locale.conf"
  record "$(jq -cn --arg l "$(localectl status | sed -n 's/^ *System Locale: //p')" '{locale_before: $l}')"
  if ! grep -q '^en_US.UTF-8 UTF-8' /etc/locale.gen; then
    sudo sed -i -E 's/^#[[:space:]]*(en_US\.UTF-8 UTF-8)[[:space:]]*$/\1/' /etc/locale.gen
  fi
  locale -a 2>/dev/null | grep -qix 'en_US.utf8' || sudo locale-gen
  sudo localectl set-locale LANG=en_US.UTF-8
}

# True if a USB device calls itself a fingerprint reader.
has_fingerprint_reader() {
  grep -qsi 'fingerprint' /sys/bus/usb/devices/*/product
}

fingerprint_enrolled() {
  command -v fprintd-list >/dev/null 2>&1 && fprintd-list "$USER" 2>/dev/null | grep -q '^ - #'
}

# Put pam_fprintd first in sudo's rules. The file is backed up and recorded,
# so `mujo uninstall` puts the old one back.
do_fprint_pam() {
  local tmp
  backup_dir
  mkdir -p -- "$BACKUP_DIR/etc/pam.d"
  sudo_or_cat /etc/pam.d/sudo >"$BACKUP_DIR/etc/pam.d/sudo"
  record "$(jq -cn '{etc: "/etc/pam.d/sudo", kind: "file"}')"
  tmp=$(mktemp)
  awk 'NR == 1 { print; print "auth\t\tsufficient\tpam_fprintd.so"; next } { print }' "$BACKUP_DIR/etc/pam.d/sudo" >"$tmp"
  sudo install -m 0644 -- "$tmp" /etc/pam.d/sudo
  rm -f -- "$tmp"
}

system_fingerprint() {
  has_fingerprint_reader || return 0
  step "Fingerprint"
  if grep -qs 'pam_fprintd' /etc/pam.d/sudo; then
    ok "sudo accepts the fingerprint (password as the fallback)"
    return 0
  fi
  if (( ! DO_FPRINT )); then
    info "sudo asks for the password only (run install.sh again to change that)"
    return 0
  fi
  pacman -Q fprintd >/dev/null 2>&1 || act "pacman -S --needed fprintd" do_pacman_install fprintd
  if (( DRY )); then
    act "enroll a finger if none is enrolled, then add the fingerprint to /etc/pam.d/sudo" true
    return 0
  fi
  if ! fingerprint_enrolled && is_interactive; then
    info "Touch the reader again and again until it says enroll-completed."
    fprintd-enroll </dev/tty || true
  fi
  if fingerprint_enrolled; then
    act "add the fingerprint to /etc/pam.d/sudo (the password stays as the fallback)" do_fprint_pam
  else
    info "no finger is enrolled, so sudo was left as it is; run 'fprintd-enroll', then install.sh again"
  fi
}

system_settings() {
  step "Locale, time zone and login shell"
  local lang
  lang=$(localectl status 2>/dev/null | sed -n 's/^ *System Locale: LANG=//p')
  if [[ $lang == en_US.UTF-8 ]]; then
    ok "locale is en_US.UTF-8"
  elif (( DO_LOCALE )); then
    act "generate en_US.UTF-8 and set LANG=en_US.UTF-8 (was ${lang:-unset}; applies at the next login)" do_locale
  else
    info "kept LANG=${lang:-unset}"
  fi

  local tz_now
  tz_now=$(timedatectl show -p Timezone --value 2>/dev/null || true)
  if [[ $tz_now == "$ANS_TZ" ]] || cmp -s -- "/usr/share/zoneinfo/$tz_now" "/usr/share/zoneinfo/$ANS_TZ"; then
    ok "time zone is $ANS_TZ${tz_now:+ ($tz_now)}"
  else
    act "set the time zone: ${tz_now:-unset} -> $ANS_TZ" sudo timedatectl set-timezone "$ANS_TZ"
  fi

  local sh
  sh=$(getent passwd "$USER" | cut -d: -f7)
  if [[ $(basename -- "$sh") == zsh ]]; then
    ok "login shell is $sh"
  else
    act "set the login shell: $sh -> /usr/bin/zsh" sudo chsh -s /usr/bin/zsh "$USER"
  fi
}

do_remove() {
  if sudo pacman -Rns --noconfirm "$@"; then
    record "$(json_array "$@" | jq -c '{packages_removed: .}')"
  else
    info "pacman could not remove: $* (another package may depend on them); continuing"
  fi
}

system_removals() {
  local -a pkgs=()
  (( DO_REMOVE )) && pkgs+=("${REPLACED_PRESENT[@]}")
  if (( DO_VICINAE )); then
    local v
    for v in vicinae-bin vicinae; do pacman -Q "$v" >/dev/null 2>&1 && pkgs+=("$v"); done
  fi
  (( ${#pkgs[@]} )) || return 0
  step "Packages to remove (cannot be undone by mujo)"
  act "pacman -Rns ${pkgs[*]}" do_remove "${pkgs[@]}"
}

# ---------------------------------------------------------------- main

main() {
  if (( ! DRY )); then
    mkdir -p -- "$MUJO_STATE_DIR"
    exec > >(tee -a "$LOG") 2>&1
    exec 3>&1
    printf '\n===== %s install.sh %s (%s)\n' "$MUJO_NAME" "$MUJO_VERSION" "$(date -Is)"
  fi
  printf '%s installer%s\n' "$MUJO_NAME" "$( (( DRY )) && echo ': dry run, nothing will change')"

  preflight
  questions
  plan_links
  plan_generated_backups

  if (( ! DRY )) && is_interactive; then
    local go
    printf '\n'
    confirm go "Apply the plan above?" y
    (( go )) || { info "nothing changed"; exit 0; }
  fi

  if (( ! SKIP_SYSTEM )); then
    trap stop_keepalive EXIT
    sudo_keepalive
    system_packages
  fi
  user_steps
  if (( ! SKIP_SYSTEM )); then
    system_files
    system_services
    system_settings
    system_fingerprint
    system_removals
  fi
  write_manifest

  printf '\n'
  if (( CHANGES == 0 )); then
    echo "Nothing to do: $MUJO_NAME is installed and up to date."
  elif (( DRY )); then
    echo "Dry run: $CHANGES change(s) planned, none made."
  else
    echo "Done: $CHANGES change(s)."
    [[ -n $BACKUP_DIR ]] && echo "Backups and manifest: $(tilde "$BACKUP_DIR")"
    echo "Log: $(tilde "$LOG")"
    (( SKIP_SYSTEM )) || echo "Reboot to log in through greetd into the mujo session."
  fi
}

main
