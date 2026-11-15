#!/usr/bin/env bats
# Token resolution, template rendering, build, check and settings changes.

load helpers

@test "build renders every consumer with a do-not-edit header" {
  run mujo theme build
  [ "$status" -eq 0 ]
  [ -f "$(conf)/quickshell/mujo/theme/tokens.json" ]
  [ -f "$(conf)/hypr/mujo_tokens.lua" ]
  [ -f "$(conf)/ghostty/mujo-theme" ]
  [ -f "$(conf)/btop/themes/mujo.theme" ]
  [ -f "$(conf)/yazi/theme.toml" ]
  [ -f "$(conf)/fzf/mujo.fzfrc" ]
  [ -f "$(conf)/zsh/mujo-theme.zsh" ]
  [ -f "$(conf)/gtk-3.0/gtk.css" ]
  [ -f "$(conf)/gtk-4.0/gtk.css" ]
  [ -f "$(state)/theme/system/greetd/config.toml" ]
  [ -f "$(state)/theme/system/vtrgb/palette.vtrgb" ]
  grep -q "Do not edit" "$(conf)/ghostty/mujo-theme"
  grep -q "Do not edit" "$(conf)/gtk-3.0/gtk.css"
  run grep -q "Do not edit" "$(state)/theme/system/vtrgb/palette.vtrgb"
  [ "$status" -ne 0 ]
}

@test "build is journaled and a second build changes nothing" {
  mujo theme build
  run mujo theme build --json
  [ "$status" -eq 0 ]
  [ "$(jq '[.data.files[] | select(.status != "unchanged")] | length' <<<"$output")" = 0 ]
  run mujo log --json
  [ "$(jq '.data.entries | length' <<<"$output")" = 2 ]
  [ "$(jq -r '.data.entries[0].reversible' <<<"$output")" = false ]
  [ "$(jq -r '.data.entries[1].reversible' <<<"$output")" = true ]
}

@test "check passes after a build" {
  mujo theme build
  run mujo theme check
  [ "$status" -eq 0 ]
  [[ $output == *"theme check: ok"* ]]
}

@test "check fails before a build and after a hand edit" {
  run mujo theme check
  [ "$status" -eq 1 ]
  mujo theme build
  echo "# edited" >>"$(conf)/ghostty/mujo-theme"
  run mujo theme check --json ghostty
  [ "$status" -eq 1 ]
  [ "$(jq -r '.data.problems[0].kind' <<<"$output")" = drift ]
  [ "$(jq -r '.data.problems[0].consumer' <<<"$output")" = ghostty ]
}

@test "check finds hardcoded colours in a copy of the repo" {
  cp -r "$MUJO_REPO" "$BATS_TEST_TMPDIR/repo"
  mkdir -p "$BATS_TEST_TMPDIR/repo/config/ghostty"
  echo 'background = #ff0000' >"$BATS_TEST_TMPDIR/repo/config/ghostty/config"
  echo 'color: mauve' >"$BATS_TEST_TMPDIR/repo/config/ghostty/extra.conf"
  "$BATS_TEST_TMPDIR/repo/bin/mujo" theme build
  run "$BATS_TEST_TMPDIR/repo/bin/mujo" theme check --json
  [ "$status" -eq 1 ]
  [ "$(jq '[.data.problems[] | select(.rule == "hex-colour")] | length' <<<"$output")" = 1 ]
  [ "$(jq '[.data.problems[] | select(.rule == "palette-name")] | length' <<<"$output")" = 1 ]
}

@test "check flags number literals on size properties in QML" {
  cp -r "$MUJO_REPO" "$BATS_TEST_TMPDIR/repo"
  mkdir -p "$BATS_TEST_TMPDIR/repo/config/quickshell/mujo"
  printf 'Item {\n    width: 52\n    opacity: 1\n    radius: Tokens.radiusMd\n}\n' \
    >"$BATS_TEST_TMPDIR/repo/config/quickshell/mujo/Bar.qml"
  "$BATS_TEST_TMPDIR/repo/bin/mujo" theme build
  run "$BATS_TEST_TMPDIR/repo/bin/mujo" theme check --json
  [ "$status" -eq 1 ]
  [ "$(jq '[.data.problems[] | select(.rule == "qml-literal")] | length' <<<"$output")" = 1 ]
}

@test "accent change rebuilds, is journaled, and undo restores it" {
  mujo theme build
  run mujo theme accent blue
  [ "$status" -eq 0 ]
  grep -q '"#89b4fa"' "$(conf)/quickshell/mujo/theme/tokens.json"
  [ "$(jq -r .accent "$(conf)/mujo/config.json")" = blue ]
  run mujo undo
  [ "$status" -eq 0 ]
  grep -q '"accent": "#cba6f7"' "$(conf)/quickshell/mujo/theme/tokens.json"
  [ "$(jq -r .accent "$(conf)/mujo/config.json")" = mauve ]
  run mujo theme check
  [ "$status" -eq 0 ]
}

@test "dry-run changes nothing and records nothing" {
  mujo theme build
  before=$(sha256sum "$(conf)/ghostty/mujo-theme")
  run mujo theme accent green --dry-run
  [ "$status" -eq 0 ]
  [[ $output == *"dry run"* ]]
  [[ $output == *'+  "accent": '* ]]
  [ "$before" = "$(sha256sum "$(conf)/ghostty/mujo-theme")" ]
  [ ! -f "$(conf)/mujo/config.json" ]
  run mujo log --json
  [ "$(jq '.data.entries | length' <<<"$output")" = 1 ]
}

@test "same accent is a no-op" {
  mujo theme accent mauve
  entries=$(wc -l <"$(state)/journal.jsonl")
  run mujo theme accent mauve
  [ "$status" -eq 0 ]
  [[ $output == *"already mauve"* ]]
  [ "$(wc -l <"$(state)/journal.jsonl")" -eq "$entries" ]
}

