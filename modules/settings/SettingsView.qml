import QtQuick
import Qt5Compat.GraphicalEffects
import Quickshell
import "../../components"
import "../display"
import "../wallpapers"

FocusScope {
    id: root

    readonly property int pad: 16
    readonly property int headerHeight: 40
    readonly property int gap: 12
    readonly property real sidebarWidth: Math.max(150, Math.min(216, root.width * 0.26))

    readonly property color settingsBackground: "#0A0A0A"
    readonly property color settingsSurface: "#141414"
    readonly property color settingsSurfaceRaised: "#1E1E1E"
    readonly property color settingsSurfaceOverlay: "#2A2A2A"

    readonly property var categories: [
        {
            label: "Appearance",
            icon: "preferences-appearance-symbolic",
            fallback: "applications-graphics",
            description: "Theme, accent color, and the overall look of the shell."
        },
        {
            label: "Wallpaper",
            icon: "preferences-desktop-wallpaper-symbolic",
            fallback: "image-x-generic",
            description: "Wallpaper selection and background images for each monitor."
        },
        {
            label: "Display",
            icon: "preferences-desktop-display-symbolic",
            fallback: "video-display",
            description: "Monitor layout, resolution, and refresh rate."
        },
        {
            label: "Typography",
            icon: "preferences-desktop-font-symbolic",
            fallback: "font-x-generic",
            description: "Font family and text sizes used across the shell."
        },
        {
            label: "About",
            icon: "help-about-symbolic",
            fallback: "dialog-information",
            description: "Version and environment information for this shell."
        }
    ]

    // Owned by SettingsService so IPC callers can preselect a page; the
    // sidebar writes through to the service.
    readonly property int categoryIndex: SettingsService.categoryIndex

    // First-visit latches for the page Loaders in the detail pane: a
    // page's tree is created the first time its category is selected and
    // kept for the rest of the session (the shell-level Loader destroys
    // the whole view when Settings closes anyway), so opening Settings
    // never pays for pages the user does not visit.
    property bool _displayVisited: false
    property bool _wallpaperVisited: false

    readonly property var activeCategory: root.categories[Math.max(0, Math.min(root.categories.length - 1, root.categoryIndex))]

    signal closeRequested()

    Keys.onEscapePressed: root.closeRequested()

    // Reopening the window while the Display page is selected must behave
    // like opening the old DynamicCenter surface did: a fresh sync.
    // DisplayManager.onVisibleChanged cannot provide this here - its
    // `visible` is bound to the category alone, so it does not change when
    // the window opens or closes.
    Connections {
        target: SettingsService

        function onOpenChanged() {
            if (SettingsService.open && root.categoryIndex === SettingsService.displayCategory)
                DisplayService.syncFromHyprland()
        }
    }

    // The lazy Loader in shell.qml CREATES this view as a result of the
    // open, so the Connections above never observes that first open change.
    // Run the same check once at creation; later category switches are
    // covered by DisplayManager.onVisibleChanged as before.
    Component.onCompleted: {
        if (SettingsService.open && root.categoryIndex === SettingsService.displayCategory)
            DisplayService.syncFromHyprland()
    }

    // Deliberately square and full-bleed: this view fills a real application
    // window, so corner rounding belongs to the compositor (his Hyprland
    // rounding rules), not to the app - an app-drawn radius would double up
    // with the compositor's own corner shape.
    Rectangle {
        id: baseLayer

        anchors.fill: parent
        color: settingsBackground
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, Theme.materialBorderOpacity)
    }

    Item {
        id: header

        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            topMargin: root.pad
            leftMargin: root.pad
            rightMargin: root.pad
        }

        height: root.headerHeight

        Text {
            anchors.verticalCenter: parent.verticalCenter

            text: "Settings"
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: 16
            font.weight: Font.DemiBold
        }

        Rectangle {
            id: closeButton

            anchors {
                right: parent.right
                verticalCenter: parent.verticalCenter
            }

            width: 30
            height: 30
            radius: 9
            color: closeArea.containsMouse ? Theme.surfaceHover : "transparent"

            Behavior on color {
                ColorAnimation { duration: 120 }
            }

            Image {
                id: closeIcon

                anchors.centerIn: parent
                width: 16
                height: 16
                source: Quickshell.iconPath("window-close-symbolic", "window-close")
                sourceSize.width: 32
                sourceSize.height: 32
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                smooth: true
                visible: false
            }

            ColorOverlay {
                anchors.fill: closeIcon

                source: closeIcon
                color: closeArea.containsMouse ? Theme.text : Theme.textDim
            }

            MouseArea {
                id: closeArea

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.closeRequested()
            }
        }
    }

    Item {
        id: body

        anchors {
            top: header.bottom
            left: parent.left
            right: parent.right
            bottom: parent.bottom
            topMargin: root.gap
            leftMargin: root.pad
            rightMargin: root.pad
            bottomMargin: root.pad
        }

        Rectangle {
            id: sidebar

            anchors {
                top: parent.top
                left: parent.left
                bottom: parent.bottom
            }

            width: root.sidebarWidth
            radius: 14
            color: settingsSurface
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, Theme.materialBorderOpacity * 0.7)

            Column {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 4

                Repeater {
                    model: root.categories

                    delegate: Rectangle {
                        id: sidebarItem

                        required property var modelData
                        required property int index

                        readonly property bool active: root.categoryIndex === sidebarItem.index

                        width: parent.width
                        height: 42
                        radius: 10
                        color: sidebarItem.active
                            ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, sidebarArea.containsMouse ? 0.26 : 0.18)
                            : (sidebarArea.containsMouse ? Theme.surfaceHover : "transparent")

                        Behavior on color {
                            ColorAnimation { duration: 120 }
                        }

                        Row {
                            anchors {
                                left: parent.left
                                right: parent.right
                                verticalCenter: parent.verticalCenter
                                leftMargin: 10
                                rightMargin: 8
                            }

                            spacing: 10

                            Item {
                                width: 20
                                height: 20
                                anchors.verticalCenter: parent.verticalCenter

                                Image {
                                    id: itemIcon

                                    anchors.fill: parent
                                    source: Quickshell.iconPath(sidebarItem.modelData.icon, sidebarItem.modelData.fallback)
                                    sourceSize.width: 36
                                    sourceSize.height: 36
                                    fillMode: Image.PreserveAspectFit
                                    asynchronous: true
                                    smooth: true
                                    visible: false
                                }

                                ColorOverlay {
                                    anchors.fill: itemIcon

                                    source: itemIcon
                                    color: sidebarItem.active
                                        ? Theme.accent
                                        : (sidebarArea.containsMouse ? Theme.text : Theme.textDim)
                                }
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter

                                width: parent.width - 30
                                text: sidebarItem.modelData.label
                                color: sidebarItem.active
                                    ? Theme.accent
                                    : (sidebarArea.containsMouse ? Theme.text : Theme.textDim)
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                font.weight: sidebarItem.active ? Font.DemiBold : Font.Medium
                                elide: Text.ElideRight
                            }
                        }

                        MouseArea {
                            id: sidebarArea

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: SettingsService.categoryIndex = sidebarItem.index
                        }
                    }
                }
            }
        }

        Rectangle {
            id: detail

            anchors {
                top: parent.top
                left: sidebar.right
                right: parent.right
                bottom: parent.bottom
                leftMargin: root.gap
            }

            radius: 14
            color: settingsBackground
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, Theme.materialBorderOpacity)

            Text {
                id: detailTitle

                visible: root.categoryIndex !== SettingsService.displayCategory && root.categoryIndex !== SettingsService.wallpaperCategory

                anchors {
                    top: parent.top
                    left: parent.left
                    right: parent.right
                    topMargin: 22
                    leftMargin: 22
                    rightMargin: 22
                }

                text: root.activeCategory ? root.activeCategory.label : ""
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: 18
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }

            Text {
                id: detailDescription

                visible: root.categoryIndex !== SettingsService.displayCategory && root.categoryIndex !== SettingsService.wallpaperCategory

                anchors {
                    top: detailTitle.bottom
                    left: parent.left
                    right: parent.right
                    topMargin: 6
                    leftMargin: 22
                    rightMargin: 22
                }

                text: root.activeCategory ? root.activeCategory.description : ""
                color: Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: 12
                lineHeight: 1.25
                wrapMode: Text.WordWrap
            }

            Rectangle {
                id: divider

                visible: root.categoryIndex !== SettingsService.displayCategory && root.categoryIndex !== SettingsService.wallpaperCategory

                anchors {
                    top: detailDescription.bottom
                    left: parent.left
                    right: parent.right
                    topMargin: 18
                    leftMargin: 22
                    rightMargin: 22
                }

                height: 1
                color: Qt.rgba(1, 1, 1, Theme.materialBorderOpacity)
            }

            Rectangle {
                id: placeholder

                visible: root.categoryIndex !== SettingsService.displayCategory && root.categoryIndex !== SettingsService.wallpaperCategory

                anchors {
                    top: divider.bottom
                    left: parent.left
                    right: parent.right
                    bottom: parent.bottom
                    topMargin: 18
                    leftMargin: 22
                    rightMargin: 22
                    bottomMargin: 22
                }

                radius: 12
                color: "transparent"
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.04)

                Column {
                    anchors.centerIn: parent

                    width: Math.min(360, placeholder.width - 48)
                    spacing: 10

                    Item {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 28
                        height: 28
                        opacity: 0.75

                        Image {
                            id: placeholderIcon

                            anchors.fill: parent
                            source: root.activeCategory
                                ? Quickshell.iconPath(root.activeCategory.icon, root.activeCategory.fallback)
                                : ""
                            sourceSize.width: 56
                            sourceSize.height: 56
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                            smooth: true
                            visible: false
                        }

                        ColorOverlay {
                            anchors.fill: placeholderIcon

                            source: placeholderIcon
                            color: Theme.textMuted
                        }
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter

                        width: parent.width
                        text: root.activeCategory
                            ? root.activeCategory.label + " settings are not available yet."
                            : ""
                        color: Theme.textMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter

                        width: parent.width
                        text: "This section is a placeholder for the upcoming integration."
                        color: Qt.rgba(Theme.textMuted.r, Theme.textMuted.g, Theme.textMuted.b, 0.7)
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                    }
                }
            }

            // The Display page hosts the real DisplayManager (moved out of
            // DynamicCenter). The generic title / description / placeholder
            // chrome above hides itself for this category so the manager
            // gets the full detail pane - it needs the height, and it carries
            // its own headings.
            //
            // Lazy (Loader latch): the manager's tree - the heaviest in
            // Settings - is created on the first visit to this category
            // and kept afterwards. The page keeps its own `visible`
            // binding, so its onVisibleChanged behaviour on later category
            // switches is exactly what it was when it lived here directly.
            Loader {
                id: displayLoader

                anchors.fill: parent
                anchors.margins: 12
                active: root.categoryIndex === SettingsService.displayCategory || root._displayVisited
                sourceComponent: displayPageComponent

                onLoaded: {
                    root._displayVisited = true
                    // First-creation compensation: the page is born
                    // visible, so the onVisibleChanged trigger it relies
                    // on (sync + take focus) never fires for this first
                    // show the way it does for a switch into an existing
                    // page. Run the same two actions here.
                    DisplayService.syncFromHyprland()
                    if (item) item.forceActiveFocus()
                }
            }

            Component {
                id: displayPageComponent

                DisplayManager {
                    anchors.fill: parent
                    visible: root.categoryIndex === SettingsService.displayCategory

                    settingsBackground: root.settingsBackground
                    settingsSurface: root.settingsSurface
                    settingsSurfaceRaised: root.settingsSurfaceRaised
                    settingsSurfaceOverlay: root.settingsSurfaceOverlay

                    onCloseRequested: root.closeRequested()
                }
            }

            // Same arrangement for the Wallpaper page: a thin view over
            // the shared WallpaperService with its own headings, so the
            // generic chrome hides for this category too. Lazy the same
            // way - its thumbnail grid is the second-heaviest tree here.
            Loader {
                id: wallpaperLoader

                anchors.fill: parent
                anchors.margins: 12
                active: root.categoryIndex === SettingsService.wallpaperCategory || root._wallpaperVisited
                sourceComponent: wallpaperPageComponent

                onLoaded: {
                    root._wallpaperVisited = true
                    // First-creation compensation, as above: the page is
                    // born visible, so its onVisibleChanged reload never
                    // fires for the first show.
                    WallpaperService.reload()
                }
            }

            Component {
                id: wallpaperPageComponent

                WallpaperPage {
                    anchors.fill: parent
                    visible: root.categoryIndex === SettingsService.wallpaperCategory

                    settingsBackground: root.settingsBackground
                    settingsSurface: root.settingsSurface
                    settingsSurfaceRaised: root.settingsSurfaceRaised
                    settingsSurfaceOverlay: root.settingsSurfaceOverlay
                }
            }
        }
    }
}
