#!/usr/bin/env bats
# Token resolution, template rendering, build, check and settings changes.

load helpers

@test "build renders every consumer with a do-not-edit header" {
  run karma theme build
  [ "$status" -eq 0 ]
  [ -f "$(conf)/quickshell/karma/theme/tokens.json" ]
  [ -f "$(conf)/hypr/karma_tokens.lua" ]
  [ -f "$(conf)/kitty/karma-theme.conf" ]
  [ -f "$(conf)/btop/themes/karma.theme" ]
  [ -f "$(conf)/yazi/theme.toml" ]
  [ -f "$(conf)/fzf/karma.fzfrc" ]
  [ -f "$(conf)/zsh/karma-theme.zsh" ]
  [ -f "$(conf)/gtk-3.0/gtk.css" ]
  [ -f "$(conf)/gtk-4.0/gtk.css" ]
  [ -f "$(state)/theme/system/greetd/config.toml" ]
  [ -f "$(state)/theme/system/vtrgb/palette.vtrgb" ]
  grep -q "Do not edit" "$(conf)/kitty/karma-theme.conf"
  grep -q "Do not edit" "$(conf)/gtk-3.0/gtk.css"
  run grep -q "Do not edit" "$(state)/theme/system/vtrgb/palette.vtrgb"
  [ "$status" -ne 0 ]
}

@test "build is journaled and a second build changes nothing" {
  karma theme build
  run karma theme build --json
  [ "$status" -eq 0 ]
  [ "$(jq '[.data.files[] | select(.status != "unchanged")] | length' <<<"$output")" = 0 ]
  run karma log --json
  [ "$(jq '.data.entries | length' <<<"$output")" = 2 ]
  [ "$(jq -r '.data.entries[0].reversible' <<<"$output")" = false ]
  [ "$(jq -r '.data.entries[1].reversible' <<<"$output")" = true ]
}

@test "check passes after a build" {
  karma theme build
  run karma theme check
  [ "$status" -eq 0 ]
  [[ $output == *"theme check: ok"* ]]
}

@test "check fails before a build and after a hand edit" {
  run karma theme check
  [ "$status" -eq 1 ]
  karma theme build
  echo "# edited" >>"$(conf)/kitty/karma-theme.conf"
  run karma theme check --json kitty
  [ "$status" -eq 1 ]
  [ "$(jq -r '.data.problems[0].kind' <<<"$output")" = drift ]
  [ "$(jq -r '.data.problems[0].consumer' <<<"$output")" = kitty ]
}

@test "check finds hardcoded colours in a copy of the repo" {
  cp -r "$KARMA_REPO" "$BATS_TEST_TMPDIR/repo"
  mkdir -p "$BATS_TEST_TMPDIR/repo/config/kitty"
  echo 'background #ff0000' >"$BATS_TEST_TMPDIR/repo/config/kitty/kitty.conf"
  echo 'color: mauve' >"$BATS_TEST_TMPDIR/repo/config/kitty/extra.conf"
  "$BATS_TEST_TMPDIR/repo/bin/karma" theme build
  run "$BATS_TEST_TMPDIR/repo/bin/karma" theme check --json
  [ "$status" -eq 1 ]
  [ "$(jq '[.data.problems[] | select(.rule == "hex-colour")] | length' <<<"$output")" = 1 ]
  [ "$(jq '[.data.problems[] | select(.rule == "palette-name")] | length' <<<"$output")" = 1 ]
}

@test "check flags number literals on size properties in QML" {
  cp -r "$KARMA_REPO" "$BATS_TEST_TMPDIR/repo"
  mkdir -p "$BATS_TEST_TMPDIR/repo/config/quickshell/karma"
  printf 'Item {\n    width: 52\n    opacity: 1\n    radius: Tokens.radiusMd\n}\n' \
    >"$BATS_TEST_TMPDIR/repo/config/quickshell/karma/Bar.qml"
  "$BATS_TEST_TMPDIR/repo/bin/karma" theme build
  run "$BATS_TEST_TMPDIR/repo/bin/karma" theme check --json
  [ "$status" -eq 1 ]
  [ "$(jq '[.data.problems[] | select(.rule == "qml-literal")] | length' <<<"$output")" = 1 ]
}

@test "accent change rebuilds, is journaled, and undo restores it" {
  karma theme build
  run karma theme accent blue
  [ "$status" -eq 0 ]
  grep -q '"#89b4fa"' "$(conf)/quickshell/karma/theme/tokens.json"
  [ "$(jq -r .accent "$(conf)/karma/config.json")" = blue ]
  run karma undo
  [ "$status" -eq 0 ]
  grep -q '"accent": "#cba6f7"' "$(conf)/quickshell/karma/theme/tokens.json"
  [ "$(jq -r .accent "$(conf)/karma/config.json")" = mauve ]
  run karma theme check
  [ "$status" -eq 0 ]
}

