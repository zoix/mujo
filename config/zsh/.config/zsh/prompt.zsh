# karma prompt: hand-written, no starship.
#
#   ~/karma  main +1 *2 ?1 ⇡1   4s  ✘ 1
#   ❯
#
# Line 1: directory, git branch and status, duration of commands that took
# 3 s or more, exit code if it was not 0. Line 2: the prompt character, in the
# accent colour, or the error colour after a failure.
# Colours are the token roles in KARMA_COLOR (karma-theme.zsh). On the Linux
# console, which has no 24-bit colour, the ANSI slots are used instead; the
# console palette that install.sh sets maps magenta to the accent.

zmodload zsh/datetime
autoload -Uz add-zsh-hook

typeset -gA _karma_c
if [[ $TERM == linux || -z ${KARMA_COLOR[accent]:-} ]]; then
  _karma_c=(accent magenta text white muted 8 success green warning yellow error red info blue)
  _karma_char='>'
  _karma_err_glyph='x'
  _karma_git_glyph=''
else
  _karma_c=("${(@kv)KARMA_COLOR}")
  _karma_char='❯'
  _karma_err_glyph='✘'
  _karma_git_glyph=' '
fi

typeset -g _karma_cmd_start=0 _karma_took='' _karma_git=''

_karma_preexec() {
  _karma_cmd_start=$EPOCHREALTIME
}

# Branch and status from one `git status` call.
_karma_git_status() {
  _karma_git=''
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
  local s="%F{${_karma_c[accent]}}${_karma_git_glyph}${branch}%f"
  (( staged ))    && s+=" %F{${_karma_c[success]}}+${staged}%f"
  (( unstaged ))  && s+=" %F{${_karma_c[warning]}}*${unstaged}%f"
  (( untracked )) && s+=" %F{${_karma_c[muted]}}?${untracked}%f"
  (( ahead ))     && s+=" %F{${_karma_c[info]}}⇡${ahead}%f"
  (( behind ))    && s+=" %F{${_karma_c[info]}}⇣${behind}%f"
  _karma_git=$s
}

_karma_precmd() {
  local code=$?
  _karma_took=''
  if (( _karma_cmd_start > 0 )); then
    local secs=$(( EPOCHREALTIME - _karma_cmd_start ))
    _karma_cmd_start=0
    if (( secs >= 3 )); then
      local -i s=$secs
      if (( s >= 3600 )); then
        _karma_took="$(( s / 3600 ))h$(( s % 3600 / 60 ))m"
      elif (( s >= 60 )); then
        _karma_took="$(( s / 60 ))m$(( s % 60 ))s"
      else
        _karma_took="${s}s"
      fi
    fi
  fi
  _karma_git_status

  local line1="%F{${_karma_c[info]}}%B%~%b%f"
  [[ -n $_karma_git ]] && line1+="  ${_karma_git}"
  [[ -n $_karma_took ]] && line1+="  %F{${_karma_c[muted]}}${_karma_took}%f"
  (( code )) && line1+="  %F{${_karma_c[error]}}${_karma_err_glyph} ${code}%f"

  PROMPT=$'\n'"${line1}"$'\n'"%(?.%F{${_karma_c[accent]}}.%F{${_karma_c[error]}})${_karma_char}%f "
}

add-zsh-hook preexec _karma_preexec
add-zsh-hook precmd _karma_precmd
