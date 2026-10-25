// Root window: Top Shelf + app row, the Control Center and All Apps overlays, the in-app
// Quick Menu, and the remote/gamepad/keyboard navigation between them.
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
    readonly property var quickMenu: quickLoader.item

    function goHome() {
        controlCenter.close()
        allApps.close()
        settingsPage.close()
        mode = "row"
        keys.forceActiveFocus()
    }

    function openControlCenter() {
        if (mode === "control") return
        allApps.close(); settingsPage.close()
        mode = "control"
        controlCenter.open()
    }

    // Guide/Home with an app in front (decided in __main__.py): the Quick Menu over it.
    function quick(appId) {
        const w = Launcher.windows.find(x => x.appId === appId)
        quickMenu.open(appId, w ? w.name : "")
    }

    function returnHome() {
        Launcher.home()
        requestActivate()
        goHome()
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

    onActiveChanged: {
        if (!active) opening.done()
        else if (mode === "row") returnAnim.restart()
    }

    Connections {
        target: Launcher
        function onLaunched(key) { opening.show(key) }
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
                Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutQuad } }

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
            y: lowered ? parent.height - height * 0.42
                       : parent.height - height - (taskbar.items.length ? taskbar.height + 10 * Theme.s : 70 * Theme.s)
            opacity: lowered ? 0.45 : root.mode === "task" ? 0.6 : 1
            model: root.apps
            currentIndex: root.current
            active: root.mode === "row"
            Behavior on y { NumberAnimation { duration: Theme.med + 120; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: Theme.med } }
            onHoveredIndex: (i) => { if (root.mode === "row") root.current = i }
            onLaunchRequested: (i) => { root.current = i; root.launchCurrent() }
        }

        Taskbar {
            id: taskbar
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            items: Launcher.windows
            active: root.mode === "task"
            onExitUp: root.mode = "row"
        }
    }

    ParallelAnimation {
        id: returnAnim
        NumberAnimation { target: scene; property: "scale"; from: 1.03; to: 1; duration: 240; easing.type: Easing.OutCubic }
        NumberAnimation { target: scene; property: "opacity"; from: 0; to: 1; duration: 200; easing.type: Easing.OutCubic }
    }

    Item {
        id: keys
        anchors.fill: parent
        focus: true

        Keys.onPressed: (e) => {
            const k = e.key
            if (opening.failed) { opening.hide(); e.accepted = true; return }
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
                else if (k === Qt.Key_Down) {
                    if (taskbar.items.length) { taskbar.reset(); root.mode = "task" }
                    else { const t = row.currentTile(); if (t) t.nudge(0, 1) }
                }
                else if (k === Qt.Key_Delete && Launcher.running.indexOf(root.focused.appId) >= 0) Launcher.closeApp(root.focused.appId)
                else if (ok) root.launchCurrent()
                else return
                break
            case "task":
                if (!taskbar.handleKey(e)) return
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

    Loader {
        id: quickLoader
        source: "QuickMenu.qml"
        onStatusChanged: if (status === Loader.Error) console.warn("Quick Menu unavailable (needs layer-shell-qt)")
    }

    Loader {
        source: "MouseIndicator.qml"
        onStatusChanged: if (status === Loader.Error) console.warn("Mouse mode indicator unavailable (needs layer-shell-qt)")
    }

    Loader {
        source: "TypeKeyboard.qml"
        onStatusChanged: if (status === Loader.Error) console.warn("Typing keyboard unavailable (needs layer-shell-qt)")
    }

    Connections {
        target: root.quickMenu
        function onHomeRequested() { root.returnHome() }
        function onSettingsRequested() { root.returnHome(); root.mode = "settings"; settingsPage.open() }
    }

    Rectangle {
        id: opening
        anchors.fill: parent
        color: "black"
        visible: opacity > 0
        opacity: shown ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: opening.shown ? 260 : 400 } }

        property bool shown: false
        property bool failed: false
        property string key: ""
        property var app: ({})
        property string error: ""

        function show(k) {
            app = root.apps.concat(Apps.allApps).find(a => a.key === k) || { name: "App" }
            key = k; failed = false; error = ""; shown = true
            giveUp.restart()
        }
        function done() { if (shown && !failed) hide() }
        function hide() { shown = false; failed = false; giveUp.stop() }

        Timer {
            id: giveUp
            interval: 30000
            onTriggered: {
                opening.error = Launcher.lastError(opening.key)
                opening.failed = true
                autoHide.restart()
            }
        }
        Timer { id: autoHide; interval: 10000; onTriggered: opening.hide() }

        Connections {
            target: Launcher
            function onRunningChanged() {
                if (opening.shown && opening.app.appId && Launcher.running.indexOf(opening.app.appId) >= 0) opening.done()
            }
        }

        MouseArea { anchors.fill: parent; enabled: opening.failed; onClicked: opening.hide() }

        Column {
            anchors.centerIn: parent
            width: parent.width * 0.6
            spacing: 28 * Theme.s

            Image {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 150 * Theme.s; height: width
                source: opening.app.icon ? "image://icon/" + encodeURIComponent(opening.app.icon) : ""
                sourceSize: Qt.size(192, 192)
                visible: status === Image.Ready
            }

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: (opening.failed ? "Couldn't open " : "Opening ") + (opening.app.name || "") + (opening.failed ? "" : "…")
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: 40 * Theme.s
                font.weight: Font.DemiBold
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 14 * Theme.s
                visible: !opening.failed
                Repeater {
                    model: 3
                    Rectangle {
                        required property int index
                        width: 14 * Theme.s; height: width; radius: width / 2
                        color: Theme.text
                        SequentialAnimation on opacity {
                            running: opening.visible && !opening.failed
                            loops: Animation.Infinite
                            PauseAnimation { duration: index * 160 }
                            NumberAnimation { to: 1; duration: 300 }
                            NumberAnimation { to: 0.25; duration: 500 }
                            PauseAnimation { duration: (2 - index) * 160 }
                        }
                    }
                }
            }

            Text {
                width: parent.width
                visible: opening.failed
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: (opening.error || "It didn't open a window.") + "\n\nPress any button to go back."
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: 24 * Theme.s
            }
        }
    }
}
