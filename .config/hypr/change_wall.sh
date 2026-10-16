#!/usr/bin/env bash
# Cycle wallpapers in ~/Pictures/wallpaper/main on the main monitor (SUPER+Space)

DIR="$HOME/Pictures/wallpaper/main"
STATE="$HOME/.cache/current_wallpaper"
MONITOR="HDMI-A-1"

# fall back to the focused monitor if the main one isn't connected
hyprctl monitors -j | jq -e --arg m "$MONITOR" 'any(.[]; .name == $m)' >/dev/null ||
  MONITOR="$(hyprctl monitors -j | jq -r '.[] | select(.focused) | .name')"

mapfile -t WALLS < <(find "$DIR" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) -printf '%f\n' | sort)
TOTAL=${#WALLS[@]}
[ "$TOTAL" -eq 0 ] && exit 1

INDEX=$(cat "$STATE" 2>/dev/null || echo -1)
INDEX=$(((INDEX + 1) % TOTAL))
echo "$INDEX" >"$STATE"

hyprctl hyprpaper wallpaper "$MONITOR,$DIR/${WALLS[$INDEX]}"
