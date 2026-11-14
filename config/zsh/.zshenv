# karma: keep zsh's files in ~/.config/zsh. Read by every zsh, so keep it small.
# zsh reads only this one .zshenv, so it loads the one in ZDOTDIR itself.
export ZDOTDIR="${XDG_CONFIG_HOME:-$HOME/.config}/zsh"
[[ -r $ZDOTDIR/.zshenv ]] && source "$ZDOTDIR/.zshenv"
