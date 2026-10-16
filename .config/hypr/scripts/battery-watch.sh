#!/usr/bin/env bash
# Plug/unplug + low/critical/full battery notifications (systemd user service).
# swaync only replaces/closes notifications by the id it hands out (notify-send -p),
# so the ids are tracked here: plugging in closes a "Battery low/critical" warning,
# and each new plug/unplug card replaces the previous one instead of stacking.
AC=/sys/class/power_supply/AC/online
BAT=/sys/class/power_supply/BAT0
ICONS="$HOME/.config/hypr/icons"
LOW=20; CRIT=8

warn_id=""   # open low/critical warning
info_id=0    # last plug/unplug/full card

close() {
  [ -n "$1" ] && [ "$1" != 0 ] && gdbus call --session --dest org.freedesktop.Notifications \
    --object-path /org/freedesktop/Notifications \
    --method org.freedesktop.Notifications.CloseNotification "$1" >/dev/null 2>&1
}
info() { info_id=$(notify-send -p -a Power -r "$info_id" -e "$@"); }
warn() { close "$warn_id"; warn_id=$(notify-send -p -a Power -u critical "$@"); }

last_ac=$(cat $AC); warned_low=0; warned_crit=0; warned_full=0
while sleep 2; do
  ac=$(cat $AC); cap=$(cat $BAT/capacity); st=$(cat $BAT/status)

  if [ "$ac" != "$last_ac" ]; then
    if [ "$ac" = 1 ]; then
      close "$warn_id"; warn_id=""                       # charger in: low warning goes away
      info -u low -t 2500 -i "$ICONS/battery-charging.svg" "Charging" "$cap%"
    else
      info -u low -t 2500 -i "$ICONS/battery-on.svg" "On battery" "$cap%"
    fi
    last_ac=$ac; warned_low=0; warned_crit=0
  fi

  if [ "$ac" = 0 ]; then
    if [ "$cap" -le $CRIT ] && [ $warned_crit = 0 ]; then
      warn -i "$ICONS/battery-critical.svg" "Battery critical" "$cap% · plug in now"
      warned_crit=1; warned_low=1
    elif [ "$cap" -le $LOW ] && [ $warned_low = 0 ]; then
      warn -i "$ICONS/battery-low.svg" "Battery low" "$cap% left"
      warned_low=1
    fi
    warned_full=0
  elif { [ "$st" = Full ] || [ "$cap" -ge 100 ]; } && [ $warned_full = 0 ]; then
    info -i "$ICONS/battery-full.svg" "Fully charged" "You can unplug now"
    warned_full=1
  fi
done
