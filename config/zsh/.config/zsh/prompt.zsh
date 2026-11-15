# mujo prompt: hand-written, no starship.
#
#   ~/mujo  main +1 *2 ?1 ⇡1   4s  ✘ 1
#   ❯
#
# Line 1: directory, git branch and status, duration of commands that took
# 3 s or more, exit code if it was not 0. Line 2: the prompt character, in the
# accent colour, or the error colour after a failure.
# Colours are the token roles in MUJO_COLOR (mujo-theme.zsh). On the Linux
# console, which has no 24-bit colour, the ANSI slots are used instead; the
# console palette that install.sh sets maps magenta to the accent.

zmodload zsh/datetime
autoload -Uz add-zsh-hook

typeset -gA _mujo_c
if [[ $TERM == linux || -z ${MUJO_COLOR[accent]:-} ]]; then
  _mujo_c=(accent magenta text white muted 8 success green warning yellow error red info blue)
  _mujo_char='>'
  _mujo_err_glyph='x'
  _mujo_git_glyph=''
else
  _mujo_c=("${(@kv)MUJO_COLOR}")
  _mujo_char='❯'
  _mujo_err_glyph='✘'
  _mujo_git_glyph=' '
fi

typeset -g _mujo_cmd_start=0 _mujo_took='' _mujo_git=''

_mujo_preexec() {
  _mujo_cmd_start=$EPOCHREALTIME
}

# Branch and status from one `git status` call.
_mujo_git_status() {
  _mujo_git=''
  local line branch='' ahead=0 behind=0 staged=0 unstaged=0 untracked=0
  local -a lines
  lines=("${(@f)$(command git status --porcelain=v2 --branch 2>/dev/null)}") || return
  (( ${#lines} )) && [[ -n ${lines[1]} ]] || return
  for line in "${lines[@]}"; do
    case $line in
      '# branch.head '*) branch=${line#\# branch.head } ;;
      '# branch.oid '*) [[ -z $branch || $branch == '(detached)' ]] && branch=${${line#\# branch.oid }[1,7]} ;;
      '# branch.ab '*)
        local ab=${line#\# branch.ab }
        ahead=${${ab%% *}#+}
        behind=${${ab##* }#-}
        ;;
      '? '*) (( untracked++ )) ;;
      [12u]' '*)
        [[ ${line[3]} != . ]] && (( staged++ ))
        [[ ${line[4]} != . ]] && (( unstaged++ ))
        ;;
    esac
  done
  [[ $branch == '(detached)' ]] && branch='detached'
  local s="%F{${_mujo_c[accent]}}${_mujo_git_glyph}${branch}%f"
  (( staged ))    && s+=" %F{${_mujo_c[success]}}+${staged}%f"
  (( unstaged ))  && s+=" %F{${_mujo_c[warning]}}*${unstaged}%f"
  (( untracked )) && s+=" %F{${_mujo_c[muted]}}?${untracked}%f"
  (( ahead ))     && s+=" %F{${_mujo_c[info]}}⇡${ahead}%f"
  (( behind ))    && s+=" %F{${_mujo_c[info]}}⇣${behind}%f"
  _mujo_git=$s
}

_mujo_precmd() {
  local code=$?
  _mujo_took=''
  if (( _mujo_cmd_start > 0 )); then
    local secs=$(( EPOCHREALTIME - _mujo_cmd_start ))
    _mujo_cmd_start=0
    if (( secs >= 3 )); then
      local -i s=$secs
      if (( s >= 3600 )); then
        _mujo_took="$(( s / 3600 ))h$(( s % 3600 / 60 ))m"
      elif (( s >= 60 )); then
        _mujo_took="$(( s / 60 ))m$(( s % 60 ))s"
      else
        _mujo_took="${s}s"
      fi
    fi
  fi
  _mujo_git_status

  local line1="%F{${_mujo_c[info]}}%B%~%b%f"
  [[ -n $_mujo_git ]] && line1+="  ${_mujo_git}"
  [[ -n $_mujo_took ]] && line1+="  %F{${_mujo_c[muted]}}${_mujo_took}%f"
  (( code )) && line1+="  %F{${_mujo_c[error]}}${_mujo_err_glyph} ${code}%f"

  PROMPT=$'\n'"${line1}"$'\n'"%(?.%F{${_mujo_c[accent]}}.%F{${_mujo_c[error]}})${_mujo_char}%f "
}

add-zsh-hook preexec _mujo_preexec
add-zsh-hook precmd _mujo_precmd
