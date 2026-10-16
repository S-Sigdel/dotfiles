-- Hyprland config (Lua, 0.56+). Ported 1:1 from the legacy hyprland.conf.
-- Wiki: https://wiki.hypr.land/Configuring/Start/
-- Test changes without applying:  Hyprland --verify-config -c ~/.config/hypr/hyprland.lua

------------------
---- MONITORS ----
------------------

hl.monitor({ output = "eDP-1",    mode = "1920x1080@60",  position = "0x1767",    scale = 1 })
hl.monitor({ output = "HDMI-A-1", mode = "2560x1440@120", position = "1920x1273", scale = 1 })
hl.monitor({ output = "DP-2",     mode = "1920x1080@60",  position = "4480x793",  scale = 1, transform = 1 })
-- any other monitor (e.g. a borrowed one): best mode, placed automatically
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })

hl.workspace_rule({ workspace = "1", monitor = "eDP-1" })
hl.workspace_rule({ workspace = "2", monitor = "HDMI-A-1" })
hl.workspace_rule({ workspace = "3", monitor = "DP-3" })
hl.workspace_rule({ workspace = "special:magic", gaps_out = 60 })

---------------------
---- MY PROGRAMS ----
---------------------

local terminal    = "ghostty"
local fileManager = "nemo"
local menu        = "rofi -show drun -show-icons"
local ss          = "~/.config/hypr/scripts/screenshot.sh"

-------------------
---- AUTOSTART ----
-------------------

hl.on("hyprland.start", function()
    hl.exec_cmd("gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'")
    hl.exec_cmd("/home/thinking/.local/bin/waybar_timer serve")
    -- give systemd user services the session env first, then start the bar
    -- (self-restarting: waybar.service.d/autorestart.conf) and notifications
    -- (on the live mode config: swaync.service.d/live-config.conf)
    hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE && systemctl --user restart waybar swaync")
    hl.exec_cmd("~/.config/hypr/scripts/wallpaper.sh")   -- awww (animated changes) if installed, else hyprpaper
    hl.exec_cmd("~/.config/hypr/scripts/visualizer.sh")   -- audio bars on the desktop, every monitor
    hl.exec_cmd("~/.config/hypr/scripts/record-picker.py serve")   -- F9 recorder dialog, preloaded so it opens instantly
    hl.exec_cmd("ghostty --initial-window=false")   -- warm terminal daemon: instant SUPER+Enter
    hl.exec_cmd("qs -p ~/.config/hypr/wallspill")      -- SUPER+Space wallpapers spill in from the centre
    hl.exec_cmd("~/.config/hypr/scripts/desktop-idle.sh")   -- pause live wallpaper + visualizer while windows cover them
    hl.exec_cmd("qs -p ~/.config/hypr/flip3d")         -- Flip 3D window switcher (SUPER+Tab, 3-finger swipe up)
    hl.exec_cmd("swayosd-server -s ~/.config/swayosd/style.css --top-margin 0.82")
    hl.exec_cmd("wl-paste --type text --watch cliphist -db-path /tmp/cliphist.db -max-items 100 store")
    hl.exec_cmd("wl-paste --type image --watch cliphist -db-path /tmp/cliphist.db -max-items 100 store")
end)

-------------------------------
---- ENVIRONMENT VARIABLES ----
-------------------------------

hl.env("GTK_THEME", "Adwaita:dark")
hl.env("GTK2_RC_FILES", "/usr/share/themes/Adwaita-dark/gtk-2.0/gtkrc")
hl.env("QT_STYLE_OVERRIDE", "Adwaita-Dark")
hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")

-----------------------
---- LOOK AND FEEL ----
-----------------------

