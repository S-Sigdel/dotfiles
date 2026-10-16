#!/usr/bin/env bash
# Clipboard history picker (SUPER+SHIFT+V): rofi + glass theme.
#   Enter         copy the entry back to the clipboard
#   Shift+Delete  remove the entry from history
# Images get a cached thumbnail and an "Image · WxH · type" label.

DB_PATH="${CLIPHIST_DB:-/tmp/cliphist.db}"
THUMBS="$HOME/.cache/cliphist-thumbs"
mkdir -p "$THUMBS"

while :; do
  mapfile -t lines < <(cliphist -db-path "$DB_PATH" list)
  if [ ${#lines[@]} -eq 0 ]; then
    notify-send -a Clipboard -u low -t 2000 "Clipboard history is empty"; exit 0
  fi

  # rows are piped straight into rofi: a $(...) would strip the \0 icon separators
  make_rows() {
    for line in "${lines[@]}"; do
      id="${line%%$'\t'*}"
      content="${line#*$'\t'}"
      if [[ "$content" =~ \[\[\ binary\ data\ ([0-9.]+\ [KMG]?i?B)\ ([a-z]+)\ ([0-9]+x[0-9]+)\ \]\] ]]; then
        size="${BASH_REMATCH[1]}" type="${BASH_REMATCH[2]}" dims="${BASH_REMATCH[3]/x/×}"
        # key by the whole entry (id+size+dims): ids restart after a reboot (/tmp db)
        thumb="$THUMBS/$(printf '%s' "$line" | md5sum | cut -c1-16).$type"
        [ -s "$thumb" ] || printf '%s\n' "$line" | cliphist -db-path "$DB_PATH" decode >"$thumb"
        printf '󰋩  Image · %s · %s · %s\0icon\x1f%s\n' "$dims" "$type" "$size" "$thumb"
      else
        # one tidy line: collapse whitespace, trim, cap length
        text=$(printf '%s' "$content" | tr '\n\t' '  ' | tr -s ' ' | sed 's/^ //; s/ $//')
        (( ${#text} > 90 )) && text="${text:0:89}…"
        printf '%s\0icon\x1f%s\n' "${text:-(whitespace)}" "$HOME/.config/hypr/icons/clip-text.svg"
      fi
    done
  }

  idx=$(make_rows | rofi -dmenu -i -show-icons -format i \
        -p "󰅌" -mesg "Enter: copy   ·   Shift+Del: remove" \
        -kb-custom-1 "Shift+Delete" -kb-delete-entry "" \
        -theme ~/.config/rofi/clipboard.rasi)
  code=$?

  [ -z "$idx" ] && exit 0
  line="${lines[$idx]}"
  case $code in
    0)  printf '%s\n' "$line" | cliphist -db-path "$DB_PATH" decode | wl-copy; exit 0 ;;
    10) printf '%s\n' "$line" | cliphist -db-path "$DB_PATH" delete ;;   # remove, then reopen
    *)  exit 0 ;;
  esac
done
