#!/usr/bin/env bash
# Stop desktop eye-candy nobody can see. When a monitor's workspace has a tiled or
# fullscreen window, its live wallpaper (wallspill) pauses and its visualizer cava
# is frozen (SIGSTOP); both resume the moment the desktop shows again.
# Started by hyprland.lua.

SOCK="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"
RUN="${XDG_RUNTIME_DIR:-/tmp}/visualizer"
declare -A last

PIDF="${XDG_RUNTIME_DIR:-/tmp}/desktop-idle.pid"

# one instance: replace a previous one
old=$(cat "$PIDF" 2>/dev/null)
[ -n "$old" ] && kill -0 "$old" 2>/dev/null && { kill "$old"; sleep 0.3; }
echo $$ > "$PIDF"

update() {
  local mon covered pid
  while read -r mon covered; do
    # cava runs inside the monitor's kitty panel (visualizer.sh)
    pid=$(cat "$RUN/$mon.pid" 2>/dev/null)
    [ -n "$pid" ] && pkill "-$([ "$covered" = true ] && echo STOP || echo CONT)" -P "$pid" -x cava
    if [ "${last[$mon]}" != "$covered" ]; then
      qs -p ~/.config/hypr/wallspill ipc call -- spill cover "$mon" "$covered" >/dev/null 2>&1 &&
        last[$mon]=$covered
    fi
  done < <(jq -rn --argjson m "$(hyprctl -j monitors)" --argjson c "$(hyprctl -j clients)" '
    $m[] | .activeWorkspace.id as $w | .specialWorkspace.id as $s
    | "\(.name) \(any($c[]; (.workspace.id == $w or .workspace.id == $s)
                       and .mapped and (.hidden | not)
                       and ((.floating | not) or .fullscreen > 0)))"')
}

# on exit nothing stays frozen (nc + the loop are our children)
trap 'pkill -P $$; pkill -CONT -x cava
      for m in $(hyprctl -j monitors | jq -r ".[].name"); do
        qs -p ~/.config/hypr/wallspill ipc call -- spill cover "$m" false >/dev/null 2>&1; done
      [ "$(cat "$PIDF" 2>/dev/null)" = $$ ] && rm -f "$PIDF"' EXIT
trap 'exit 0' TERM INT HUP

# wallspill may still be starting: keep trying until it has heard the state once
for _ in $(seq 20); do update; [ ${#last[@]} -gt 0 ] && break; sleep 1; done

nc -U "$SOCK" | while IFS= read -r ev; do
  case "$ev" in
    workspace\>\>*|focusedmon\>\>*|openwindow\>\>*|closewindow\>\>*|movewindow*|\
    changefloatingmode\>\>*|fullscreen\>\>*|activespecial\>\>*|monitoradded*) ;;
    *) continue ;;
  esac
  while IFS= read -r -t 0.15 _; do :; done   # let the burst of events settle
  update
done &
wait $!
