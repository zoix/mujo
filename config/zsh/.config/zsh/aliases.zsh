# mujo: short names for everyday commands. Sourced by .zshrc before
# local.zsh, so an alias defined there wins over one here. Aliases for a
# tool are only made when the tool is installed: `ls` stays `ls` without eza.

alias c="clear"

if (( $+commands[eza] )); then
  alias ls="eza --sort Name --icons=auto"
  alias l="ls"
  alias ll="ls --long"
  alias la="ls --long --all"
  alias lr="ls --long --recurse"
  alias lra="ls --long --recurse --all"
  alias lt="ls --long --tree"
  alias lta="ls --long --tree --all"
fi

if (( $+commands[nvim] )); then
  alias v="nvim"
  alias vi="nvim"
  alias vim="nvim"
fi

if (( $+commands[git] )); then
  alias gs="git status"
  alias ga="git add -A"
  alias gc="git commit -m"
  alias gcam="git commit -am"
  alias gpl="git pull"
  alias gps="git push"
  alias gck="git checkout"
  # Throw away every change and every untracked file. There is no way back.
  alias gnah="git reset --hard && git clean -df"
fi

(( $+commands[lazygit] )) && alias lg="lazygit"
(( $+commands[tmux] ))    && alias tm="tmux"
