#!/usr/bin/env bash
# Screen recorder - F9:
#   press        -> pick what (area / full screen) and sound (desktop, voice, both,
#                   none), 3-2-1 countdown, recording starts. Esc cancels any step.
#   press again  -> stop; saved to ~/Videos/Recordings, notification offers Open.
# Last choices are pre-selected. Desktop+voice records the mic separately and
# mixes it in on stop (wf-recorder takes one audio source). GPU (VAAPI) encoding.
#   record.sh status   json for the waybar indicator

DIR="$HOME/Videos/Recordings"
RUN="${XDG_RUNTIME_DIR:-/tmp}/record"
LAST="$HOME/.cache/record-last"
ICON="$HOME/.config/hypr/icons/record.svg"
NID=9993
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

notify() { notify-send -a Recorder -i "$ICON" -r $NID "$@"; }
close_notify() {
  gdbus call --session --dest org.freedesktop.Notifications --object-path /org/freedesktop/Notifications \
    --method org.freedesktop.Notifications.CloseNotification $NID >/dev/null 2>&1
}

# ---------------------------------------------------------------- stop
if recording; then
  read -r mode < "$RUN/mode"; out=$(cat "$RUN/file"); s=$(( $(date +%s) - $(cat "$RUN/start") ))
  kill -INT "$(cat "$RUN/pid")"                                   # wf-recorder finalizes the file
  [ -f "$RUN/micpid" ] && kill -INT "$(cat "$RUN/micpid")" 2>/dev/null
  while kill -0 "$(cat "$RUN/pid")" 2>/dev/null; do sleep 0.1; done
  [ -f "$RUN/micpid" ] && while kill -0 "$(cat "$RUN/micpid")" 2>/dev/null; do sleep 0.1; done
  pkill -RTMIN+9 waybar

  if [ "$mode" = both ]; then                                     # mix voice into the video's desktop audio
    notify -u low "Saving recording…"
    ffmpeg -v error -y -i "$RUN/video.mp4" -i "$RUN/mic.flac" \
      -filter_complex "[0:a][1:a]amix=inputs=2:duration=first:dropout_transition=0:normalize=0[a]" \
      -map 0:v -map "[a]" -c:v copy -c:a aac -b:a 160k "$out" 2>"$RUN/mix.log" \
      || mv "$RUN/video.mp4" "$out"                                # mixing failed: keep the video at least
    rm -f "$RUN/video.mp4" "$RUN/mic.flac"
  fi
  rm -f "$RUN"/{pid,micpid,file,start,mode,label}

  (
    a=$(notify-send -a Recorder -i "$ICON" -r $NID -A open=Open -A folder="Show in folder" \
        "Recording saved · $((s/60)):$(printf %02d $((s%60)))" "$(basename "$out")")
    case "$a" in
      open)   xdg-open "$out" ;;
      folder) nemo "$out" ;;
    esac
  ) & disown
  exit 0
fi

# ---------------------------------------------------------------- start
# one start at a time: a second F9 while the menus/countdown are up does nothing
exec 9>"$RUN/start.lock"; flock -n 9 || exit 0
[ -f "$LAST" ] && . "$LAST"                                       # last_what / last_sound

menu() {  # $1 prompt, $2 preselect label, rest = entries -> prints chosen entry
  local prompt=$1 pre=$2; shift 2
  local row=0 i=0; for e in "$@"; do [ "$e" = "$pre" ] && row=$i; i=$((i+1)); done
  printf '%s\n' "$@" | rofi -dmenu -i -no-custom -p "$prompt" -selected-row "$row" \
    -mesg "Record" -theme-str 'window {width: 420px;} listview {lines: 5;} entry {enabled: false;}'
}

# 1. what
mons=($(hyprctl monitors -j | jq -r '.[].name'))
whats=("󰩭  Select area")
if [ ${#mons[@]} -eq 1 ]; then whats+=("󰍹  Full screen")
else for m in "${mons[@]}"; do whats+=("󰍹  Full screen · $m"); done; fi
what=$(menu "󰑊" "$last_what" "${whats[@]}") || exit 0

# 2. sound
sounds=("󰓃  Desktop sound + my voice" "󰓃  Desktop sound only" "󰍬  My voice only" "󰝟  No sound")
sound=$(menu "󰕾" "$last_sound" "${sounds[@]}") || exit 0
printf 'last_what=%q\nlast_sound=%q\n' "$what" "$sound" > "$LAST"

# area / output
target=()
case "$what" in
  *"Select area"*) geom=$(slurp -d -b '#10111799' -c '#a9c2d6' -s '#a9c2d61a' -w 2) || exit 0
                   target=(-g "$geom"); label="Area" ;;
  *"·"*)           out_name=${what##*· }; target=(-o "$out_name"); label="$out_name" ;;
  *)               target=(-o "${mons[0]}"); label="Full screen" ;;
esac

desk="$(pactl get-default-sink).monitor"
mic="$(pactl get-default-source)"
case "$sound" in
  *"+ my voice"*) mode=both;  audio=(--audio="$desk"); label+=" · desktop + voice" ;;
  *"Desktop"*)    mode=desk;  audio=(--audio="$desk"); label+=" · desktop sound" ;;
  *"voice"*)      mode=mic;   audio=(--audio="$mic");  label+=" · voice" ;;
  *)              mode=none;  audio=();                label+=" · no sound" ;;
esac

# 3. countdown (closed before recording starts, so it's never in the video)
for n in 3 2 1; do
  notify -u critical -t 0 "Recording in $n" "$label · F9 to stop"
  sleep 1
done
close_notify; sleep 0.3

out="$DIR/$(date +%Y-%m-%d_%H-%M-%S).mp4"
video="$out"; [ "$mode" = both ] && video="$RUN/video.mp4"
if [ -e /dev/dri/renderD128 ]; then enc=(-c h264_vaapi -d /dev/dri/renderD128)
else enc=(-c libx264 -p preset=veryfast -p crf=23); fi

if [ "$mode" = both ]; then
  ffmpeg -v error -y -f pulse -i "$mic" -c:a flac "$RUN/mic.flac" </dev/null >"$RUN/mic.log" 2>&1 9>&- &
  echo $! > "$RUN/micpid"
fi
wf-recorder -y "${target[@]}" "${enc[@]}" "${audio[@]}" -f "$video" >"$RUN/log" 2>&1 9>&- &
echo $! > "$RUN/pid"; echo "$out" > "$RUN/file"; date +%s > "$RUN/start"
echo "$mode" > "$RUN/mode"; echo "$label" > "$RUN/label"

sleep 0.5
if ! recording; then                                               # say why instead of doing nothing
  [ -f "$RUN/micpid" ] && kill "$(cat "$RUN/micpid")" 2>/dev/null
  rm -f "$RUN"/{pid,micpid,file,start,mode,label}
  notify -u critical "Recording failed" "$(tail -2 "$RUN/log")"
  exit 1
fi
pkill -RTMIN+9 waybar