hl.config({
    general = {
        gaps_in  = 2,
        gaps_out = 5,

        -- thin borders: soft steel-blue on the focused window, near-invisible otherwise
        border_size = 2,
        col = {
            active_border   = { colors = { "rgba(a9c2d6cc)", "rgba(8fa6bacc)" }, angle = 45 },
            inactive_border = "rgba(ffffff08)",
        },

        resize_on_border        = true,
        extend_border_grab_area = 12,
        allow_tearing           = false,
        layout                  = "dwindle",
    },

    decoration = {
        rounding       = 12,
        rounding_power = 3,   -- squircle-ish corners

        active_opacity   = 1.0,
        inactive_opacity = 1.0,
        dim_inactive     = true,
        dim_strength     = 0.12,

        shadow = {
            enabled        = true,
            range          = 24,
            render_power   = 4,
            offset         = "0 6",
            color          = "rgba(00000055)",
            color_inactive = "rgba(00000030)",
        },

        blur = {
            enabled           = true,
            size              = 8,
            passes            = 3,
            new_optimizations = true,
            ignore_opacity    = true,
            xray              = false,
            noise             = 0.01,
            contrast          = 0.95,
            brightness        = 0.9,
            vibrancy          = 0.15,
            popups            = true,
        },
    },

    animations = { enabled = true },

    dwindle = {
        preserve_split = true,
        smart_split    = false,
        force_split    = 2,
    },

    master = { new_status = "master" },

    misc = {
        middle_click_paste           = false,
        focus_on_activate            = true,
        mouse_move_enables_dpms      = true,
        key_press_enables_dpms       = true,
        force_default_wallpaper      = 0,
        disable_hyprland_logo        = true,
        animate_manual_resizes       = true,
        animate_mouse_windowdragging = true,
    },

    xwayland = { enabled = true },
})

-- Smooth, decelerating curves; windows "snap" open and "zip" away
local function bezier(name, x0, y0, x1, y1)
    hl.curve(name, { type = "bezier", points = { { x0, y0 }, { x1, y1 } } })
end
bezier("expoOut",   0.16, 1,    0.3,  1)
bezier("quintOut",  0.22, 1,    0.36, 1)
bezier("smooth",    0.25, 0.1,  0.25, 1)
bezier("fadeCurve", 0.33, 0,    0.2,  1)
bezier("linear",    0,    0,    1,    1)
bezier("easeOutQuint", 0.23, 1,  0.32, 1)
bezier("snap",      0.05, 0.9,  0.1,  1.04)   -- fast in, tiny settle
bezier("zip",       0.4,  0,    0.9,  0.2)    -- accelerate away

local function anim(leaf, speed, curve, style)
    hl.animation({ leaf = leaf, enabled = true, speed = speed, bezier = curve, style = style })
end
anim("global",           6,   "quintOut")
anim("windowsIn",        3,   "snap",      "popin 82%")
anim("windowsOut",       2,   "zip",       "popin 85%")
anim("windowsMove",      5,   "expoOut",   "slide")
anim("border",           6,   "smooth")
anim("fadeIn",           2,   "fadeCurve")
anim("fadeOut",          2,   "zip")
anim("fadeSwitch",       5,   "fadeCurve")
anim("fadeDim",          6,   "fadeCurve")
anim("layersIn",         4,   "easeOutQuint", "fade")     -- stock Hyprland: bar/launcher fade in
anim("layersOut",        1.5, "linear",       "fade")
anim("fadeLayersIn",     3,   "fadeCurve")
anim("fadeLayersOut",    2.5, "fadeCurve")
anim("workspaces",       4,   "expoOut",   "slide")
anim("specialWorkspace", 5,   "expoOut",   "slidefadevert 10%")
anim("zoomFactor",       6,   "quintOut")
anim("monitorAdded",     10,  "default")                   -- stock Hyprland login/startup animation

---------------
---- INPUT ----
---------------

