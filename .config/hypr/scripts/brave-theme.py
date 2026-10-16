#!/usr/bin/env python3
"""Rebuild the Brave theme as frosted glass over the wallpaper.

    brave-theme.py <image> [monitor]

Chrome themes can't be transparent, so this fakes it: the tab strip and toolbar
images are the exact slice of the wallpaper that sits behind a Brave window
tiled at the top-left of the monitor, blurred like Hyprland's own blur. With
Brave tiled or maximised there it reads as see-through glass; colours for text,
icons and the address bar come from the wallpaper's hues (as in cava-colors.py).

Writes an unpacked theme extension to ~/stow/config/.config/brave-theme (Brave
remembers the folder it was loaded from, so the path must stay put; generated,
so git-ignored). Brave shows each new build when it next starts (or on ↻ in
brave://extensions): it only reads a theme when loading the extension, nothing
can reload another unpacked extension, and a disabled theme gets uninstalled.
"""
import colorsys
import importlib.util
import json
import os
import subprocess
import sys
import time

OUT = os.path.expanduser("~/stow/config/.config/brave-theme")
HEIGHT = 140   # tab strip + toolbar + a margin, in logical px

sys.dont_write_bytecode = True   # no __pycache__ in the repo
spec = importlib.util.spec_from_file_location(
    "cava_colors", os.path.join(os.path.dirname(os.path.abspath(__file__)), "cava-colors.py"))
cc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cc)


def rgb(h, l, s):
    return [round(c * 255) for c in colorsys.hls_to_rgb(h, l, s)]


def hexc(h, l, s):
    return "#%02x%02x%02x" % tuple(rgb(h, l, s))


def hypr(*args):
    try:
        return json.loads(subprocess.run(["hyprctl", "-j", *args], capture_output=True, text=True).stdout)
    except (OSError, ValueError):
        return None


def geometry(name):
    """(screen w, h, window x, y, w) in logical px for a Brave window on monitor `name`."""
    mons = hypr("monitors") or []
    m = next((m for m in mons if m["name"] == name), None) or next((m for m in mons if m["focused"]), None)
    if not m:
        return 1920, 1080, 5, 37, 1910
    sw, sh = m["width"] / m["scale"], m["height"] / m["scale"]
    if m["transform"] % 2:
        sw, sh = sh, sw
    # a Brave window that's open on this monitor wins; otherwise where a tiled window starts
    for c in hypr("clients") or []:
        if "brave" in c["class"].lower() and c["monitor"] == m["id"] and not c["floating"]:
            return sw, sh, c["at"][0] - m["x"], c["at"][1] - m["y"], c["size"][0]
    gaps = hypr("getoption", "general:gaps_out") or {}
    gap = int((gaps.get("css") or "5").split()[0])
    left, top, right, _ = m["reserved"]
    return sw, sh, left + gap, top + gap, sw - left - right - 2 * gap


def main():
    img = sys.argv[1]
    sw, sh, x, y, w = (round(v) for v in geometry(sys.argv[2] if len(sys.argv) > 2 else ""))
    (ha, sa), (hb, sb) = cc.pick(cc.palette(img))
    sa, sb = min(sa, 0.45), min(sb, 0.55)

    os.makedirs(os.path.join(OUT, "images"), exist_ok=True)
    img_dir = os.path.join(OUT, "images")
    # the wallpaper as awww shows it (cover-fit, centred), then the slice behind the window;
    # blurred from a taller crop so the edges don't smear in from nothing
    pad = 40
    glass = os.path.join(img_dir, "glass.png")
    subprocess.run([
        "magick", img + "[0]", "-resize", f"{sw}x{sh}^", "-gravity", "center", "-extent", f"{sw}x{sh}",
        "-gravity", "northwest", "-crop", f"{w + 2 * pad}x{HEIGHT + 2 * pad}+{max(x - pad, 0)}+{max(y - pad, 0)}",
        "+repage", "-blur", "0x14", "-modulate", "90,115",
        "-gravity", "northwest", "-crop", f"{w}x{HEIGHT}+{min(pad, x)}+{min(pad, y)}", "+repage",
        "-attenuate", "0.06", "+noise", "Gaussian", "-strip", glass], check=True)

    # tab strip: lightly smoked glass; toolbar + active tab: a touch darker so they read as one
    # surface; unfocused window: darker and greyer. All tinted towards the wallpaper's base hue.
    def smoke(name, pct, mod="100,100"):
        subprocess.run(["magick", glass, "-modulate", mod, "-fill", hexc(ha, 0.06, sa * 0.4),
                        "-colorize", f"{pct}%", os.path.join(img_dir, name)], check=True)
    smoke("frame.png", 22)
    smoke("frame_inactive.png", 50, "85,60")
    smoke("toolbar.png", 40)
    smoke("tab_background.png", 22)
    os.remove(glass)

    text = rgb(ha, 0.88, 0.1)
    accent = rgb(hb, 0.8, sb * 0.6)
    now = time.localtime()
    manifest = {
        "manifest_version": 3,
        "name": "rice glass",
        # bumped every build so Brave doesn't reuse its cached theme pack
        "version": "1.%d.%d.%d" % (int(time.strftime("%y%j")), now.tm_hour * 60 + now.tm_min, now.tm_sec),
        "description": "Frosted wallpaper glass (hypr/scripts/brave-theme.py).",
        "theme": {
            "images": {
                "theme_frame": "images/frame.png",
                "theme_frame_inactive": "images/frame_inactive.png",
                "theme_toolbar": "images/toolbar.png",
                "theme_tab_background": "images/tab_background.png",
            },
            "colors": {
                "frame": rgb(ha, 0.12, sa * 0.4),
                "frame_inactive": rgb(ha, 0.09, sa * 0.25),
                "toolbar": rgb(ha, 0.1, sa * 0.4),
                "toolbar_text": text,
                "toolbar_button_icon": accent,
                "tab_text": text,
                "tab_background_text": rgb(ha, 0.72, 0.08),
                "tab_background_text_inactive": rgb(ha, 0.55, 0.06),
                "bookmark_text": rgb(ha, 0.78, 0.08),
                "omnibox_background": rgb(ha, 0.07, sa * 0.35),
                "omnibox_text": text,
                "ntp_background": rgb(ha, 0.08, sa * 0.4),
                "ntp_text": text,
                "ntp_link": accent,
            },
        },
    }
    with open(os.path.join(OUT, "manifest.json"), "w") as f:
        json.dump(manifest, f, indent=2)
    try:
        os.remove(os.path.join(OUT, "Cached Theme.pak"))
    except FileNotFoundError:
        pass
    print(OUT, manifest["version"], f"slice {w}x{HEIGHT}+{x}+{y} of {sw}x{sh}")


if __name__ == "__main__":
    main()
