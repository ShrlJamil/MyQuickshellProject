import QtQuick
import QtQuick.Dialogs
import Qt5Compat.GraphicalEffects
import "../../components"

// The Settings Wallpaper page. A thin view over WallpaperService,
// which owns the collection, the selection, the active wallpaper and
// the apply history. Applying never closes Settings: the pipeline runs
// inside the service and this page just reflects its status.
Item {
    id: root

    // Local Settings surface tokens, set by the host (SettingsView) so this
    // page stays monochrome-dark regardless of the global Wallust palette.
    // Text, accent and hover tokens keep following the global theme.
    property color settingsBackground: "#0A0A0A"
    property color settingsSurface: "#141414"
    property color settingsSurfaceRaised: "#1E1E1E"
    property color settingsSurfaceOverlay: "#2A2A2A"

    onVisibleChanged: if (root.visible) {
        WallpaperService.reload()
        root.rebuildFilter()
        grid.forceActiveFocus()
    }

    Component.onCompleted: root.rebuildFilter()

    // The grid's view of the collection: a page-local filter over the
    // service model. Searching rebuilds this list only - the service's
    // own model (and the files on disk) are never touched, the selection
    // is path-based in the service and survives filtering untouched.
    ListModel {
        id: filteredModel
    }

    function rebuildFilter() {
        const src = WallpaperService.wallpapers
        const q = searchInput.text.trim().toLowerCase()
        filteredModel.clear()
        for (let i = 0; i < src.count; i++) {
            const e = src.get(i)
            if (q === "" || e.fileName.toLowerCase().indexOf(q) >= 0)
                filteredModel.append({ fileUrl: e.fileUrl, filePath: e.filePath, fileName: e.fileName })
        }
        root.syncIndexToSelection()
    }

    // The selected collection entry, looked up in the SERVICE model (not
    // the filtered one) so the preview can keep showing the selection
    // even while a search query filters it out of the grid.
    readonly property var selectedInfo: {
        const src = WallpaperService.wallpapers
        for (let i = 0; i < src.count; i++) {
            const e = src.get(i)
            if (e.filePath === WallpaperService.selectedPath)
                return e
        }
        return null
    }

    // True while the grid's currentIndex is being aligned TO the service
    // selection (page open, rescan): keyboard/mouse navigation drives the
    // selection, never the other way around.
    property bool _syncingIndex: false

    function syncIndexToSelection() {
        for (let i = 0; i < filteredModel.count; i++) {
            if (filteredModel.get(i).filePath === WallpaperService.selectedPath) {
                root._syncingIndex = true
                grid.currentIndex = i
                root._syncingIndex = false
                return
            }
        }
        // Selection not in the model (yet): just release the guard the
        // count change set, so navigation is never left silently dead.
        root._syncingIndex = false
    }

    // Shared by Enter and double-click: the service guards the rest
    // (unknown path, busy queueing), exactly as for the Apply button.
    function applyPath(path) {
        if (path)
            WallpaperService.apply(path)
    }

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
        color: Qt.rgba(1, 1, 1, Theme.materialBorderOpacity)
    }

    // ---- toolbar: search ------------------------------------------------------------
    Rectangle {
        id: searchBox

        anchors {
            top: divider.bottom
            left: parent.left
            right: clearSearchButton.left
            topMargin: 12
            leftMargin: 10
            rightMargin: clearSearchButton.visible ? 8 : 0
        }

        height: 30
        radius: 8
        color: settingsSurface
        border.width: 1
        border.color: searchInput.activeFocus ? Qt.rgba(1, 1, 1, 0.28) : Qt.rgba(1, 1, 1, Theme.materialBorderOpacity)

        TextInput {
            id: searchInput

            anchors {
                fill: parent
                leftMargin: 10
                rightMargin: 10
            }

            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: 12
            verticalAlignment: TextInput.AlignVCenter
            clip: true
            selectionColor: Theme.accent
            selectedTextColor: settingsBackground

            onTextChanged: root.rebuildFilter()
            // Enter means the same thing here as on the grid: apply.
            onAccepted: root.applyPath(WallpaperService.selectedPath)
        }

        Text {
            anchors {
                left: parent.left
                verticalCenter: parent.verticalCenter
                leftMargin: 10
            }

            visible: searchInput.text === ""
            text: "Search wallpapers…"
            color: Theme.textMuted
            font.family: Theme.fontFamily
            font.pixelSize: 12
        }
    }

    PageButton {
        id: clearSearchButton

        anchors {
            top: searchBox.top
            right: parent.right
            rightMargin: 10
        }

        visible: searchInput.text !== ""
        label: "Clear"
        onActivated: {
            searchInput.text = ""
            grid.forceActiveFocus()
        }
    }

    // ---- preview of the current selection --------------------------------------------
    Rectangle {
        id: previewStrip

        anchors {
            top: searchBox.bottom
            left: parent.left
            right: parent.right
            topMargin: 10
            leftMargin: 10
            rightMargin: 10
        }

        height: 100
        radius: 10
        color: settingsSurface

        Rectangle {
            id: previewFrame

            anchors {
                left: parent.left
                verticalCenter: parent.verticalCenter
                leftMargin: 10
            }

            width: 142
            height: 80
            radius: 7
            color: settingsSurfaceRaised

            Image {
                id: previewImage

                anchors.fill: parent
                source: root.selectedInfo ? root.selectedInfo.fileUrl : ""
                sourceSize.width: 512
                fillMode: Image.PreserveAspectCrop
                asynchronous: true

                layer.enabled: previewImage.status === Image.Ready
                layer.smooth: true
                layer.effect: OpacityMask {
                    maskSource: Rectangle {
                        width: previewImage.width
                        height: previewImage.height
                        radius: 7
                    }
                }
            }

            Text {
                anchors.centerIn: parent
                width: parent.width - 12
                visible: !root.selectedInfo || previewImage.status === Image.Error
                text: previewImage.status === Image.Error ? "Preview unavailable" : "No selection"
                color: Theme.textMuted
                font.family: Theme.fontFamily
                font.pixelSize: 10
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }
        }

        Column {
            anchors {
                left: previewFrame.right
                right: parent.right
                verticalCenter: parent.verticalCenter
                leftMargin: 14
                rightMargin: 12
            }

            spacing: 4

            Text {
                width: parent.width
                text: root.selectedInfo ? root.selectedInfo.fileName : "No wallpaper selected"
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: 13
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }

            Text {
                visible: root.selectedInfo !== null && previewImage.status === Image.Ready
                text: previewImage.implicitWidth + " × " + previewImage.implicitHeight
                color: Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: 11
            }

            Row {
                spacing: 7

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 7
                    height: 7
                    radius: 3.5
                    color: !root.selectedInfo ? "transparent"
                         : WallpaperService.selectedPath === WallpaperService.activePath ? Theme.accent
                         : Theme.textMuted
                }

                Text {
                    text: !root.selectedInfo ? "Select a wallpaper from the collection below."
                        : WallpaperService.selectedPath === WallpaperService.activePath ? "Currently applied"
                        : "Selected — not applied yet"
                    color: Theme.textDim
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                }
            }
        }
    }

    // ---- collection ----------------------------------------------------------------
    GridView {
        id: grid

        anchors {
            top: previewStrip.bottom
            left: parent.left
            right: parent.right
            bottom: footerDivider.top
            topMargin: 10
            leftMargin: 4
            rightMargin: 4
            bottomMargin: 8
        }

        clip: true
        model: filteredModel
        cellWidth: Math.floor(grid.width / Math.max(2, Math.floor(grid.width / 250)))
        cellHeight: Math.round((grid.cellWidth - 12) * 0.5625) + 34

        // Keyboard: arrows move the current item (the view scrolls it into
        // view itself) and the selection follows; Enter applies. Focus is
        // taken when the page shows and when a cell is clicked.
        focus: true
        keyNavigationEnabled: true

        onCurrentIndexChanged: {
            if (!root._syncingIndex && grid.currentItem)
                WallpaperService.select(grid.currentItem.filePath)
        }

        // A rescan rebuilds the model under the view: index changes from
        // that are the model settling, not navigation - ignore them, the
        // scanFinished hook re-aligns the index to the selection.
        onCountChanged: root._syncingIndex = true

        Keys.onReturnPressed: root.applyPath(WallpaperService.selectedPath)
        Keys.onEnterPressed: root.applyPath(WallpaperService.selectedPath)

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
                    sourceSize.width: 512
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

                // Load-failure fallback: the card (and its name below)
                // stays fully selectable; only the picture is missing.
                Rectangle {
                    visible: thumb.status === Image.Error
                    anchors.fill: thumb
                    radius: 7
                    color: settingsSurfaceRaised

                    Text {
                        anchors.centerIn: parent
                        text: "Image unavailable"
                        color: Theme.textMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
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
                        color: settingsBackground
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
                    onTapped: {
                        grid.forceActiveFocus()
                        grid.currentIndex = cell.index
                        WallpaperService.select(cell.filePath)
                    }
                    onDoubleTapped: root.applyPath(cell.filePath)
                }
            }
        }
    }

    // ---- footer (pinned; only the grid scrolls) --------------------------------------
    Rectangle {
        id: footerDivider

        anchors {
            bottom: footer.top
            left: parent.left
            right: parent.right
            bottomMargin: 10
            leftMargin: 10
            rightMargin: 10
        }

        height: 1
        color: Qt.rgba(1, 1, 1, Theme.materialBorderOpacity)
    }

    Item {
        id: footer

        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
            leftMargin: 10
            rightMargin: 10
            bottomMargin: 10
        }

        height: 30

        Text {
            id: statusText

            anchors {
                left: parent.left
                right: footerButtons.left
                verticalCenter: parent.verticalCenter
                rightMargin: 12
            }

            text: WallpaperService.statusMessage
            color: WallpaperService.status === "error" ? Theme.accent : Theme.textMuted
            font.family: Theme.fontFamily
            font.pixelSize: 11
            elide: Text.ElideRight
        }

        Row {
            id: footerButtons

            anchors {
                right: parent.right
                verticalCenter: parent.verticalCenter
            }

            spacing: 8

            PageButton {
                label: "Browse…"
                disabled: WallpaperService.busy
                onActivated: importDialog.open()
            }

            PageButton {
                label: WallpaperService.status === "applying" ? "Applying…" : "Apply"
                accent: true
                // Nothing to apply when the selection already IS the
                // applied wallpaper - the same dirty-check the Display
                // page's Apply uses. Enter / double-click stay live
                // commands regardless (see applyPath).
                disabled: WallpaperService.busy || !WallpaperService.selectedPath
                    || WallpaperService.selectedPath === WallpaperService.activePath
                onActivated: WallpaperService.apply(WallpaperService.selectedPath)
            }
        }
    }

    // ---- empty states ---------------------------------------------------------------
    Column {
        visible: WallpaperService.wallpapers.count === 0

        anchors.centerIn: grid
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
            text: "Your collection in ~/Pictures/Wallpapers is empty. Use Browse… below to add an image."
            color: Qt.rgba(Theme.textMuted.r, Theme.textMuted.g, Theme.textMuted.b, 0.7)
            font.family: Theme.fontFamily
            font.pixelSize: 11
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
        }
    }

    Column {
        visible: WallpaperService.wallpapers.count > 0 && filteredModel.count === 0

        anchors.centerIn: grid
        width: Math.min(360, root.width - 48)
        spacing: 8

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width
            text: "No matches for \"" + searchInput.text.trim() + "\""
            color: Theme.textMuted
            font.family: Theme.fontFamily
            font.pixelSize: 13
            font.weight: Font.DemiBold
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width
            text: "No wallpaper name contains that text. Clear the search to see the whole collection."
            color: Qt.rgba(Theme.textMuted.r, Theme.textMuted.g, Theme.textMuted.b, 0.7)
            font.family: Theme.fontFamily
            font.pixelSize: 11
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
        }
    }

    // ---- import success flash -------------------------------------------------------
    // A small pill that fades in over the top of the grid when an import
    // lands in the collection, then fades out on its own. Purely a
    // confirmation note - the footer status line keeps the details.
    Rectangle {
        id: importFlash

        anchors {
            top: grid.top
            horizontalCenter: parent.horizontalCenter
            topMargin: 10
        }

        width: flashText.implicitWidth + 28
        height: 30
        radius: height / 2
        color: settingsSurfaceOverlay
        opacity: 0
        visible: opacity > 0

        Behavior on opacity {
            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
        }

        Text {
            id: flashText

            anchors.centerIn: parent
            text: "Image saved to ~/Pictures/Wallpapers"
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: 12
            font.weight: Font.DemiBold
        }

        Timer {
            id: flashTimer

            interval: 2600
            onTriggered: importFlash.opacity = 0
        }
    }

    Connections {
        target: WallpaperService

        function onScanFinished() {
            root.rebuildFilter()
        }

        function onImportFinished(success, path) {
            if (!success)
                return
            importFlash.opacity = 1
            flashTimer.restart()
        }
    }

    FileDialog {
        id: importDialog

        title: "Import Wallpaper"
        nameFilters: ["Images (*.jpg *.jpeg *.png *.webp)"]

        // Cancellation needs no handling: no state changes until a file
        // is actually accepted here. QtQuick.Dialogs has no closed
        // signal - focus returns to the grid off the visible change,
        // which covers accept and cancel alike.
        onAccepted: WallpaperService.importFile(WallpaperService.pathFromUrl(selectedFile))
        onVisibleChanged: if (!importDialog.visible)
            grid.forceActiveFocus()
    }
}
