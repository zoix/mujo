#!/usr/bin/env bats
# install.sh, user part only (--skip-system): no sudo, no packages, no /etc.
# Every test runs in a throwaway $HOME with an old stow tree like the one on
# the target laptop: a hyprland.conf package and a folded ~/.local/bin.

load helpers

setup() {
  export HOME=$BATS_TEST_TMPDIR/home
  unset XDG_CONFIG_HOME XDG_STATE_HOME XDG_DATA_HOME XDG_CACHE_HOME KARMA_SYSROOT KARMA_ROOT
  unset HYPRLAND_INSTANCE_SIGNATURE WAYLAND_DISPLAY DBUS_SESSION_BUS_ADDRESS
  export XDG_RUNTIME_DIR=$BATS_TEST_TMPDIR/run
  mkdir -p "$HOME/.local" "$HOME/.config" "$XDG_RUNTIME_DIR"
  INSTALL="$KARMA_REPO/install.sh"
}

old_dotfiles() {
  local d=$HOME/dots
  mkdir -p "$d/hypr/.config/hypr" "$d/bin/.local/bin"
  cat >"$d/hypr/.config/hypr/hyprland.conf" <<'EOF'
monitor = eDP-1,2880x1920@120,0x0,2
monitor = DP-1,5120x2160@60,2880x0,1.6
bindl = , switch:on:Lid Switch, exec, hyprctl dispatch dpms off eDP-1
bindl = , switch:off:Lid Switch, exec, hyprctl dispatch dpms on eDP-1
exec-once = sh -lc 'hyprctl dispatch moveworkspacetomonitor 1 DP-1'
env = ELECTRON_OZONE_PLATFORM_HINT,wayland
input {
    kb_layout = us
    kb_variant = altgr-intl
    sensitivity = 0.5
}
EOF
  printf '#!/bin/sh\necho old-tool\n' >"$d/bin/.local/bin/old-tool"
  chmod +x "$d/bin/.local/bin/old-tool"
  stow -d "$d" -t "$HOME" hypr bin
  # Like Claude Code's installer on the target laptop: a program writes an
  # absolute symlink into the folded ~/.local/bin, so it lands in the package
  # and stow refuses to restow that package afterwards.
  printf '#!/bin/sh\necho real-tool\n' >"$BATS_TEST_TMPDIR/real-tool"
  chmod +x "$BATS_TEST_TMPDIR/real-tool"
  ln -s "$BATS_TEST_TMPDIR/real-tool" "$HOME/.local/bin/abs-tool"
}

install() {
  "$INSTALL" --yes --skip-system "$@"
}

snapshot() {
  (cd "$HOME" && find . -path ./.local/state/karma/install.log -prune -o -printf '%p %y %l %s %T@\n' | sort)
}

@test "dry run prints the plan and changes nothing" {
  old_dotfiles
  before=$(snapshot)
  run install --dry-run
  [ "$status" -eq 0 ]
  [[ $output == *"dry run, nothing will change"* ]]
  [[ $output == *"link ~/.zshenv"* ]]
  [[ $output == *"unfold ~/.local/bin"* ]]
  [[ $output == *"none made"* ]]
  [ "$before" = "$(snapshot)" ]
}