hl.config({
    input = {
        kb_layout  = "us",
        kb_variant = "",
        kb_model   = "",
        kb_options = "",
        kb_rules   = "",

        follow_mouse  = 1,
        sensitivity   = 0.6,
        accel_profile = "adaptive",   -- macOS-style: slow moves precise, fast flicks travel far

        touchpad = {
            natural_scroll       = false,
            scroll_factor        = 0.4,
            disable_while_typing = true,
            clickfinger_behavior = true,
            tap_to_click         = true,
        },

        -- XP-Pen tablet mapped to the main monitor
        tablet = {
            transform       = 0,
            output          = "HDMI-A-1",
            region_position = "0 0",
            region_size     = "2560 1440",
        },
    },

    gestures = {
        workspace_swipe_distance                 = 1200,
        workspace_swipe_cancel_ratio             = 0.2,
        workspace_swipe_min_speed_to_force       = 5,
        workspace_swipe_direction_lock           = true,
        workspace_swipe_direction_lock_threshold = 10,
        workspace_swipe_create_new               = true,
    },
})

hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })

-- Flip 3D switcher (flip3d/shell.qml): swipe up opens / flips to the next window, down backs out
local function flip(name) return function() hl.dispatch(hl.dsp.global("flip3d:" .. name)) end end
hl.gesture({ fingers = 3, direction = "up",   action = flip("up") })
hl.gesture({ fingers = 3, direction = "down", action = flip("down") })

-- Touchpad a touch faster than mice, like a MacBook trackpad
-- Per-device settings don't inherit input.touchpad in the Lua config, so the
-- touchpad's tap/click/scroll behaviour is spelled out here too.
hl.device({
    name                 = "synaptics-tm3471-030",
    sensitivity          = 0.65,
    tap_to_click         = true,
    clickfinger_behavior = true,   -- 2-finger click = right click
    disable_while_typing = true,
    natural_scroll       = false,
    scroll_factor        = 0.4,
})

---------------------
---- KEYBINDINGS ----
---------------------

local mod = "SUPER"
local function key(k) return mod .. " + " .. k end
local function exec(cmd) return hl.dsp.exec_cmd(cmd) end

hl.bind(key("RETURN"),      exec(terminal))
hl.bind(key("Q"),           hl.dsp.window.close())
hl.bind(key("M"),           hl.dsp.exit())
hl.bind(key("E"),           exec(fileManager))
hl.bind(key("V"),           hl.dsp.window.float({ action = "toggle" }))
hl.bind(key("D"),           exec(menu))
hl.bind(key("P"),           hl.dsp.window.pseudo())
hl.bind(key("O"),           hl.dsp.layout("togglesplit"))
hl.bind(key("W"),           hl.dsp.window.fullscreen())
hl.bind(key("space"),       exec("~/.config/hypr/change_wall.sh"))
hl.bind(key("SHIFT + Y"),   exec("~/.config/hypr/scripts/lock.sh"))
hl.bind(key("G"),           exec("/home/thinking/.config/hypr/scripts/toggle-grayscale.sh"))
hl.bind(key("Z"),           exec("wshowkeys -a bottom -m 80 -t 1500 -o HDMI-A-1 -p"))
hl.bind(key("SHIFT + V"),   exec("~/.config/hypr/cliphist-rofi.sh"))
hl.bind(key("N"),           exec("swaync-client -t -sw"))
hl.bind(key("SHIFT + N"),   exec("~/.config/hypr/scripts/notif-mode.sh cycle"))

-- vim-style focus / move
for k, dir in pairs({ h = "left", l = "right", k = "up", j = "down" }) do
    if k == "k" or k == "j" then   -- h/l are bound below
        hl.bind(key(k), hl.dsp.focus({ direction = dir }))
    end
    hl.bind(key("SHIFT + " .. k:upper()), hl.dsp.window.move({ direction = dir }))
end

