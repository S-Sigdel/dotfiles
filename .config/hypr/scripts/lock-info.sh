#!/usr/bin/env bash
# Status lines for the hyprlock HUD (labels poll this).

case "$1" in
  media)
    IFS='|' read -r status title artist < <(playerctl metadata --format '{{status}}|{{title}}|{{artist}}' 2>/dev/null)
    [ "$status" = Playing ] || { echo "♪  NO MUSIC"; exit 0; }
    line="$title${artist:+ - $artist}"
    (( ${#line} > 48 )) && line="${line:0:45}..."
    # pango markup: escape & < >
    line=${line//&/&amp;}; line=${line//</&lt;}; line=${line//>/&gt;}
    echo "♪  ${line^^}"
    ;;
  battery)
    bat=/sys/class/power_supply/BAT0
    [ -r "$bat/capacity" ] || exit 0
    cap=$(<"$bat/capacity"); st=$(<"$bat/status")
    icons=(󰂎 󰁺 󰁻 󰁼 󰁽 󰁾 󰁿 󰂀 󰂁 󰂂 󰁹)
    icon=${icons[$((cap / 10))]}
    [ "$st" = Charging ] && icon=󰂄
    echo "$icon  $cap%"
    ;;
esac
