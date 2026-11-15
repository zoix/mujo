# shellcheck shell=bash
# mujo pkg: find packages by fuzzy search and install or remove them. Covers
# the official repositories (pacman) and, with an AUR helper, the AUR.

mujo_register pkg "Search, install and remove packages (pacman and AUR)"

help_pkg() {
  cat <<EOF
Usage: $MUJO_NAME pkg [install] [--window]
       $MUJO_NAME pkg remove [--window]
       $MUJO_NAME pkg list [--aur]

install  Type to search every package in the official repositories and, if
         yay or paru is installed, the AUR. The right side shows the
         description. Tab marks several, Enter installs what is marked
         (official ones with 'sudo pacman -S', AUR ones with the helper).
         Installed packages are marked with a star.
remove   The same list for the packages you installed yourself; Enter removes
         what is marked, with dependencies nothing else needs
         ('sudo pacman -Rns'). pacman shows the full list and asks first.
list     The package names the install picker searches (--aur: only the AUR).

Installing and removing are recorded in the journal; they cannot be undone
by '$MUJO_NAME undo'.
EOF
}

pkg_helper() {
  local h
  for h in yay paru; do
    if command -v "$h" >/dev/null 2>&1; then
      echo "$h"
      return 0
    fi
  done
  return 1
}

# pkg_names: "SOURCE<TAB>NAME<TAB>MARK<TAB>DISPLAY" per line; MARK is "*" if
# installed, DISPLAY is the line the picker shows.
pkg_names() {
  local helper
  {
    pacman -Slq 2>/dev/null | sed 's/^/repo\t/'
    if helper=$(pkg_helper); then
      "$helper" -Slqa 2>/dev/null | sed 's/^/aur\t/'
    fi
  } | gawk -F'\t' 'BEGIN { OFS = "\t"; while (("pacman -Qq 2>/dev/null" | getline name) > 0) have[name] = 1 }
      !seen[$2]++ { mark = (($2 in have) ? "*" : " ")
        print $1, $2, mark, sprintf("%s %-44s %s", mark, $2, ($1 == "aur" ? "AUR" : "")) }'
}

pkg_record() {
  local verb=$1
  shift
  local jid
  jid=$(journal_new_id)
  journal_record "$jid" "pkg $verb: $*" '{}' "$(json_array "$@" | jq -c --arg v "$verb" '{($v): .}')" null
}

pkg_cmd_install() {
  (( $# == 0 )) || usage_error "unexpected argument '$1'"
  tui_require
  need pacman gawk
  local helper preview
  helper=$(pkg_helper) || helper=""
  # {1} is the source, {2} the name.
  preview='if [ {1} = repo ]; then pacman -Si {2}; else '"${helper:-false}"' -Si {2}; fi 2>/dev/null'
  local -a rows=() repo=() aur=()
  mapfile -t rows < <(pkg_names | tui_pick --multi --delimiter '\t' --with-nth 4 \
    --prompt 'Install > ' --header $'Tab: mark several\nEnter: install   * = installed' \
    --preview "$preview" --preview-window 'right,55%,wrap' || true)
  local row source name
  for row in "${rows[@]}"; do
    IFS=$'\t' read -r source name _ <<<"$row"
    if [[ $source == aur ]]; then aur+=("$name"); else repo+=("$name"); fi
  done
  if (( ${#repo[@]} + ${#aur[@]} == 0 )); then
    say "Nothing chosen."
    return 0
  fi
  local ok=1
  if (( ${#repo[@]} )); then
    say "sudo pacman -S --needed ${repo[*]}"
    if sudo pacman -S --needed "${repo[@]}"; then pkg_record install "${repo[@]}"; else ok=0; fi
  fi
  if (( ${#aur[@]} )); then
    say "$helper -S ${aur[*]}"
    if "$helper" -S "${aur[@]}"; then pkg_record install "${aur[@]}"; else ok=0; fi
  fi
  (( ok )) || warn "something was not installed; see the messages above"
  # In its own window, wait so that the result can be read.
  [[ -n ${MUJO_WINDOW:-} ]] && tui_pause
  (( ok )) || exit "$EXIT_FAIL"
}

pkg_cmd_remove() {
  (( $# == 0 )) || usage_error "unexpected argument '$1'"
  tui_require
  need pacman
  local -a names=()
  mapfile -t names < <(pacman -Qqe 2>/dev/null | tui_pick --multi --prompt 'Remove > ' \
    --header $'Tab: mark several\nEnter: remove (pacman asks first)' \
    --preview 'pacman -Qi {1} 2>/dev/null' --preview-window 'right,55%,wrap' || true)
  if (( ${#names[@]} == 0 )); then
    say "Nothing chosen."
    return 0
  fi
  say "sudo pacman -Rns ${names[*]}"
  local ok=1
  if sudo pacman -Rns "${names[@]}"; then pkg_record remove "${names[@]}"; else ok=0; fi
  # In its own window, wait so that the result can be read.
  [[ -n ${MUJO_WINDOW:-} ]] && tui_pause
  (( ok )) || exit "$EXIT_FAIL"
}

cmd_pkg() {
  local sub=${1:-install}
  (( $# )) && shift
  mujo_set_cmd "pkg $sub"
  case $sub in
    install) pkg_cmd_install "$@" ;;
    remove) pkg_cmd_remove "$@" ;;
    list)
      local only_aur=0
      while (( $# )); do
        case $1 in
          --aur) only_aur=1; shift ;;
          *) usage_error "unexpected argument '$1'" ;;
        esac
      done
      need pacman gawk
      local rows
      rows=$(pkg_names | { if (( only_aur )); then gawk -F'\t' '$1 == "aur"'; else cat; fi; })
      gawk -F'\t' '{ print $3, $2, ($1 == "aur" ? "(AUR)" : "") }' <<<"$rows" | say_stream
      jq -cRn '{packages: [inputs | select(length > 0) | split("\t")
        | {name: .[1], source: .[0], installed: (.[2] == "*")}]}' <<<"$rows" | emit
      ;;
    *) usage_error "unknown subcommand '$sub'" ;;
  esac
}