-- h/l: move focus within the workspace; at the edge, hop to the nearest
-- occupied workspace in that direction (no wrap-around), landing on the
-- window closest to where we came from
local function focus_or_hop(dir)
    return function()
        local before = hl.get_active_window()
        if before then
            hl.dispatch(hl.dsp.focus({ direction = dir }))
            local after = hl.get_active_window()
            if after and after.address ~= before.address then return end
        end

        local cur = hl.get_active_workspace()
        if not cur then return end
        local step = dir == "right" and 1 or -1
        local target
        for _, ws in ipairs(hl.get_workspaces()) do
            if not ws.special and ws.id > 0 and ws.windows > 0
                and (ws.id - cur.id) * step > 0
                and (not target or (ws.id - target.id) * step < 0) then
                target = ws
            end
        end
        if not target then return end

        hl.dispatch(hl.dsp.focus({ workspace = target.id }))
        local edge
        for _, w in ipairs(hl.get_workspace_windows(target.id)) do
            if not w.floating and (not edge or (w.at.x - edge.at.x) * step < 0) then
                edge = w
            end
        end
        if edge then hl.dispatch(hl.dsp.focus({ window = edge })) end
    end
end
hl.bind(key("h"), focus_or_hop("left"))
hl.bind(key("l"), focus_or_hop("right"))

-- workspaces 1-10
for i = 1, 10 do
    local n = i % 10
    hl.bind(key(n),               hl.dsp.focus({ workspace = i }))
    hl.bind(key("SHIFT + " .. n), hl.dsp.window.move({ workspace = i }))
end

-- Flip 3D switcher: open, then keep tapping to cycle (Enter / click to go, Esc to back out)
hl.bind(key("TAB"),         hl.dsp.global("flip3d:next"))
hl.bind(key("SHIFT + TAB"), hl.dsp.global("flip3d:prev"))

-- scratchpad
hl.bind(key("S"),         hl.dsp.workspace.toggle_special("magic"))
hl.bind(key("SHIFT + S"), hl.dsp.window.move({ workspace = "special:magic" }))

-- scroll through workspaces, drag windows
hl.bind(key("mouse_down"), hl.dsp.focus({ workspace = "e+1" }))
hl.bind(key("mouse_up"),   hl.dsp.focus({ workspace = "e-1" }))
hl.bind(key("mouse:272"),  hl.dsp.window.drag(),   { mouse = true })   -- SUPER + left-drag: move
hl.bind(key("mouse:273"),  hl.dsp.window.resize(), { mouse = true })   -- SUPER + right-drag: resize

-- resize mode: SUPER+R, then h/j/k/l, Esc to leave
hl.bind(key("R"), hl.dsp.submap("resize"))
hl.define_submap("resize", function()
    hl.bind("l",      hl.dsp.window.resize({ x = 20,  y = 0,   relative = true }), { repeating = true })
    hl.bind("h",      hl.dsp.window.resize({ x = -20, y = 0,   relative = true }), { repeating = true })
    hl.bind("k",      hl.dsp.window.resize({ x = 0,   y = -20, relative = true }), { repeating = true })
    hl.bind("j",      hl.dsp.window.resize({ x = 0,   y = 20,  relative = true }), { repeating = true })
    hl.bind("escape", hl.dsp.submap("reset"))
end)

-- volume / brightness keys -> swayosd popup
local media = { locked = true, repeating = true }
hl.bind("XF86AudioRaiseVolume",  exec("swayosd-client --output-volume +5"),        media)
hl.bind("XF86AudioLowerVolume",  exec("swayosd-client --output-volume -5"),        media)
hl.bind("XF86AudioMute",         exec("swayosd-client --output-volume mute-toggle"), media)
hl.bind("XF86AudioMicMute",      exec("swayosd-client --input-volume mute-toggle"),  media)
hl.bind("XF86MonBrightnessUp",   exec("swayosd-client --brightness +5"),           media)
hl.bind("XF86MonBrightnessDown", exec("swayosd-client --brightness -5"),           media)
hl.bind("CAPS + Caps_Lock",      exec("swayosd-client --caps-lock"),               { release = true })

