// One settings row, drawn from a descriptor: header, note, info, value/action, toggle,
// option (‹ value ›), slider, or app (icon + reorder state). `glyph` is a leading UI icon,
// `trail` a list of trailing UI icons.
import QtQuick

Item {
    id: r

    property var row: ({})
    property bool focused: false
    property bool confirming: false
    property bool grabbed: false

    signal clicked()
    signal hovered()

    readonly property string kind: row.kind || "value"
    readonly property bool box: kind !== "header" && kind !== "note"
    readonly property color fg: focused ? Theme.focusText : (row.danger ? "#ff453a" : Theme.text)
    readonly property color sub: focused ? "#99000000" : Theme.dim

    height: kind === "header" ? 64 * Theme.s
          : kind === "note" ? note.implicitHeight + 20 * Theme.s
          : row.detail ? 92 * Theme.s : 76 * Theme.s

    Rectangle {
        anchors.fill: parent
        visible: r.box
        radius: 18 * Theme.s
        color: r.focused ? Theme.focusFill : r.kind === "info" ? "#0affffff" : "#14ffffff"
        border.width: r.grabbed ? 3 * Theme.s : 0
        border.color: "#0a84ff"
        scale: r.focused ? 1.02 : 1
        Behavior on color { ColorAnimation { duration: Theme.fast } }
        Behavior on scale { SpringAnimation { spring: 4; damping: 0.3 } }
    }

    Text {
        visible: r.kind === "header"
        anchors { left: parent.left; leftMargin: 8 * Theme.s; bottom: parent.bottom; bottomMargin: 10 * Theme.s }
        text: (r.row.label || "").toUpperCase()
        color: Theme.dim
        font.family: Theme.font
        font.pixelSize: 19 * Theme.s
        font.weight: Font.DemiBold
        font.letterSpacing: 1.2 * Theme.s
    }

    Icon {
        id: noteIcon
        visible: r.kind === "note" && !!r.row.danger
        x: 8 * Theme.s; y: 12 * Theme.s
        name: "warning-circle"
        size: 24 * Theme.s
        color: "#ff6961"
    }

    Text {
        id: note
        visible: r.kind === "note"
        width: parent.width - x - 8 * Theme.s
        x: noteIcon.visible ? 42 * Theme.s : 8 * Theme.s
        y: 10 * Theme.s
        text: r.row.label || ""
        color: r.row.danger ? "#ff6961" : Theme.dim
        font.family: Theme.font
        font.pixelSize: 22 * Theme.s
        wrapMode: Text.WordWrap
        lineHeight: 1.15
    }

    Row {
        visible: r.box
        anchors { left: parent.left; leftMargin: 26 * Theme.s; verticalCenter: parent.verticalCenter; right: trailing.left; rightMargin: 20 * Theme.s }
        spacing: 18 * Theme.s

        Icon {
            visible: !!r.row.glyph
            anchors.verticalCenter: parent.verticalCenter
            name: r.row.glyph || ""
            size: 30 * Theme.s
            color: r.fg
        }

        Item {
            visible: r.kind === "app"
            width: 46 * Theme.s; height: width
            anchors.verticalCenter: parent.verticalCenter

            Rectangle {
                anchors.fill: parent
                visible: appIcon.status !== Image.Ready
                radius: 10 * Theme.s
                color: r.focused ? "#26000000" : "#3a3a3c"
                opacity: r.row.dimmed ? 0.4 : 1
                Text {
                    anchors.centerIn: parent
                    text: (r.row.label || "?").charAt(0)
                    color: r.fg
                    font.family: Theme.font
                    font.pixelSize: 24 * Theme.s
                    font.weight: Font.Bold
                }
            }

            Image {
                id: appIcon
                anchors.fill: parent
                source: r.kind === "app" && r.row.icon ? "image://icon/" + encodeURIComponent(r.row.icon) : ""
                sourceSize: Qt.size(64, 64)
                cache: false
                opacity: r.row.dimmed ? 0.4 : 1
            }
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - (r.kind === "app" ? 64 * Theme.s : 0) - (r.row.glyph ? 48 * Theme.s : 0)
            spacing: 4 * Theme.s
            Text {
                width: parent.width
                text: r.confirming && r.row.confirm ? r.row.confirm : (r.grabbed ? "≡  " : "") + (r.row.label || "")
                color: r.fg
                opacity: r.row.dimmed && !r.focused ? 0.5 : 1
                font.family: Theme.font
                font.pixelSize: 26 * Theme.s
                font.weight: r.focused ? Font.DemiBold : Font.Normal
                elide: Text.ElideRight
            }
            Text {
                visible: !!r.row.detail
                width: parent.width
                text: r.row.detail || ""
                color: r.sub
                font.family: Theme.font
                font.pixelSize: 19 * Theme.s
                elide: Text.ElideRight
            }
        }
    }

    Row {
        id: trailing
        visible: r.box
        anchors { right: parent.right; rightMargin: 26 * Theme.s; verticalCenter: parent.verticalCenter }
        spacing: 14 * Theme.s

        Icon {
            visible: r.kind === "option" && r.focused
            anchors.verticalCenter: parent.verticalCenter
            name: "caret-left"
            size: 20 * Theme.s
            color: r.sub
        }

        Text {
            visible: !!r.row.value && r.kind !== "slider"
            anchors.verticalCenter: parent.verticalCenter
            text: r.row.value || ""
            color: r.kind === "option" || r.kind === "app" ? r.fg : r.sub
            font.family: Theme.font
            font.pixelSize: 24 * Theme.s
            font.weight: r.kind === "option" ? Font.Medium : Font.Normal
        }

        Icon {
            visible: r.kind === "option" && r.focused
            anchors.verticalCenter: parent.verticalCenter
            name: "caret-right"
            size: 20 * Theme.s
            color: r.sub
        }

        Repeater {
            model: r.row.trail || []
            Icon {
                required property string modelData
                anchors.verticalCenter: parent.verticalCenter
                name: modelData
                size: 26 * Theme.s
                color: r.sub
            }
        }

        Item {
            visible: r.kind === "slider"
            width: 300 * Theme.s; height: 28 * Theme.s
            anchors.verticalCenter: parent.verticalCenter
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width; height: 10 * Theme.s; radius: height / 2
                color: r.focused ? "#26000000" : "#26ffffff"
                Rectangle {
                    height: parent.height; radius: parent.radius
                    width: parent.width * Math.max(0, Math.min(1, r.row.value || 0))
                    color: r.focused ? "#000000" : "#ffffff"
                    Behavior on width { NumberAnimation { duration: Theme.fast } }
                }
            }
        }

        Text {
            visible: r.kind === "slider"
            anchors.verticalCenter: parent.verticalCenter
            width: 70 * Theme.s
            horizontalAlignment: Text.AlignRight
            text: r.row.valueText || ""
            color: r.fg
            font.family: Theme.font
            font.pixelSize: 24 * Theme.s
        }

        Rectangle {
            visible: r.kind === "toggle"
            width: 66 * Theme.s; height: 38 * Theme.s; radius: height / 2
            anchors.verticalCenter: parent.verticalCenter
            color: r.row.checked ? "#30d158" : (r.focused ? "#33000000" : "#48484a")
            Behavior on color { ColorAnimation { duration: Theme.fast } }
            Rectangle {
                width: parent.height - 6 * Theme.s; height: width; radius: width / 2
                anchors.verticalCenter: parent.verticalCenter
                x: r.row.checked ? parent.width - width - 3 * Theme.s : 3 * Theme.s
                color: "white"
                Behavior on x { NumberAnimation { duration: Theme.fast; easing.type: Easing.OutCubic } }
            }
        }

        Icon {
            visible: !!r.row.selected
            anchors.verticalCenter: parent.verticalCenter
            name: "check"
            size: 26 * Theme.s
            color: r.focused ? Theme.focusText : "#0a84ff"
        }

        Icon {
            visible: !!r.row.chevron
            anchors.verticalCenter: parent.verticalCenter
            name: "caret-right"
            size: 22 * Theme.s
            color: r.sub
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: r.box && r.kind !== "info"
        hoverEnabled: true
        onEntered: if (Pointer.active) r.hovered()
        onPositionChanged: if (Pointer.active && !r.focused) r.hovered()
        onClicked: r.clicked()
    }
}
