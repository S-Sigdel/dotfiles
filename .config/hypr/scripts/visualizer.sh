#!/usr/bin/env bash
# Desktop audio visualizer: cava bars drawn on the desktop (above the wallpaper,
# below windows) on every monitor, via kitty's layer-shell "background" panel.
# Follows hotplug: a monitor that gets connected gets its own bars, a removed
# monitor's bars are cleaned up. Started by hyprland.lua; re-running restarts it.
#
#   visualizer.sh          run (one instance; replaces a previous one)
#   visualizer.sh stop     remove all bars

CONF="$HOME/.config/cava/visualizer.conf"
HEIGHT_PCT=30            # bars live in the bottom 30% of each screen
SIDE_MARGIN=24
RUN="${XDG_RUNTIME_DIR:-/tmp}/visualizer"
SOCK="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"
mkdir -p "$RUN"

start_on() {  # $1 = monitor name
  local mon=$1 h top
  [ -f "$RUN/$mon.pid" ] && kill -0 "$(cat "$RUN/$mon.pid")" 2>/dev/null && return
  # logical height (rotated monitors swap width/height)
  h=$(hyprctl monitors -j | jq -r --arg m "$mon" \
      '.[] | select(.name == $m) | ((if (.transform % 2) == 1 then .width else .height end) / .scale | floor)')
  [ -z "$h" ] && return
  top=$(( h * (100 - HEIGHT_PCT) / 100 ))
  kitten panel --edge=background --layer=bottom --output-name "$mon" \
    --margin-top "$top" --margin-left "$SIDE_MARGIN" --margin-right "$SIDE_MARGIN" \
    --class cava-bg \
    -o background_opacity=0 -o window_padding_width=0 -o font_size=7 \
    -o confirm_os_window_close=0 -o scrollback_lines=0 -o enable_audio_bell=no \
    cava -p "$CONF" >/dev/null 2>&1 &
  echo $! > "$RUN/$mon.pid"
}

stop_on() {
  [ -f "$RUN/$1.pid" ] && kill "$(cat "$RUN/$1.pid")" 2>/dev/null
  rm -f "$RUN/$1.pid"
}

stop_panels() {
  for f in "$RUN"/*.pid; do [ -e "$f" ] && stop_on "$(basename "$f" .pid)"; done
}

# stop a previous instance and wait until its own cleanup has finished,
# so it can't tear down the bars this instance is about to create
old=$(cat "$RUN/daemon" 2>/dev/null)
if [ -n "$old" ] && kill -0 "$old" 2>/dev/null; then
  kill "$old"; for _ in $(seq 50); do kill -0 "$old" 2>/dev/null || break; sleep 0.1; done
fi
stop_panels; rm -f "$RUN/daemon"
[ "$1" = stop ] && exit 0
command -v cava >/dev/null || { notify-send -a Visualizer "cava isn't installed" "sudo pacman -S cava"; exit 1; }

echo $$ > "$RUN/daemon"
# on exit: remove our bars and the event listener (nc + loop are our children)
trap 'stop_panels; pkill -P $$; rm -f "$RUN/daemon"' EXIT
trap 'exit 0' TERM INT HUP

for mon in $(hyprctl monitors -j | jq -r '.[].name'); do start_on "$mon"; done

# hotplug: monitoradded>>NAME / monitorremoved>>NAME
nc -U "$SOCK" | while IFS= read -r ev; do
  case "$ev" in
    monitoradded\>\>*)   sleep 1; start_on "${ev#monitoradded>>}" ;;
    monitorremoved\>\>*) stop_on  "${ev#monitorremoved>>}" ;;
  esac
done &
# wait (not a foreground pipeline) so TERM is handled immediately
wait $!
