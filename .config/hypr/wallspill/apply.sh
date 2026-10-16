#!/bin/sh
# Set a wallpaper on awww with no transition. Live wallpapers (video / gif) are
# played by the wallspill overlay, so awww just holds their first frame
# (cached in ~/.cache/wallspill) for the flip3d backdrop and as a fallback.
# Also recolours the desktop visualizer and the Brave theme to match
# (scripts/cava-colors.py, scripts/brave-theme.py).
#   apply.sh <monitor> <file>

mon=$1 file=$2
case "$file" in
  *.mp4|*.webm|*.mkv|*.mov|*.gif|*.MP4|*.WEBM|*.MKV|*.MOV|*.GIF)
    cache="$HOME/.cache/wallspill"
    still="$cache/$(basename "$file").png"
    mkdir -p "$cache"
    [ -s "$still" ] || ffmpeg -v error -y -i "$file" -frames:v 1 "$still"
    file=$still ;;
esac
# the visualizer and Brave take their colours from the SUPER+Space wallpaper
case "$file" in "$HOME/Pictures/wallpaper/main/"*|"$HOME/.cache/wallspill/"*)
  python3 -I "$HOME/.config/hypr/scripts/cava-colors.py" "$file" >/dev/null 2>&1 &
  python3 -I "$HOME/.config/hypr/scripts/brave-theme.py" "$file" "$mon" >/dev/null 2>&1 & ;;
esac
exec awww img -o "$mon" --resize crop --transition-type none "$file"
