// Full-screen grid of every installed desktop app over a blurred backdrop.
import QtQuick
import QtQuick.Effects

FocusScope {
    id: all

    property Item source
    property bool shown: false
    property bool loaded: false

    signal closed()
    signal unloaded()

    function open() { loaded = true; shown = true; grid.currentIndex = 0; grid.positionViewAtBeginning(); grid.forceActiveFocus() }
    function close() { if (!shown) return; shown = false; closed() }

    visible: opacity > 0
    opacity: shown ? 1 : 0
    scale: shown ? 1 : 1.04
    Behavior on opacity { NumberAnimation { duration: Theme.med } }
    Behavior on scale { NumberAnimation { duration: Theme.med; easing.type: Easing.OutCubic } }
    onOpacityChanged: if (opacity === 0 && !shown && loaded) { loaded = false; unloaded() }

    Loader {
        anchors.fill: parent
        active: all.visible
        sourceComponent: Item {
            ShaderEffectSource {
                id: behind
                anchors.fill: parent
                sourceItem: all.source
                visible: false
            }
            MultiEffect {
                anchors.fill: parent
                source: behind
                blurEnabled: true; blur: 1; blurMax: 64
                brightness: -0.35
                saturation: 0.2
            }
        }
    }
    Rectangle { anchors.fill: parent; color: "#80000000" }

    Text {
        id: title
        x: Theme.gutter; y: 70 * Theme.s
        text: "All Apps"
        color: Theme.text
        font.family: Theme.font
        font.pixelSize: 56 * Theme.s
        font.weight: Font.Bold
    }

    GridView {
        id: grid
        anchors { top: title.bottom; topMargin: 10 * Theme.s; bottom: parent.bottom; left: parent.left; right: parent.right }
        leftMargin: Theme.gutter - 20 * Theme.s
        rightMargin: Theme.gutter
        topMargin: 50 * Theme.s
        bottomMargin: 80 * Theme.s
        readonly property int columns: Math.max(1, Math.floor((width - 2 * Theme.gutter) / (300 * Theme.s)))
        cellWidth: (width - leftMargin - rightMargin) / columns
        cellHeight: cellWidth * 0.6 + 70 * Theme.s
        model: all.loaded ? Apps.allApps : []
        clip: true
        keyNavigationEnabled: true
        highlightFollowsCurrentItem: true
        preferredHighlightBegin: height * 0.2
        preferredHighlightEnd: height * 0.7
        highlightRangeMode: GridView.ApplyRange
        highlightMoveDuration: 260

        delegate: Item {
            id: cell
            required property var modelData
            required property int index
            width: grid.cellWidth; height: grid.cellHeight
            z: GridView.isCurrentItem ? 10 : 0

            AppTile {
                id: t
                x: 20 * Theme.s; y: 10 * Theme.s
                width: cell.width - 40 * Theme.s
                height: width * 0.6
                app: cell.modelData
                focused: cell.GridView.isCurrentItem && all.activeFocus
                running: Launcher.running.indexOf(cell.modelData.appId) >= 0
                glow: false
                iconCache: false
                onHovered: grid.currentIndex = cell.index
                onActivated: { t.pop(); Launcher.launch(cell.modelData.key) }
            }
        }

        Keys.onPressed: (e) => {
            if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Select) {
                const t = grid.currentItem
                if (t) { t.children[0].pop(); Launcher.launch(t.modelData.key) }
            } else if ([Qt.Key_Escape, Qt.Key_Back, Qt.Key_Backspace, Qt.Key_HomePage].indexOf(e.key) >= 0) {
                all.close()
            } else return
            e.accepted = true
        }
    }
}
