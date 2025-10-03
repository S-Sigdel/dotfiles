
# Dotfiles for Arch Linux (Managed with GNU Stow)

This repository contains my personal configuration files (**dotfiles**) for my Arch Linux environment.  
It uses **GNU Stow** to manage symlinks, making the setup modular, clean, and easily reproducible across machines.

---

## 📂 Repository Structure

```

.
├── .config/
│   ├── flameshot/    # Flameshot screenshot tool
│   ├── ghostty/      # Ghost terminal multiplexer
│   ├── hypr/         # Hyprland window manager configuration
│   ├── kitty/        # Kitty terminal configuration
│   ├── nvim/         # Neovim configuration
    .
    . # more configs
    .
    .
    .
│   └── shaders/      # Custom shaders for ghostty
├── .zshrc            # Zsh shell configuration
└── README.md          # This file

````

Each top-level folder inside `.config` is a **Stow module**. The `.zshrc` is managed separately as its own module.

---

## ⚙️ Features

- **Modular & clean** — Each application or tool has its own module.
- **Safe symlinking** — GNU Stow handles creating and removing symlinks cleanly.
- **Portable & reproducible** — Clone the repo and Stow modules on any system.
- **Version controlled** — Track all config changes in Git for easy rollback.

---

## 🚀 Installation / Setup

> **Important:** Backup any existing configuration files before applying Stow.

1. **Clone the repository**:

```bash
git clone https://github.com/S-Sigdel/dotfiles.git ~/dotfiles
cd ~/dotfiles
````

2. **Install Stow** (if not installed):

```bash
sudo pacman -S stow
```

3. **Stow your modules**:

```bash
# Stow individual modules
stow -v -t ~ .zshrc      # Zsh shell configuration
stow -v -t ~/.config flameshot ghostty hypr kitty nvim shaders
```

> This creates symlinks in your home directory (`~`) and `~/.config` pointing to the corresponding files in this repo.

4. **Reload your environment**:

```bash
source ~/.zshrc
# or restart your terminal/session
```

---

## 🧩 Modules Overview

| Module      | Description                                                      |
| ----------- | ---------------------------------------------------------------- |
| `.zshrc`    | Zsh shell configuration, aliases, environment variables, plugins |
| `flameshot` | Flameshot screenshot tool configuration                          |
| `ghostty`   | Ghost terminal multiplexer setup                                 |
| `hypr`      | Hyprland window manager configuration                            |
| `kitty`     | Kitty terminal emulator configuration                            |
| `nvim`      | Neovim editor configuration                                      |
| `shaders`   | Custom shaders for graphical apps                                |

---

## 🔄 Updating & Maintenance

* Pull updates and reapply Stow symlinks:

```bash
cd ~/dotfiles
git pull
stow -v -R .zshrc
stow -v -R -t ~/.config flameshot ghostty hypr kitty nvim shaders
```

* Add new modules as needed. Stow ensures everything stays organized.

---

## 💡 Tips & Best Practices

* Keep modules self-contained: only include files related to that module.
* Avoid conflicting filenames across modules.
* Use `stow -D <module>` to safely remove a module before updating or uninstalling it.

---

## 📜 License

MIT License

Copyright (c) 2025 Sakshyam Sigdel

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.


```
