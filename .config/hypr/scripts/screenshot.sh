#!/usr/bin/env bash
# Screenshots: grimblast (capture) + satty (annotate). Saves to ~/Pictures/SS
#   area     - select region -> clipboard
#   area-save- select region -> clipboard + file
#   edit     - select region -> satty editor (flameshot-style)
#   screen   - current monitor -> clipboard + file
#   window   - active window  -> clipboard + file

DIR="$HOME/Pictures/SS"
mkdir -p "$DIR"
export XDG_SCREENSHOTS_DIR="$DIR"
FILE="$DIR/$(date +%Y-%m-%d_%H-%M-%S).png"

# don't stack two captures if the key is mashed
pgrep -x slurp >/dev/null && exit 0

case "$1" in
  area)      grimblast --notify --freeze copy area ;;
  area-save) grimblast --notify --freeze copysave area "$FILE" ;;
  edit)      grimblast --freeze save area - | satty --filename - ;;
  screen)    grimblast --notify copysave output "$FILE" ;;
  window)    grimblast --notify copysave active "$FILE" ;;
  *) echo "usage: $0 {area|area-save|edit|screen|window}"; exit 1 ;;
esac
