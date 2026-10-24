// Root window: Top Shelf + app row, the Control Center and All Apps overlays, and the
// remote/gamepad/keyboard navigation between them.
import QtQuick
import QtQuick.Window
import QtQuick.Effects

Window {
    id: root

    width: 1600
    height: 900
    visible: true
    visibility: startWindowed ? Window.Windowed : Window.FullScreen
    color: "black"
    title: "X27 TV"

    property int current: 0
    property string mode: "row"
    property var now: new Date()

    readonly property var allTile: ({
        key: "all", name: "All Apps", tagline: "Everything installed on this TV.", icon: "",
        accent1: "#636366", accent2: "#1c1c1e", installed: true, appId: "", hero: "", url: ""
    })
    readonly property var apps: Apps.apps.concat([allTile])
    readonly property var focused: apps[Math.min(current, apps.length - 1)]

    function goHome() {
        controlCenter.close()
        allApps.close()
        settingsPage.close()
        mode = "row"
        keys.forceActiveFocus()
    }

    function launchCurrent() {
        const app = focused
        const tile = row.currentTile()
        if (tile) tile.pop()
        if (app.key === "all") { mode = "all"; allApps.open(); return }
        Launcher.launch(app.key)
    }

    function move(dx) {
        const next = current + dx
        if (next < 0 || next >= apps.length) {
            const tile = row.currentTile()
            if (tile) tile.nudge(dx, 0)
            return
        }
        current = next
    }

    onHeightChanged: Theme.s = height / 1080
    Component.onCompleted: Theme.s = height / 1080

    onActiveChanged: if (active && mode === "row") returnAnim.restart()

    Connections {
        target: Launcher
        function onLaunched() { curtain.flash() }
    }

    Timer { interval: 1000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.now = new Date() }

    Timer {
        id: cleanup
        interval: 500
        onTriggered: { gc(); root.releaseResources(); System.trimMemory() }
    }

    Item {
        id: scene
        anchors.fill: parent

        TopShelf {
            id: shelf
            anchors.fill: parent
            app: root.focused
            expanded: root.mode === "shelf" || root.mode === "top"
            running: Launcher.running.indexOf(root.focused.appId) >= 0
        }

        Row {
            id: topBar
            anchors { top: parent.top; right: parent.right; topMargin: 48 * Theme.s; rightMargin: Theme.gutter }
            spacing: 28 * Theme.s

            Rectangle {
                id: ccButton
                width: 60 * Theme.s; height: width; radius: width / 2
                anchors.verticalCenter: parent.verticalCenter
                color: root.mode === "top" ? Theme.focusFill : "#33ffffff"
                scale: root.mode === "top" ? 1.15 : 1
                Behavior on color { ColorAnimation { duration: Theme.fast } }
                Behavior on scale { SpringAnimation { spring: 4; damping: 0.3 } }

                Icon {
                    anchors.centerIn: parent
                    name: "sliders-horizontal"
                    size: 32 * Theme.s
                    color: root.mode === "top" ? "black" : "white"
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: { root.mode = "control"; controlCenter.open() }
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Qt.formatTime(root.now, "HH:mm")
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: 36 * Theme.s
                font.weight: Font.Medium
            }
        }

        AppRow {
            id: row
            anchors { left: parent.left; right: parent.right }
            readonly property bool lowered: root.mode === "shelf" || root.mode === "top"
            y: lowered ? parent.height - height * 0.42 : parent.height - height - 70 * Theme.s
            opacity: lowered ? 0.45 : 1
            model: root.apps
            currentIndex: root.current
            active: root.mode === "row"
            Behavior on y { NumberAnimation { duration: Theme.med + 120; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: Theme.med } }
            onHoveredIndex: (i) => { if (root.mode === "row") root.current = i }
            onLaunchRequested: (i) => { root.current = i; root.launchCurrent() }
        }
    }

    ParallelAnimation {
        id: returnAnim
        NumberAnimation { target: scene; property: "scale"; from: 1.05; to: 1; duration: 520; easing.type: Easing.OutCubic }
        NumberAnimation { target: scene; property: "opacity"; from: 0; to: 1; duration: 420; easing.type: Easing.OutCubic }
    }

    Item {
        id: keys
        anchors.fill: parent
        focus: true

        Keys.onPressed: (e) => {
            const k = e.key
            const ok = k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Select || k === Qt.Key_Space
            const back = k === Qt.Key_Escape || k === Qt.Key_Back || k === Qt.Key_Backspace
            if (k === Qt.Key_HomePage) { root.goHome(); e.accepted = true; return }
            if (k === Qt.Key_Menu || k === Qt.Key_F1) { root.mode = "control"; controlCenter.open(); e.accepted = true; return }

            switch (root.mode) {
            case "row":
                if (k === Qt.Key_Left) root.move(-1)
                else if (k === Qt.Key_Right) root.move(1)
                else if (k === Qt.Key_PageUp || k === Qt.Key_Home) root.current = 0
                else if (k === Qt.Key_PageDown || k === Qt.Key_End) root.current = root.apps.length - 1
                else if (k === Qt.Key_Up) root.mode = "shelf"
                else if (k === Qt.Key_Down) { const t = row.currentTile(); if (t) t.nudge(0, 1) }
                else if (ok) root.launchCurrent()
                else return
                break
            case "shelf":
                if (k === Qt.Key_Down || back) root.mode = "row"
                else if (k === Qt.Key_Up) root.mode = "top"
                else if (k === Qt.Key_Left) root.move(-1)
                else if (k === Qt.Key_Right) root.move(1)
                else if (ok) root.launchCurrent()
                else return
                break
            case "top":
                if (k === Qt.Key_Down) root.mode = "shelf"
                else if (back) root.mode = "row"
                else if (ok) { root.mode = "control"; controlCenter.open() }
                else return
                break
            default:
                return
            }
            e.accepted = true
        }
    }

    AllApps {
        id: allApps
        anchors.fill: parent
        source: scene
        onClosed: { root.mode = "row"; keys.forceActiveFocus() }
        onUnloaded: cleanup.restart()
    }

    Settings {
        id: settingsPage
        anchors.fill: parent
        source: scene
        onClosed: { root.mode = "row"; keys.forceActiveFocus() }
        onUnloaded: cleanup.restart()
    }

    ControlCenter {
        id: controlCenter
        anchors.fill: parent
        source: scene
        onClosed: { root.mode = allApps.shown ? "all" : "row"; if (allApps.shown) allApps.open(); else keys.forceActiveFocus() }
        onSettingsRequested: { allApps.close(); root.mode = "settings"; settingsPage.open() }
    }

    Rectangle {
        id: curtain
        anchors.fill: parent
        color: "black"
        opacity: 0
        function flash() { curtainAnim.restart() }
        SequentialAnimation {
            id: curtainAnim
            NumberAnimation { target: curtain; property: "opacity"; to: 1; duration: 260; easing.type: Easing.InCubic }
            PauseAnimation { duration: 900 }
            NumberAnimation { target: curtain; property: "opacity"; to: 0; duration: 400 }
        }
    }
}
