// Generic settings list: renders row descriptors with SettingRow and handles remote
// navigation, option changes, confirm-twice actions and grab-to-reorder. Focus follows its
// row when rows are added or removed above it (e.g. a "Pairing…" note).
import QtQuick

FocusScope {
    id: pane

    property var rows: []
    property var host: null
    property var backHandler: null
    property int index: 0
    property int confirming: -1
    property bool grabbed: false
    property real scrollTarget: 0
    property bool touched: false
    property string focusKey: ""

    signal back()

    function focusable(i) {
        const r = rows[i]
        return !!r && r.kind !== "header" && r.kind !== "note" && r.kind !== "info"
    }

    function keyOf(r) { return r ? r.kind + "|" + (r.label || "") : "" }

    function first() {
        for (let i = 0; i < rows.length; i++) if (focusable(i)) return i
        return 0
    }

    function reset() { index = first(); confirming = -1; grabbed = false; touched = false; flick.contentY = 0 }

    function step(d) {
        let i = index + d
        while (i >= 0 && i < rows.length && !focusable(i)) i += d
        if (i >= 0 && i < rows.length) index = i
    }

    function activate(i) {
        const r = rows[i]
        if (!r || !focusable(i)) return
        if (r.confirm && confirming !== i) { confirming = i; return }
        confirming = -1
        if (r.move) { grabbed = !grabbed; return }
        if (r.run) r.run()
    }

    function goBack() {
        if (grabbed) { grabbed = false; return }
        if (backHandler && backHandler()) return
        back()
    }

    function scrollToCurrent() {
        const item = rep.itemAt(index)
        if (!item) return
        const max = Math.max(0, col.height - flick.height)
        scrollTarget = Math.max(0, Math.min(max, item.y - flick.height * 0.35))
        scroll.restart()
    }

    onRowsChanged: {
        const key = focusKey
        const moved = rows.findIndex((r, i) => focusable(i) && keyOf(r) === key)
        if (!touched) index = first()
        else if (moved >= 0) {
            if (moved !== index) confirming = -1
            index = moved
        } else if (!focusable(index)) {
            const before = index
            step(1)
            if (index === before) step(-1)
            if (!focusable(index)) index = first()
        }
        focusKey = keyOf(rows[index])
        Qt.callLater(scrollToCurrent)
    }
    onIndexChanged: { focusKey = keyOf(rows[index]); Qt.callLater(scrollToCurrent) }
    Component.onCompleted: index = first()

    Keys.onPressed: (e) => {
        touched = true
        const r = rows[index] || {}
        switch (e.key) {
        case Qt.Key_Up:
        case Qt.Key_Down: {
            const d = e.key === Qt.Key_Up ? -1 : 1
            confirming = -1
            if (grabbed && r.move) {
                const j = index + d
                if (j >= 0 && j < rows.length && rows[j].move) { r.move(d); index = j }
            } else step(d)
            break
        }
        case Qt.Key_Left:
        case Qt.Key_Right:
            if (r.change && !grabbed) r.change(e.key === Qt.Key_Left ? -1 : 1)
            else if (e.key === Qt.Key_Left) goBack()
            break
        case Qt.Key_Return: case Qt.Key_Enter: case Qt.Key_Select: case Qt.Key_Space:
            activate(index); break
        case Qt.Key_Escape: case Qt.Key_Back: case Qt.Key_Backspace:
            goBack(); break
        default:
            return
        }
        e.accepted = true
    }

    Flickable {
        id: flick
        anchors.fill: parent
        contentHeight: col.height + 40 * Theme.s
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        NumberAnimation { id: scroll; target: flick; property: "contentY"; to: pane.scrollTarget; duration: 240; easing.type: Easing.OutCubic }

        Column {
            id: col
            width: flick.width - 20 * Theme.s
            x: 10 * Theme.s
            y: 10 * Theme.s
            spacing: 10 * Theme.s

            Repeater {
                id: rep
                model: pane.rows
                delegate: SettingRow {
                    required property var modelData
                    required property int index
                    width: col.width
                    row: modelData
                    focused: pane.activeFocus && index === pane.index
                    confirming: pane.confirming === index
                    grabbed: pane.grabbed && index === pane.index
                    onHovered: if (pane.focusable(index)) { pane.touched = true; pane.index = index; pane.forceActiveFocus() }
                    onClicked: { pane.index = index; pane.forceActiveFocus(); pane.activate(index) }
                }
            }
        }
    }
}