@test "dry-run changes nothing and records nothing" {
  karma theme build
  before=$(sha256sum "$(conf)/kitty/karma-theme.conf")
  run karma theme accent green --dry-run
  [ "$status" -eq 0 ]
  [[ $output == *"dry run"* ]]
  [[ $output == *'+  "accent": '* ]]
  [ "$before" = "$(sha256sum "$(conf)/kitty/karma-theme.conf")" ]
  [ ! -f "$(conf)/karma/config.json" ]
  run karma log --json
  [ "$(jq '.data.entries | length' <<<"$output")" = 1 ]
}

@test "same accent is a no-op" {
  karma theme accent mauve
  entries=$(wc -l <"$(state)/journal.jsonl")
  run karma theme accent mauve
  [ "$status" -eq 0 ]
  [[ $output == *"already mauve"* ]]
  [ "$(wc -l <"$(state)/journal.jsonl")" -eq "$entries" ]
}

@test "reduce-motion zeroes every duration and undo restores them" {
  karma theme build
  karma theme reduce-motion on
  grep -q '"durationNormal": 0' "$(conf)/quickshell/karma/theme/tokens.json"
  grep -q '"reduceMotion": true' "$(conf)/quickshell/karma/theme/tokens.json"
  grep -q 'normal = 0,' "$(conf)/hypr/karma_tokens.lua"
  karma undo
  grep -q '"durationNormal": 220' "$(conf)/quickshell/karma/theme/tokens.json"
}

@test "undo of a build restores the previous files; repeated undo walks back" {
  karma theme build
  echo "# old" >>"$(conf)/kitty/karma-theme.conf"
  karma theme build kitty
  run grep -q "# old" "$(conf)/kitty/karma-theme.conf"
  [ "$status" -ne 0 ]
  karma undo
  grep -q "# old" "$(conf)/kitty/karma-theme.conf"
  run karma undo --json
  [ "$status" -eq 0 ]
  [ "$(jq -r '.command' <<<"$output")" = "theme restore" ]
  [ ! -f "$(conf)/kitty/karma-theme.conf" ]
}

@test "undo of a first build removes the files it created" {
  karma theme build
  karma undo
  [ ! -f "$(conf)/kitty/karma-theme.conf" ]
}

@test "undo refuses irreversible and already undone entries" {
  karma theme build
  karma theme build
  id=$(jq -r 'select(.reversible == false) | .id' "$(state)/journal.jsonl")
  run karma undo "$id"
  [ "$status" -eq 1 ]
  [[ $output == *"cannot be undone"* ]]
  karma theme accent blue
  acc=$(jq -r 'select(.summary | startswith("theme accent")) | .id' "$(state)/journal.jsonl")
  karma undo "$acc"
  run karma undo "$acc"
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
  run karma theme render "$tpl"
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
  run karma theme render "$tpl"
  [ "$status" -eq 1 ]
  [[ $output == *"unknown token 'color.nope'"* ]]
  echo '{{ color.accent | sparkle }}' >"$tpl"
  run karma theme render "$tpl"
  [ "$status" -eq 1 ]
  [[ $output == *"unknown filter 'sparkle'"* ]]
  echo '{{color.accent}}' >"$tpl"
  run karma theme render "$tpl"
  [ "$status" -eq 1 ]
  [[ $output == *"malformed placeholder"* ]]
}

@test "an invalid accent in config.json is reported" {
  mkdir -p "$(conf)/karma"
  echo '{"accent": "chartreuse"}' >"$(conf)/karma/config.json"
  run karma theme build
  [ "$status" -eq 1 ]
  [[ $output == *"unknown accent 'chartreuse'"* ]]
}

@test "show returns a resolved subtree" {
  run karma theme show color.bg --json
  [ "$status" -eq 0 ]
  [ "$(jq -r .data.value.frame <<<"$output")" = "#11111b" ]
}

@test "accent references resolve everywhere" {
  run karma theme show --json
  [ "$(jq -r '.data.value.color.accent' <<<"$output")" = "#cba6f7" ]
  [ "$(jq -r '.data.value.term.cursor' <<<"$output")" = "#cba6f7" ]
  [ "$(jq -r '.data.value.console.ansi[5]' <<<"$output")" = "#cba6f7" ]
  [ "$(jq '[.. | strings | select(test("^\\{"))] | length' <<<"$output")" = 0 ]
}
