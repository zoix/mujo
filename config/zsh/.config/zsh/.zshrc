# mujo: interactive zsh. No framework; plugins come from the Arch repos.
# The aliases are in aliases.zsh. Personal settings (more aliases, tool hooks,
# PATH) go in local.zsh next to this file. install.sh creates it once and never touches it again.

# Colours generated from design/tokens.json by `mujo theme build`.
[[ -r $ZDOTDIR/mujo-theme.zsh ]] && source "$ZDOTDIR/mujo-theme.zsh"

# History: shared between sessions, no duplicates, kept out of $HOME.
HISTFILE="${XDG_STATE_HOME:-$HOME/.local/state}/zsh/history"
[[ -d ${HISTFILE:h} ]] || mkdir -p "${HISTFILE:h}"
HISTSIZE=50000
SAVEHIST=50000
setopt share_history extended_history hist_ignore_all_dups hist_ignore_space
setopt hist_reduce_blanks hist_verify

setopt auto_cd interactive_comments no_beep
bindkey -e

# Completion (mujo's own completion lives in functions/).
fpath=("$ZDOTDIR/functions" $fpath)
autoload -Uz compinit
_mujo_cache="${XDG_CACHE_HOME:-$HOME/.cache}/zsh"
[[ -d $_mujo_cache ]] || mkdir -p "$_mujo_cache"
compinit -d "$_mujo_cache/zcompdump"
unset _mujo_cache
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'

# fzf key bindings: Ctrl-T files, Ctrl-R history, Alt-C directories.
# Its colours come from FZF_DEFAULT_OPTS_FILE (set in .zshenv).
(( $+commands[fzf] )) && source <(fzf --zsh)

# Up with something typed opens the same history list as Ctrl-R, already
# searching for it. On an empty line, and while stepping back from one, Up
# and Down go through the history one command at a time as usual.
if (( $+widgets[fzf-history-widget] )); then
  _mujo_up() {
    if [[ -z $BUFFER || $BUFFER == *$'\n'* ]] \
      || { (( _mujo_stepping )) && [[ $LASTWIDGET == (_mujo_up|down-line-or-history) ]]; }; then
      _mujo_stepping=1
      zle up-line-or-history
    else
      _mujo_stepping=0
      zle fzf-history-widget
    fi
  }
  zle -N _mujo_up
  bindkey '^[[A' _mujo_up
  bindkey '^[OA' _mujo_up
fi

[[ -r /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh ]] \
  && source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh

source "$ZDOTDIR/prompt.zsh"

[[ -r $ZDOTDIR/aliases.zsh ]] && source "$ZDOTDIR/aliases.zsh"
[[ -r $ZDOTDIR/local.zsh ]] && source "$ZDOTDIR/local.zsh"

# Syntax highlighting must be loaded last, after every widget is defined.
[[ -r /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]] \
  && source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
