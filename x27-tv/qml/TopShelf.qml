// Full-bleed hero behind the row: accent gradient (or hero image) with slow Ken Burns
// drift, a large blurred icon, and the focused app's title and tagline that crossfade on change.
import QtQuick
import QtQuick.Effects

Item {
    id: shelf

    property var app: ({})
    property var shown: ({})
    property bool expanded: false
    property bool running: false

    clip: true

    onAppChanged: {
        if (!shown.key) { shown = app; return }
        if (app.key !== shown.key) swap.restart()
    }

    SequentialAnimation {
        id: swap
        ParallelAnimation {
            NumberAnimation { target: info; property: "opacity"; to: 0; duration: 120 }
            NumberAnimation { target: art; property: "opacity"; to: 0; duration: 120 }
        }
        ScriptAction { script: shelf.shown = shelf.app }
        PropertyAction { target: info; property: "x"; value: Theme.gutter + 40 * Theme.s }
        ParallelAnimation {
            NumberAnimation { target: info; property: "opacity"; to: 1; duration: 380; easing.type: Easing.OutCubic }
            NumberAnimation { target: info; property: "x"; to: Theme.gutter; duration: 520; easing.type: Easing.OutCubic }
            NumberAnimation { target: art; property: "opacity"; to: 1; duration: 520; easing.type: Easing.OutCubic }
        }
    }

    Item {
        id: backdrop
        anchors.centerIn: parent
        width: parent.width * 1.15; height: parent.height * 1.15

        SequentialAnimation on scale {
            loops: Animation.Infinite
            NumberAnimation { from: 1; to: 1.07; duration: 18000; easing.type: Easing.InOutSine }
            NumberAnimation { from: 1.07; to: 1; duration: 18000; easing.type: Easing.InOutSine }
        }
        SequentialAnimation on anchors.horizontalCenterOffset {
            loops: Animation.Infinite
            NumberAnimation { from: -30 * Theme.s; to: 30 * Theme.s; duration: 23000; easing.type: Easing.InOutSine }
            NumberAnimation { from: 30 * Theme.s; to: -30 * Theme.s; duration: 23000; easing.type: Easing.InOutSine }
        }

        Rectangle {
            anchors.centerIn: parent
            width: Math.hypot(parent.width, parent.height); height: width
            rotation: -28
            gradient: Gradient {
                GradientStop { position: 0.15; color: shelf.app.accent1 || "#2c2c2e"; Behavior on color { ColorAnimation { duration: Theme.slow } } }
                GradientStop { position: 0.85; color: shelf.app.accent2 || "#000000"; Behavior on color { ColorAnimation { duration: Theme.slow } } }
            }
        }

        Image {
            anchors.fill: parent
            source: shelf.shown.hero || ""
            fillMode: Image.PreserveAspectCrop
            opacity: status === Image.Ready ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.slow } }
        }
    }

    Image {
        id: art
        width: parent.height * 0.95; height: width
        x: parent.width * 0.62; y: -parent.height * 0.08
        source: shelf.shown.icon ? "image://icon/" + encodeURIComponent(shelf.shown.icon) : ""
        sourceSize: Qt.size(128, 128)
        opacity: 1
        visible: !shelf.shown.hero
        layer.enabled: true
        layer.effect: MultiEffect { blurEnabled: true; blur: 1; blurMax: 64; opacity: 0.4; saturation: 0.3 }
        RotationAnimation on rotation { from: -6; to: 6; duration: 20000; loops: Animation.Infinite; easing.type: Easing.InOutSine }
    }

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0; color: "#66000000" }
            GradientStop { position: 0.3; color: "#00000000" }
            GradientStop { position: 0.55; color: "#33000000" }
            GradientStop { position: 0.82; color: "#e6000000" }
            GradientStop { position: 1; color: "#ff000000" }
        }
    }
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: "#99000000" }
            GradientStop { position: 0.55; color: "#00000000" }
        }
    }

    Column {
        id: info
        x: Theme.gutter
        y: shelf.expanded ? parent.height * 0.34 : parent.height * 0.16
        width: parent.width * 0.5
        spacing: 18 * Theme.s
        Behavior on y { NumberAnimation { duration: Theme.med + 120; easing.type: Easing.OutCubic } }

        Text {
            width: parent.width
            text: shelf.shown.name || ""
            color: Theme.text
            font.family: Theme.font
            font.pixelSize: (shelf.expanded ? 104 : 84) * Theme.s
            font.weight: Font.Bold
            font.letterSpacing: -1.5 * Theme.s
            elide: Text.ElideRight
            Behavior on font.pixelSize { NumberAnimation { duration: Theme.med + 120; easing.type: Easing.OutCubic } }
        }

        Text {
            width: parent.width
            text: shelf.shown.tagline || ""
            color: "#e6ffffff"
            font.family: Theme.font
            font.pixelSize: 30 * Theme.s
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }

        Item { width: 1; height: 16 * Theme.s }

        Row {
            spacing: 18 * Theme.s
            opacity: shelf.expanded ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.med } }

            Rectangle {
                height: 64 * Theme.s; width: openLabel.implicitWidth + 64 * Theme.s
                radius: 14 * Theme.s
                color: Theme.focusFill
                scale: shelf.expanded ? 1.06 : 1
                Behavior on scale { SpringAnimation { spring: 4; damping: 0.3 } }
                Text {
                    id: openLabel
                    anchors.centerIn: parent
                    text: shelf.shown.installed === false ? "Install" : shelf.running ? "Resume" : "Open"
                    color: Theme.focusText
                    font.family: Theme.font
                    font.pixelSize: 26 * Theme.s
                    font.weight: Font.DemiBold
                }
            }
        }
    }
}
