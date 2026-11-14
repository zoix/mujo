# karma theme engine (jq module): resolves design tokens and renders templates.
# Loaded with `jq -L lib` and `include "theme";`. See docs/tokens.md.

def _refpat: "^\\{[a-z0-9_.]+\\}$";

def _path($ref): $ref | split(".") | map(if test("^[0-9]+$") then tonumber else . end);

# Effective settings: tokens.json defaults, then config.json, then a one-off override.
def settings($tok; $cfg; $over):
  ($tok.defaults
   + ($cfg | {accent, reduce_motion, mode, motion} | with_entries(select(.value != null)))
   + $over)
  | if (.accent | type) != "string" then error("accent must be a string")
    elif (.reduce_motion | type) != "boolean" then error("reduce_motion must be true or false")
    elif (.mode != "dark" and .mode != "light") then error("mode must be dark or light")
    elif (.motion != "normal" and .motion != "gentle") then error("motion must be normal or gentle")
    else . end;

def _resolve_once($root; $accent):
  walk(if type == "string" and test(_refpat) then
         .[1:-1] as $r
         | if $r == "accent" then ($root.palette[$accent] // error("accent '\($accent)' has no palette entry"))
           else ((try ($root | getpath(_path($r))) catch null) // error("unresolved reference {\($r)}"))
           end
       else . end);

# One pass over a token tree whose palette is already chosen.
def _resolve_tree($s):
  if .schema_version != 1 then error("tokens.json: unsupported schema_version \(.schema_version)") else . end
  | if (any(.accents[]; . == $s.accent) | not)
    then error("unknown accent '\($s.accent)'; valid: \(.accents | join(", "))") else . end
  | ([.palette | to_entries[]
      | select((.value | type) != "string" or (.value | test("^#[0-9a-f]{6}$") | not)) | .key]) as $bad
  | if ($bad | length) > 0 then error("palette entries must be lowercase #rrggbb: \($bad | join(", "))") else . end
  | reduce range(0; 8) as $_ (.; . as $root | _resolve_once($root; $s.accent))
  | ([paths(strings | test(_refpat))] | map(map(tostring) | join("."))) as $left
  | if ($left | length) > 0
    then error("references still unresolved after 8 passes (cycle?): \($left | join(", "))") else . end
  # Gentle motion: everything takes nearly twice as long, and the configs
  # that read .motion.gentle fade instead of sliding.
  | .motion.gentle = ($s.motion == "gentle")
  | if .motion.gentle then .motion.duration |= map_values(. * 1.8 | round) else . end
  | if $s.reduce_motion then .motion.duration |= map_values(0) else . end
  | del(.defaults)
  | .settings = $s;

# Resolve every {reference}, validate, apply settings. Output is what templates see.
# In light mode the "light" subtree is merged over the tokens first. The
# console palette (TTY and login screen, installed in /etc) stays dark in
# both modes, so that a mode change never touches system files.
def resolve($s):
  (del(.light) | _resolve_tree($s)) as $dark
  | if $s.mode == "light"
    then ((. * (.light // {})) | del(.light) | _resolve_tree($s) | .console = $dark.console)
    else $dark end;

# ---- filters -----------------------------------------------------------------

def _hexval: ascii_downcase | explode
  | map(if . >= 97 then . - 87 else . - 48 end) | reduce .[] as $d (0; . * 16 + $d);
def _hex2: [(. / 16 | floor), (. % 16)] | map(if . < 10 then . + 48 else . + 87 end) | implode;
def _color: if type == "string" and test("^#[0-9a-f]{6}$") then . else error("expected a colour, got \(tojson)") end;
def _rgb: _color | ltrimstr("#") as $h | [$h[0:2], $h[2:4], $h[4:6]] | map(_hexval);
def _alpha($a):
  if $a == null then error("this filter needs an alpha argument, e.g. hexa(0.8)")
  else ($a | tonumber) as $n
    | if $n < 0 or $n > 1 then error("alpha must be between 0 and 1")
      else ($n * 255 | round | _hex2) end
  end;
def _num: if type == "number" then . else error("expected a number, got \(tojson)") end;
def _curve:
  if type == "array" and length == 4 and all(.[]; type == "number") then .
  else error("expected a curve [x1, y1, x2, y2], got \(tojson)") end;
def _str:
  if type == "string" then .
  elif type == "number" or type == "boolean" then tostring
  elif type == "array" then map(_str) | join(",")
  else error("token is a group, not a value; pick a leaf") end;

def _filter1($f; $a):
  if   $f == "hex"   then _color
  elif $f == "bare"  then _color | ltrimstr("#")
  elif $f == "rgb"   then _rgb | map(tostring) | join(", ")
  elif $f == "r"     then _rgb | .[0] | tostring
  elif $f == "g"     then _rgb | .[1] | tostring
  elif $f == "b"     then _rgb | .[2] | tostring
  elif $f == "hexa"  then _color + _alpha($a)
  elif $f == "qml_a" then "#" + _alpha($a) + (_color | ltrimstr("#"))
  elif $f == "hypr"  then "rgb(" + (_color | ltrimstr("#")) + ")"
  elif $f == "hypra" then "rgba(" + (_color | ltrimstr("#")) + _alpha($a) + ")"
  elif $f == "ms"    then _num | tostring
  elif $f == "s"     then _num / 1000 | tostring
  elif $f == "ds"    then _num / 100 | tostring
  elif $f == "px"    then (_num | tostring) + "px"
  else error("unknown filter '\($f)'") end;

def _apply($f; $a):
  if $f == null then _str
  elif $f == "q" then tojson
  elif $f == "csv" then (if type == "array" then map(_str) | join(", ") else error("csv needs a list") end)
  elif $f == "qml_curve" then _curve | "[\(.[0]), \(.[1]), \(.[2]), \(.[3]), 1, 1]"
  elif $f == "lua_points" then _curve | "{ {\(.[0]), \(.[1])}, {\(.[2]), \(.[3])} }"
  elif type == "array" then map(_filter1($f; $a)) | join(",")
  else _filter1($f; $a) end;

# ---- rendering ---------------------------------------------------------------

def _placeholder:
  "\\{\\{ (?<p>[a-z_][a-z0-9_]*(?:\\.[a-z0-9_]+)*)(?: \\| (?<f>[a-z_]+)(?:\\((?<a>[0-9.]+)\\))?)? \\}\\}";

def _lookup($t; $p):
  (try ($t | getpath(_path($p))) catch null) as $v
  | if $v == null then error("unknown token '\($p)'") else $v end;

def render($tpl; $t; $name):
  try (
    if ($tpl | gsub(_placeholder; "") | test("\\{\\{ ?[a-z_][a-z0-9_.]*( ?\\||\\s*\\}\\})"))
    then error("malformed placeholder; use '{{ path }}' or '{{ path | filter }}'") else . end
    | $tpl | gsub(_placeholder; (. as $m | _lookup($t; $m.p) | _apply($m.f; $m.a)))
  ) catch error("\($name): \(.)");

def header($c; $ce; $id; $prog):
  if $c == "" then ""
  else "\($c) Generated by '\($prog) theme build' from design/tokens.json (consumer: \($id)).\($ce)\n"
     + "\($c) Do not edit: change design/tokens.json and rebuild.\($ce)\n\n"
  end;
