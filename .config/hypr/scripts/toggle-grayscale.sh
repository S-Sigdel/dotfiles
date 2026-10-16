#!/bin/bash
SHADER="/home/thinking/.config/hypr/shaders/grayscale.glsl"
CURRENT=$(hyprctl getoption decoration:screen_shader | grep -oP '(?<=str: ).*' | tr -d '[:space:]')

if [ "$CURRENT" = "$SHADER" ]; then
    hyprctl keyword decoration:screen_shader ""
    notify-send -t 2000 "Hyprland" "Grayscale OFF" 2>/dev/null || true
else
    hyprctl keyword decoration:screen_shader "$SHADER"
    notify-send -t 2000 "Hyprland" "Grayscale ON" 2>/dev/null || true
fi
