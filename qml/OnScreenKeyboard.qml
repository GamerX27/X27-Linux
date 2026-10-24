// TV text entry: a d-pad navigable keyboard with shift, symbols, space, backspace and a
// password reveal toggle. A physical or remote keyboard can type into it directly.
import QtQuick
import QtQuick.Effects

FocusScope {
    id: kb

    property string title: ""
    property string text: ""
    property bool password: false
    property bool reveal: false
    property bool shift: false
    property bool symbols: false
    property bool shown: false
    property var callback: null
    property int row: 0
    property int col: 0

    signal finished()

    readonly property var letters: ["1234567890", "qwertyuiop", "asdfghjkl-", "zxcvbnm_.@"]
    readonly property var symbolRows: ["1234567890", "!#$%&*()+=", "/\\:;'\"?,<>", "[]{}|~^`€£"]
    readonly property var keys: {
        const src = symbols ? symbolRows : letters
        const rows = src.map(line => line.split("").map(ch => ({ label: shift && !symbols ? ch.toUpperCase() : ch, w: 1 })))
        const bottom = [
            { label: "", icon: "arrow-fat-up", act: "shift", w: 1.5 },
            { label: symbols ? "abc" : "#+=", act: "symbols", w: 1.5 },
            { label: "space", act: "space", w: 3 },
            { label: "", icon: "backspace", act: "back", w: 1.5 }
        ]
        if (password) bottom.push({ label: "", icon: reveal ? "eye-slash" : "eye", act: "reveal", w: 1.5 })
        bottom.push({ label: "Done", act: "done", w: 2, accent: true })
        bottom.push({ label: "Cancel", act: "cancel", w: 2 })
        rows.push(bottom)
        return rows
    }

    function open(t, isPassword, cb) {
        title = t; password = isPassword; callback = cb
        text = ""; reveal = false; shift = false; symbols = false; row = 1; col = 0
        shown = true
        forceActiveFocus()
    }

    function finish(ok) {
        shown = false
        const cb = callback, value = text
        callback = null
        text = ""
        finished()
        if (ok && cb) cb(value)
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

    function press(k) {
        switch (k.act) {
        case "shift": shift = !shift; break
        case "symbols": symbols = !symbols; col = Math.min(col, keys[row].length - 1); break
        case "space": text += " "; break
        case "back": text = text.slice(0, -1); break
        case "reveal": reveal = !reveal; break
        case "done": finish(true); break
        case "cancel": finish(false); break
        default:
            text += k.label
            if (shift) shift = false
        }
    }

    visible: opacity > 0
    opacity: shown ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Theme.fast } }

    Keys.onPressed: (e) => {
        switch (e.key) {
        case Qt.Key_Left: col = Math.max(0, col - 1); break
        case Qt.Key_Right: col = Math.min(keys[row].length - 1, col + 1); break
        case Qt.Key_Up: moveRow(-1); break
        case Qt.Key_Down: moveRow(1); break
        case Qt.Key_Return: case Qt.Key_Enter: case Qt.Key_Select: press(keys[row][col]); break
        case Qt.Key_Backspace: text = text.slice(0, -1); break
        case Qt.Key_Escape: case Qt.Key_Back: finish(false); break
        default:
            if (e.text.length === 1 && e.text >= " " && !(e.modifiers & Qt.ControlModifier)) text += e.text
            else return
        }
        e.accepted = true
    }

    Rectangle { anchors.fill: parent; color: "#b3000000" }

    Rectangle {
        id: panel
        anchors.centerIn: parent
        width: grid.width + 80 * Theme.s
        height: col0.implicitHeight + 80 * Theme.s
        radius: 36 * Theme.s
        color: "#f21c1c1e"
        border.color: Theme.glassEdge
        border.width: Math.max(1, Theme.s)
        scale: kb.shown ? 1 : 0.96
        Behavior on scale { NumberAnimation { duration: Theme.med; easing.type: Easing.OutCubic } }

        Column {
            id: col0
            anchors.centerIn: parent
            spacing: 24 * Theme.s

            Text {
                text: kb.title
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: 34 * Theme.s
                font.weight: Font.DemiBold
            }

            Rectangle {
                width: grid.width; height: 76 * Theme.s
                radius: 16 * Theme.s
                color: "#2c2c2e"
                border.color: "#0a84ff"
                border.width: 2 * Theme.s
                Text {
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 24 * Theme.s }
                    text: (kb.password && !kb.reveal ? "•".repeat(kb.text.length) : kb.text) + "▏"
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 30 * Theme.s
                    elide: Text.ElideLeft
                }
            }

            Column {
                id: grid
                spacing: 10 * Theme.s
                readonly property real unit: 84 * Theme.s

                Repeater {
                    model: kb.keys
                    Row {
                        required property var modelData
                        required property int index
                        readonly property int r: index
                        spacing: 10 * Theme.s

                        Repeater {
                            model: parent.modelData
                            Rectangle {
                                required property var modelData
                                required property int index
                                readonly property bool current: kb.row === parent.r && kb.col === index
                                readonly property bool on: (modelData.act === "shift" && kb.shift) || (modelData.act === "reveal" && kb.reveal)
                                width: grid.unit * modelData.w + 10 * Theme.s * (modelData.w - 1)
                                height: 72 * Theme.s
                                radius: 14 * Theme.s
                                color: current ? Theme.focusFill : modelData.accent ? "#0a84ff" : on ? "#636366" : "#3a3a3c"
                                scale: current ? 1.08 : 1
                                z: current ? 1 : 0
                                Behavior on scale { SpringAnimation { spring: 5; damping: 0.3 } }
                                Icon {
                                    anchors.centerIn: parent
                                    visible: !!parent.modelData.icon
                                    name: parent.modelData.icon || ""
                                    size: 30 * Theme.s
                                    color: parent.current ? Theme.focusText : Theme.text
                                }
                                Text {
                                    anchors.centerIn: parent
                                    text: parent.modelData.label
                                    color: parent.current ? Theme.focusText : Theme.text
                                    font.family: Theme.font
                                    font.pixelSize: (parent.modelData.w > 1 ? 24 : 30) * Theme.s
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
