#!/usr/bin/env bash
# Wallpaper daemon. awww when installed (animated changes and live wallpapers via
# ../wallspill), hyprpaper otherwise. Started by hyprland.lua.
#
# hyprpaper.conf stays the one list of per-monitor wallpapers; under awww the
# main monitor gets whatever SUPER+Space last picked instead.

CONF="$HOME/.config/hypr/hyprpaper.conf"
MAIN_DIR="$HOME/Pictures/wallpaper/main"
STATE="$HOME/.cache/current_wallpaper"

if ! command -v awww-daemon >/dev/null; then
  exec hyprpaper
fi

pkill -x hyprpaper
pgrep -x awww-daemon >/dev/null || { awww-daemon >/dev/null 2>&1 & }
for _ in $(seq 50); do awww query >/dev/null 2>&1 && break; sleep 0.1; done

# the wallpaper SUPER+Space last picked (same ordering as change_wall.sh)
mapfile -t WALLS < <(find -L "$MAIN_DIR" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' -o -iname '*.gif' -o -iname '*.mp4' -o -iname '*.webm' \) -printf '%f\n' | sort)
INDEX=$(cat "$STATE" 2>/dev/null || echo -1)
MAIN=""
[ "${#WALLS[@]}" -gt 0 ] && [ "$INDEX" -ge 0 ] && MAIN="$MAIN_DIR/${WALLS[$((INDEX % ${#WALLS[@]}))]}"

# monitor/path pairs from the wallpaper { } blocks
awk '/^[[:space:]]*monitor[[:space:]]*=/ { sub(/.*=[[:space:]]*/, ""); m = $0 }
     /^[[:space:]]*path[[:space:]]*=/    { sub(/.*=[[:space:]]*/, ""); print m "\t" $0 }' "$CONF" |
while IFS=$'\t' read -r mon path; do
  path="${path/#\~/$HOME}"
  [[ "$path" == "$MAIN_DIR"/* && -n "$MAIN" ]] && path="$MAIN"
  ~/.config/hypr/wallspill/apply.sh "$mon" "$path"
  # live wallpapers play in the wallspill overlay, which may still be starting up
  case "$path" in *.mp4|*.webm|*.gif)
    for _ in $(seq 40); do
      qs -p ~/.config/hypr/wallspill ipc call -- spill show "$mon" "$path" 2>/dev/null && break
      sleep 0.25
    done ;;
  esac
done
