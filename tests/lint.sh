#!/usr/bin/env bash
# Run every check: syntax, shellcheck, bats, theme check (in a sandbox),
# Lua and zsh syntax of the configs, qmllint.
# Usage: tests/lint.sh        Exit 0 only if everything that can run passes.
set -euo pipefail

repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd -- "$repo"
fail=0
skipped=()

step() { printf '\n== %s\n' "$*"; }

shell_files=(install.sh bin/mujo lib/*.sh tests/*.sh tests/stubs/*)

step "bash syntax"
for f in "${shell_files[@]}"; do bash -n "$f" || fail=1; done
echo ok

step "shellcheck"
if command -v shellcheck >/dev/null; then
  shellcheck -x "${shell_files[@]}" tests/*.bash && echo ok || fail=1
else
  skipped+=("shellcheck (pacman -S shellcheck)")
  echo "skipped: shellcheck is not installed"
fi

step "bats"
if command -v bats >/dev/null; then
  bats tests/ || fail=1
else
  skipped+=("bats (pacman -S bats)")
  echo "skipped: bats is not installed"
fi

step "theme build + check (sandboxed)"
sbx=$(mktemp -d)
trap 'rm -rf "$sbx"' EXIT
if XDG_CONFIG_HOME=$sbx/config XDG_STATE_HOME=$sbx/state bin/mujo theme build >/dev/null \
   && XDG_CONFIG_HOME=$sbx/config XDG_STATE_HOME=$sbx/state bin/mujo theme check; then
  :
else
  fail=1
fi

step "Lua syntax (config/hypr and the generated mujo_tokens.lua)"
if command -v luac >/dev/null; then
  lua_ok=1
  for f in config/hypr/.config/hypr/*.lua "$sbx/config/hypr/mujo_tokens.lua"; do
    luac -p -- "$f" || { lua_ok=0; fail=1; }
  done
  (( lua_ok )) && echo ok
else
  skipped+=("Lua syntax (pacman -S lua)")
  echo "skipped: luac is not installed"
fi

step "Hyprland --verify-config (installed layout: linked modules, generated tokens, host.lua)"
if command -v Hyprland >/dev/null; then
  hypr=$sbx/config/hypr
  for f in config/hypr/.config/hypr/*.lua; do ln -s "$repo/$f" "$hypr/$(basename "$f")"; done
  printf 'hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })\n' >"$hypr/host.lua"
  out=$(cd "$sbx" && XDG_CONFIG_HOME=$sbx/config timeout 30 Hyprland --verify-config -c "$hypr/hyprland.lua" 2>&1 \
    | sed -n '/Config parsing result/,$p') || true
  if grep -qx 'config ok' <<<"$out"; then echo ok; else printf '%s\n' "$out"; fail=1; fi
else
  skipped+=("Hyprland --verify-config (Hyprland not installed)")
  echo "skipped: Hyprland is not installed"
fi

step "zsh syntax (config/zsh and the generated mujo-theme.zsh)"
if command -v zsh >/dev/null; then
  zsh_ok=1
  while IFS= read -r -d '' f; do
    zsh -n -- "$f" || { zsh_ok=0; fail=1; }
  done < <(find config/zsh -type f -print0)
  zsh -n -- "$sbx/config/zsh/mujo-theme.zsh" || { zsh_ok=0; fail=1; }
  (( zsh_ok )) && echo ok
else
  skipped+=("zsh syntax (pacman -S zsh)")
  echo "skipped: zsh is not installed"
fi

step "tmux config (tmux.conf and the generated mujo-theme.conf load without errors)"
if command -v tmux >/dev/null; then
  # A private server and a private home, so the real tmux is never touched.
  mkdir -p "$sbx/home/.config/tmux"
  cp config/tmux/.config/tmux/tmux.conf "$sbx/config/tmux/mujo-theme.conf" "$sbx/home/.config/tmux/"
  tmux_sock=$sbx/tmux.sock
  if out=$(HOME=$sbx/home TMUX='' tmux -S "$tmux_sock" -f /dev/null new-session -d -s lint \; \
             source-file "$sbx/home/.config/tmux/tmux.conf" 2>&1) && [[ -z $out ]]; then
    echo ok
  else
    printf '%s\n' "$out"; fail=1
  fi
  tmux -S "$tmux_sock" kill-server 2>/dev/null || true
else
  skipped+=("tmux config (pacman -S tmux)")
  echo "skipped: tmux is not installed"
fi

step "Quickshell tokens (generated tokens.json has every value Tokens.qml reads)"
tokens_json=$sbx/config/quickshell/mujo/theme/tokens.json
missing=$(grep -oE ': t\.[A-Za-z]+$' config/quickshell/.config/quickshell/mujo/theme/Tokens.qml | sed 's/.*t\.//' \
  | while read -r key; do jq -e --arg k "$key" 'has($k)' "$tokens_json" >/dev/null 2>&1 || echo "$key"; done)
if [[ -z $missing ]]; then echo ok; else echo "not in tokens.json: $missing"; fail=1; fi

step "QML syntax (config/quickshell)"
# The Qt 6 tool by full path: a `qmlformat` on PATH may be Qt 5's, which
# rejects typed function signatures.
qmlformat=/usr/lib/qt6/bin/qmlformat
if [[ -x $qmlformat ]]; then
  qml_ok=1
  while IFS= read -r -d '' f; do
    "$qmlformat" "$f" >/dev/null 2>&1 || { echo "syntax error: $f"; qml_ok=0; fail=1; }
  done < <(find config/quickshell -name '*.qml' -print0)
  (( qml_ok )) && echo ok
else
  skipped+=("QML syntax (pacman -S qt6-declarative)")
  echo "skipped: qmlformat not found"
fi

echo
if (( ${#skipped[@]} )); then
  printf 'Skipped: %s\n' "${skipped[@]}"
fi
if (( fail )); then
  echo "RESULT: FAIL"
  exit 1
fi
echo "RESULT: PASS${skipped:+ (with skips)}"
