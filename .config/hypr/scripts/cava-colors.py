#!/usr/bin/env python3
"""Recolour the desktop visualizer to match a wallpaper.

    cava-colors.py <image>
    cava-colors.py --restore    (again for the last image, after visualizer.sh resets the config)

Finds the wallpaper's two strongest vivid hues and writes a muted gradient
(dark base in the first hue -> soft tip in the second) into the visualizer's
runtime config, then tells the running cava to reload its colours (SIGUSR2).
The tracked ~/.config/cava/visualizer.conf is left alone; visualizer.sh
copies it to the runtime config at start.
"""
import colorsys
import os
import re
import subprocess
import sys

BASE = os.path.expanduser("~/.config/cava/visualizer.conf")
RUN = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "visualizer", "cava.conf")
LAST = os.path.expanduser("~/.cache/visualizer-wallpaper")


def palette(path):
    out = subprocess.run(
        ["magick", path + "[0]", "-resize", "96x54!", "-colors", "16", "-format", "%c", "histogram:info:-"],
        capture_output=True, text=True, check=True).stdout
    cols = []
    for line in out.splitlines():
        m = re.match(r"\s*(\d+):\s*\(([\d.]+),([\d.]+),([\d.]+)", line)
        if m:
            n, r, g, b = int(m[1]), *(float(m[i]) / 255 for i in (2, 3, 4))
            cols.append((n, colorsys.rgb_to_hls(r, g, b)))
    return cols


def pick(cols):
    # weight by how much of the image it covers and how vivid it is
    def vivid(c):
        n, (h, l, s) = c
        return n * s * (1 - abs(l - 0.5) * 1.6)
    ranked = sorted((c for c in cols if c[1][2] > 0.18 and 0.12 < c[1][1] < 0.9), key=vivid, reverse=True)
    if not ranked:  # greyscale wallpaper: fall back to the old slate -> steel blue
        return (0.59, 0.25), (0.58, 0.3)
    a = ranked[0][1]
    hue_gap = lambda h1, h2: min(abs(h1 - h2), 1 - abs(h1 - h2))
    b = next((c[1] for c in ranked[1:] if hue_gap(c[1][0], a[0]) > 0.08), a)
    # dark base takes the darker of the two, the tips the lighter
    if b[1] < a[1]:
        a, b = b, a
    return (a[0], a[2]), (b[0], b[2])


def hexc(h, l, s):
    r, g, b = colorsys.hls_to_rgb(h, l, s)
    return "#%02x%02x%02x" % (round(r * 255), round(g * 255), round(b * 255))


def main():
    img = sys.argv[1]
    if img == "--restore":
        try:
            img = open(LAST).read().strip()
        except OSError:
            return
        if not os.path.exists(img):
            return
    else:
        with open(LAST, "w") as f:
            f.write(img)
    (ha, sa), (hb, sb) = pick(palette(img))
    # muted: capped saturation, dark at the base, never neon at the tips
    sa, sb = min(sa, 0.45), min(sb, 0.55)
    grad = [hexc(ha, 0.20, sa * 0.7), hexc(ha, 0.36, sa), hexc(hb, 0.56, sb), hexc(hb, 0.76, sb * 0.85)]

    conf = open(RUN if os.path.exists(RUN) else BASE).read()
    for i, c in enumerate(grad, 1):
        conf = re.sub(rf"^gradient_color_{i}\s*=.*$", f"gradient_color_{i} = '{c}'", conf, flags=re.M)
    os.makedirs(os.path.dirname(RUN), exist_ok=True)
    with open(RUN, "w") as f:
        f.write(conf)
    subprocess.run(["pkill", "-USR2", "-f", "^cava -p " + re.escape(RUN)])
    print(" ".join(grad))


if __name__ == "__main__":
    main()
