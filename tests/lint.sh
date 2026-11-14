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

shell_files=(install.sh bin/karma lib/*.sh tests/*.sh)

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
if XDG_CONFIG_HOME=$sbx/config XDG_STATE_HOME=$sbx/state bin/karma theme build >/dev/null \
   && XDG_CONFIG_HOME=$sbx/config XDG_STATE_HOME=$sbx/state bin/karma theme check; then
  :
else
  fail=1
fi

step "Lua syntax (config/hypr and the generated karma_tokens.lua)"
if command -v luac >/dev/null; then
  lua_ok=1
  for f in config/hypr/.config/hypr/*.lua "$sbx/config/hypr/karma_tokens.lua"; do
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

step "zsh syntax (config/zsh and the generated karma-theme.zsh)"
if command -v zsh >/dev/null; then
  zsh_ok=1
  while IFS= read -r -d '' f; do
    zsh -n -- "$f" || { zsh_ok=0; fail=1; }
  done < <(find config/zsh -type f -print0)
  zsh -n -- "$sbx/config/zsh/karma-theme.zsh" || { zsh_ok=0; fail=1; }
  (( zsh_ok )) && echo ok
else
  skipped+=("zsh syntax (pacman -S zsh)")
  echo "skipped: zsh is not installed"
fi

step "qmllint (generated Tokens.qml)"
qmllint=$(command -v qmllint || echo /usr/lib/qt6/bin/qmllint)
if [[ ! -x $qmllint ]]; then
  skipped+=("qmllint (pacman -S qt6-declarative)")
  echo "skipped: qmllint not found"
elif ! pacman -Q quickshell >/dev/null 2>&1; then
  skipped+=("qmllint (needs quickshell installed for its imports)")
  echo "skipped: quickshell is not installed, so its QML module cannot be resolved"
else
  "$qmllint" "$sbx/config/quickshell/karma/theme/Tokens.qml" && echo ok || fail=1
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
