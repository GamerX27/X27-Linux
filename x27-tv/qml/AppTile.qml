// A single app card: rounded accent face with the icon, lift + shadow + parallax tilt and
// a moving sheen when focused, plus running/install badges.
import QtQuick
import QtQuick.Effects

Item {
    id: tile

    property var app: ({})
    property bool focused: false
    property bool running: false
    property bool installing: false
    property bool showLabel: true
    property bool glow: true
    property bool iconCache: true
    property real tiltX: 0
    property real tiltY: 0
    property real wobble: 0

    signal activated()
    signal hovered()

    function nudge(dx, dy) {
        nudgeX.from = dx * 1.2; nudgeY.from = dy * 1.2
        nudgeAnim.restart()
    }

    function pop() { popAnim.restart() }

    readonly property real tx: tiltX + (focused ? Math.sin(wobble) * 0.35 : 0)
    readonly property real ty: tiltY + (focused ? Math.cos(wobble * 0.8) * 0.25 : 0)

    z: focused ? 10 : 0
    scale: focused ? Theme.focusScale : 1
    Behavior on scale { SpringAnimation { spring: 4; damping: 0.32; epsilon: 0.002 } }

    NumberAnimation on wobble {
        running: tile.focused && tile.Window.active
        from: 0; to: Math.PI * 2; duration: 6000; loops: Animation.Infinite
    }

    ParallelAnimation {
        id: nudgeAnim
        SpringAnimation { id: nudgeX; target: tile; property: "tiltX"; to: 0; spring: 3; damping: 0.18 }
        SpringAnimation { id: nudgeY; target: tile; property: "tiltY"; to: 0; spring: 3; damping: 0.18 }
    }

    SequentialAnimation {
        id: popAnim
        NumberAnimation { target: card; property: "scale"; to: 0.94; duration: 90; easing.type: Easing.OutQuad }
        SpringAnimation { target: card; property: "scale"; to: 1; spring: 5; damping: 0.25 }
    }

    Item {
        id: card
        anchors.fill: parent
        transform: [
            Rotation { origin.x: card.width / 2; origin.y: card.height / 2; axis { x: 0; y: 1; z: 0 } angle: tile.tx * 7 },
            Rotation { origin.x: card.width / 2; origin.y: card.height / 2; axis { x: 1; y: 0; z: 0 } angle: -tile.ty * 7 }
        ]

        RectangularShadow {
            anchors.fill: parent
            anchors.margins: 6 * Theme.s
            radius: Theme.tileRadius
            offset.y: tile.focused ? 30 * Theme.s : 10 * Theme.s
            blur: tile.focused ? 60 * Theme.s : 24 * Theme.s
            color: "#000000"
            opacity: tile.focused ? 0.75 : 0.45
            Behavior on offset.y { NumberAnimation { duration: Theme.med } }
            Behavior on blur { NumberAnimation { duration: Theme.med } }
        }

        Item {
            id: face
            anchors.fill: parent
            layer.enabled: tile.glow || tile.focused || tile.app.installed === false
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: mask
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1
                saturation: tile.app.installed === false ? -0.9 : 0
                brightness: tile.app.installed === false ? -0.15 : 0
            }

            Rectangle {
                anchors.fill: parent
                radius: Theme.tileRadius
                gradient: Gradient {
                    GradientStop { position: 0; color: Qt.lighter(tile.app.accent1 || "#3a3a3c", 1.1) }
                    GradientStop { position: 1; color: tile.app.accent2 || "#1c1c1e" }
                }
            }

            Image {
                id: glowIcon
                anchors.centerIn: parent
                width: parent.height * 1.3; height: width
                source: icon.source
                sourceSize: Qt.size(64, 64)
                cache: tile.iconCache
                opacity: 0.35
                visible: tile.glow && icon.status === Image.Ready
                layer.enabled: visible
                layer.effect: MultiEffect { blurEnabled: true; blur: 1; blurMax: 64 }
            }

            Image {
                id: icon
                anchors.centerIn: parent
                anchors.horizontalCenterOffset: tile.tx * 6 * Theme.s
                anchors.verticalCenterOffset: -tile.ty * 6 * Theme.s
                width: parent.height * 0.5; height: width
                source: tile.app.icon ? "image://icon/" + encodeURIComponent(tile.app.icon) : ""
                sourceSize: Qt.size(iconPx, iconPx)
                readonly property int iconPx: Math.ceil(width * 1.25 / 32) * 32
                cache: tile.iconCache
                fillMode: Image.PreserveAspectFit
                smooth: true
                mipmap: true
            }

            Text {
                anchors.centerIn: parent
                visible: tile.app.key !== "all" && icon.status !== Image.Ready
                text: (tile.app.name || "?").charAt(0)
                color: "white"
                font.family: Theme.font
                font.pixelSize: parent.height * 0.48
                font.weight: Font.Bold
            }

            Grid {
                anchors.centerIn: parent
                visible: tile.app.key === "all"
                columns: 3; spacing: parent.height * 0.06
                Repeater {
                    model: 9
                    Rectangle {
                        width: tile.height * 0.11; height: width; radius: width * 0.28
                        color: "white"; opacity: 0.92
                    }
                }
            }

            Rectangle {
                anchors.fill: parent
                radius: Theme.tileRadius
                gradient: Gradient {
                    GradientStop { position: 0; color: "#33ffffff" }
                    GradientStop { position: 0.45; color: "#00ffffff" }
                }
            }

            Rectangle {
                id: sheen
                width: parent.width * 0.55; height: parent.height * 3
                anchors.verticalCenter: parent.verticalCenter
                x: parent.width * (0.25 + tile.tx * 0.55) - width / 2
                rotation: 22
                visible: face.layer.enabled
                opacity: tile.focused ? 0.55 : 0
                Behavior on opacity { NumberAnimation { duration: Theme.med } }
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: "#00ffffff" }
                    GradientStop { position: 0.5; color: "#40ffffff" }
                    GradientStop { position: 1; color: "#00ffffff" }
                }
            }
        }

        Rectangle {
            id: mask
            anchors.fill: parent
            radius: Theme.tileRadius
            visible: false
            layer.enabled: true
        }

        Rectangle {
            anchors.fill: parent
            radius: Theme.tileRadius
            color: "transparent"
            border.width: Math.max(1, 1.5 * Theme.s)
            border.color: tile.focused ? "#66ffffff" : "#1fffffff"
        }

        Rectangle {
            visible: tile.app.installed === false || tile.installing
            anchors { top: parent.top; right: parent.right; margins: 12 * Theme.s }
            height: 30 * Theme.s; width: badge.implicitWidth + 24 * Theme.s
            radius: height / 2
            color: "#cc000000"
            Text {
                id: badge
                anchors.centerIn: parent
                text: tile.installing ? "Installing…" : "Get"
                color: "white"
                font.family: Theme.font
                font.pixelSize: 15 * Theme.s
                font.weight: Font.DemiBold
            }
            SequentialAnimation on opacity {
                running: tile.installing; loops: Animation.Infinite
                NumberAnimation { to: 0.4; duration: 600 }
                NumberAnimation { to: 1; duration: 600 }
            }
        }
    }

    Text {
        visible: tile.showLabel
        anchors { top: card.bottom; topMargin: 22 * Theme.s; horizontalCenter: parent.horizontalCenter }
        text: tile.app.name || ""
        color: Theme.text
        font.family: Theme.font
        font.pixelSize: 24 * Theme.s
        font.weight: Font.Medium
        opacity: tile.focused ? 1 : 0
        scale: 1 / tile.scale
        Behavior on opacity { NumberAnimation { duration: Theme.med } }
    }

    Rectangle {
        visible: tile.running
        width: 8 * Theme.s; height: width; radius: width / 2
        color: Theme.text
        anchors { top: card.bottom; topMargin: tile.focused && tile.showLabel ? 60 * Theme.s : 14 * Theme.s; horizontalCenter: parent.horizontalCenter }
        Behavior on anchors.topMargin { NumberAnimation { duration: Theme.med } }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onEntered: if (Pointer.active) tile.hovered()
        onPositionChanged: if (Pointer.active && !tile.focused) tile.hovered()
        onClicked: tile.activated()
    }
}
