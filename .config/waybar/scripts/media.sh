#!/usr/bin/env bash
# "Now playing" for waybar, outside the bar process.
# waybar's built-in mpris module segfaults on some player events (browser tabs
# appearing/vanishing); here a playerctl hiccup can only kill this script, and
# waybar restarts custom scripts on its own.
DIM='#6e7585'
MAX=45

esc() { sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g'; }

emit() {  # status player title artist
  local status=$1 player=$2 title artist icon text
  title=$(printf '%s' "$3" | esc); artist=$(printf '%s' "$4" | esc)
  case "$player" in
    spotify*)  icon='󰓇' ;;
    firefox*)  icon='󰈹' ;;
    brave*)    icon='󰖟' ;;
    chromium*) icon='󰊯' ;;
    *)         icon='󰎆' ;;
  esac
  (( ${#title} > MAX )) && title="${title:0:MAX-1}…"
  case "$status" in
    Playing)
      text="<span color='$DIM'>$icon</span>  $title"
      [ -n "$artist" ] && text+=" <span color='$DIM'>· $artist</span>" ;;
    Paused)
      text="<span color='$DIM'>󰏤</span>  <span color='$DIM'>$title</span>" ;;
    *) text="" ;;
  esac
  jq -cn --arg t "$text" --arg c "${status,,}" --arg tip "$3${4:+ — $4}" \
    '{text:$t, class:$c, alt:$c, tooltip:$tip}'
}

# --follow prints a line on every change (an empty line when no player is left)
playerctl metadata --follow \
  --format $'{{status}}\t{{playerName}}\t{{title}}\t{{artist}}' 2>/dev/null |
while IFS=$'\t' read -r status player title artist; do
  if [ -z "$status" ] || [ -z "$title" ]; then
    echo '{"text":"","class":"stopped"}'
  else
    emit "$status" "$player" "$title" "$artist"
  fi
done
