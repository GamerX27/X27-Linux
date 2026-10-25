// Gamepad as Mouse indicator: a strip along the top on labwc's overlay layer that takes no
// input or focus. Toggling the mode shows "Mouse mode on/off" for a moment; while the mode is
// driving an app, a small "Mouse" pill stays in the top-right corner.
import QtQuick
import QtQuick.Window
import org.kde.layershell 1.0 as LayerShell

Window {
    id: ind

    property bool toastShown: false
    property bool wasEnabled: false

    color: "transparent"
    flags: Qt.FramelessWindowHint | Qt.WindowTransparentForInput
    width: 1600
    height: 150 * Theme.s
    visible: toastShown || Mouse.active
    title: "X27 TV Mouse Mode"

    LayerShell.Window.scope: "x27-tv-mouse"
    LayerShell.Window.layer: LayerShell.Window.LayerOverlay
    LayerShell.Window.anchors: LayerShell.Window.AnchorTop | LayerShell.Window.AnchorLeft | LayerShell.Window.AnchorRight
    LayerShell.Window.exclusionZone: -1
    LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityNone

    Timer { id: hideToast; interval: 2500; onTriggered: ind.toastShown = false }

    Connections {
        target: Mouse
        function onChanged() {
            if (Mouse.enabled === ind.wasEnabled) return
            ind.wasEnabled = Mouse.enabled
            ind.toastShown = true
            hideToast.restart()
        }
    }

    Rectangle {
        id: toast
        anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 40 * Theme.s }
        width: toastRow.implicitWidth + 56 * Theme.s
        height: 76 * Theme.s
        radius: height / 2
        color: "#f21c1c1e"
        border.color: Theme.glassEdge
        border.width: Math.max(1, Theme.s)
        opacity: ind.toastShown ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.fast } }

        Row {
            id: toastRow
            anchors.centerIn: parent
            spacing: 16 * Theme.s
            Icon {
                anchors.verticalCenter: parent.verticalCenter
                name: "cursor"
                size: 30 * Theme.s
                color: Mouse.enabled ? "#30d158" : Theme.dim
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Mouse.enabled ? "Mouse mode on" : "Mouse mode off"
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: 28 * Theme.s
                font.weight: Font.DemiBold
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: Mouse.enabled
                text: "·  L3+R3 to turn off"
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: 24 * Theme.s
            }
        }
    }

    Rectangle {
        anchors { right: parent.right; top: parent.top; margins: 28 * Theme.s }
        width: badgeRow.implicitWidth + 32 * Theme.s
        height: 48 * Theme.s
        radius: height / 2
        color: "#d91c1c1e"
        border.color: Theme.glassEdge
        border.width: Math.max(1, Theme.s)
        opacity: Mouse.active && !ind.toastShown ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.fast } }

        Row {
            id: badgeRow
            anchors.centerIn: parent
            spacing: 10 * Theme.s
            Icon {
                anchors.verticalCenter: parent.verticalCenter
                name: "cursor"
                size: 22 * Theme.s
                color: "#30d158"
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Mouse"
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: 20 * Theme.s
                font.weight: Font.Medium
            }
        }
    }
}
