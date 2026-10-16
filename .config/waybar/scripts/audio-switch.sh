#!/usr/bin/env bash
# rofi picker for the audio output. Moves every playing app to the chosen output.
# Also offers "Laptop speakers" / "Headphones" when that needs a card-profile switch
# (this sound chip exposes only one of them at a time).

CARD=$(pactl --format=json list cards | jq -r '.[0].name')
PROFILE=$(pactl --format=json list cards | jq -r '.[0].active_profile')
SPK_PROFILE="HiFi (HDMI1, HDMI2, HDMI3, Mic1, Mic2, Speaker)"
HP_PROFILE="HiFi (HDMI1, HDMI2, HDMI3, Headphones, Mic1, Mic2)"
DEFAULT=$(pactl get-default-sink)

pretty() {
  case "$1" in
    *Speaker*)    echo "󰓃  Laptop speakers" ;;
    *Headphones*) echo "󰋋  Headphones" ;;
    *HDMI1*)      echo "󰍹  Monitor (HDMI / DP 1)" ;;
    *HDMI2*)      echo "󰍹  Monitor (HDMI / DP 2)" ;;
    *HDMI3*)      echo "󰍹  Monitor (HDMI / DP 3)" ;;
    *bluez*)      echo "󰂯  $2" ;;
    *)            echo "󰓃  $2" ;;
  esac
}

declare -A TARGET
menu=""
# usable sinks (skip unplugged HDMI ports)
while IFS=$'\t' read -r name desc avail; do
  [ "$avail" = "not available" ] && continue
  label=$(pretty "$name" "$desc")
  [ "$name" = "$DEFAULT" ] && label="$label   ✓"
  TARGET["$label"]="sink:$name"
  menu+="$label"$'\n'
done < <(pactl --format=json list sinks | jq -r '.[] | .active_port as $a | [.name, .description, ([.ports[] | select(.name == $a) | .availability][0] // "")] | @tsv')

# offer the output hidden behind the other profile
if [ "$PROFILE" = "$HP_PROFILE" ]; then
  label="󰓃  Laptop speakers"; TARGET["$label"]="profile:$SPK_PROFILE"; menu+="$label"$'\n'
elif [ "$PROFILE" = "$SPK_PROFILE" ]; then
  label="󰋋  Headphones"; TARGET["$label"]="profile:$HP_PROFILE"; menu+="$label"$'\n'
fi

choice=$(printf '%s' "$menu" | rofi -dmenu -i -p "󰕾" -mesg "Audio output" \
  -theme-str 'window {width: 380px;} listview {lines: 6;}')
[ -z "$choice" ] && exit 0
target="${TARGET[$choice]}"

move_all() {
  pactl set-default-sink "$1"
  for i in $(pactl list short sink-inputs | awk '{print $1}'); do
    pactl move-sink-input "$i" "$1" 2>/dev/null
  done
  notify-send -a "Audio" -i audio-speakers -r 9992 "Audio output" "${choice%   ✓}"
}

case "$target" in
  sink:*) move_all "${target#sink:}" ;;
  profile:*)
    pactl set-card-profile "$CARD" "${target#profile:}"
    sleep 0.6
    want=$([[ "$choice" == *Headphones* ]] && echo Headphones || echo Speaker)
    sink=$(pactl list short sinks | awk -v w="$want" '$2 ~ w {print $2; exit}')
    [ -n "$sink" ] && move_all "$sink"
    ;;
esac
