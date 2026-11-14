import QtQuick
import QtQuick.Shapes
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

    // Tangga permukaan keluarga Settings: hex gelap tetap di mode
    // gelap (desain aslinya), turunan Theme di mode terang.
    readonly property color settingsBackground: Theme.darkMode ? "#0A0A0A" : Theme.background
    readonly property color settingsSurface: Theme.darkMode ? "#141414" : Theme.surface
    readonly property color settingsSurfaceRaised: Theme.darkMode ? "#1E1E1E" : Theme.surfaceRaised
    readonly property color settingsSurfaceOverlay: Theme.darkMode ? "#2A2A2A" : Theme.surfaceOverlay

    // One extra step above the overlay tier, same +0x0A spacing as the
    // ladder above. The hosted pages sit on the surface tier now (the
    // detail pane shares the active tab's colour), so their whole
    // ladder shifts up one step and their overlay tier lands here.
    readonly property color settingsSurfaceMax: Theme.darkMode ? "#343434" : Qt.lighter(Theme.surfaceOverlay, 1.06)

    readonly property var categories: [
        {
            label: "Appearance",
            svg: "assets/appearance-svgrepo-com.svg",
        },
        {
            label: "Wallpaper",
            svg: "assets/wallpaper-svgrepo-com.svg",
        },
        {
            label: "Display",
            svg: "assets/display-svgrepo-com.svg",
        },
        {
            label: "About",
            svg: "assets/about-svgrepo-com.svg",
        }
    ]

    // Owned by SettingsService so IPC callers can preselect a page; the
    // tab strip writes through to the service.
    readonly property int categoryIndex: SettingsService.categoryIndex

    // Appearance has no SettingsService constant (no IPC target opens
    // it directly); its position in categories above is fixed at 0.
    readonly property int appearanceCategory: 0

    // About likewise has no IPC target; after the tab redesign it is
    // the only category still served by the generic chrome (the title
    // above its content box) - Typography moved into the Appearance
    // page as a section, so no category remains at its old index.
    readonly property int aboutCategory: 3

    // First-visit latches for the page Loaders in the detail pane: a
    // page's tree is created the first time its category is selected and
    // kept for the rest of the session (the shell-level Loader destroys
    // the whole view when Settings closes anyway), so opening Settings
    // never pays for pages the user does not visit.
    property bool _displayVisited: false
    property bool _wallpaperVisited: false
    property bool _appearanceVisited: false

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
        border.color: "transparent"
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

        // Browser-style tab strip: the categories as horizontal tabs
        // along the top of the body, replacing the sidebar. Only the
        // top 38px of the strip is its own territory: the strip item
        // runs 20px further down, underlapping the detail pane, and
        // the active tab's fill runs with it. The pane sits on a
        // higher layer (see detail.z), so the underlap is covered by
        // the page and the tab reads as diving behind the page sheet
        // instead of ending flush at its edge. The tabs and the
        // hairline stay pinned to the top 38px - the strip's visible
        // geometry does not move.
        Item {
            id: tabStrip

            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
            }

            height: 38 + 20

            Rectangle {
                anchors {
                    left: parent.left
                    right: parent.right
                    bottom: parent.bottom
                    bottomMargin: 20
                }

                height: 1
                color: "transparent"
            }

            Row {
                anchors {
                    left: parent.left
                    top: parent.top
                }

                spacing: 4

                Repeater {
                    model: root.categories

                    delegate: Item {
                        id: tabItem

                        required property var modelData
                        required property int index

                        readonly property bool active: root.categoryIndex === tabItem.index

                        width: tabRow.implicitWidth + 28
                        height: 38
                        z: tabItem.active ? 1 : 0

                        // The active tab is one silhouette: rounded top
                        // corners and straight sides, its fill running
                        // 20px below the tab, behind the detail pane, so
                        // tab and page read as a single piece of surface
                        // with the tab tucked under the page. A hovered
                        // inactive tab takes the same silhouette in a
                        // darker fill, so hover previews the active form.
                        Shape {
                            id: tabShape

                            visible: tabItem.active || tabArea.containsMouse

                            anchors {
                                left: parent.left
                                right: parent.right
                                top: parent.top
                            }

                            height: tabItem.height + 20
                            preferredRendererType: Shape.CurveRenderer

                            ShapePath {
                                fillColor: tabItem.active ? settingsSurface : Qt.darker(settingsSurface, 1.4)
                                strokeColor: "transparent"
                                startX: 0
                                startY: tabShape.height

                                PathLine {
                                    x: 0
                                    y: 8
                                }

                                PathQuad {
                                    x: 8
                                    y: 0
                                    controlX: 0
                                    controlY: 0
                                }

                                PathLine {
                                    x: tabItem.width - 8
                                    y: 0
                                }

                                PathQuad {
                                    x: tabItem.width
                                    y: 8
                                    controlX: tabItem.width
                                    controlY: 0
                                }

                                PathLine {
                                    x: tabItem.width
                                    y: tabShape.height
                                }
                            }
                        }

                        Row {
                            id: tabRow

                            anchors.centerIn: parent
                            spacing: 8

                            Item {
                                width: 16
                                height: 16
                                anchors.verticalCenter: parent.verticalCenter

                                Image {
                                    id: tabIcon

                                    anchors.fill: parent
                                    source: "file://" + Quickshell.shellPath(tabItem.modelData.svg)
                                    sourceSize.width: 32
                                    sourceSize.height: 32
                                    fillMode: Image.PreserveAspectFit
                                    asynchronous: true
                                    smooth: true
                                    visible: false
                                }

                                ColorOverlay {
                                    anchors.fill: tabIcon

                                    source: tabIcon
                                    color: tabItem.active ? Theme.accent
                                        : (tabArea.containsMouse ? Theme.text : Theme.textDim)
                                }
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter

                                text: tabItem.modelData.label
                                color: tabItem.active ? Theme.text
                                    : (tabArea.containsMouse ? Theme.text : Theme.textDim)
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                font.weight: tabItem.active ? Font.DemiBold : Font.Medium
                            }
                        }

                        MouseArea {
                            id: tabArea

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: SettingsService.categoryIndex = tabItem.index
                        }
                    }
                }
            }
        }

        Rectangle {
            id: detail

            anchors {
                top: tabStrip.top
                left: parent.left
                right: parent.right
                bottom: parent.bottom
                topMargin: 38
            }

            // Above the tab strip, whose 20px underlap reaches under
            // this pane and is covered by it.
            z: 1

            radius: 14
            color: settingsSurface
            border.width: 1
            border.color: "transparent"

            Text {
                id: detailTitle

                visible: root.categoryIndex === root.aboutCategory

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

            Rectangle {
                id: divider

                visible: root.categoryIndex === root.aboutCategory

                anchors {
                    top: detailTitle.bottom
                    left: parent.left
                    right: parent.right
                    topMargin: 18
                    leftMargin: 22
                    rightMargin: 22
                }

                height: 1
                color: "transparent"
            }

            Rectangle {
                id: placeholder

                visible: root.categoryIndex === root.aboutCategory

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

                    // The author's JL brandmark (assets/brandmark.svg,
                    // traced from his brand library's white-on-
                    // transparent PNG master). It ships white, which
                    // is its approved form on dark surfaces like this
                    // one, so it renders as-is with no tint.
                    Image {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 186
                        height: 96
                        source: "file://" + Quickshell.shellPath("assets/brandmark.svg")
                        sourceSize.width: 372
                        sourceSize.height: 192
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        smooth: true
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter

                        text: "MyQuickshellProject"
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: 16
                        font.weight: Font.DemiBold
                        horizontalAlignment: Text.AlignHCenter
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter

                        text: "by Sahrul Jamil"
                        color: Theme.textDim
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        horizontalAlignment: Text.AlignHCenter
                    }

                    Column {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 5

                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 8

                            Text {
                                text: "Shell"
                                color: Theme.textMuted
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                            }

                            Text {
                                text: "Quickshell 0.3.2"
                                color: Theme.textDim
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                            }
                        }

                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 8

                            Text {
                                text: "Toolkit"
                                color: Theme.textMuted
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                            }

                            Text {
                                text: "Qt 6.11"
                                color: Theme.textDim
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                            }
                        }

                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 8

                            Text {
                                text: "Compositor"
                                color: Theme.textMuted
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                            }

                            Text {
                                text: "Hyprland 0.57"
                                color: Theme.textDim
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                            }
                        }
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter

                        text: "github.com/ShrlJamil/MyQuickshellProject"
                        color: Theme.textMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
            }

            // The Display page hosts the real DisplayManager (moved out of
            // DynamicCenter). The generic title chrome above hides itself
            // for this category so the manager
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

                    settingsBackground: root.settingsSurface
                    settingsSurface: root.settingsSurfaceRaised
                    settingsSurfaceRaised: root.settingsSurfaceOverlay
                    settingsSurfaceOverlay: root.settingsSurfaceMax

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

                    settingsBackground: root.settingsSurface
                    settingsSurface: root.settingsSurfaceRaised
                    settingsSurfaceRaised: root.settingsSurfaceOverlay
                    settingsSurfaceOverlay: root.settingsSurfaceMax
                }
            }

            // Same arrangement for the Appearance page: a thin view over
            // PreferencesService with its own headings, so the generic
            // chrome hides for this category too. Lazy the same way.
            // No first-creation compensation: the page is pure bindings
            // to the service and relies on no onVisibleChanged trigger.
            Loader {
                id: appearanceLoader

                anchors.fill: parent
                anchors.margins: 12
                active: root.categoryIndex === root.appearanceCategory || root._appearanceVisited
                sourceComponent: appearancePageComponent

                onLoaded: root._appearanceVisited = true
            }

            Component {
                id: appearancePageComponent

                AppearancePage {
                    anchors.fill: parent
                    visible: root.categoryIndex === root.appearanceCategory

                    settingsBackground: root.settingsSurface
                    settingsSurface: root.settingsSurfaceRaised
                    settingsSurfaceRaised: root.settingsSurfaceOverlay
                    settingsSurfaceOverlay: root.settingsSurfaceMax
                }
            }
        }
    }
}