@test "install links configs, unfolds ~/.local/bin and ports host.lua" {
  old_dotfiles
  run install
  [ "$status" -eq 0 ]
  [ -L "$HOME/.zshenv" ]
  [ -L "$HOME/.config/hypr/hyprland.lua" ]
  [ -L "$HOME/.config/ghostty/config" ]
  [ ! -L "$HOME/.local/bin" ]
  [ -d "$HOME/.local/bin" ]
  [ "$("$HOME/.local/bin/old-tool")" = old-tool ]
  [ "$("$HOME/.local/bin/abs-tool")" = real-tool ]
  [ -L "$HOME/dots/bin/.local/bin/abs-tool" ]
  run "$HOME/.local/bin/karma" version
  [ "$status" -eq 0 ]
  host=$HOME/.config/hypr/host.lua
  grep -q 'output = "eDP-1", mode = "2880x1920@120", position = "0x0", scale = "2"' "$host"
  grep -q 'kb_variant = "altgr-intl"' "$host"
  grep -q 'sensitivity = 0.5' "$host"
  grep -q 'hl.bind("switch:on:Lid Switch"' "$host"
  grep -q 'hl.workspace_rule({ workspace = "1", monitor = "DP-1" })' "$host"
  if command -v luac >/dev/null; then luac -p "$host"; fi
  [ -f "$HOME/.config/hypr/karma_tokens.lua" ]
  [ -f "$HOME/.config/zsh/local.zsh" ]
  [ "$(jq -r .install.keyboard.variant "$HOME/.config/karma/config.json")" = altgr-intl ]
  manifest=$(ls -d "$HOME"/.local/state/karma/backups/*/manifest.json)
  [ "$(jq '[.entries[] | select(.unfolded.package == "bin")] | length' "$manifest")" = 1 ]
  [ "$(jq -r '.entries[] | select(.unfolded.package == "bin") | .unfolded.link' "$manifest")" = ../dots/bin/.local/bin ]
  [ -L "$HOME/.config/hypr/hyprland.conf" ]
}

@test "uninstall puts the home directory back as it was" {
  old_dotfiles
  home_state() {
    (cd "$HOME" && find . \( -path ./.local/state -o -path ./.cache \) -prune -o -printf '%p %y %l\n' | sort)
  }
  before=$(home_state)
  install
  [ -L "$HOME/.config/hypr/hyprland.lua" ]

  run "$KARMA_REPO/bin/karma" uninstall --skip-system
  [ "$status" -eq 2 ]
  run "$KARMA_REPO/bin/karma" uninstall --skip-system --dry-run
  [ "$status" -eq 0 ]
  [ -L "$HOME/.config/hypr/hyprland.lua" ]

  run "$KARMA_REPO/bin/karma" uninstall --skip-system --yes
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/.config/hypr/hyprland.lua" ]
  [ -L "$HOME/.local/bin" ]
  [ "$before" = "$(home_state)" ]
  # what karma wrote was moved, not deleted
  [ -f "$(ls -d "$HOME"/.local/state/karma/uninstalled/*)/.config/hypr/host.lua" ]

  # and installing again works
  install
  [ -L "$HOME/.config/hypr/hyprland.lua" ]
}

@test "a second run changes nothing" {
  old_dotfiles
  install
  before=$(snapshot)
  run install
  [ "$status" -eq 0 ]
  [[ $output == *"Nothing to do"* ]]
  [ "$before" = "$(snapshot)" ]
}

@test "--retire-old-config unstows the old package and keeps the original" {
  old_dotfiles
  install
  run install --retire-old-config
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/.config/hypr/hyprland.conf" ]
  [ -f "$HOME/dots/hypr/.config/hypr/hyprland.conf" ]
  [ -L "$HOME/.config/hypr/hyprland.lua" ]
  manifest=$(ls -d "$HOME"/.local/state/karma/backups/*/manifest.json | tail -n 1)
  [ "$(jq -r '.entries[] | select(.unstowed) | .unstowed.package' "$manifest")" = hypr ]
  dir=$(dirname "$manifest")
  [ -L "$dir/home/.config/hypr/hyprland.conf" ]
}

@test "a plain file in the way is backed up, then replaced by the link" {
  mkdir -p "$HOME/.config/ghostty"
  echo "font-size = 14" >"$HOME/.config/ghostty/config"
  run install
  [ "$status" -eq 0 ]
  [ -L "$HOME/.config/ghostty/config" ]
  backup=$(ls -d "$HOME"/.local/state/karma/backups/*)
  [ "$(cat "$backup/home/.config/ghostty/config")" = "font-size = 14" ]
}

@test "a fresh home gets a default monitor rule and no lid binds" {
  run install
  [ "$status" -eq 0 ]
  grep -q 'output = "", mode = "preferred"' "$HOME/.config/hypr/host.lua"
  run grep -q 'Lid Switch' "$HOME/.config/hypr/host.lua"
  [ "$status" -ne 0 ]
}

@test "a symlinked directory that stow does not own stops the install" {
  mkdir -p "$BATS_TEST_TMPDIR/elsewhere"
  ln -s "$BATS_TEST_TMPDIR/elsewhere" "$HOME/.config/zsh"
  run install
  [ "$status" -eq 1 ]
  [[ $output == *"that stow does not manage"* ]]
  [ ! -e "$HOME/.zshenv" ]
}

@test "without a terminal and without --yes it refuses to guess" {
  run "$INSTALL" --skip-system </dev/null
  [ "$status" -eq 1 ]
  [[ $output == *"pass --yes"* ]]
}
