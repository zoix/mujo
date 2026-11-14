# karma: environment for every zsh (login, interactive or not).
# ~/.zshenv only sets ZDOTDIR; zsh then reads this file.

typeset -U path PATH
path=("$HOME/.local/bin" $path)

export FZF_DEFAULT_OPTS_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/fzf/karma.fzfrc"
