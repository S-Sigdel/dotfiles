#!/usr/bin/env bash
# Volume module clicks: single click = mute toggle, double click = output picker.
# Waits briefly to see if a second click follows, so a double click never flickers mute.
PENDING="${XDG_RUNTIME_DIR:-/tmp}/waybar-audio-click"
WINDOW=0.28

if [ -f "$PENDING" ]; then
  rm -f "$PENDING"
  exec ~/.config/waybar/scripts/audio-switch.sh
fi

touch "$PENDING"
sleep "$WINDOW"
if [ -f "$PENDING" ]; then
  rm -f "$PENDING"
  wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
fi
