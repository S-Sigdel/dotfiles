#!/usr/bin/env bash
# Cycle wallpapers in ~/Pictures/wallpaper/main on the main monitor (SUPER+Space)

DIR="$HOME/Pictures/wallpaper/main"
STATE="$HOME/.cache/current_wallpaper"
MONITOR="HDMI-A-1"

# fall back to the focused monitor if the main one isn't connected
hyprctl monitors -j | jq -e --arg m "$MONITOR" 'any(.[]; .name == $m)' >/dev/null ||
  MONITOR="$(hyprctl monitors -j | jq -r '.[] | select(.focused) | .name')"

# -L: follow symlinks, so wallpapers kept elsewhere (e.g. ../moon.png) can be linked in
mapfile -t WALLS < <(find -L "$DIR" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' -o -iname '*.gif' -o -iname '*.mp4' -o -iname '*.webm' \) -printf '%f\n' | sort)
TOTAL=${#WALLS[@]}
[ "$TOTAL" -eq 0 ] && exit 1

INDEX=$(cat "$STATE" 2>/dev/null || echo -1)
INDEX=$(((INDEX + 1) % TOTAL))
echo "$INDEX" >"$STATE"

WALL="$DIR/${WALLS[$INDEX]}"
if pgrep -x awww-daemon >/dev/null; then
  # spills out from the centre in an organic blob, live ones already playing (wallspill/);
  # straight onto awww if the overlay isn't running
  qs -p ~/.config/hypr/wallspill ipc call spill to "$MONITOR" "$WALL" 2>/dev/null ||
    ~/.config/hypr/wallspill/apply.sh "$MONITOR" "$WALL"
else
  hyprctl hyprpaper wallpaper "$MONITOR,$WALL"
fi
