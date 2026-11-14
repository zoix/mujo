# shellcheck shell=bash
# karma weather: the current weather for one place, from open-meteo.com.
# Nothing is asked of the network until a place has been set.

karma_register weather "Current weather for a place you choose"

help_weather() {
  cat <<EOF
Usage: $KARMA_NAME weather [show] [--refresh]
       $KARMA_NAME weather set PLACE
       $KARMA_NAME weather units [c | f]
       $KARMA_NAME weather clear

show   The weather now and today's high and low (the default). The answer
       is kept for half an hour; --refresh asks again.
set    Choose the place by name, e.g. "Lisbon" or "Portland, Oregon". The
       name is looked up once; after that only its coordinates, rounded to
       about a kilometre, are sent. Journaled; can be undone.
units  Celsius (the default) or Fahrenheit.
clear  Forget the place; no more requests are made.

The service is open-meteo.com: no account and no key. It sees the place
and this machine's network address, nothing else. The dashboard and the
lock screen show the result.
EOF
}

WEATHER_CACHE=$KARMA_CACHE_DIR/weather.json
WEATHER_API=${KARMA_WEATHER_API:-https://api.open-meteo.com/v1/forecast}
WEATHER_GEO=${KARMA_WEATHER_GEO:-https://geocoding-api.open-meteo.com/v1/search}

weather_get() {
  curl -fsS --max-time 10 --get "$@" 2>/dev/null
}

# The words for a WMO weather code.
weather_words='def words: {
  "0": "Clear", "1": "Mostly clear", "2": "Partly cloudy", "3": "Overcast",
  "45": "Fog", "48": "Freezing fog",
  "51": "Light drizzle", "53": "Drizzle", "55": "Heavy drizzle",
  "56": "Freezing drizzle", "57": "Freezing drizzle",
  "61": "Light rain", "63": "Rain", "65": "Heavy rain",
  "66": "Freezing rain", "67": "Freezing rain",
  "71": "Light snow", "73": "Snow", "75": "Heavy snow", "77": "Snow grains",
  "80": "Light showers", "81": "Showers", "82": "Heavy showers",
  "85": "Snow showers", "86": "Heavy snow showers",
  "95": "Thunderstorm", "96": "Thunderstorm with hail", "99": "Thunderstorm with hail"
}[tostring] // "Unknown";'

weather_cmd_show() {
  local refresh=0
  while (( $# )); do
    case $1 in
      --refresh) refresh=1; shift ;;
      *) usage_error "unexpected argument '$1'" ;;
    esac
  done
  local cfg place units
  cfg=$(config_read)
  place=$(jq -c '.weather // empty' <<<"$cfg")
  units=$(jq -r '.weather_units // "c"' <<<"$cfg")
  if [[ -z $place ]]; then
    say "No place set. Choose one with: $KARMA_NAME weather set PLACE"
    jq -n '{set: false}' | emit
    return 0
  fi
  local now cached=""
  now=$(date +%s)
  if (( ! refresh )) && [[ -f $WEATHER_CACHE ]]; then
    cached=$(jq -c --argjson now "$now" --argjson p "$place" --arg u "$units" \
      'select(.fetched > $now - 1800 and .place == $p.name and .unit == $u)' "$WEATHER_CACHE" 2>/dev/null) || cached=""
  fi
  if [[ -z $cached ]]; then
    need curl
    local raw
    raw=$(weather_get "$WEATHER_API" \
      -d "latitude=$(jq -r .lat <<<"$place")" -d "longitude=$(jq -r .lon <<<"$place")" \
      -d current=temperature_2m,weather_code,is_day -d daily=temperature_2m_max,temperature_2m_min \
      -d timezone=auto -d forecast_days=1 \
      -d "temperature_unit=$([[ $units == f ]] && echo fahrenheit || echo celsius)") \
      || die "$EXIT_FAIL" "could not reach the weather service"
    cached=$(jq -c --argjson now "$now" --argjson p "$place" --arg u "$units" "$weather_words"'
      {set: true, place: $p.name, region: $p.region, unit: $u,
       temperature: (.current.temperature_2m | round), code: .current.weather_code,
       description: (.current.weather_code | words), day: (.current.is_day == 1),
       high: (.daily.temperature_2m_max[0] | round), low: (.daily.temperature_2m_min[0] | round),
       fetched: $now}' <<<"$raw" 2>/dev/null) || die "$EXIT_FAIL" "the weather service sent an unexpected answer"
    printf '%s\n' "$cached" | atomic_write "$WEATHER_CACHE"
  fi
  jq -r '"\(.place): \(.temperature)°\(.unit | ascii_upcase), \(.description | ascii_downcase) (high \(.high)°, low \(.low)°)"' <<<"$cached" | say_stream
  printf '%s' "$cached" | emit
}

cmd_weather() {
  local sub=show
  case ${1:-} in
    show|set|units|clear) sub=$1; shift ;;
  esac
  karma_set_cmd "weather $sub"
  local cfg before after
  cfg=$(config_read)
  case $sub in
    show) weather_cmd_show "$@" ;;
    set)
      (( $# >= 1 )) || usage_error "set needs a place name"
      local query="$*" found
      before=$(jq -c '{place: (.weather.name // null)}' <<<"$cfg")
      if (( OPT_DRY_RUN )); then
        say "weather set (dry run): would look up '$query' at open-meteo.com"
        jq -n --argjson b "$before" '{journal_id: null, changed: true, before: $b, after: $b}' | emit
        return 0
      fi
      need curl
      # "Portland, Oregon": the part after the comma picks among namesakes.
      local name=${query%%,*} hint=""
      if [[ $query == *,* ]]; then
        hint=${query#*,}
        hint=${hint#"${hint%%[![:space:]]*}"}
      fi
      found=$(weather_get "$WEATHER_GEO" --data-urlencode "name=$name" -d count=10 -d format=json \
        | jq -c --arg h "$hint" '
            [.results[]? | {name, region: ([.admin1, .country] | map(select(. != null)) | join(", ")),
              lat: (.latitude * 100 | round / 100), lon: (.longitude * 100 | round / 100)}]
            | (map(select($h != "" and (.region | ascii_downcase | contains($h | ascii_downcase)))) + .)[0] // empty') \
        || die "$EXIT_FAIL" "could not reach the weather service"
      [[ -n $found ]] || die "$EXIT_FAIL" "no place called '$query' was found"
      after=$(jq -c '{place: .name}' <<<"$found")
      local label
      label=$(jq -r '"\(.name) (\(.region))"' <<<"$found")
      karma_lock
      config_set weather "$found"
      rm -f -- "$WEATHER_CACHE"
      change_end "weather: place set to $label" "$before" "$after" \
        "$(jq -c 'if .weather then ["weather", "set", "\(.weather.name), \(.weather.region)"] else ["weather", "clear"] end' <<<"$cfg")"
      ;;
    units)
      (( $# <= 1 )) || usage_error "too many arguments"
      local cur
      cur=$(jq -r '.weather_units // "c"' <<<"$cfg")
      if (( $# == 0 )); then
        say "Weather units: $([[ $cur == f ]] && echo Fahrenheit || echo Celsius)"
        jq -n --arg u "$cur" '{units: $u}' | emit
        return 0
      fi
      [[ $1 == c || $1 == f ]] || usage_error "expected c or f, got '$1'"
      before=$(jq -cn --arg u "$cur" '{units: $u}')
      after=$(jq -cn --arg u "$1" '{units: $u}')
      change_begin "weather units: $cur -> $1" "$before" "$after" || return 0
      karma_lock
      config_set weather_units "\"$1\""
      change_end "weather units: $cur -> $1" "$before" "$after" "$(json_array weather units "$cur")"
      ;;
    clear)
      (( $# == 0 )) || usage_error "unexpected argument '$1'"
      before=$(jq -c '{place: (.weather.name // null)}' <<<"$cfg")
      change_begin "weather: place forgotten" "$before" '{"place":null}' || return 0
      karma_lock
      jq 'del(.weather)' <<<"$cfg" | atomic_write "$KARMA_CONFIG_FILE"
      rm -f -- "$WEATHER_CACHE"
      ui_ipc notify reload
      change_end "weather: place forgotten" "$before" '{"place":null}' \
        "$(jq -c '["weather", "set", "\(.weather.name), \(.weather.region)"]' <<<"$cfg")"
      ;;
  esac
}
