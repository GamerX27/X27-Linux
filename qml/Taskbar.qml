// Taskbar along the bottom of the home screen: one pill per running app. OK opens a small
// Open/Close menu, X (or Delete) closes directly, Up goes back to the app row.
import QtQuick

Item {
    id: bar

    property var items: []
    property bool active: false
    property int index: 0
    property bool menuOpen: false
    property int menuIndex: 0

    signal exitUp()

    readonly property var current: items.length ? items[Math.min(index, items.length - 1)] : null

    function reset() { menuOpen = false; menuIndex = 0; index = Math.min(index, Math.max(0, items.length - 1)) }

    function close(item) {
        menuOpen = false
        if (item) Launcher.closeApp(item.appId)
    }

    function handleKey(e) {
        const k = e.key
        if (k === Qt.Key_Delete || k === Qt.Key_X) { close(current); return true }
        if (menuOpen) {
            if (k === Qt.Key_Left || k === Qt.Key_Up) menuIndex = 0
            else if (k === Qt.Key_Right || k === Qt.Key_Down) menuIndex = 1
            else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Select || k === Qt.Key_Space) {
                if (menuIndex === 0) { menuOpen = false; Launcher.focusApp(current.appId) }
                else close(current)
            }
            else if (k === Qt.Key_Escape || k === Qt.Key_Back || k === Qt.Key_Backspace) menuOpen = false
            else return false
            return true
        }
        if (k === Qt.Key_Left) index = Math.max(0, index - 1)
        else if (k === Qt.Key_Right) index = Math.min(items.length - 1, index + 1)
        else if (k === Qt.Key_Up || k === Qt.Key_Escape || k === Qt.Key_Back || k === Qt.Key_Backspace) exitUp()
        else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Select || k === Qt.Key_Space) { menuOpen = true; menuIndex = 0 }
        else return false
        return true
    }

    onItemsChanged: {
        if (index >= items.length) index = Math.max(0, items.length - 1)
        if (!items.length) { menuOpen = false; if (active) exitUp() }
    }
    onActiveChanged: if (!active) menuOpen = false

    height: 96 * Theme.s
    visible: opacity > 0
    opacity: items.length ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Theme.med } }

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0; color: "#00000000" }
            GradientStop { position: 1; color: "#cc000000" }
        }
    }

    Text {
        id: label
        anchors { left: parent.left; leftMargin: Theme.gutter; verticalCenter: strip.verticalCenter }
        text: "Running"
        color: Theme.dim
        font.family: Theme.font
        font.pixelSize: 20 * Theme.s
        font.weight: Font.DemiBold
        font.letterSpacing: 1 * Theme.s
    }

    Row {
        id: strip
        anchors { left: label.right; leftMargin: 24 * Theme.s; verticalCenter: parent.verticalCenter }
        spacing: 14 * Theme.s

        Repeater {
            model: bar.items
            Rectangle {
                id: pill
                required property var modelData
                required property int index
                readonly property bool focused: bar.active && bar.index === index
                width: pillRow.implicitWidth + 36 * Theme.s
                height: 64 * Theme.s
                radius: height / 2
                color: focused ? Theme.focusFill : "#26ffffff"
                scale: focused ? 1.06 : 1
                z: focused ? 1 : 0
                Behavior on color { ColorAnimation { duration: Theme.fast } }
                Behavior on scale { SpringAnimation { spring: 4; damping: 0.3 } }

                Row {
                    id: pillRow
                    anchors.centerIn: parent
                    spacing: 12 * Theme.s

                    Item {
                        width: 40 * Theme.s; height: width
                        anchors.verticalCenter: parent.verticalCenter
                        Image {
                            id: appIcon
                            anchors.fill: parent
                            source: pill.modelData.icon ? "image://icon/" + encodeURIComponent(pill.modelData.icon) : ""
                            sourceSize: Qt.size(64, 64)
                            visible: status === Image.Ready
                        }
                        Icon {
                            anchors.centerIn: parent
                            visible: appIcon.status !== Image.Ready
                            name: "app-window"
                            size: 32 * Theme.s
                            color: pill.focused ? Theme.focusText : Theme.text
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: pill.modelData.name
                        color: pill.focused ? Theme.focusText : Theme.text
                        font.family: Theme.font
                        font.pixelSize: 22 * Theme.s
                        font.weight: pill.focused ? Font.DemiBold : Font.Normal
                        width: Math.min(implicitWidth, 260 * Theme.s)
                        elide: Text.ElideRight
                    }

                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: pill.focused && !bar.menuOpen
                        name: "x-circle"
                        size: 26 * Theme.s
                        color: "#99000000"
                        MouseArea { anchors.fill: parent; anchors.margins: -8 * Theme.s; onClicked: bar.close(pill.modelData) }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    z: -1
                    hoverEnabled: true
                    onEntered: if (Pointer.active && bar.active) bar.index = pill.index
                    onClicked: Launcher.focusApp(pill.modelData.appId)
                }

                Rectangle {
                    id: menu
                    visible: pill.focused && bar.menuOpen
                    anchors { bottom: parent.top; bottomMargin: 16 * Theme.s; horizontalCenter: parent.horizontalCenter }
                    width: menuRow.implicitWidth + 20 * Theme.s
                    height: 76 * Theme.s
                    radius: 22 * Theme.s
                    color: "#f21c1c1e"
                    border.color: Theme.glassEdge
                    border.width: Math.max(1, Theme.s)

                    Row {
                        id: menuRow
                        anchors.centerIn: parent
                        spacing: 10 * Theme.s
                        Repeater {
                            model: [{ label: "Open", icon: "arrow-square-out" }, { label: "Close", icon: "x-circle" }]
                            Rectangle {
                                required property var modelData
                                required property int index
                                readonly property bool sel: bar.menuIndex === index
                                width: choice.implicitWidth + 40 * Theme.s
                                height: 56 * Theme.s
                                radius: 16 * Theme.s
                                color: sel ? (index === 1 ? "#ff453a" : Theme.focusFill) : "transparent"
                                Row {
                                    id: choice
                                    anchors.centerIn: parent
                                    spacing: 10 * Theme.s
                                    Icon {
                                        anchors.verticalCenter: parent.verticalCenter
                                        name: parent.parent.modelData.icon
                                        size: 24 * Theme.s
                                        color: parent.parent.sel && parent.parent.index === 0 ? Theme.focusText : Theme.text
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: parent.parent.modelData.label
                                        color: parent.parent.sel && parent.parent.index === 0 ? Theme.focusText : Theme.text
                                        font.family: Theme.font
                                        font.pixelSize: 22 * Theme.s
                                        font.weight: Font.DemiBold
                                    }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        if (parent.index === 0) { bar.menuOpen = false; Launcher.focusApp(pill.modelData.appId) }
                                        else bar.close(pill.modelData)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Text {
        anchors { right: parent.right; rightMargin: Theme.gutter; verticalCenter: strip.verticalCenter }
        visible: bar.active
        text: bar.menuOpen ? "‹ ›  choose   ·   OK  confirm" : "OK  options   ·   X  close"
        color: Theme.dim
        font.family: Theme.font
        font.pixelSize: 19 * Theme.s
    }
}
