#!/usr/bin/env bash
# Plug/unplug + low/critical/full battery notifications (started by Hyprland)
AC=/sys/class/power_supply/AC/online
BAT=/sys/class/power_supply/BAT0
LOW=20; CRIT=8
ID=9991

# quiet, transient, one card that replaces itself (never stacks)
notify() { notify-send -a "Power" -r $ID -e "$@"; }

last_ac=$(cat $AC); warned_low=0; warned_crit=0; warned_full=0
while sleep 2; do
  ac=$(cat $AC); cap=$(cat $BAT/capacity); st=$(cat $BAT/status)

  if [ "$ac" != "$last_ac" ]; then
    if [ "$ac" = 1 ]; then
      notify -u low -t 2500 -i "$HOME/.config/hypr/icons/battery-charging.svg" "Charging" "$cap%"
    else
      notify -u low -t 2500 -i "$HOME/.config/hypr/icons/battery-on.svg" "On battery" "$cap%"
    fi
    last_ac=$ac; warned_low=0; warned_crit=0
  fi

  if [ "$ac" = 0 ]; then
    if [ "$cap" -le $CRIT ] && [ $warned_crit = 0 ]; then
      notify -u critical -i "$HOME/.config/hypr/icons/battery-critical.svg" "Battery critical" "$cap% · plug in now"
      warned_crit=1
    elif [ "$cap" -le $LOW ] && [ $warned_low = 0 ]; then
      notify -u critical -i "$HOME/.config/hypr/icons/battery-low.svg" "Battery low" "$cap% left"
      warned_low=1
    fi
    warned_full=0
  elif { [ "$st" = Full ] || [ "$cap" -ge 100 ]; } && [ $warned_full = 0 ]; then
    notify -i "$HOME/.config/hypr/icons/battery-full.svg" "Fully charged" "You can unplug now"
    warned_full=1
  fi
done
