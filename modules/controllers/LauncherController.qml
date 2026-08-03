import QtQml

QtObject {
    id: root

    property bool visible: false

    function show() { root.visible = true }
    function hide() { root.visible = false }
    function toggle() { root.visible = !root.visible }
}
