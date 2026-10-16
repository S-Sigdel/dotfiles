#!/usr/bin/env bash
# fastfetch with an animated, looping logo (ghostty / kitty).
#
# fastfetch can only draw a still image, and ghostty doesn't support the kitty
# protocol's built-in animation. So: place our own image on the logo spot, then a
# tiny background loop keeps re-sending its pixels (a=t, same image id). The
# terminal swaps the picture in place: no text, no cursor moves, so it never
# interferes with typing, and the image scrolls with the output like any other.
# The loop ends when this shell exits; re-running replaces the previous loop.
#
# Frames are cut from the video once and cached; delete the cache to re-cut.

DIR="$HOME/.config/fastfetch"
VIDEO="$DIR/snapgram.io_66b2jxfctpj4.mp4"
FRAMES="$HOME/.cache/fastfetch/frames"
FPS=15
ID=4242
# must match "logo" in config.jsonc
COLS=26 ROWS=16 PAD_TOP=1 PAD_LEFT=2

# not a kitty-graphics terminal (tty, ssh, etc): plain fastfetch, no animation
if [[ ! -t 1 || ( "$TERM" != *ghostty* && "$TERM" != *kitty* ) ]]; then
  exec fastfetch "$@"
fi

# cut frames on first run (or if the video changed)
if [[ ! -f "$FRAMES/frame_001.png" || "$VIDEO" -nt "$FRAMES/frame_001.png" ]]; then
  mkdir -p "$FRAMES" && rm -f "$FRAMES"/*.png
  ffmpeg -v error -i "$VIDEO" -vf "crop=720:900:0:60,scale=288:360:flags=lanczos,fps=$FPS" "$FRAMES/frame_%03d.png"
fi

# one loop per terminal: stop the previous one if fastfetch is run again here
tty_id=$(tty | tr '/' '_')
PIDFILE="$HOME/.cache/fastfetch/loop$tty_id.pid"
[[ -f "$PIDFILE" ]] && kill "$(cat "$PIDFILE")" 2>/dev/null

# fastfetch would report this script's bash as "the shell" - tell it the real one
caller=$(ps -o comm= -p "$PPID" 2>/dev/null)
case "$caller" in
  zsh)  export FF_SHELL="zsh $(zsh --version | awk '{print $2}')" ;;
  bash) export FF_SHELL="bash ${BASH_VERSION%%(*}" ;;
  *)    export FF_SHELL="${caller:-$(basename "$SHELL")}" ;;
esac

# start at the top so the logo position is known exactly
printf '\e[H\e[2J'
fastfetch --logo "$FRAMES/frame_001.png" "$@"

b64() { printf '%s' "$1" | base64 -w0; }
frames=("$FRAMES"/frame_*.png)
paths=()
for f in "${frames[@]}"; do paths+=("$(b64 "$f")"); done

# place our image on top of fastfetch's still frame (C=1: cursor stays put, z=1: above it)
printf '\e7\e[%d;%dH\e_Ga=T,f=100,t=f,i=%d,p=1,c=%d,r=%d,C=1,z=1,q=2;%s\e\\\e8' \
  $((1 + PAD_TOP)) $((1 + PAD_LEFT)) "$ID" "$COLS" "$ROWS" "${paths[0]}"

shell_pid=$PPID
delay=$(awk "BEGIN{print 1/$FPS}")
(
  trap 'exit 0' TERM
  while kill -0 "$shell_pid" 2>/dev/null; do
    for p in "${paths[@]}"; do
      # a=t: transmit only -> replaces the pixels of image $ID, placement stays
      printf '\e_Ga=t,f=100,t=f,i=%d,q=2;%s\e\\' "$ID" "$p" || exit 0
      sleep "$delay"
      kill -0 "$shell_pid" 2>/dev/null || exit 0
    done
  done
) </dev/null &
echo $! > "$PIDFILE"
disown
