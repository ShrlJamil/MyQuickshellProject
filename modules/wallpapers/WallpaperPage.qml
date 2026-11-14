import QtQuick
import QtQuick.Dialogs
import Qt5Compat.GraphicalEffects
import "../../components"

// The Settings Wallpaper page. A thin view over WallpaperService,
// which owns the collection, the active wallpaper and the apply
// history. The page is deliberately light on text - no search, no
// file names, no status prose - but fully interactive: the active
// wallpaper large at the top, then the whole collection under it as
// a scrolling thumbnail grid, loaded from the wallpaper files. There is
// no selection state and no Apply step: clicking any thumbnail
// applies it immediately (the service queues latest-wins while
// busy), and an imported image applies as soon as its import lands,
// so nothing here can sit in a "not applied yet" state.
Item {
    id: root

    // Local Settings surface tokens, set by the host (SettingsView) so this
    // page stays monochrome-dark regardless of the global Wallust palette.
    // Text, accent and hover tokens keep following the global theme.
    property color settingsBackground: Theme.darkMode ? "#0A0A0A" : Theme.background
    property color settingsSurface: Theme.darkMode ? "#141414" : Theme.surface
    property color settingsSurfaceRaised: Theme.darkMode ? "#1E1E1E" : Theme.surfaceRaised
    property color settingsSurfaceOverlay: Theme.darkMode ? "#2A2A2A" : Theme.surfaceOverlay

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
        border.color: "transparent"

        Text {
            id: btnLabel

            anchors.centerIn: parent
            text: btn.label
            color: btn.accent ? settingsBackground : Theme.text
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
            topMargin: 10
            leftMargin: 10
        }

        text: "Wallpaper"
        color: Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: 18
        font.weight: Font.DemiBold
    }

    PageButton {
        anchors {
            right: parent.right
            verticalCenter: pageTitle.verticalCenter
            rightMargin: 10
        }

        label: "Browse…"
        disabled: WallpaperService.busy
        onActivated: importDialog.open()
    }

    Rectangle {
        id: divider

        anchors {
            top: pageTitle.bottom
            left: parent.left
            right: parent.right
            topMargin: 14
            leftMargin: 10
            rightMargin: 10
        }

        height: 1
        color: "transparent"
    }

    // ---- the active wallpaper, large ------------------------------------------
    Rectangle {
        id: bigPreview

        anchors {
            top: divider.bottom
            horizontalCenter: parent.horizontalCenter
            topMargin: 12
        }

        // 16:9, as large as the page allows while reserving room for
        // at least a slice of the collection grid below: the fixed
        // reservations total about 170 (gaps and a minimum grid
        // viewport).
        width: Math.max(240, Math.min(root.width - 20, 720, (root.height - 170) * 16 / 9))
        height: Math.round(width * 9 / 16)
        radius: 10
        color: settingsSurfaceRaised

        Image {
            id: bigImage

            anchors.fill: parent
            source: WallpaperService.activePath ? WallpaperService.urlForPath(WallpaperService.activePath) : ""
            sourceSize.width: 1280
            fillMode: Image.PreserveAspectCrop
            asynchronous: true

            // Rounded via layer OpacityMask - the codebase's proven
            // pattern (Item.clip does not round an Image).
            layer.enabled: bigImage.status === Image.Ready
            layer.smooth: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: bigImage.width
                    height: bigImage.height
                    radius: 10
                }
            }
        }
    }

    // ---- the collection ---------------------------------------------------------
    GridView {
        id: grid

        anchors {
            top: bigPreview.bottom
            left: parent.left
            right: parent.right
            bottom: parent.bottom
            topMargin: 12
            leftMargin: 4
            rightMargin: 4
            bottomMargin: 6
        }

        clip: true
        model: WallpaperService.wallpapers
        cellWidth: Math.floor(grid.width / Math.max(2, Math.floor(grid.width / 250)))
        cellHeight: Math.round((grid.cellWidth - 12) * 0.5625) + 12

        delegate: Item {
            id: cell

            required property string filePath
            required property url fileUrl

            readonly property bool isActive: cell.filePath === WallpaperService.activePath

            width: grid.cellWidth
            height: grid.cellHeight

            Rectangle {
                anchors.fill: parent
                anchors.margins: 6
                radius: 10
                color: cellHover.hovered ? Theme.surfaceHover : "transparent"
                border.width: cell.isActive ? 2 : 1
                border.color: cell.isActive ? Theme.accent : Qt.rgba(1, 1, 1, 0.04)

                Image {
                    id: cellThumb

                    anchors.fill: parent
                    anchors.margins: 4
                    source: cell.fileUrl
                    sourceSize.width: 512
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true

                    layer.enabled: cellThumb.status === Image.Ready
                    layer.smooth: true
                    layer.effect: OpacityMask {
                        maskSource: Rectangle {
                            width: cellThumb.width
                            height: cellThumb.height
                            radius: 7
                        }
                    }
                }

                // Load-failure fallback: the cell stays clickable, only
                // the picture is missing.
                Rectangle {
                    visible: cellThumb.status === Image.Error
                    anchors.fill: cellThumb
                    radius: 7
                    color: settingsSurfaceRaised
                }

                HoverHandler {
                    id: cellHover
                    cursorShape: Qt.PointingHandCursor
                }
                TapHandler {
                    onTapped: if (!cell.isActive)
                        WallpaperService.apply(cell.filePath)
                }
            }
        }
    }

    // ---- empty collection ---------------------------------------------------------
    Text {
        visible: WallpaperService.wallpapers.count === 0

        anchors.centerIn: grid
        text: "No wallpapers yet"
        color: Theme.textMuted
        font.family: Theme.fontFamily
        font.pixelSize: 13
        font.weight: Font.DemiBold
    }

    // An import applies straight away: the imported image becomes the
    // active wallpaper as soon as it lands in the collection.
    Connections {
        target: WallpaperService

        function onImportFinished(success, path) {
            if (success && path)
                WallpaperService.apply(path)
        }
    }

    FileDialog {
        id: importDialog

        title: "Import Wallpaper"
        nameFilters: ["Images (*.jpg *.jpeg *.png *.webp)"]

        onAccepted: WallpaperService.importFile(WallpaperService.pathFromUrl(selectedFile))
    }
}