hl.bind("XF86AudioNext",  exec("playerctl next"),       { locked = true })
hl.bind("XF86AudioPause", exec("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPlay",  exec("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPrev",  exec("playerctl previous"),   { locked = true })

-- screenshots -> ~/Pictures/SS (grimblast + satty)
hl.bind("Print",            exec(ss .. " area"))        -- region -> clipboard
hl.bind("SHIFT + Print",    exec(ss .. " area-save"))   -- region -> clipboard + file
hl.bind("CTRL + Print",     exec(ss .. " edit"))        -- region -> annotate
hl.bind(key("Print"),       exec(ss .. " screen"))      -- current monitor
hl.bind("ALT + Print",      exec(ss .. " window"))      -- active window

-- screen recorder: F9 (with fn-lock off it sends KEY_NOTIFICATION_CENTER = XF86NotificationCenter)
-- press: pick area / click a monitor, press again: stop + save (see scripts/record.sh)
hl.bind("XF86NotificationCenter", exec("~/.config/hypr/scripts/record.sh"))

------------------------
---- WINDOW RULES ------
------------------------

hl.window_rule({ name = "suppress-maximize", match = { class = ".*" }, suppress_event = "maximize" })
hl.window_rule({
    name  = "fix-xwayland-drags",
    match = { class = "^$", title = "^$", xwayland = true, float = true, fullscreen = false, pin = false },
    no_focus = true,
})

local pavu = "^(pavucontrol|org.pulseaudio.pavucontrol)$"
hl.window_rule({ name = "pavucontrol", match = { class = pavu }, float = true, size = "900 600", center = true })
hl.window_rule({ name = "float-utils", match = { class = "^(nm-connection-editor|blueman-manager|qt6ct|nwg-look)$" }, float = true })
hl.window_rule({ name = "pip", match = { title = "^(Picture-in-Picture|Picture in picture)$" }, float = true, pin = true })
hl.window_rule({ name = "file-progress", match = { class = "^(org.kde.dolphin)$", title = "^(Copying.*|Moving.*|Progress.*)$" }, float = true })
hl.window_rule({ name = "file-dialogs", match = { title = "^(Open File|Save File|Save As|Open Folder|File Upload.*)$" }, float = true, center = true })

-- recorder dialog/countdown: centered, and gone instantly so it's never in the video
hl.window_rule({ name = "recorder", match = { class = "^(dev.local.recorder)$" },
                 float = true, center = true, no_anim = true, no_dim = true, pin = true })

-- don't dim / fade media, games, screenshots
local media_apps = "^(mpv|vlc|steam_app_.*|gamescope)$"
hl.window_rule({ name = "media-opaque", match = { class = media_apps }, opacity = "1.0 override 1.0 override", no_dim = true })
hl.window_rule({ name = "youtube-opaque", match = { title = "^(.*YouTube.*)$" }, opacity = "1.0 override 1.0 override" })
hl.window_rule({
    name = "satty", match = { class = "^(com.gabm.satty)$" },
    float = true, center = true, no_dim = true, opacity = "1.0 override 1.0 override",
})

-----------------------
---- LAYER RULES ------
-----------------------

for _, ns in ipairs({ "waybar", "rofi", "swaync-control-center", "swaync-notification-window", "swayosd" }) do
    hl.layer_rule({ name = "glass-" .. ns, match = { namespace = ns }, blur = true, ignore_alpha = 0.3 })
end
hl.layer_rule({ name = "rofi-anim",   match = { namespace = "rofi" },                  animation = "popin 94%" })
hl.layer_rule({ name = "swaync-anim", match = { namespace = "swaync-control-center" }, animation = "fade" })
hl.layer_rule({ name = "no-anim-selection",  match = { namespace = "selection" },  no_anim = true })
hl.layer_rule({ name = "no-anim-hyprpicker", match = { namespace = "hyprpicker" }, no_anim = true })
hl.layer_rule({ name = "no-anim-flip3d",     match = { namespace = "flip3d" },     no_anim = true })   -- it animates itself
