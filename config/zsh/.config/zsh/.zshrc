# karma: interactive zsh. No framework; plugins come from the Arch repos.
# Personal settings (aliases, tool hooks, PATH) go in local.zsh next to this
# file. install.sh creates it once and never touches it again.

# Colours generated from design/tokens.json by `karma theme build`.
[[ -r $ZDOTDIR/karma-theme.zsh ]] && source "$ZDOTDIR/karma-theme.zsh"

# History: shared between sessions, no duplicates, kept out of $HOME.
HISTFILE="${XDG_STATE_HOME:-$HOME/.local/state}/zsh/history"
[[ -d ${HISTFILE:h} ]] || mkdir -p "${HISTFILE:h}"
HISTSIZE=50000
SAVEHIST=50000
setopt share_history extended_history hist_ignore_all_dups hist_ignore_space
setopt hist_reduce_blanks hist_verify

setopt auto_cd interactive_comments no_beep
bindkey -e

# Completion (karma's own completion lives in functions/).
fpath=("$ZDOTDIR/functions" $fpath)
autoload -Uz compinit
_karma_cache="${XDG_CACHE_HOME:-$HOME/.cache}/zsh"
[[ -d $_karma_cache ]] || mkdir -p "$_karma_cache"
compinit -d "$_karma_cache/zcompdump"
unset _karma_cache
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'

# fzf key bindings: Ctrl-T files, Ctrl-R history, Alt-C directories.
# Its colours come from FZF_DEFAULT_OPTS_FILE (set in .zshenv).
(( $+commands[fzf] )) && source <(fzf --zsh)

[[ -r /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh ]] \
  && source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh

source "$ZDOTDIR/prompt.zsh"

[[ -r $ZDOTDIR/local.zsh ]] && source "$ZDOTDIR/local.zsh"

# Syntax highlighting must be loaded last, after every widget is defined.
[[ -r /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]] \
  && source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
