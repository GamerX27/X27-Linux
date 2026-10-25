// Gamepad as Mouse's typing keyboard (Y): a full keyboard docked at the bottom, on labwc's
// overlay layer, that never takes keyboard focus, so the app keeps it and each key is typed
// into the app as it's pressed (Mouse.tapKey). The pad drives it through Mouse.typingKey:
// D-pad/left stick move, A presses, X is Shift, B/Y close it. Shift, Ctrl and Alt are sticky
// for the next key (Ctrl+L, Ctrl+A); Caps stays on for letters until pressed again.
import QtQuick
import QtQuick.Window
import org.kde.layershell 1.0 as LayerShell

Window {
    id: kb

    property int row: 2
    property int col: 1
    property bool shift: false
    property bool ctrl: false
    property bool alt: false
    property bool caps: false

    // k: evdev key, t/s: plain and shifted label, w: width in key units (15 per row).
    function chars(plain, shifted) {
        return plain.split("").map((c, i) => ({ k: codes[c], t: c, s: shifted[i], w: 1, letter: c >= "a" && c <= "z" }))
    }
    readonly property var codes: {
        const m = { "`": "KEY_GRAVE", "-": "KEY_MINUS", "=": "KEY_EQUAL", "[": "KEY_LEFTBRACE", "]": "KEY_RIGHTBRACE",
                    "\\": "KEY_BACKSLASH", ";": "KEY_SEMICOLON", "'": "KEY_APOSTROPHE", ",": "KEY_COMMA", ".": "KEY_DOT", "/": "KEY_SLASH" }
        for (const c of "abcdefghijklmnopqrstuvwxyz0123456789") m[c] = "KEY_" + c.toUpperCase()
        return m
    }
    readonly property var keys: [
        [...chars("`1234567890-=", "~!@#$%^&*()_+"), { k: "KEY_BACKSPACE", icon: "backspace", w: 2 }],
        [{ k: "KEY_TAB", t: "Tab", w: 1.5 }, ...chars("qwertyuiop[]", "QWERTYUIOP{}"), { k: "KEY_BACKSLASH", t: "\\", s: "|", w: 1.5 }],
        [{ act: "caps", t: "Caps", w: 1.75 }, ...chars("asdfghjkl;'", "ASDFGHJKL:\""), { k: "KEY_ENTER", t: "Enter", w: 2.25, accent: true }],
        [{ act: "shift", icon: "arrow-fat-up", w: 2.25 }, ...chars("zxcvbnm,./", "ZXCVBNM<>?"), { act: "shift", icon: "arrow-fat-up", w: 1.75 }, { k: "KEY_UP", t: "↑", w: 1 }],
        [{ k: "KEY_ESC", t: "Esc", w: 1.5 }, { act: "ctrl", t: "Ctrl", w: 1.5 }, { act: "alt", t: "Alt", w: 1.5 }, { k: "KEY_SPACE", t: "", w: 6 },
         { act: "hide", icon: "keyboard", w: 1.5 }, { k: "KEY_LEFT", t: "←", w: 1 }, { k: "KEY_DOWN", t: "↓", w: 1 }, { k: "KEY_RIGHT", t: "→", w: 1 }]
    ]

    function label(key) {
        if (key.s === undefined) return key.t || ""
        return (key.letter ? shift !== caps : shift) ? key.s : key.t
    }

    function isOn(key) {
        return (key.act === "shift" && shift) || (key.act === "ctrl" && ctrl) || (key.act === "alt" && alt) || (key.act === "caps" && caps)
    }

    function press(key) {
        switch (key.act) {
        case "shift": shift = !shift; return
        case "ctrl": ctrl = !ctrl; return
        case "alt": alt = !alt; return
        case "caps": caps = !caps; return
        case "hide": Mouse.set_typing(false); return
        }
        const mods = []
        if (key.letter ? shift !== caps : shift) mods.push("shift")
        if (ctrl) mods.push("ctrl")
        if (alt) mods.push("alt")
        Mouse.tapKey(key.k, mods)
        shift = false; ctrl = false; alt = false
    }

    function center(r, c) {
        let x = 0
        for (let i = 0; i < c; i++) x += keys[r][i].w
        return x + keys[r][c].w / 2
    }

    function moveRow(d) {
        const r = Math.max(0, Math.min(keys.length - 1, row + d))
        if (r === row) return
        const target = center(row, col)
        let best = 0, dist = 1e9
        for (let c = 0; c < keys[r].length; c++) {
            const dd = Math.abs(center(r, c) - target)
            if (dd < dist) { dist = dd; best = c }
        }
        row = r; col = best
    }

    color: "transparent"
    flags: Qt.FramelessWindowHint
    width: 1600
    height: panel.height + 56 * Theme.s
    visible: Mouse.typing
    title: "X27 TV Keyboard"

    LayerShell.Window.scope: "x27-tv-keyboard"
    LayerShell.Window.layer: LayerShell.Window.LayerOverlay
    LayerShell.Window.anchors: LayerShell.Window.AnchorBottom | LayerShell.Window.AnchorLeft | LayerShell.Window.AnchorRight
    LayerShell.Window.exclusionZone: -1
    LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityNone

    onVisibleChanged: if (visible) { shift = false; ctrl = false; alt = false }

    Connections {
        target: Mouse
        function onTypingKey(action) {
            switch (action) {
            case "left": kb.col = Math.max(0, kb.col - 1); break
            case "right": kb.col = Math.min(kb.keys[kb.row].length - 1, kb.col + 1); break
            case "up": kb.moveRow(-1); break
            case "down": kb.moveRow(1); break
            case "press": kb.press(kb.keys[kb.row][kb.col]); break
            case "shift": kb.shift = !kb.shift; break
            case "close": Mouse.set_typing(false); break
            }
        }
    }

    Rectangle {
        id: panel
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 28 * Theme.s }
        width: grid.width + 48 * Theme.s
        height: col0.implicitHeight + 40 * Theme.s
        radius: 28 * Theme.s
        color: "#f51c1c1e"
        border.color: Theme.glassEdge
        border.width: Math.max(1, Theme.s)

        Column {
            id: col0
            anchors.centerIn: parent
            spacing: 14 * Theme.s

            Text {
                width: grid.width
                text: "A press · X shift · LB backspace · RB space · Start enter · B or Y close"
                color: Theme.dim
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignHCenter
                font.family: Theme.font
                font.pixelSize: 18 * Theme.s
            }

            Column {
                id: grid
                spacing: 8 * Theme.s
                readonly property real unit: 62 * Theme.s

                Repeater {
                    model: kb.keys
                    Row {
                        required property var modelData
                        required property int index
                        readonly property int r: index
                        spacing: 8 * Theme.s

                        Repeater {
                            model: parent.modelData
                            Rectangle {
                                required property var modelData
                                required property int index
                                readonly property bool current: kb.row === parent.r && kb.col === index
                                readonly property bool on: kb.isOn(modelData)
                                width: grid.unit * modelData.w + 8 * Theme.s * (modelData.w - 1)
                                height: 54 * Theme.s
                                radius: 11 * Theme.s
                                color: current ? Theme.focusFill : on ? "#0a84ff" : modelData.accent ? "#48484a" : "#3a3a3c"
                                scale: current ? 1.08 : 1
                                z: current ? 1 : 0
                                Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutQuad } }
                                Icon {
                                    anchors.centerIn: parent
                                    visible: !!parent.modelData.icon
                                    name: parent.modelData.icon || ""
                                    size: 24 * Theme.s
                                    color: parent.current ? Theme.focusText : Theme.text
                                }
                                Text {
                                    anchors.centerIn: parent
                                    text: kb.label(parent.modelData)
                                    color: parent.current ? Theme.focusText : Theme.text
                                    font.family: Theme.font
                                    font.pixelSize: (parent.modelData.s === undefined ? 19 : 24) * Theme.s
                                    font.weight: Font.Medium
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: { kb.row = parent.parent.r; kb.col = parent.index; kb.press(parent.modelData) }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
