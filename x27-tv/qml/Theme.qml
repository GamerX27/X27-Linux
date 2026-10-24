// Shared look: palette, type, sizes (scaled from a 1080p reference) and motion timings.
pragma Singleton
import QtQuick

QtObject {
    property real s: 1

    readonly property string font: {
        const fams = Qt.fontFamilies()
        for (const f of ["Inter", "SF Pro Display", "Adwaita Sans", "Cantarell", "Noto Sans"])
            if (fams.indexOf(f) >= 0) return f
        return "sans-serif"
    }

    readonly property color text: "#ffffff"
    readonly property color dim: "#a1a1a6"
    readonly property color faint: "#636366"
    readonly property color glass: "#8c1c1c1e"
    readonly property color glassEdge: "#26ffffff"
    readonly property color focusFill: "#f2ffffff"
    readonly property color focusText: "#000000"

    readonly property real tileW: 380 * s
    readonly property real tileH: 228 * s
    readonly property real tileRadius: 22 * s
    readonly property real gutter: 96 * s
    readonly property real focusScale: 1.14

    readonly property int fast: 160
    readonly property int med: 320
    readonly property int slow: 700
}
