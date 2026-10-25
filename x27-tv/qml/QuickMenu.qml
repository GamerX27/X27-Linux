// In-app quick menu: a panel over whatever app is open, on labwc's overlay layer, with the app
// dimmed and paused (frozen) behind it. Opened by Guide/Home or Super+Q in an app: Home, Exit
// App, volume, audio output, Gamepad as Mouse, Settings, Sleep; Guide or Back closes it.
import QtQuick
import QtQuick.Window
import org.kde.layershell 1.0 as LayerShell

Window {
    id: qm

    property string appId: ""
    property string appName: ""
    property int index: 0
    property int confirming: -1
    property var now: new Date()

    signal homeRequested()
    signal settingsRequested()

    readonly property var sink: Audio.sinks.find(s => s.default) || null
    readonly property var items: [
        { kind: "action", label: "Home", icon: "squares-four", run: () => qm.homeRequested() },
        ...(appId ? [{ kind: "action", label: "Exit " + (appName || "App"), icon: "x-circle",
                       run: () => { Launcher.closeApp(qm.appId); qm.homeRequested() } }] : []),
        { kind: "volume", label: "Volume" },
        ...(Audio.sinks.length > 1 ? [{ kind: "output", label: "Output" }] : []),
        ...(Mouse.available ? [{ kind: "mouse", label: "Gamepad as Mouse" }] : []),
        { kind: "action", label: "Settings", icon: "gear-six", run: () => qm.settingsRequested() },
        { kind: "action", label: "Sleep", icon: "moon", run: () => System.suspend() }
    ]

    function open(id, name) {
        appId = id; appName = name; index = 0; confirming = -1
        visible = true
        requestActivate()
        panel.forceActiveFocus()
        Launcher.pauseApp(id)
        System.refresh(); Audio.refresh()
    }
    function close() {
        visible = false
        Launcher.resumeApp(appId)
    }

    function cycleOutput(d) {
        const sinks = Audio.sinks
        if (sinks.length < 2) return
        const i = Math.max(0, sinks.findIndex(s => s.default))
        Audio.setDefault(sinks[(i + d + sinks.length) % sinks.length].id)
    }

    function activate(it) {
        if (it.kind === "volume") { System.toggleMute(); return }
        if (it.kind === "output") { cycleOutput(1); return }
        if (it.kind === "mouse") { Mouse.toggle(); if (Mouse.enabled) close(); return }
        if (it.confirm && confirming !== index) { confirming = index; return }
        confirming = -1
        close()
        it.run()
    }

    color: "transparent"
    flags: Qt.FramelessWindowHint
    visible: false
    width: 1600
    height: 900
    title: "X27 TV Quick Menu"

    LayerShell.Window.scope: "x27-tv-quick"
    LayerShell.Window.layer: LayerShell.Window.LayerOverlay
    LayerShell.Window.anchors: LayerShell.Window.AnchorTop | LayerShell.Window.AnchorBottom
                               | LayerShell.Window.AnchorLeft | LayerShell.Window.AnchorRight
    LayerShell.Window.exclusionZone: -1
    LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityExclusive

    Timer { interval: 1000; running: qm.visible; repeat: true; triggeredOnStart: true; onTriggered: qm.now = new Date() }

    Rectangle {
        anchors.fill: parent
        color: "#73000000"
        MouseArea { anchors.fill: parent; onClicked: qm.close() }
    }

    Item {
        id: panel
        anchors { top: parent.top; bottom: parent.bottom; right: parent.right; margins: 32 * Theme.s }
        width: 560 * Theme.s
        focus: true

        Keys.onPressed: (e) => {
            const it = qm.items[qm.index]
            switch (e.key) {
            case Qt.Key_Up: qm.index = Math.max(0, qm.index - 1); qm.confirming = -1; break
            case Qt.Key_Down: qm.index = Math.min(qm.items.length - 1, qm.index + 1); qm.confirming = -1; break
            case Qt.Key_Left: case Qt.Key_Right: {
                const d = e.key === Qt.Key_Left ? -1 : 1
                if (it.kind === "volume") System.setVolume(System.volume + 0.05 * d)
                else if (it.kind === "output") qm.cycleOutput(d)
                break
            }
            case Qt.Key_Return: case Qt.Key_Enter: case Qt.Key_Select: case Qt.Key_Space:
                qm.activate(it); break
            case Qt.Key_Escape: case Qt.Key_Back: case Qt.Key_Backspace: case Qt.Key_Menu: case Qt.Key_HomePage:
                qm.close(); break
            default: return
            }
            e.accepted = true
        }

        Rectangle {
            anchors.fill: parent
            radius: 36 * Theme.s
            color: "#fa1c1c1e"
            border.color: Theme.glassEdge
            border.width: Math.max(1, Theme.s)
        }

        Column {
            id: content
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 36 * Theme.s }
            spacing: 10 * Theme.s

            Text {
                text: Qt.formatTime(qm.now, "HH:mm")
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: 72 * Theme.s
                font.weight: Font.DemiBold
                font.letterSpacing: -2 * Theme.s
            }
            Text {
                width: parent.width
                text: qm.appName ? "In " + qm.appName : "Quick Menu"
                color: Theme.dim
                elide: Text.ElideRight
                font.family: Theme.font
                font.pixelSize: 26 * Theme.s
            }
            Item { width: 1; height: 18 * Theme.s }

            Repeater {
                model: qm.items
                delegate: Rectangle {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property bool current: qm.index === index
                    readonly property bool slider: modelData.kind === "volume"
                    readonly property bool mouse: modelData.kind === "mouse"
                    width: content.width
                    height: (slider ? 112 : mouse ? 104 : 76) * Theme.s
                    radius: 20 * Theme.s
                    color: current ? Theme.focusFill : "#14ffffff"
                    scale: current ? 1.03 : 1
                    Behavior on color { ColorAnimation { duration: Theme.fast } }
                    Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutQuad } }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: { qm.index = row.index; qm.confirming = -1 }
                        onClicked: (m) => {
                            qm.index = row.index
                            if (row.slider) System.setVolume(m.x / width)
                            else qm.activate(row.modelData)
                        }
                    }

                    Icon {
                        visible: !!row.modelData.icon
                        x: 26 * Theme.s
                        anchors.verticalCenter: parent.verticalCenter
                        name: row.modelData.icon || ""
                        size: 28 * Theme.s
                        color: row.current ? Theme.focusText : Theme.text
                    }

                    Text {
                        anchors { left: parent.left; leftMargin: (row.modelData.icon ? 72 : 28) * Theme.s; right: parent.right; rightMargin: 28 * Theme.s
                                  top: parent.top; topMargin: (row.slider || row.mouse ? 18 : 0) * Theme.s }
                        height: row.slider || row.mouse ? implicitHeight : parent.height
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                        text: row.slider ? "Volume" + (System.muted ? "  ·  Muted" : "  ·  " + Math.round(System.volume * 100) + "%")
                            : row.modelData.kind === "output" ? "‹  " + (qm.sink ? qm.sink.name : "Output") + "  ›"
                            : row.mouse ? "Gamepad as Mouse  ·  " + (Mouse.enabled ? "On" : "Off")
                            : (qm.confirming === row.index ? row.modelData.confirm : row.modelData.label)
                        color: row.current ? Theme.focusText : Theme.text
                        font.family: Theme.font
                        font.pixelSize: 26 * Theme.s
                        font.weight: row.current ? Font.DemiBold : Font.Normal
                    }

                    Text {
                        visible: row.mouse
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 28 * Theme.s; bottomMargin: 16 * Theme.s }
                        text: "A click · X right-click · Y keyboard · L3+R3 off"
                        color: row.current ? "#99000000" : Theme.dim
                        elide: Text.ElideRight
                        font.family: Theme.font
                        font.pixelSize: 18 * Theme.s
                    }

                    Rectangle {
                        visible: row.slider
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

        Text {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 36 * Theme.s }
            text: "Guide or Back returns to " + (qm.appName || "the app")
            color: Theme.faint
            elide: Text.ElideRight
            font.family: Theme.font
            font.pixelSize: 20 * Theme.s
        }
    }
}
