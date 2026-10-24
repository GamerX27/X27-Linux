// Glass side panel: clock, network, volume and power/session actions. Up/Down to move,
// Left/Right for volume, OK to activate (power actions need a second press to confirm).
import QtQuick
import QtQuick.Effects

FocusScope {
    id: cc

    property Item source
    property bool shown: false
    property int index: 0
    property int confirming: -1
    property var now: new Date()

    signal closed()
    signal settingsRequested()

    readonly property var items: [
        { kind: "volume", label: "Volume" },
        { kind: "action", label: "Settings", icon: "gear-six", run: () => cc.settingsRequested() },
        { kind: "action", label: "Sleep", icon: "moon", run: () => System.suspend() },
        { kind: "action", label: "Restart", icon: "arrow-clockwise", confirm: "Press again to restart", run: () => System.reboot() },
        { kind: "action", label: "Power Off", icon: "power", confirm: "Press again to power off", run: () => System.poweroff() },
        { kind: "action", label: "Exit to Login", icon: "sign-out", confirm: "Press again to exit", run: () => System.exitSession() }
    ]

    function open() { index = 0; confirming = -1; shown = true; System.refresh(); forceActiveFocus() }
    function close() { if (!shown) return; shown = false; closed() }

    visible: panel.opacity > 0

    Timer { interval: 1000; running: cc.shown; repeat: true; triggeredOnStart: true; onTriggered: cc.now = new Date() }

    Keys.onPressed: (e) => {
        const it = items[index]
        switch (e.key) {
        case Qt.Key_Up: index = Math.max(0, index - 1); confirming = -1; break
        case Qt.Key_Down: index = Math.min(items.length - 1, index + 1); confirming = -1; break
        case Qt.Key_Left: if (it.kind === "volume") System.setVolume(System.volume - 0.05); break
        case Qt.Key_Right: if (it.kind === "volume") System.setVolume(System.volume + 0.05); break
        case Qt.Key_Return: case Qt.Key_Enter: case Qt.Key_Select: case Qt.Key_Space:
            if (it.kind === "volume") System.toggleMute()
            else if (it.confirm && confirming !== index) confirming = index
            else { confirming = -1; close(); it.run() }
            break
        case Qt.Key_Escape: case Qt.Key_Back: case Qt.Key_Backspace: case Qt.Key_Menu: case Qt.Key_HomePage:
            close(); break
        default: return
        }
        e.accepted = true
    }

    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: cc.shown ? 0.35 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.med } }
        MouseArea { anchors.fill: parent; enabled: cc.shown; onClicked: cc.close() }
    }

    Item {
        id: panel
        width: 560 * Theme.s
        height: content.implicitHeight + 72 * Theme.s
        y: 40 * Theme.s
        x: cc.shown ? parent.width - width - 40 * Theme.s : parent.width + 20 * Theme.s
        opacity: cc.shown ? 1 : 0
        Behavior on x { NumberAnimation { duration: Theme.med + 80; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: Theme.med } }

        RectangularShadow {
            anchors.fill: parent
            radius: 36 * Theme.s
            blur: 80 * Theme.s
            offset.y: 20 * Theme.s
            color: "#b0000000"
        }

        Loader {
            anchors.fill: parent
            active: cc.visible
            sourceComponent: Item {
                ShaderEffectSource {
                    id: behind
                    anchors.fill: parent
                    sourceItem: cc.source
                    sourceRect: Qt.rect(panel.x, panel.y, panel.width, panel.height)
                    visible: false
                }

                MultiEffect {
                    anchors.fill: parent
                    source: behind
                    blurEnabled: true; blur: 1; blurMax: 64
                    saturation: 0.5
                    maskEnabled: true
                    maskSource: panelMask
                    maskThresholdMin: 0.5
                    maskSpreadAtMin: 1
                }

                Rectangle {
                    id: panelMask
                    anchors.fill: parent
                    radius: 36 * Theme.s
                    visible: false
                    layer.enabled: true
                }
            }
        }

        Rectangle {
            anchors.fill: parent
            radius: 36 * Theme.s
            color: Theme.glass
            border.color: Theme.glassEdge
            border.width: Math.max(1, Theme.s)
        }

        Column {
            id: content
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 36 * Theme.s }
            spacing: 10 * Theme.s

            Text {
                text: Qt.formatTime(cc.now, "HH:mm")
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: 88 * Theme.s
                font.weight: Font.DemiBold
                font.letterSpacing: -2 * Theme.s
            }
            Text {
                text: cc.now.toLocaleDateString(Qt.locale(), "dddd d MMMM")
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: 26 * Theme.s
            }
            Item { width: 1; height: 14 * Theme.s }
            Row {
                spacing: 14 * Theme.s
                Rectangle {
                    width: 14 * Theme.s; height: width; radius: width / 2
                    anchors.verticalCenter: parent.verticalCenter
                    color: System.network === "Not connected" ? "#ff453a" : "#30d158"
                }
                Text {
                    text: System.network || "Checking network…"
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 24 * Theme.s
                }
            }
            Item { width: 1; height: 18 * Theme.s }

            Repeater {
                model: cc.items
                delegate: Rectangle {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property bool current: cc.index === index
                    width: content.width
                    height: (modelData.kind === "volume" ? 112 : 76) * Theme.s
                    radius: 20 * Theme.s
                    color: current ? Theme.focusFill : "#14ffffff"
                    scale: current ? 1.03 : 1
                    Behavior on color { ColorAnimation { duration: Theme.fast } }
                    Behavior on scale { SpringAnimation { spring: 4; damping: 0.3 } }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: if (Pointer.active) { cc.index = row.index; cc.confirming = -1 }
                        onPositionChanged: if (Pointer.active && cc.index !== row.index) { cc.index = row.index; cc.confirming = -1 }
                        onClicked: (m) => {
                            if (row.modelData.kind === "volume") System.setVolume(m.x / width)
                            else if (row.modelData.confirm && cc.confirming !== row.index) cc.confirming = row.index
                            else { cc.close(); row.modelData.run() }
                        }
                    }

                    Icon {
                        id: rowIcon
                        visible: !!row.modelData.icon
                        x: 26 * Theme.s
                        anchors.verticalCenter: parent.verticalCenter
                        name: row.modelData.icon || ""
                        size: 28 * Theme.s
                        color: row.current ? Theme.focusText : Theme.text
                    }

                    Text {
                        anchors { left: parent.left; leftMargin: (row.modelData.icon ? 72 : 28) * Theme.s; top: parent.top; topMargin: (row.modelData.kind === "volume" ? 18 : 0) * Theme.s }
                        height: row.modelData.kind === "volume" ? implicitHeight : parent.height
                        verticalAlignment: Text.AlignVCenter
                        text: row.modelData.kind === "volume"
                              ? "Volume" + (System.muted ? "  ·  Muted" : "  ·  " + Math.round(System.volume * 100) + "%")
                              : (cc.confirming === row.index ? row.modelData.confirm : row.modelData.label)
                        color: row.current ? Theme.focusText : Theme.text
                        font.family: Theme.font
                        font.pixelSize: 26 * Theme.s
                        font.weight: row.current ? Font.DemiBold : Font.Normal
                    }

                    Rectangle {
                        visible: row.modelData.kind === "volume"
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 28 * Theme.s }
                        height: 10 * Theme.s
                        radius: height / 2
                        color: row.current ? "#26000000" : "#26ffffff"
                        Rectangle {
                            height: parent.height; radius: parent.radius
                            width: parent.width * (System.muted ? 0 : System.volume)
                            color: row.current ? "#000000" : "#ffffff"
                            Behavior on width { NumberAnimation { duration: Theme.fast } }
                        }
                    }
                }
            }
        }
    }
}
