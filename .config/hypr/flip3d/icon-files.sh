#!/bin/sh
# icon name -> image file, one "name<TAB>path" line each (path empty if none).
# Prefers the app's own hicolor art so the accent matches its branding.
# Used for accent sampling: plain files load safely off the GUI thread,
# unlike image://icon (which crashed Quickshell when read from a Canvas).

roots="/usr/share/icons/hicolor $HOME/.local/share/icons/hicolor
/var/lib/flatpak/exports/share/icons/hicolor $HOME/.local/share/flatpak/exports/share/icons/hicolor
/usr/share/icons/Papirus"

for name in "$@"; do
    p=""
    case "$name" in /*) [ -f "$name" ] && p=$name ;; esac
    for dir in $roots; do
        [ -n "$p" ] && break
        for sz in 64x64 48x48 128x128 256x256 scalable 32x32; do
            for ext in png svg; do
                f="$dir/$sz/apps/$name.$ext"
                if [ -f "$f" ]; then p=$f; break 2; fi
            done
        done
    done
    if [ -z "$p" ]; then
        for f in "/usr/share/pixmaps/$name.png" "/usr/share/pixmaps/$name.svg"; do
            if [ -f "$f" ]; then p=$f; break; fi
        done
    fi
    printf '%s\t%s\n' "$name" "$p"
done
