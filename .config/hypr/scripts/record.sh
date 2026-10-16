#!/usr/bin/env bash
# Screen recorder - one key (F9) does everything:
#   press        -> drag a box, or click a monitor for the whole screen (Esc cancels)
#   press again  -> stop; saved to ~/Videos/Recordings, notification offers "Open"
# Records the sound your computer is playing. Hardware (VAAPI) encoding, falls
# back to x264. While recording, waybar shows a red dot + timer (click = stop).
#   record.sh status   json for the waybar module

DIR="$HOME/Videos/Recordings"
RUN="${XDG_RUNTIME_DIR:-/tmp}/record"
PID="$RUN/pid" FILE="$RUN/file" START="$RUN/start"
mkdir -p "$DIR" "$RUN"

recording() { [ -f "$PID" ] && kill -0 "$(cat "$PID")" 2>/dev/null; }

if [ "$1" = status ]; then
  if recording; then
    s=$(( $(date +%s) - $(cat "$START") ))
    printf '{"text":"󰑊  %d:%02d","class":"recording","tooltip":"Recording - F9 or click to stop"}\n' $((s/60)) $((s%60))
  else
    echo '{"text":""}'
  fi
  exit 0
fi

# ---- stop ----
if recording; then
  kill -INT "$(cat "$PID")"                      # lets wf-recorder finish the file
  while kill -0 "$(cat "$PID")" 2>/dev/null; do sleep 0.1; done
  out=$(cat "$FILE"); s=$(( $(date +%s) - $(cat "$START") ))
  rm -f "$PID" "$FILE" "$START"
  pkill -RTMIN+9 waybar
  (
    a=$(notify-send -a Recorder -A open=Open -A folder="Show in folder" \
        "Recording saved · $((s/60)):$(printf %02d $((s%60)))" "$(basename "$out")")
    case "$a" in
      open)   xdg-open "$out" ;;
      folder) nemo "$out" ;;
    esac
  ) & disown
  exit 0
fi

# ---- start ----
pgrep -x slurp >/dev/null && exit 0
geom=$(slurp -o -d -b '#10111799' -c '#a9c2d6' -s '#a9c2d61a' -w 2) || exit 0   # Esc -> cancel
out="$DIR/$(date +%Y-%m-%d_%H-%M-%S).mp4"
audio="$(pactl get-default-sink).monitor"

if [ -e /dev/dri/renderD128 ]; then
  enc=(-c h264_vaapi -d /dev/dri/renderD128)
else
  enc=(-c libx264 -p preset=veryfast -p crf=23)
fi

wf-recorder -y -g "$geom" "${enc[@]}" --audio="$audio" -f "$out" >"$RUN/log" 2>&1 &
echo $! > "$PID"; echo "$out" > "$FILE"; date +%s > "$START"
sleep 0.5
if ! recording; then   # failed to start: say why instead of silently doing nothing
  rm -f "$PID" "$FILE" "$START"
  notify-send -a Recorder -u critical "Recording failed" "$(tail -2 "$RUN/log")"
  exit 1
fi
pkill -RTMIN+9 waybar
