#!/usr/bin/env bash
# Notification modes:
#   normal    - popups on
#   silent    - no popups, notifications still collect in the shade (DND)
#   invisible - like silent, plus open popups closed and the bar bell hides the count
# usage: notif-mode.sh {normal|silent|invisible|get|is <mode>|cycle|sync|apply}
#
# swaync only reads toggle states when its panel opens, so to update the mode
# buttons live we write the active mode into a generated config and reload it
# (panel stays open). Template: ~/.config/swaync/config.json
FLAG="$HOME/.cache/notif-invisible"
STATE="$HOME/.cache/notif-mode"   # source of truth; never ask swaync (avoids D-Bus startup deadlock)
TEMPLATE="$HOME/.config/swaync/config.json"
LIVE="$HOME/.cache/swaync/config.json"

get() {
  local m; m=$(cat "$STATE" 2>/dev/null)
  case "$m" in normal|silent|invisible) echo "$m" ;; *) echo normal ;; esac
}

# push the saved mode into a running swaync (DND on/off); used after swaync starts
apply() {
  case "$(get)" in
    normal)    rm -f "$FLAG"; swaync-client -df >/dev/null ;;
    silent)    rm -f "$FLAG"; swaync-client -dn >/dev/null ;;
    invisible) touch "$FLAG"; swaync-client -dn >/dev/null ;;
  esac
}

# write the live config with the current mode's button marked active
sync() {
  mkdir -p "$(dirname "$LIVE")"
  local mode="${1:-$(get)}"
  jq --arg m "$mode" '(.["widget-config"]["buttons-grid#modes"].actions) |=
      [ .[] | .active = ((.label | ascii_downcase) | test($m)) ]' "$TEMPLATE" > "$LIVE.tmp" &&
    mv "$LIVE.tmp" "$LIVE"
}

set_mode() {
  # bounce DND so waybar's subscription always gets an event
  swaync-client -df >/dev/null
  case "$1" in
    normal)    rm -f "$FLAG" ;;
    silent)    rm -f "$FLAG"; swaync-client -dn >/dev/null ;;
    invisible) touch "$FLAG"; swaync-client -dn >/dev/null; swaync-client --hide-all >/dev/null ;;
  esac
  echo "$1" > "$STATE"
  sync "$1"
  swaync-client -R >/dev/null
}

case "$1" in
  normal|silent|invisible) set_mode "$1" ;;
  get) get ;;
  is) [ "$(get)" = "$2" ] && echo true || echo false ;;
  sync) sync ;;
  apply) apply ;;
  cycle)
    case "$(get)" in
      normal) set_mode silent ;;
      silent) set_mode invisible ;;
      *)      set_mode normal ;;
    esac ;;
  *) echo "usage: $0 {normal|silent|invisible|get|is <mode>|cycle|sync|apply}"; exit 1 ;;
esac
