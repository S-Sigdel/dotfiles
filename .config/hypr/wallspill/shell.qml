// Wallpaper spill: the new wallpaper bleeds out from the centre in an organic,
// noisy blob (spill.frag). Stills are then handed to awww and this goes away;
// live wallpapers (mp4/webm/gif) keep playing here, already moving during the
// spill, while awww holds their first frame underneath (apply.sh).
// Run:   qs -p ~/.config/hypr/wallspill          (started by hyprland.lua)
// Use:   qs -p ~/.config/hypr/wallspill ipc call spill to <monitor> <file>
//        qs -p ~/.config/hypr/wallspill ipc call spill show <monitor> <file>   (no animation)
//        qs -p ~/.config/hypr/wallspill ipc call spill cover <monitor> true|false
//
// A live wallpaper pauses while tiled/fullscreen windows cover its monitor
// (scripts/desktop-idle.sh sends `cover`), so it costs nothing behind your work.
//
// It's a background-layer surface mapped fresh for every spill, so it sits on
// top of awww's wallpaper but under the visualizer bars and windows.

pragma ComponentBehavior: Bound
import QtQuick
import QtMultimedia
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: root

    property var screenTarget: Quickshell.screens[0]
    property string monitor: ""
    property bool spilling: false
    property int cur: -1           // slot playing the live wallpaper, -1 = none (awww shows a still)
    property int inc: 0            // slot spilling in
    property real progress: 0
    property real seed: 0
    property point origin: Qt.point(0.5, 0.5)
    property var queued: null      // a spill asked for while one is running
    property var coverMap: ({})    // monitor -> covered by windows (desktop-idle.sh)
    readonly property bool hold: !!coverMap[monitor] && !spilling

    readonly property var slots: [slotA, slotB]

    function isLive(f) { return /\.(mp4|webm|mkv|mov|gif)$/i.test(f) }

    IpcHandler {
        target: "spill"
        function to(monitor: string, path: string): void { root.start(monitor, path, true) }
        function show(monitor: string, path: string): void { root.start(monitor, path, false) }
        function cover(monitor: string, covered: bool): void {
            const m = Object.assign({}, root.coverMap)
            m[monitor] = covered
            root.coverMap = m
        }
    }

    function start(mon, file, animate) {
        if (spilling) { queued = [mon, file, animate]; return }
        const s = Quickshell.screens.find(x => x.name === mon)
        if (!s) { apply(mon, file); return }
        if (screenTarget !== s) {
            dropLive()                 // that monitor keeps awww's still of it
            screenTarget = s
        }
        monitor = mon
        if (!animate) {
            apply(mon, file)
            if (!isLive(file)) { dropLive(); return }
            const i = cur === 0 ? 1 : 0
            slots[i].file = file
            const old = cur
            cur = i
            if (old >= 0) slots[old].file = ""
            return
        }
        inc = cur === 0 ? 1 : 0
        seed = Math.random() * 100
        origin = Qt.point(0.5 + (Math.random() - 0.5) * 0.08, 0.5 + (Math.random() - 0.5) * 0.08)
        progress = 0
        spilling = true
        watchdog.restart()
        slots[inc].file = file
        if (slots[inc].ready) grow.restart()   // otherwise onReadyChanged starts it
    }

    // never hang: if the new wallpaper won't load or play, just set it and reset
    Timer {
        id: watchdog
        interval: 5000
        onTriggered: {
            if (!root.spilling) return
            grow.stop()
            const f = root.slots[root.inc].file
            root.slots[root.inc].file = ""
            root.dropLive()
            root.spilling = false
            root.queued = null
            if (f) root.apply(root.monitor, f)
        }
    }

    function dropLive() {
        if (cur >= 0) slots[cur].file = ""
        cur = -1
    }

    function apply(mon, file) {
        setWall.command = ["sh", Qt.resolvedUrl("apply.sh").toString().replace("file://", ""), mon, file]
        setWall.running = true
    }

    NumberAnimation {
        id: grow
        target: root; property: "progress"; from: 0; to: 1; duration: 1100
        easing.type: Easing.BezierSpline; easing.bezierCurve: [0.55, 0, 0.35, 1, 1, 1]
        onFinished: root.apply(root.monitor, root.slots[root.inc].file)
    }

    // the real wallpaper is in place underneath: give it a frame, then settle
    Process {
        id: setWall
        onExited: if (root.spilling) settle.restart()
    }
    Timer {
        id: settle
        interval: 120
        onTriggered: {
            watchdog.stop()
            const s = root.slots[root.inc]
            const old = root.cur
            if (root.isLive(s.file)) {
                root.cur = root.inc            // keeps playing, now as the wallpaper
                if (old >= 0) root.slots[old].file = ""
                root.spilling = false
            } else {
                // window goes in this same frame; awww already shows the same still.
                // (cleared now, not later: a queued spill below reuses this slot)
                root.cur = -1
                root.spilling = false
                s.file = ""
                if (old >= 0) root.slots[old].file = ""
            }
            if (root.queued) {
                const q = root.queued
                root.queued = null
                root.start(q[0], q[1], q[2])
            }
        }
    }

    // one wallpaper: a video, an animated gif or a still
    component Slot: Item {
        id: slot
        property string file: ""
        readonly property url url: file ? "file://" + file : ""
        readonly property bool video: /\.(mp4|webm|mkv|mov)$/i.test(file)
        readonly property bool gif: /\.gif$/i.test(file)
        readonly property bool ready: file !== "" && (video ? framed : gif ? anim.status === AnimatedImage.Ready
                                                                           : still.status === Image.Ready)
        property bool framed: false
        signal readied()
        onReadyChanged: if (ready) readied()
        onFileChanged: framed = false

        // paused behind windows; it still loads and shows its first frame
        readonly property bool hold: root.hold
        onHoldChanged: if (video && framed) hold ? player.pause() : player.play()

        MediaPlayer {
            id: player
            source: slot.video ? slot.url : ""
            loops: MediaPlayer.Infinite
            videoOutput: out
            onSourceChanged: if (source.toString()) play()
            onMediaStatusChanged: if (mediaStatus === MediaPlayer.BufferedMedia) firstFrame.restart()
        }
        Timer {
            id: firstFrame; interval: 60
            onTriggered: { slot.framed = true; if (slot.hold) player.pause() }
        }
        VideoOutput {
            id: out
            anchors.fill: parent
            fillMode: VideoOutput.PreserveAspectCrop
            visible: slot.video
        }
        AnimatedImage {
            id: anim
            anchors.fill: parent
            source: slot.gif ? slot.url : ""
            fillMode: Image.PreserveAspectCrop
            playing: slot.gif && !slot.hold
            cache: false
            visible: slot.gif
        }
        Image {
            id: still
            anchors.fill: parent
            source: !slot.video && !slot.gif ? slot.url : ""
            sourceSize: Qt.size(width, height)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: false
            visible: !slot.video && !slot.gif
            onStatusChanged: if (status === Image.Error && root.spilling) root.apply(root.monitor, slot.file)
        }
    }

    PanelWindow {
        id: win
        screen: root.screenTarget
        visible: root.spilling || root.cur >= 0
        color: "transparent"
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Background
        WlrLayershell.namespace: "wallspill"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        mask: Region {}            // never takes input

        // the live wallpaper shows directly; the one spilling in is drawn by the shader
        Slot { id: slotA; anchors.fill: parent; onReadied: if (root.spilling && root.inc === 0) grow.restart() }
        Slot { id: slotB; anchors.fill: parent; onReadied: if (root.spilling && root.inc === 1) grow.restart() }
        ShaderEffectSource { id: srcA; sourceItem: slotA; live: true; visible: false; hideSource: root.cur !== 0 }
        ShaderEffectSource { id: srcB; sourceItem: slotB; live: true; visible: false; hideSource: root.cur !== 1 }

        ShaderEffect {
            anchors.fill: parent
            visible: root.spilling
            property variant src: root.inc === 0 ? srcA : srcB
            property real progress: root.progress
            property real aspect: width / Math.max(1, height)
            property real seed: root.seed
            property point origin: root.origin
            // far enough that the wobbliest edge still clears the farthest corner
            property real reach: {
                const ox = Math.max(origin.x, 1 - origin.x) * aspect
                const oy = Math.max(origin.y, 1 - origin.y)
                return Math.sqrt(ox * ox + oy * oy) + 0.35
            }
            fragmentShader: "spill.frag.qsb"
        }
    }
}
