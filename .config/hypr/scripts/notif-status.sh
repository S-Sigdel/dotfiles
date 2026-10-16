#!/usr/bin/env bash
# Waybar bell: wraps `swaync-client -swb` and applies the "invisible" mode
FLAG="$HOME/.cache/notif-invisible"
swaync-client -swb | while read -r line; do
  if [ -f "$FLAG" ]; then
    echo '{"text":"","alt":"invisible","tooltip":"Invisible mode","class":"invisible"}'
  else
    echo "$line"
  fi
done
