#!/usr/bin/env bash
# rofi power menu
choice=$(printf '󰌾  Lock\n󰍃  Logout\n󰜉  Reboot\n󰐥  Shutdown\n󰤄  Suspend' \
  | rofi -dmenu -i -p "power" -theme-str 'window {width: 260px;} listview {lines: 5;}')
case "$choice" in
  *Lock) ~/.config/hypr/scripts/lock.sh ;;
  *Logout) hyprctl dispatch 'hl.dsp.exit()' ;;
  *Reboot) systemctl reboot ;;
  *Shutdown) systemctl poweroff ;;
  *Suspend) systemctl suspend ;;
esac
