#!/usr/bin/env bash
# Screen recorder - F9:
#   press        -> one dialog: what (area / full screen per monitor) + sound
#                   toggles (desktop, my voice) -> [area: drag a box] -> 3-2-1
#                   countdown window -> recording. Esc cancels any step.
#   press again  -> stop; saved to ~/Videos/Recordings, notification offers Open.
# Last choices are pre-selected. Desktop+voice records the mic alongside and
# mixes it in on stop (wf-recorder takes one audio source). GPU (VAAPI) encoding.
#   record.sh status   json for the waybar indicator

DIR="$HOME/Videos/Recordings"
RUN="${XDG_RUNTIME_DIR:-/tmp}/record"
LAST="$HOME/.cache/record-last"
ICON="$HOME/.config/hypr/icons/record.svg"
PICKER="$HOME/.config/hypr/scripts/record-picker.py"
mkdir -p "$DIR" "$RUN"

recording() { [ -f "$RUN/pid" ] && kill -0 "$(cat "$RUN/pid")" 2>/dev/null; }

if [ "$1" = status ]; then
  if recording; then
    s=$(( $(date +%s) - $(cat "$RUN/start") ))
    printf '{"text":"󰑊  %d:%02d","class":"recording","tooltip":"Recording · %s\\nF9 or click to stop"}\n' \
      $((s/60)) $((s%60)) "$(cat "$RUN/label")"
  else
    echo '{"text":""}'
  fi
  exit 0
fi

# ---------------------------------------------------------------- stop
if recording; then
  read -r mode < "$RUN/mode"; out=$(cat "$RUN/file"); s=$(( $(date +%s) - $(cat "$RUN/start") ))
  kill -INT "$(cat "$RUN/pid")"                                   # wf-recorder finalizes the file
  [ -f "$RUN/micpid" ] && kill -INT "$(cat "$RUN/micpid")" 2>/dev/null
  while kill -0 "$(cat "$RUN/pid")" 2>/dev/null; do sleep 0.1; done
  [ -f "$RUN/micpid" ] && while kill -0 "$(cat "$RUN/micpid")" 2>/dev/null; do sleep 0.1; done
  pkill -RTMIN+9 waybar

  nid=0
  if [ "$mode" = both ]; then                                     # mix voice into the desktop audio
    # -p: swaync only replaces notifications by the id *it* handed out
    nid=$(notify-send -p -a Recorder -i "$ICON" -u low -e "Saving recording…")
    ffmpeg -v error -y -i "$RUN/video.mp4" -i "$RUN/mic.flac" \
      -filter_complex "[0:a][1:a]amix=inputs=2:duration=first:dropout_transition=0:normalize=0[a]" \
      -map 0:v -map "[a]" -c:v copy -c:a aac -b:a 160k "$out" 2>"$RUN/mix.log" \
      || mv "$RUN/video.mp4" "$out"                                # mixing failed: keep the video at least
    rm -f "$RUN/video.mp4" "$RUN/mic.flac"
  fi
  rm -f "$RUN"/{pid,micpid,file,start,mode,label}

  (
    a=$(notify-send -a Recorder -i "$ICON" -r "$nid" -A open=Open -A folder="Show in folder" \
        "Recording saved · $((s/60)):$(printf %02d $((s%60)))" "$(basename "$out")")
    case "$a" in
      open)   xdg-open "$out" ;;
      folder) nemo "$out" ;;
    esac
  ) & disown
  exit 0
fi

# ---------------------------------------------------------------- start
# one start at a time: a second F9 while the dialog/countdown is up does nothing
exec 9>"$RUN/start.lock"; flock -n 9 || exit 0

last_what=area last_desk=1 last_mic=1
[ -f "$LAST" ] && . "$LAST"

mons=$(hyprctl monitors -j | jq -r '[.[].name] | join(" ")')
read -r what desk mic < <("$PICKER" pick --monitors "$mons" \
  --what "$last_what" --desk "$last_desk" --mic "$last_mic" 9>&-)
[ -n "$what" ] || exit 0                                           # cancelled
printf 'last_what=%q\nlast_desk=%q\nlast_mic=%q\n' "$what" "$desk" "$mic" > "$LAST"

case "$what" in
  area)   geom=$(slurp -d -b '#10111799' -c '#a9c2d6' -s '#a9c2d61a' -w 2) || exit 0
          target=(-g "$geom"); label="Area" ;;
  full:*) out_name=${what#full:}; target=(-o "$out_name")
          label="Full screen"; [ "$(wc -w <<<"$mons")" -gt 1 ] && label+=" · $out_name" ;;
  *)      exit 0 ;;
esac

deskdev="$(pactl get-default-sink).monitor"
micdev="$(pactl get-default-source)"
case "$desk$mic" in
  11) mode=both; audio=(--audio="$deskdev"); label+=" · desktop + voice" ;;
  10) mode=desk; audio=(--audio="$deskdev"); label+=" · desktop sound" ;;
  01) mode=mic;  audio=(--audio="$micdev");  label+=" · voice" ;;
  *)  mode=none; audio=();                   label+=" · no sound" ;;
esac

# countdown window (no close animation, so it's gone before the first frame)
"$PICKER" countdown --label "$label" 9>&- || exit 0
sleep 0.15

out="$DIR/$(date +%Y-%m-%d_%H-%M-%S).mp4"
video="$out"; [ "$mode" = both ] && video="$RUN/video.mp4"
if [ -e /dev/dri/renderD128 ]; then enc=(-c h264_vaapi -d /dev/dri/renderD128)
else enc=(-c libx264 -p preset=veryfast -p crf=23); fi

if [ "$mode" = both ]; then
  ffmpeg -v error -y -f pulse -i "$micdev" -c:a flac "$RUN/mic.flac" </dev/null >"$RUN/mic.log" 2>&1 9>&- &
  echo $! > "$RUN/micpid"
fi
wf-recorder -y "${target[@]}" "${enc[@]}" "${audio[@]}" -f "$video" >"$RUN/log" 2>&1 9>&- &
echo $! > "$RUN/pid"; echo "$out" > "$RUN/file"; date +%s > "$RUN/start"
echo "$mode" > "$RUN/mode"; echo "$label" > "$RUN/label"

sleep 0.5
if ! recording; then                                               # say why instead of doing nothing
  [ -f "$RUN/micpid" ] && kill "$(cat "$RUN/micpid")" 2>/dev/null
  rm -f "$RUN"/{pid,micpid,file,start,mode,label}
  notify-send -a Recorder -i "$ICON" -u critical "Recording failed" "$(tail -2 "$RUN/log")"
  exit 1
fi
pkill -RTMIN+9 waybar
