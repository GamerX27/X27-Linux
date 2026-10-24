// A Phosphor UI icon from qml/icons (fill style; bold for check and carets), rendered
// crisp at its size in any color.
import QtQuick

Image {
    property string name: ""
    property color color: "white"
    property real size: 28 * Theme.s

    width: size
    height: size
    sourceSize: Qt.size(Math.ceil(size * 2), Math.ceil(size * 2))
    source: name ? "image://icon/" + encodeURIComponent("ui:" + name + ":" + color) : ""
    fillMode: Image.PreserveAspectFit
    smooth: true
    mipmap: true
}
