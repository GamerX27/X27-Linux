// The home row: a horizontal strip of AppTiles that keeps focus inside the safe area
// and scrolls smoothly once focus nears the edge.
import QtQuick

ListView {
    id: row

    property bool active: true

    signal launchRequested(int index)
    signal hoveredIndex(int index)

    function currentTile() { return currentItem ? currentItem.tile : null }

    orientation: ListView.Horizontal
    spacing: 44 * Theme.s
    height: Theme.tileH + 110 * Theme.s
    leftMargin: Theme.gutter
    rightMargin: Theme.gutter
    clip: false
    interactive: false
    highlightFollowsCurrentItem: true
    highlightRangeMode: ListView.ApplyRange
    preferredHighlightBegin: Theme.gutter
    preferredHighlightEnd: width - Theme.gutter - Theme.tileW
    highlightMoveDuration: 380
    highlightMoveVelocity: -1
    cacheBuffer: width

    delegate: Item {
        id: cell
        required property var modelData
        required property int index
        property alias tile: t
        width: Theme.tileW
        height: row.height
        z: ListView.isCurrentItem ? 10 : 0

        AppTile {
            id: t
            width: Theme.tileW; height: Theme.tileH
            y: 30 * Theme.s
            app: cell.modelData
            focused: cell.ListView.isCurrentItem && row.active
            running: Launcher.running.indexOf(cell.modelData.appId) >= 0
            installing: Launcher.installing.indexOf(cell.modelData.key) >= 0
            onHovered: row.hoveredIndex(cell.index)
            onActivated: row.launchRequested(cell.index)
        }
    }
}