@test "reduce-motion zeroes every duration and undo restores them" {
  mujo theme build
  mujo theme reduce-motion on
  grep -q '"durationNormal": 0' "$(conf)/quickshell/mujo/theme/tokens.json"
  grep -q '"reduceMotion": true' "$(conf)/quickshell/mujo/theme/tokens.json"
  grep -q 'normal = 0,' "$(conf)/hypr/mujo_tokens.lua"
  mujo undo
  grep -q '"durationNormal": 220' "$(conf)/quickshell/mujo/theme/tokens.json"
}

@test "undo of a build restores the previous files; repeated undo walks back" {
  mujo theme build
  echo "# old" >>"$(conf)/ghostty/mujo-theme"
  mujo theme build ghostty
  run grep -q "# old" "$(conf)/ghostty/mujo-theme"
  [ "$status" -ne 0 ]
  mujo undo
  grep -q "# old" "$(conf)/ghostty/mujo-theme"
  run mujo undo --json
  [ "$status" -eq 0 ]
  [ "$(jq -r '.command' <<<"$output")" = "theme restore" ]
  [ ! -f "$(conf)/ghostty/mujo-theme" ]
}

@test "undo of a first build removes the files it created" {
  mujo theme build
  mujo undo
  [ ! -f "$(conf)/ghostty/mujo-theme" ]
}

@test "undo refuses irreversible and already undone entries" {
  mujo theme build
  mujo theme build
  id=$(jq -r 'select(.reversible == false) | .id' "$(state)/journal.jsonl")
  run mujo undo "$id"
  [ "$status" -eq 1 ]
  [[ $output == *"cannot be undone"* ]]
  mujo theme accent blue
  acc=$(jq -r 'select(.summary | startswith("theme accent")) | .id' "$(state)/journal.jsonl")
  mujo undo "$acc"
  run mujo undo "$acc"
  [ "$status" -eq 1 ]
  [[ $output == *"already undone"* ]]
}

@test "render applies every filter" {
  tpl=$BATS_TEST_TMPDIR/t.tmpl
  cat >"$tpl" <<'EOF'
hex={{ color.accent | hex }} bare={{ color.accent | bare }} rgb={{ color.accent | rgb }}
r={{ color.accent | r }} hexa={{ color.accent | hexa(0.8) }} qml={{ color.accent | qml_a(0.8) }}
hypr={{ color.accent | hypr }} hypra={{ color.accent | hypra(0.5) }}
ms={{ motion.duration.normal | ms }} s={{ motion.duration.normal | s }} ds={{ motion.duration.normal | ds }}
px={{ font.size.md | px }} q={{ font.family | q }} csv={{ motion.ease.standard | csv }}
qc={{ motion.ease.enter | qml_curve }} lp={{ motion.ease.standard | lua_points }}
list={{ console.ansi | r }}
lua={{0.2, 0}}
EOF
  run mujo theme render "$tpl"
  [ "$status" -eq 0 ]
  [[ $output == *"hex=#cba6f7 bare=cba6f7 rgb=203, 166, 247"* ]]
  [[ $output == *"r=203 hexa=#cba6f7cc qml=#cccba6f7"* ]]
  [[ $output == *"hypr=rgb(cba6f7) hypra=rgba(cba6f780)"* ]]
  [[ $output == *"ms=220 s=0.22 ds=2.2"* ]]
  [[ $output == *'px=13px q="JetBrainsMono Nerd Font" csv=0.2, 0, 0, 1'* ]]
  [[ $output == *"qc=[0.05, 0.7, 0.1, 1, 1, 1] lp={ {0.2, 0}, {0, 1} }"* ]]
  [[ $output == *"list=30,243,166,249,137,203,148,205,88,243,166,249,137,203,148,166"* ]]
  [[ $output == *"lua={{0.2, 0}}"* ]]
}

@test "render fails on unknown tokens, filters and malformed placeholders" {
  tpl=$BATS_TEST_TMPDIR/t.tmpl
  echo '{{ color.nope }}' >"$tpl"
  run mujo theme render "$tpl"
  [ "$status" -eq 1 ]
  [[ $output == *"unknown token 'color.nope'"* ]]
  echo '{{ color.accent | sparkle }}' >"$tpl"
  run mujo theme render "$tpl"
  [ "$status" -eq 1 ]
  [[ $output == *"unknown filter 'sparkle'"* ]]
  echo '{{color.accent}}' >"$tpl"
  run mujo theme render "$tpl"
  [ "$status" -eq 1 ]
  [[ $output == *"malformed placeholder"* ]]
}

@test "an invalid accent in config.json is reported" {
  mkdir -p "$(conf)/mujo"
  echo '{"accent": "chartreuse"}' >"$(conf)/mujo/config.json"
  run mujo theme build
  [ "$status" -eq 1 ]
  [[ $output == *"unknown accent 'chartreuse'"* ]]
}

@test "show returns a resolved subtree" {
  run mujo theme show color.bg --json
  [ "$status" -eq 0 ]
  [ "$(jq -r .data.value.frame <<<"$output")" = "#11111b" ]
}

@test "accent references resolve everywhere" {
  run mujo theme show --json
  [ "$(jq -r '.data.value.color.accent' <<<"$output")" = "#cba6f7" ]
  [ "$(jq -r '.data.value.term.cursor' <<<"$output")" = "#cba6f7" ]
  [ "$(jq -r '.data.value.console.ansi[5]' <<<"$output")" = "#cba6f7" ]
  [ "$(jq '[.. | strings | select(test("^\\{"))] | length' <<<"$output")" = 0 ]
}
