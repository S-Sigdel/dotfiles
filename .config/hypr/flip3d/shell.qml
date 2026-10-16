// Flip 3D — Vista-style window switcher for Hyprland.
// Run:      qs -p ~/.config/hypr/flip3d
// Triggers: SUPER+Tab / SUPER+SHIFT+Tab, 3-finger swipe up/down (global shortcuts "flip3d:*")
// Inside:   Tab/→/↓/scroll = next, Shift+Tab/←/↑ = prev, Enter/click = go, Esc/click outside = back
//
// Opening: the current screen is captured and pinned to the front card, which
// starts exactly over its window; the card glides into its slot carrying the
// screen with it while everything around the window fades away, the other
// windows rise into a perspective stack behind it and lightning strikes the
// front card. Every cycle flies the travelling card on a different path;
// picking a window strikes it with lightning before it lands.

pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets

ShellRoot {
    id: root

    // closed → loading (asking hyprctl) → capturing (window up, grabbing the page)
    //        → shown → leaving → closed
    property string phase: "closed"
    property var wins: []
    property int front: 0
    property var mon: null
    property var screenTarget: Quickshell.screens[0]
    property string wallpaper: ""
    property real lift: 0          // 0 = page fills the screen, 1 = page has become the front card
    property int pageCard: -1      // the card carrying the captured screen while it shrinks / grows
    property int pageOrigin: -1    // the window that was focused when the screen was captured
    property int queued: 0         // cycles pressed while the screen is still shrinking
    property real bgOp: 0
    property bool launched: false
    property bool hadPage: false
    property int pending: 0        // cycles pressed before the stack exists
    property var accents: ({})     // class -> color, survives between opens
    property var iconFiles: ({})   // icon name -> file path, for accent sampling

    readonly property int n: wins.length
    readonly property bool active: phase === "shown"
    readonly property real sw: screenTarget ? screenTarget.width : 1920
    readonly property real sh: screenTarget ? screenTarget.height : 1080
    readonly property real f: sh * 1.35                 // focal length of the camera
    readonly property var cur: n > 0 ? wins[front] : null
    readonly property color curAccent: cur ? (accents[cur.cls] || hashAccent(cur.cls)) : "#000000"
    property real ambientBoost: 0
    readonly property var styles: ["arc", "swing", "flip", "dive", "spin", "tumble", "ghost", "shrink"]
    property int styleIdx: 0

    readonly property var keys: ["x", "y", "z", "rx", "ry", "rz", "s", "o", "d"]

    signal launch()
    signal cycled(int dir, string style)
    signal leave(int sel)
    signal drop()

    // ---------------------------------------------------------------- triggers

    GlobalShortcut { appid: "flip3d"; name: "next"; description: "Flip 3D: open / next window"; onPressed: root.next() }
    GlobalShortcut { appid: "flip3d"; name: "prev"; description: "Flip 3D: open / previous window"; onPressed: root.prev() }
    GlobalShortcut { appid: "flip3d"; name: "up";   description: "Flip 3D: swipe up";   onPressed: root.next() }
    GlobalShortcut { appid: "flip3d"; name: "down"; description: "Flip 3D: swipe down"; onPressed: root.cancel() }

    IpcHandler {
        target: "flip"
        function next(): void { root.next() }
        function prev(): void { root.prev() }
        function toggle(): void { root.phase === "closed" ? root.show() : root.cancel() }
        function close(): void { root.cancel() }
    }

    function next() { phase === "closed" ? show() : step(1) }
    function prev() { phase === "closed" ? show() : step(-1) }

    // ------------------------------------------------------------------ flow

    function show() {
        if (phase !== "closed") return
        phase = "loading"
        pending = 0
        query.running = true
    }

    Process {
        id: query
        command: ["sh", "-c", "hyprctl -j clients; echo '@@'; hyprctl -j monitors; echo '@@'; hyprctl hyprpaper listactive 2>/dev/null; awww query 2>/dev/null"]
        stdout: StdioCollector { onStreamFinished: root.load(text) }
    }

    function norm(a) { return String(a).toLowerCase().replace(/^0x/, "") }
    function toplevelFor(address) {
        const t = Hyprland.toplevels.values.find(t => norm(t.address) === norm(address))
        return t ? t.wayland : null
    }

    function load(text) {
        const parts = text.split("@@")
        let clients, monitors
        try {
            clients = JSON.parse(parts[0])
            monitors = JSON.parse(parts[1])
        } catch (e) {
            phase = "closed"
            return
        }
        const m = monitors.find(x => x.focused) || monitors[0]
        const list = clients
            .filter(c => c.mapped && !c.hidden && c.size[0] > 20 && c.size[1] > 20)
            .sort((a, b) => a.focusHistoryID - b.focusHistoryID)
            .map(c => ({
                address: c.address,
                cls: c.class || c.initialClass || "",
                title: c.title || c.initialTitle || "",
                ws: c.workspace.name,
                wsId: c.workspace.id,
                monitor: c.monitor,
                at: c.at,
                size: c.size,
            }))
        if (!m || list.length === 0) {
            phase = "closed"
            return
        }

        // (awww prefixes its lines with ": ")
        const wp = (parts[2] || "").split("\n").map(l => l.trim().replace(/^:\s*/, "")).find(l => l.startsWith(m.name + ":"))
        // hyprpaper: "MON: /path", awww: "MON: 1920x1080, scale: 1, currently displaying: image: /path"
        const wpath = wp ? (wp.includes("image: ") ? wp.slice(wp.lastIndexOf("image: ") + 7) : wp.slice(m.name.length + 1)).trim() : ""
        wallpaper = wpath ? "file://" + wpath : ""
        mon = m
        screenTarget = Quickshell.screens.find(s => s.name === m.name) || Quickshell.screens[0]
        front = ((pending % list.length) + list.length) % list.length
        wins = list

        resolveIcons(list.filter(w => !accents[w.cls]).map(w => iconName(w.cls)))
        phase = "capturing"
        capWait.restart()
    }

    // capture never arrived: skip the page, just fade the stack in
    Timer { id: capWait; interval: 350; onTriggered: root.begin(false) }

    function begin(withPage) {
        if (launched || phase !== "capturing") return
        launched = true
        hadPage = withPage
        capWait.stop()
        phase = "shown"
        stage.forceActiveFocus()
        if (withPage) {
            pageOrigin = pageCard = front
            bgOp = 1                   // hidden under the screen until it shrinks
            liftAnim.start()
        } else {
            lift = 1
            bgIn.start()
        }
        launch()
    }

    function step(d) {
        if (phase === "loading" || phase === "capturing") { pending += d; return }
        if (liftAnim.running) { queued += d; return }
        if (!active || n < 2) return
        front = ((front + d) % n + n) % n
        cycled(d, styles[styleIdx++ % styles.length])
    }

    function select(i) {
        if (!active) return
        phase = "leaving"
        liftAnim.stop()
        dropCarrier()
        Hyprland.dispatch(`hl.dsp.focus({ window = "address:${wins[i].address}" })`)
        leave(i)
        bgOut.start()
    }

    function cancel() {
        if (phase === "loading" || phase === "capturing") { finish(); return }
        if (!active) return
        phase = "leaving"
        liftAnim.stop()
        // the screen grows back out of the card of the window it was captured around,
        // wherever that card is in the stack now
        if (hadPage && pageCard !== pageOrigin) {
            claimPage(pageOrigin)
            lift = 1
            pageCard = pageOrigin
        }
        drop()
        if (hadPage) lower.start()
        else bgOut.start()
    }

    function finish() {
        lower.stop(); bgOut.stop(); bgIn.stop(); liftAnim.stop(); capWait.stop()
        phase = "closed"
        launched = false
        pageCard = pageOrigin = -1
        queued = 0
        wins = []
        lift = 0
        bgOp = 0
    }

    NumberAnimation {
        id: liftAnim
        target: root; property: "lift"; from: 0; to: 1; duration: 600
        easing.type: Easing.BezierSpline; easing.bezierCurve: [0.45, 0, 0.2, 1, 1, 1]
        onFinished: {
            root.dropCarrier()
            if (root.queued) { const d = root.queued; root.queued = 0; root.step(d) }
        }
    }
    signal releasePage()
    signal claimPage(int i)
    function dropCarrier() { releasePage(); pageCard = -1 }
    function pulseAmbient() { ambientAnim.restart() }
    NumberAnimation {
        id: ambientAnim
        target: root; property: "ambientBoost"; from: 1; to: 0; duration: 900
        easing.type: Easing.OutCubic
    }
    NumberAnimation { id: bgIn; target: root; property: "bgOp"; from: 0; to: 1; duration: 260 }
    SequentialAnimation {
        id: bgOut
        PauseAnimation { duration: 440 }
        NumberAnimation { target: root; property: "bgOp"; to: 0; duration: 260; easing.type: Easing.OutCubic }
        ScriptAction { script: root.finish() }
    }
    SequentialAnimation {
        id: lower
        PauseAnimation { duration: 60 }
        NumberAnimation {
            target: root; property: "lift"; to: 0; duration: 480
            easing.type: Easing.BezierSpline; easing.bezierCurve: [0.45, 0, 0.2, 1, 1, 1]
        }
        ScriptAction { script: root.finish() }
    }

    // ------------------------------------------------------------ lightning

    property var bolts: []         // [{pts: [[x,y],...], w}], drawn by the bolt canvas
    property real boltAlpha: 0
    property int boltTarget: -1
    property int boltCount: 1
    property int flickerStep: 0

    // jagged path by midpoint displacement
    function jag(x1, y1, x2, y2, rough) {
        let pts = [[x1, y1], [x2, y2]]
        let d = Math.hypot(x2 - x1, y2 - y1) * rough
        for (let i = 0; i < 7; i++) {
            const out = [pts[0]]
            for (let j = 1; j < pts.length; j++) {
                const a = pts[j - 1], b = pts[j]
                const len = Math.hypot(b[0] - a[0], b[1] - a[1]) || 1
                const off = (Math.random() - 0.5) * d
                out.push([(a[0] + b[0]) / 2 - (b[1] - a[1]) / len * off,
                          (a[1] + b[1]) / 2 + (b[0] - a[0]) / len * off], b)
            }
            pts = out
            d *= 0.55
        }
        return pts
    }

    // where a card's top edge sits on screen right now
    function cardTop(c) {
        const p = c.pose
        const k = f / (f + Math.max(p.z, -0.5 * f))
        return [sw / 2 + p.x * k, sh / 2 + (p.y - c.ch * p.s * 0.42) * k]
    }

    function makeBolts() {
        const c = cardRep.itemAt(boltTarget)
        if (!c) return []
        const [tx, ty] = cardTop(c)
        const out = []
        for (let b = 0; b < boltCount; b++) {
            const sx = tx + (Math.random() - 0.5) * sw * 0.45 + (b ? (b % 2 ? -1 : 1) * sw * 0.18 : 0)
            const main = jag(sx, -30, tx + (Math.random() - 0.5) * 40, ty, 0.35)
            out.push({ pts: main, w: 1 })
            // forks
            for (let i = 0; i < 3; i++) {
                const at = main[Math.floor(main.length * (0.2 + Math.random() * 0.5))]
                const ang = Math.PI / 2 + (Math.random() - 0.5) * 1.6
                const len = (ty + 30) * (0.15 + Math.random() * 0.25)
                out.push({ pts: jag(at[0], at[1], at[0] + Math.cos(ang) * len, at[1] + Math.sin(ang) * len, 0.4), w: 0.45 })
            }
        }
        return out
    }

    // strike card i: flash, flicker (on, off, re-strike, fade), card zaps
    function strike(i, count) {
        const c = cardRep.itemAt(i)
        if (!c) return
        boltTarget = i
        boltCount = count
        flickerStep = 0
        c.zap()
        flash.restart()
        flicker.restart()
        flickerTick()
    }
    function flickerTick() {
        // alpha per frame: strike, gap, re-strike (new shape), afterglow
        const seq = [1, 0, 0.9, 0.75, 0.45, 0.2, 0]
        if (flickerStep >= seq.length) { flicker.stop(); bolts = []; boltAlpha = 0; return }
        if (flickerStep === 0 || flickerStep === 2) bolts = makeBolts()
        boltAlpha = seq[flickerStep++]
    }
    Timer { id: flicker; interval: 45; repeat: true; onTriggered: root.flickerTick() }
    SequentialAnimation {
        id: flash
        NumberAnimation { target: flashRect; property: "opacity"; to: 0.26; duration: 25 }
        NumberAnimation { target: flashRect; property: "opacity"; to: 0.05; duration: 70 }
        NumberAnimation { target: flashRect; property: "opacity"; to: 0.22; duration: 40 }
        NumberAnimation { target: flashRect; property: "opacity"; to: 0; duration: 420; easing.type: Easing.OutCubic }
    }

    // ------------------------------------------------------------- 3D math
    // A pose is the card's centre in world space (screen-centred, z into the
    // screen), Euler angles in degrees, scale, opacity and depth-fog.

    function proj(p, w, h) {
        const r = Math.PI / 180
        const ca = Math.cos(p.rx * r), sa = Math.sin(p.rx * r)
        const cb = Math.cos(p.ry * r), sb = Math.sin(p.ry * r)
        const cc = Math.cos(p.rz * r), sc = Math.sin(p.rz * r)
        // first two columns of Rz·Ry·Rx, scaled
        const r00 = p.s * cc * cb, r10 = p.s * sc * cb, r20 = -p.s * sb
        const r01 = p.s * (cc * sb * sa - sc * ca), r11 = p.s * (sc * sb * sa + cc * ca), r21 = p.s * cb * sa
        const tx = p.x - (r00 * w + r01 * h) / 2
        const ty = p.y - (r10 * w + r11 * h) / 2
        const tz = Math.max(p.z, -0.7 * f) - (r20 * w + r21 * h) / 2
        const w0 = r20 / f, w1 = r21 / f, w3 = 1 + tz / f
        const cx = sw / 2, cy = sh / 2
        return Qt.matrix4x4(
            r00 + cx * w0, r01 + cx * w1, 0, tx + cx * w3,
            r10 + cy * w0, r11 + cy * w1, 0, ty + cy * w3,
            0, 0, 0, 0,
            w0, w1, 0, w3)
    }

    function evalPose(a, m, b, t) {
        const o = {}
        const u = 1 - t
        for (const k of keys) {
            if (!m) {
                o[k] = a[k] + (b[k] - a[k]) * t
            } else {
                const c = 2 * m[k] - (a[k] + b[k]) / 2      // so the curve passes through m at t=0.5
                o[k] = u * u * a[k] + 2 * u * t * c + t * t * b[k]
            }
        }
        return o
    }

    function wrap(a) { a = ((a + 180) % 360 + 360) % 360 - 180; return a }
    function settled(p) {
        const o = Object.assign({}, p)
        o.rx = wrap(o.rx); o.ry = wrap(o.ry); o.rz = wrap(o.rz)
        return o
    }

    function resolveIcons(names) {
        const missing = [...new Set(names)].filter(name => !(name in iconFiles))
        if (!missing.length || iconQuery.running) return
        iconQuery.command = ["sh", Qt.resolvedUrl("icon-files.sh").toString().replace("file://", "")].concat(missing)
        iconQuery.running = true
    }

    Process {
        id: iconQuery
        stdout: StdioCollector {
            onStreamFinished: {
                const m = Object.assign({}, root.iconFiles)
                for (const line of text.split("\n")) {
                    const i = line.indexOf("\t")
                    if (i > 0) m[line.slice(0, i)] = line.slice(i + 1)
                }
                root.iconFiles = m
            }
        }
    }

    // the stack: front at lower-left, receding up and to the right
    function slotPose(k) {
        return {
            x: -0.12 * sw + k * 0.085 * sw,
            y: 0.05 * sh - k * 0.04 * sh,
            z: k * 0.4 * sh,
            rx: -2, ry: -24, rz: 0,
            s: 1,
            o: k <= 8 ? 1 : 0,
            d: Math.min(0.55, k * 0.075),
        }
    }

    function cardSize(w) {
        const k = Math.min(sw * 0.625 / w.size[0], sh * 0.7 / w.size[1])
        return { w: w.size[0] * k, h: w.size[1] * k }
    }

    // the part of the screen a card stands for: its window, if that's on screen,
    // otherwise a centred crop of the card's shape
    function pageRect(w) {
        if (mon && w.monitor === mon.id && w.wsId === mon.activeWorkspace.id)
            return { x: w.at[0] - mon.x, y: w.at[1] - mon.y, w: w.size[0], h: w.size[1] }
        const c = cardSize(w)
        const k = Math.min(sw / c.w, sh / c.h)
        return { x: (sw - c.w * k) / 2, y: (sh - c.h * k) / 2, w: c.w * k, h: c.h * k }
    }
    // a card laid flat over that part of the screen
    function pageStart(w) {
        const r = pageRect(w)
        return { x: r.x + r.w / 2 - sw / 2, y: r.y + r.h / 2 - sh / 2, z: 0,
                 rx: 0, ry: 0, rz: 0, s: r.w / cardSize(w).w, o: 1, d: 0 }
    }

    // push a pose off the bottom of the screen, wherever it sits in depth
    function below(p, amount) {
        const o = Object.assign({}, p)
        o.y += amount * sh * (1 + Math.max(0, p.z) / f)
        o.rx -= 24
        return o
    }

    // the path a card takes between front and back, a fresh one every cycle
    function styleMid(name, a, b) {
        const m = evalPose(a, null, b, 0.5)
        switch (name) {
        case "arc":    m.y = -0.95 * sh; m.rx = -60; break
        case "swing":  m.x = -1.05 * sw; m.z = 0.25 * sh; m.ry = 70; m.rz = -5; break
        case "flip":   m.y = -0.45 * sh; m.rx = 180; b.rx += 360; break
        case "dive":   m.y = 1.0 * sh; m.z = 0.45 * sh; m.rx = 65; break
        case "spin":   m.x = 0.6 * sw; m.y = -0.12 * sh; m.rz = 180; b.rz += 360; break
        case "tumble": m.x = 1.05 * sw; m.y = 0.35 * sh; m.ry = -125; m.rz = 28; m.rx = 18; break
        case "ghost":  m.z = -0.45 * f; m.o = 0; m.y = 0.04 * sh; break
        case "shrink": m.s = 0.06; m.o = 0.3; m.ry = 180; b.ry += 360; break
        }
        return m
    }

    function landPose(w, cw) {
        if (mon && w.monitor === mon.id) {
            return {
                x: w.at[0] - mon.x + w.size[0] / 2 - sw / 2,
                y: w.at[1] - mon.y + w.size[1] / 2 - sh / 2,
                z: 0, rx: 0, ry: 0, rz: 0, s: w.size[0] / cw, o: 1, d: 0,
            }
        }
        return { x: 0, y: 0, z: -0.3 * sh, rx: 0, ry: 0, rz: 0, s: 1.2, o: 0, d: 0 }
    }

    // --------------------------------------------------------- accent colour
    // the dominant vivid hue of the app icon, pushed to a bold-but-not-neon tone

    function hashAccent(cls) {
        let h = 0
        for (let i = 0; i < cls.length; i++) h = (h * 31 + cls.charCodeAt(i)) >>> 0
        return Qt.hsla((h % 360) / 360, 0.6, 0.64, 1)
    }

    function pickAccent(d, cls) {
        const bins = [], rs = [], gs = [], bs = []
        for (let i = 0; i < 12; i++) { bins.push(0); rs.push(0); gs.push(0); bs.push(0) }
        for (let i = 0; i < d.length; i += 4) {
            const r = d[i] / 255, g = d[i + 1] / 255, b = d[i + 2] / 255, a = d[i + 3] / 255
            if (a < 0.5) continue
            const mx = Math.max(r, g, b), mn = Math.min(r, g, b)
            const s = mx > 0 ? (mx - mn) / mx : 0
            if (s < 0.28 || mx < 0.22) continue
            let h
            if (mx === r) h = ((g - b) / (mx - mn) + 6) % 6
            else if (mx === g) h = (b - r) / (mx - mn) + 2
            else h = (r - g) / (mx - mn) + 4
            const bin = Math.floor(h * 2) % 12
            const wgt = s * mx * a
            bins[bin] += wgt; rs[bin] += r * wgt; gs[bin] += g * wgt; bs[bin] += b * wgt
        }
        let best = 0
        for (let i = 1; i < 12; i++) if (bins[i] > bins[best]) best = i
        if (bins[best] < 8) return hashAccent(cls)
        const c = Qt.rgba(rs[best] / bins[best], gs[best] / bins[best], bs[best] / bins[best], 1)
        return Qt.hsla(c.hslHue,
                       Math.min(0.85, Math.max(0.55, c.hslSaturation)),
                       Math.min(0.68, Math.max(0.56, c.hslLightness)), 1)
    }

    // desktop entries load asynchronously; reading the list makes callers re-run once it's in
    function iconName(cls) {
        DesktopEntries.applications.values.length
        const e = DesktopEntries.heuristicLookup(cls)
        return e && e.icon ? e.icon : cls.toLowerCase()
    }
    function iconFor(cls) { return Quickshell.iconPath(iconName(cls), "application-x-executable") }

    // ---------------------------------------------------------------- card

    component Card: Item {
        id: card
        required property var modelData
        required property int index

        readonly property var w: modelData
        readonly property int slot: root.n > 0 ? ((index - root.front) % root.n + root.n) % root.n : 0
        readonly property real cw: root.cardSize(w).w
        readonly property real ch: root.cardSize(w).h
        readonly property string icon: root.iconFor(w.cls)
        property color accent: root.accents[w.cls] || root.hashAccent(w.cls)
        readonly property bool hot: hover.containsMouse && root.active
        readonly property bool isFront: slot === 0

        property var pFrom: root.below(root.slotPose(slot), 1.3)
        property var pMid: null
        property var pTo: pFrom
        property real t: 1
        // the carrier rides root.lift: flat over its window at 0, at rest in the stack at 1
        readonly property bool carrier: root.pageCard === index && root.hadPage && root.phase !== "closed"
        property var rest: root.slotPose(0)
        readonly property var pose: carrier ? root.evalPose(root.pageStart(w), null, rest, root.lift)
                                            : root.evalPose(pFrom, pMid, pTo, t)
        property real flare: 0     // 0..1 light burst on the glow and face

        function shine(strength) {
            flareAnim.stop()
            flareUp.to = strength
            flareAnim.start()
            glint.x = -glint.width * 1.5
            glintAnim.restart()
        }
        SequentialAnimation {
            id: flareAnim
            NumberAnimation { id: flareUp; target: card; property: "flare"; duration: 90; easing.type: Easing.OutQuad }
            NumberAnimation { target: card; property: "flare"; to: 0; duration: 650; easing.type: Easing.OutCubic }
        }
        Timer { id: strikeLater; onTriggered: root.strike(card.index, 2) }
        property real zapped: 0    // 0..1, tints glow/outline/face toward lightning yellow
        function zap() {
            shine(1)
            zapAnim.restart()
        }
        SequentialAnimation {
            id: zapAnim
            NumberAnimation { target: card; property: "zapped"; to: 1; duration: 40 }
            NumberAnimation { target: card; property: "zapped"; to: 0; duration: 900; easing.type: Easing.InQuad }
        }
        readonly property color glow: Qt.tint(accent, Qt.rgba(1, 0.86, 0.25, zapped))

        width: cw
        height: ch
        z: 100000 - pose.z
        opacity: Math.max(0, Math.min(1, pose.o))
        visible: opacity > 0.01
        transform: Matrix4x4 { matrix: root.proj(card.pose, card.cw, card.ch) }

        function go(to, mid, dur, curve, delay) {
            motion.stop()
            pFrom = pose
            pMid = mid
            pTo = to
            t = 0
            pause.duration = delay
            tween.duration = dur
            tween.easing.bezierCurve = curve.concat([1, 1])
            motion.start()
        }

        SequentialAnimation {
            id: motion
            PauseAnimation { id: pause }
            NumberAnimation { id: tween; target: card; property: "t"; from: 0; to: 1; easing.type: Easing.BezierSpline }
            ScriptAction {
                script: {
                    const p = root.settled(card.pTo)
                    card.pMid = null
                    card.pFrom = p
                    card.pTo = p
                    card.t = 1
                }
            }
        }

        Connections {
            target: root
            function onLaunch() {
                if (card.carrier) {
                    // rides root.lift; this is where it rests once the screen has shrunk
                    motion.stop()
                    card.rest = card.pFrom = card.pTo = root.slotPose(0)
                    card.pMid = null
                    card.t = 1
                    strikeLater.interval = 600
                } else {
                    card.go(root.slotPose(card.slot), null, 760, [0.16, 1, 0.3, 1], 120 + card.slot * 45)
                    strikeLater.interval = 420
                }
                if (card.slot === 0) strikeLater.restart()
            }
            function onCycled(dir, style) {
                const now = card.slot
                const was = ((now + dir) % root.n + root.n) % root.n
                const to = root.slotPose(now)
                if ((dir > 0 && was === 0) || (dir < 0 && now === 0)) {
                    card.go(to, root.styleMid(style, card.pose, to), 720, [0.45, 0.05, 0.2, 1], 0)
                } else {
                    card.go(to, null, 520, [0.2, 1, 0.3, 1.04], Math.min(now, was) * 26)
                }
            }
            function onLeave(sel) {
                if (sel === card.index) {
                    root.strike(card.index, 1)
                    card.go(root.landPose(card.w, card.cw), null, 500, [0.22, 1, 0.36, 1], 200)
                } else {
                    card.go(root.below(card.pose, 1.35), null, 420, [0.55, 0, 0.9, 0.45], card.slot * 18)
                }
            }
            function onReleasePage() {
                if (!card.carrier) return
                // keep it where it is, now under its own motion
                motion.stop()
                card.pFrom = card.pTo = card.pose
                card.pMid = null
                card.t = 1
            }
            function onClaimPage(i) {
                if (i !== card.index) return
                motion.stop()
                card.rest = card.pose
            }
            function onDrop() {
                if (card.carrier) return   // the screen grows back out of it
                card.go(root.below(card.pose, 1.35), null, 400, [0.55, 0, 0.9, 0.45], card.slot * 20)
            }
        }

        // accent probe: paint the icon small and read its pixels, once per app class
        readonly property string probeUrl: {
            if (root.accents[w.cls]) return ""
            const file = root.iconFiles[root.iconName(w.cls)]
            return file ? "file://" + file : ""
        }
        onProbeUrlChanged: if (probeUrl) probe.loadImage(probeUrl)
        // the name can change once desktop entries finish loading
        readonly property string iname: root.iconName(w.cls)
        onInameChanged: if (!root.accents[w.cls]) root.resolveIcons([iname])
        Canvas {
            id: probe
            width: 32; height: 32
            opacity: 0
            enabled: false
            Component.onCompleted: if (card.probeUrl) loadImage(card.probeUrl)
            onImageLoaded: requestPaint()
            onPaint: {
                const url = card.probeUrl
                if (!url || !isImageLoaded(url)) return
                const ctx = getContext("2d")
                ctx.clearRect(0, 0, 32, 32)
                ctx.drawImage(url, 0, 0, 32, 32)
                const c = root.pickAccent(ctx.getImageData(0, 0, 32, 32).data, card.w.cls)
                card.accent = c
                root.accents = Object.assign({}, root.accents, { [card.w.cls]: c })
            }
        }

        // accent aura + drop shadow
        RectangularShadow {
            anchors.fill: frame
            radius: frame.radius
            blur: 46
            spread: (card.hot ? 6 : 2) + card.flare * 22
            color: card.glow
            opacity: Math.min(1, (card.hot ? 0.7 : (card.isFront ? 0.5 : 0.32)) + card.flare * 0.5)
            Behavior on opacity { enabled: card.flare === 0; NumberAnimation { duration: 180 } }
        }
        RectangularShadow {
            anchors.fill: frame
            radius: frame.radius
            offset.y: 22
            blur: 40
            color: "#000000"
            opacity: 0.55
        }

        ClippingRectangle {
            id: frame
            anchors.fill: parent
            radius: 14
            color: "#101216"

            Rectangle {
                anchors.fill: parent
                visible: !cap.hasContent
                gradient: Gradient {
                    GradientStop { position: 0; color: Qt.darker(card.accent, 3.2) }
                    GradientStop { position: 1; color: "#0d0f12" }
                }
                IconImage {
                    anchors.centerIn: parent
                    implicitSize: Math.min(parent.width, parent.height) * 0.32
                    source: card.icon
                }
            }

            ScreencopyView {
                id: cap
                anchors.fill: parent
                captureSource: root.phase !== "closed" ? root.toplevelFor(card.w.address) : null
                live: card.slot < 5 && root.phase !== "closed"
                paintCursor: false
            }

            // glass sheen
            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.09) }
                    GradientStop { position: 0.35; color: Qt.rgba(1, 1, 1, 0.0) }
                }
            }
            // flash of light on the face
            Rectangle {
                anchors.fill: parent
                color: Qt.lighter(card.glow, 1.6)
                opacity: card.flare * 0.22
            }
            // glint: a soft diagonal band of light sweeping across
            Rectangle {
                id: glint
                x: -width * 1.5
                y: -parent.height * 0.6
                width: parent.width * 0.28
                height: parent.height * 2.2
                rotation: 18
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0) }
                    GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.22) }
                    GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0) }
                }
                NumberAnimation on x {
                    id: glintAnim
                    running: false
                    to: frame.width + glint.width * 0.5
                    duration: 720
                    easing.type: Easing.OutCubic
                }
            }
            // depth fog
            Rectangle {
                anchors.fill: parent
                color: "#05070a"
                opacity: Math.max(0, Math.min(0.8, card.pose.d)) * (card.hot ? 0.4 : 1)
            }
        }

        // bold accent outline + inner hairline
        Rectangle {
            anchors.fill: frame
            radius: frame.radius
            color: "transparent"
            border.width: card.hot ? 5 : 4
            border.color: Qt.lighter(card.glow, 1 + (card.hot ? 0.15 : 0) + card.flare * 0.45)
            antialiasing: true
        }
        Rectangle {
            anchors.fill: frame
            anchors.margins: 4
            radius: frame.radius - 4
            color: "transparent"
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.10)
        }

        // the captured screen, pinned so the card's window lines up with its place in it;
        // everything around the window fades as the card shrinks into the stack
        Item {
            id: still
            visible: card.carrier && opacity > 0.001
            readonly property var r: root.pageRect(card.w)
            readonly property real k: card.cw / r.w
            readonly property real fade: Math.max(0, Math.min(1, (root.lift - 0.08) / 0.62))
            x: -r.x * k
            y: -r.y * k
            width: root.sw * k
            height: root.sh * k
            opacity: 1 - fade * fade * (3 - 2 * fade)
            ShaderEffectSource {
                anchors.fill: parent
                sourceItem: pageCap
                hideSource: true
                live: false
                visible: still.visible
            }
        }

        MouseArea {
            id: hover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.select(card.index)
        }
    }

    // --------------------------------------------------------------- window

    PanelWindow {
        id: win
        screen: root.screenTarget
        visible: root.phase === "capturing" || root.phase === "shown" || root.phase === "leaving"
        color: "transparent"
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "flip3d"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        Item {
            id: stage
            anchors.fill: parent
            focus: true

            Keys.onPressed: e => {
                switch (e.key) {
                case Qt.Key_Tab: case Qt.Key_Right: case Qt.Key_Down: case Qt.Key_L: case Qt.Key_J:
                    root.step(1); break
                case Qt.Key_Backtab: case Qt.Key_Left: case Qt.Key_Up: case Qt.Key_H: case Qt.Key_K:
                    root.step(-1); break
                case Qt.Key_Return: case Qt.Key_Enter: case Qt.Key_Space:
                    root.select(root.front); break
                case Qt.Key_Escape: case Qt.Key_Q:
                    root.cancel(); break
                default: return
                }
                e.accepted = true
            }

            // backdrop: the wallpaper, blurred and pushed back
            Item {
                anchors.fill: parent
                opacity: root.bgOp
                Rectangle { anchors.fill: parent; color: "#0b0d10" }
                Image {
                    id: wall
                    anchors.fill: parent
                    source: root.wallpaper
                    fillMode: Image.PreserveAspectCrop
                    sourceSize: Qt.size(root.sw / 2, root.sh / 2)
                    asynchronous: false
                    visible: false
                }
                MultiEffect {
                    anchors.fill: parent
                    source: wall
                    blurEnabled: true
                    blur: 1.0
                    blurMax: 48
                    brightness: -0.32
                    saturation: -0.25
                }
                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.0) }
                        GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.45) }
                    }
                }
                // ambient light: the front window's colour spills onto the backdrop
                RectangularShadow {
                    x: root.sw * 0.5 - width * 0.5 - root.sw * 0.08
                    y: root.sh * 0.5 - height * 0.5 + root.sh * 0.03
                    width: root.sw * 0.5
                    height: root.sh * 0.5
                    radius: height / 2
                    blur: root.sh * 0.35
                    spread: 0
                    color: root.curAccent
                    opacity: 0.22 + root.ambientBoost * 0.18
                    Behavior on color { ColorAnimation { duration: 450 } }
                }
            }

            MouseArea {
                anchors.fill: parent
                onClicked: root.cancel()
                property real acc: 0
                onWheel: w => {
                    acc += w.angleDelta.y !== 0 ? w.angleDelta.y : w.pixelDelta.y * 2
                    if (Math.abs(acc) >= 120 && !wheelGate.running) {
                        root.step(acc < 0 ? 1 : -1)
                        acc = 0
                        wheelGate.start()
                    }
                }
                Timer { id: wheelGate; interval: 110 }
            }

            Repeater {
                id: cardRep
                model: root.wins
                delegate: Card {}
            }

            // the screen as it was; shown (pinned to the front card) through a ShaderEffectSource
            ScreencopyView {
                id: pageCap
                width: root.sw
                height: root.sh
                z: -1
                captureSource: root.phase === "closed" || root.phase === "loading" ? null : root.screenTarget
                live: false
                paintCursor: false
                onHasContentChanged: if (hasContent) root.begin(true)
            }

            Rectangle {
                id: flashRect
                anchors.fill: parent
                z: 250000
                color: "#fff3c4"
                opacity: 0
            }
            // lightning, drawn on the GPU: three strokes per bolt (haze, body, hot core) plus a bloom
            Item {
                id: boltLayer
                anchors.fill: parent
                z: 260000
                opacity: root.boltAlpha
                visible: root.boltAlpha > 0
                layer.enabled: visible
                layer.effect: MultiEffect {
                    shadowEnabled: true
                    shadowColor: "#ffc830"
                    shadowBlur: 1.0
                    blurMax: 40
                    shadowHorizontalOffset: 0
                    shadowVerticalOffset: 0
                    shadowOpacity: 1
                }
                Repeater {
                    model: root.bolts
                    delegate: Shape {
                        id: bolt
                        required property var modelData
                        readonly property var line: modelData.pts.map(q => Qt.point(q[0], q[1]))
                        anchors.fill: parent
                        preferredRendererType: Shape.CurveRenderer
                        ShapePath {
                            strokeWidth: 16 * bolt.modelData.w
                            strokeColor: Qt.rgba(1, 0.77, 0.16, 0.22)
                            fillColor: "transparent"
                            capStyle: ShapePath.RoundCap
                            joinStyle: ShapePath.RoundJoin
                            PathPolyline { path: bolt.line }
                        }
                        ShapePath {
                            strokeWidth: 6.5 * bolt.modelData.w
                            strokeColor: Qt.rgba(1, 0.84, 0.3, 0.75)
                            fillColor: "transparent"
                            capStyle: ShapePath.RoundCap
                            joinStyle: ShapePath.RoundJoin
                            PathPolyline { path: bolt.line }
                        }
                        ShapePath {
                            strokeWidth: 2.5 * bolt.modelData.w
                            strokeColor: "#fffbe6"
                            fillColor: "transparent"
                            capStyle: ShapePath.RoundCap
                            joinStyle: ShapePath.RoundJoin
                            PathPolyline { path: bolt.line }
                        }
                    }
                }
            }

            // what's in front
            Rectangle {
                id: label
                z: 300000
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: root.sh * 0.06
                width: Math.min(root.sw * 0.6, row.implicitWidth + 36)
                height: 54
                radius: 16
                color: Qt.rgba(0.07, 0.08, 0.10, 0.72)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.08)
                opacity: root.active && root.cur ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 220 } }

                Row {
                    id: row
                    anchors.centerIn: parent
                    spacing: 12
                    Rectangle {
                        width: 4; height: 30; radius: 2
                        anchors.verticalCenter: parent.verticalCenter
                        color: root.cur ? (root.accents[root.cur.cls] || root.hashAccent(root.cur.cls)) : "transparent"
                        Behavior on color { ColorAnimation { duration: 220 } }
                    }
                    IconImage {
                        anchors.verticalCenter: parent.verticalCenter
                        implicitSize: 28
                        source: root.cur ? root.iconFor(root.cur.cls) : ""
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        Text {
                            text: root.cur ? root.cur.title : ""
                            color: "#dfe3e8"
                            font.pixelSize: 15
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                            width: Math.min(implicitWidth, root.sw * 0.6 - 120)
                        }
                        Text {
                            text: root.cur ? `${root.cur.cls}  ·  workspace ${root.cur.ws}` : ""
                            color: "#8a929c"
                            font.pixelSize: 12
                        }
                    }
                }
            }
        }
    }
}
