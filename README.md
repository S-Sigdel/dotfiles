# Dotfiles (Arch Linux + Hyprland, managed with GNU Stow)

My personal configuration for an Arch Linux / Hyprland desktop. Everything lives
in a single Stow package (`config/`) that mirrors `$HOME`, so one `stow` command
symlinks the whole setup into place.

---

## 📂 Layout

```
~/stow/                     # stow directory
└── config/                 # this repo = the stow package (mirrors $HOME)
    ├── .zshrc
    ├── .config/
    │   ├── hypr/           # Hyprland (Lua config), hyprlock, hyprpaper, scripts
    │   │   ├── scripts/    # wallpaper, lock, recorder, battery, visualizer, brave theme, ...
    │   │   ├── wallspill/  # Quickshell overlay: wallpapers "spill" in, live (video/gif) wallpapers
    │   │   └── flip3d/     # Quickshell Vista-style Flip 3D window switcher
    │   ├── waybar/         # status bar + scripts (power menu, ...)
    │   ├── swaync/         # notification centre
    │   ├── swayosd/        # volume / brightness OSD
    │   ├── rofi/           # launcher + clipboard picker themes
    │   ├── cava/           # desktop audio visualizer config
    │   ├── ghostty/  kitty/  nvim/  fastfetch/  dunst/  flameshot/  satty/  gtk-3.0/
    │   ├── systemd/user/   # waybar, swaync, battery-watch units
    │   ├── brave-flags.conf
    │   └── brave-theme/    # GENERATED (git-ignored) — see "Brave glass theme"
    └── .local/
        ├── bin/            # small helper scripts
        └── share/          # .desktop overrides, icons, rofi themes
```

> The repo must be cloned to **`~/stow/config`** — a few scripts (e.g.
> `hypr/scripts/brave-theme.py`) refer to that path directly.

---

## 🚀 Setup

```bash
sudo pacman -S --needed git stow
git clone https://github.com/S-Sigdel/dotfiles.git ~/stow/config
cd ~/stow
stow -n -v -t ~ config      # dry run: lists conflicts with files already in $HOME
stow -v -t ~ config         # create the symlinks
```

If the dry run reports conflicts ("existing target is not owned by stow"),
back up / remove those files in `$HOME` first, or use `stow --adopt -t ~ config`
to pull them into the repo and then `git diff` to review what changed.

Then enable the user services:

```bash
systemctl --user daemon-reload
systemctl --user enable --now waybar swaync battery-watch
```

### Dependencies

Hyprland (Lua config), hyprlock, hyprpaper, [awww](https://github.com/LGFae/awww)
(animated / live wallpapers; hyprpaper is the fallback), quickshell (`qs`), waybar,
swaync, swayosd, rofi, kitty, ghostty, cava, cliphist + wl-clipboard, grim, slurp,
imagemagick (`magick`), ffmpeg, jq, playerctl, python3, brave.

---

## 🔄 Updating

```bash
cd ~/stow/config && git pull
cd ~/stow && stow -v -R -t ~ config     # restow: picks up new / removed files
```

New files inside an already-linked directory (e.g. `~/.config/hypr` is one
symlink to the repo) show up immediately; restow is only needed for new
top-level entries.

---

## 🖼️ Wallpapers

`SUPER+Space` (`hypr/change_wall.sh`) cycles through `~/Pictures/wallpaper/main`
(images, `.gif`, `.mp4`, `.webm`). With awww installed the new wallpaper spills
in from the centre (`hypr/wallspill/`), live wallpapers keep playing and pause
while windows cover the desktop (`scripts/desktop-idle.sh`). Each change also
recolours the cava visualizer (`scripts/cava-colors.py`) and rebuilds the Brave
theme (`scripts/brave-theme.py`).

## 🌫️ Brave glass theme

Chrome/Brave themes can't be transparent, so `hypr/scripts/brave-theme.py` fakes
it: it renders the slice of the wallpaper behind Brave's tab strip and toolbar,
blurred and tinted, into an unpacked theme extension at
`~/stow/config/.config/brave-theme/` (generated, git-ignored).

One-time setup: run it once (or change the wallpaper), then in Brave open
`brave://extensions`, enable **Developer mode**, **Load unpacked** and pick
`~/stow/config/.config/brave-theme`.

**When it updates:** Brave only reads a theme from disk when it loads the
extension, i.e. at **startup** (or when you press ↻ on the theme in
`brave://extensions`). A wallpaper change rebuilds the files right away, but an
already-open Brave keeps the old look until it's restarted. There is no
extension API to reload another unpacked extension, and disabling + re-enabling
a theme makes Brave uninstall it, so this can't be pushed live.

`brave-flags.conf` holds Brave's command-line flags (currently `--disable-pinch`).

---

## 📜 License

MIT License

Copyright (c) 2025 Sakshyam Sigdel

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
