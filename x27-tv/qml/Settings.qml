// Settings overlay: section sidebar on the left, the active section's page on the right,
// and the shared on-screen keyboard. Pages load on demand and everything unloads on close.
import QtQuick
import QtQuick.Effects

FocusScope {
    id: settings

    property Item source
    property bool shown: false
    property bool loaded: false
    property int section: 0
    property bool inPane: false

    signal closed()
    signal unloaded()

    readonly property var sections: [
        { key: "Audio", title: "Audio", icon: "speaker-high", color: "#ff375f" },
        { key: "Display", title: "Display", icon: "monitor", color: "#0a84ff" },
        { key: "Network", title: "Network", icon: "wifi-high", color: "#30d158" },
        { key: "Bluetooth", title: "Bluetooth", icon: "bluetooth", color: "#5e5ce6" },
        { key: "Home", title: "Home Screen", icon: "squares-four", color: "#ff9f0a" },
        { key: "Power", title: "Power", icon: "moon", color: "#64d2ff" },
        { key: "System", title: "System", icon: "info", color: "#8e8e93" }
    ]

    function open() { loaded = true; shown = true; section = 0; inPane = false; sidebar.forceActiveFocus() }
    function close() { if (!shown) return; shown = false; closed() }

    function enterPane() {
        if (!page.item) return
        inPane = true
        page.item.forceActiveFocus()
    }

    function leavePane() { inPane = false; sidebar.forceActiveFocus() }

    function askText(title, password, cb) { keyboard.open(title, password, cb) }

    visible: opacity > 0
    opacity: shown ? 1 : 0
    scale: shown ? 1 : 1.03
    Behavior on opacity { NumberAnimation { duration: Theme.med } }
    Behavior on scale { NumberAnimation { duration: Theme.med; easing.type: Easing.OutCubic } }
    onOpacityChanged: if (opacity === 0 && !shown && loaded) { loaded = false; unloaded() }

    Loader {
        anchors.fill: parent
        active: settings.visible
        sourceComponent: Item {
            ShaderEffectSource { id: behind; anchors.fill: parent; sourceItem: settings.source; visible: false }
            MultiEffect {
                anchors.fill: parent
                source: behind
                blurEnabled: true; blur: 1; blurMax: 64
                brightness: -0.45
                saturation: 0.2
            }
        }
    }
    Rectangle { anchors.fill: parent; color: "#99000000" }

    Text {
        x: Theme.gutter; y: 64 * Theme.s
        text: "Settings"
        color: Theme.text
        font.family: Theme.font
        font.pixelSize: 56 * Theme.s
        font.weight: Font.Bold
    }

    FocusScope {
        id: sidebar
        x: Theme.gutter - 10 * Theme.s
        y: 170 * Theme.s
        width: parent.width * 0.3
        height: parent.height - y - 60 * Theme.s

        Keys.onPressed: (e) => {
            switch (e.key) {
            case Qt.Key_Up: settings.section = Math.max(0, settings.section - 1); break
            case Qt.Key_Down: settings.section = Math.min(settings.sections.length - 1, settings.section + 1); break
            case Qt.Key_Right: case Qt.Key_Return: case Qt.Key_Enter: case Qt.Key_Select: settings.enterPane(); break
            case Qt.Key_Escape: case Qt.Key_Back: case Qt.Key_Backspace: case Qt.Key_Left: case Qt.Key_HomePage: settings.close(); break
            default: return
            }
            e.accepted = true
        }

        Column {
            width: parent.width
            spacing: 10 * Theme.s

            Repeater {
                model: settings.sections
                Rectangle {
                    required property var modelData
                    required property int index
                    readonly property bool current: settings.section === index
                    readonly property bool focusedRow: current && sidebar.activeFocus
                    width: parent.width
                    height: 80 * Theme.s
                    radius: 18 * Theme.s
                    color: focusedRow ? Theme.focusFill : current ? "#26ffffff" : "transparent"
                    scale: focusedRow ? 1.03 : 1
                    Behavior on color { ColorAnimation { duration: Theme.fast } }
                    Behavior on scale { SpringAnimation { spring: 4; damping: 0.3 } }

                    Rectangle {
                        id: badge
                        x: 18 * Theme.s
                        anchors.verticalCenter: parent.verticalCenter
                        width: 48 * Theme.s; height: width; radius: 12 * Theme.s
                        color: parent.modelData.color
                        Icon {
                            anchors.centerIn: parent
                            name: parent.parent.modelData.icon
                            size: 30 * Theme.s
                        }
                    }

                    Text {
                        anchors { left: badge.right; leftMargin: 20 * Theme.s; verticalCenter: parent.verticalCenter }
                        text: parent.modelData.title
                        color: parent.focusedRow ? Theme.focusText : Theme.text
                        font.family: Theme.font
                        font.pixelSize: 28 * Theme.s
                        font.weight: parent.current ? Font.DemiBold : Font.Normal
                    }

                    Icon {
                        anchors { right: parent.right; rightMargin: 22 * Theme.s; verticalCenter: parent.verticalCenter }
                        visible: parent.current
                        name: "caret-right"
                        size: 22 * Theme.s
                        color: parent.focusedRow ? "#99000000" : Theme.dim
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: { settings.section = parent.index; settings.enterPane() }
                    }
                }
            }
        }
    }

    Text {
        id: sectionTitle
        x: page.x + 10 * Theme.s; y: 78 * Theme.s
        text: settings.sections[settings.section].title
        color: Theme.dim
        font.family: Theme.font
        font.pixelSize: 36 * Theme.s
        font.weight: Font.DemiBold
    }

    Loader {
        id: page
        x: parent.width * 0.38
        y: 150 * Theme.s
        width: parent.width - x - Theme.gutter
        height: parent.height - y - 50 * Theme.s
        active: settings.loaded
        source: "Settings" + settings.sections[settings.section].key + ".qml"
        onLoaded: {
            item.host = settings
            item.back.connect(settings.leavePane)
        }
    }

    OnScreenKeyboard {
        id: keyboard
        anchors.fill: parent
        onFinished: if (page.item) page.item.forceActiveFocus()
    }
}
