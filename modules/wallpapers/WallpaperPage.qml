import QtQuick
import QtQuick.Dialogs
import Qt5Compat.GraphicalEffects
import "../../components"

// The Settings Wallpaper page (MVP). A thin view over the shared
// WallpaperService - the same service the DynamicCenter carousel uses -
// so both surfaces always agree on the collection, the selection, the
// active wallpaper and the apply history. Applying never closes
// Settings: the pipeline runs inside the service and this page just
// reflects its status.
Item {
    id: root

    onVisibleChanged: if (root.visible)
        WallpaperService.reload()

    component PageButton: Rectangle {
        id: btn

        property string label: ""
        property bool accent: false
        property bool disabled: false
        signal activated()

        implicitWidth: btnLabel.implicitWidth + 24
        implicitHeight: 30
        radius: 8
        opacity: btn.disabled ? 0.45 : 1
        color: btn.accent ? Theme.accent : (btnHover.hovered && !btn.disabled ? Theme.surfaceHover : Qt.rgba(1, 1, 1, 0.03))
        border.width: 1
        border.color: btn.accent ? "transparent" : Qt.rgba(1, 1, 1, Theme.materialBorderOpacity)

        Text {
            id: btnLabel

            anchors.centerIn: parent
            text: btn.label
            color: btn.accent ? Theme.background : Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: 12
            font.weight: Font.DemiBold
        }

        HoverHandler {
            id: btnHover
            cursorShape: btn.disabled ? Qt.ArrowCursor : Qt.PointingHandCursor
        }
        TapHandler {
            enabled: !btn.disabled
            onTapped: btn.activated()
        }
    }

    // ---- header -------------------------------------------------------------
    Text {
        id: pageTitle

        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            topMargin: 10
            leftMargin: 10
            rightMargin: 10
        }

        text: "Wallpaper"
        color: Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: 18
        font.weight: Font.DemiBold
    }

    Text {
        id: pageDesc

        anchors {
            top: pageTitle.bottom
            left: parent.left
            right: parent.right
            topMargin: 6
            leftMargin: 10
            rightMargin: 10
        }

        text: "Pick from your collection in ~/Pictures/Wallpapers, or import a new image. Applying updates every monitor and regenerates the wallust / matugen theme."
        color: Theme.textDim
        font.family: Theme.fontFamily
        font.pixelSize: 12
        lineHeight: 1.25
        wrapMode: Text.WordWrap
    }

    // ---- controls ---------------------------------------------------------------
    Row {
        id: controls

        anchors {
            top: pageDesc.bottom
            left: parent.left
            topMargin: 14
            leftMargin: 10
        }

        spacing: 8

        PageButton {
            label: "Import Wallpaper"
            disabled: WallpaperService.busy
            onActivated: importDialog.open()
        }

        PageButton {
            label: WallpaperService.status === "applying" ? "Applying…" : "Apply"
            accent: true
            disabled: WallpaperService.busy || !WallpaperService.selectedPath
            onActivated: WallpaperService.apply(WallpaperService.selectedPath)
        }
    }

    Text {
        id: statusText

        anchors {
            left: controls.right
            right: parent.right
            top: pageDesc.bottom
            topMargin: 14
            leftMargin: 12
            rightMargin: 10
        }

        height: 30
        verticalAlignment: Text.AlignVCenter
        text: WallpaperService.statusMessage
        color: WallpaperService.status === "error" ? Theme.accent : Theme.textMuted
        font.family: Theme.fontFamily
        font.pixelSize: 11
        elide: Text.ElideRight
    }

    Rectangle {
        id: divider

        anchors {
            top: controls.bottom
            left: parent.left
            right: parent.right
            topMargin: 14
            leftMargin: 10
            rightMargin: 10
        }

        height: 1
        color: Qt.rgba(1, 1, 1, Theme.materialBorderOpacity)
    }

    // ---- recently used -----------------------------------------------------------
    Text {
        id: recentLabel

        visible: WallpaperService.history.length > 0

        anchors {
            top: divider.bottom
            left: parent.left
            topMargin: 14
            leftMargin: 10
        }

        text: "Recently Used"
        color: Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: 12
        font.weight: Font.DemiBold
    }

    ListView {
        id: recentStrip

        visible: WallpaperService.history.length > 0

        anchors {
            top: recentLabel.bottom
            left: parent.left
            right: parent.right
            topMargin: 8
            leftMargin: 10
            rightMargin: 10
        }

        height: 62
        orientation: ListView.Horizontal
        spacing: 8
        clip: true
        model: WallpaperService.history

        delegate: Rectangle {
            id: recentCell

            required property var modelData

            readonly property bool isSelected: modelData === WallpaperService.selectedPath
            readonly property bool isActive: modelData === WallpaperService.activePath

            width: 106
            height: 58
            radius: 8
            color: Theme.surfaceHover
            border.width: recentCell.isSelected ? 2 : 1
            border.color: recentCell.isSelected ? Theme.accent : Qt.rgba(1, 1, 1, 0.05)

            Image {
                id: recentImg

                anchors.fill: parent
                anchors.margins: 1

                source: WallpaperService.urlForPath(modelData)
                sourceSize.width: 212
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true

                // Rounded via layer OpacityMask - the codebase's proven
                // pattern (Item.clip does not round an Image).
                layer.enabled: recentImg.status === Image.Ready
                layer.smooth: true
                layer.effect: OpacityMask {
                    maskSource: Rectangle {
                        width: recentImg.width
                        height: recentImg.height
                        radius: 7
                    }
                }
            }

            Rectangle {
                visible: recentCell.isActive
                anchors {
                    top: parent.top
                    left: parent.left
                    topMargin: 5
                    leftMargin: 5
                }
                width: activeText.implicitWidth + 8
                height: 14
                radius: 4
                color: Theme.accent

                Text {
                    id: activeText

                    anchors.centerIn: parent
                    text: "ACTIVE"
                    color: Theme.background
                    font.family: Theme.fontFamily
                    font.pixelSize: 8
                    font.weight: Font.Bold
                }
            }

            TapHandler {
                onTapped: WallpaperService.select(modelData)
            }
        }
    }

    // ---- collection ----------------------------------------------------------------
    Text {
        id: collectionLabel

        anchors {
            top: recentStrip.visible ? recentStrip.bottom : divider.bottom
            left: parent.left
            topMargin: 14
            leftMargin: 10
        }

        text: "Collection" + (WallpaperService.wallpapers.count > 0 ? "  ·  " + WallpaperService.wallpapers.count : "")
        color: Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: 12
        font.weight: Font.DemiBold
    }

    GridView {
        id: grid

        anchors {
            top: collectionLabel.bottom
            left: parent.left
            right: parent.right
            bottom: parent.bottom
            topMargin: 8
            leftMargin: 4
            rightMargin: 4
            bottomMargin: 6
        }

        clip: true
        model: WallpaperService.wallpapers
        cellWidth: Math.floor(grid.width / Math.max(2, Math.floor(grid.width / 190)))
        cellHeight: Math.round((grid.cellWidth - 12) * 0.5625) + 34

        delegate: Item {
            id: cell

            required property int index
            required property string filePath
            required property string fileName
            required property url fileUrl

            readonly property bool isSelected: cell.filePath === WallpaperService.selectedPath
            readonly property bool isActive: cell.filePath === WallpaperService.activePath

            width: grid.cellWidth
            height: grid.cellHeight

            Rectangle {
                id: card

                anchors.fill: parent
                anchors.margins: 6
                radius: 10
                color: cellHover.hovered ? Theme.surfaceHover : "transparent"
                border.width: cell.isSelected ? 2 : 1
                border.color: cell.isSelected ? Theme.accent : Qt.rgba(1, 1, 1, 0.04)

                Image {
                    id: thumb

                    anchors {
                        top: parent.top
                        left: parent.left
                        right: parent.right
                        topMargin: 4
                        leftMargin: 4
                        rightMargin: 4
                    }

                    height: parent.height - 30
                    source: cell.fileUrl
                    sourceSize.width: 360
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true

                    // Rounded via layer OpacityMask - the codebase's
                    // proven pattern (Item.clip does not round an Image).
                    layer.enabled: thumb.status === Image.Ready
                    layer.smooth: true
                    layer.effect: OpacityMask {
                        maskSource: Rectangle {
                            width: thumb.width
                            height: thumb.height
                            radius: 7
                        }
                    }
                }

                Rectangle {
                    visible: cell.isActive
                    anchors {
                        top: thumb.top
                        left: thumb.left
                        topMargin: 5
                        leftMargin: 5
                    }
                    width: gridActiveText.implicitWidth + 8
                    height: 14
                    radius: 4
                    color: Theme.accent

                    Text {
                        id: gridActiveText

                        anchors.centerIn: parent
                        text: "ACTIVE"
                        color: Theme.background
                        font.family: Theme.fontFamily
                        font.pixelSize: 8
                        font.weight: Font.Bold
                    }
                }

                Text {
                    anchors {
                        top: thumb.bottom
                        left: parent.left
                        right: parent.right
                        topMargin: 5
                        leftMargin: 6
                        rightMargin: 6
                    }

                    text: cell.fileName
                    color: cell.isSelected ? Theme.text : Theme.textDim
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideMiddle
                }

                HoverHandler {
                    id: cellHover
                    cursorShape: Qt.PointingHandCursor
                }
                TapHandler {
                    onTapped: WallpaperService.select(cell.filePath)
                }
            }
        }
    }

    // ---- empty state ---------------------------------------------------------------
    Column {
        visible: WallpaperService.wallpapers.count === 0

        anchors.centerIn: parent
        width: Math.min(360, root.width - 48)
        spacing: 8

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width
            text: "No wallpapers yet"
            color: Theme.textMuted
            font.family: Theme.fontFamily
            font.pixelSize: 13
            font.weight: Font.DemiBold
            horizontalAlignment: Text.AlignHCenter
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width
            text: "Your collection in ~/Pictures/Wallpapers is empty. Import an image to get started."
            color: Qt.rgba(Theme.textMuted.r, Theme.textMuted.g, Theme.textMuted.b, 0.7)
            font.family: Theme.fontFamily
            font.pixelSize: 11
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
        }
    }

    FileDialog {
        id: importDialog

        title: "Import Wallpaper"
        nameFilters: ["Images (*.jpg *.jpeg *.png *.webp)"]

        // Cancellation needs no handling: no state changes until a file
        // is actually accepted here.
        onAccepted: WallpaperService.importFile(WallpaperService.pathFromUrl(selectedFile))
    }
}
