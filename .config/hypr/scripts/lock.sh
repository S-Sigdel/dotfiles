#!/usr/bin/env bash
# Lock with a pixelated + scanlined snapshot of the screen as the background,
# then hand over to hyprlock (hyprlock.conf reads $BG).

BG="$HOME/.cache/hyprlock-bg.png"
pgrep -x hyprlock >/dev/null && exit 0

mon=$(hyprctl activeworkspace -j | jq -r .monitor)
grim -o "$mon" -t ppm - | magick - \
  -sample 6.25% -sample 1600% \
  -modulate 70,80 -fill '#101117' -colorize 35% \
  \( -size 1x4 xc:none -fill 'rgba(0,0,0,0.35)' -draw 'point 0,3' -write mpr:scan +delete \) \
  \( +clone -fill none -draw 'color 0,0 reset' -tile mpr:scan -draw 'color 0,0 reset' \) \
  -composite "$BG" 2>/dev/null || rm -f "$BG"

exec hyprlock "$@"
