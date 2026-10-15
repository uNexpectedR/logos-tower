import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root
    // Prefer a large dock; Basecamp QQuickWidget uses SizeRootObjectToView.
    implicitWidth: 1100
    implicitHeight: 800

    readonly property var backend: logos.module("logos_tower")
    property bool ready: false
    // play | login | board — do not use object key "id" (reserved in QML).
    property string tab: "play"

    readonly property color teal: "#6A838B"
    readonly property color tealDeep: "#4F6670"
    readonly property int chromeH: 48
    readonly property bool loggedIn: !!(backend && backend.loggedIn)

    Connections {
        target: logos
        function onViewModuleReadyChanged(moduleName, isReady) {
            if (moduleName === "logos_tower")
                root.ready = isReady && root.backend !== null
        }
    }
    Component.onCompleted: {
        root.ready = root.backend !== null && logos.isViewModuleReady("logos_tower")
    }

    // Refresh public board when opening Board.
    onTabChanged: {
        if (tab === "board" && root.ready)
            logos.watch(backend.refreshBoard(), function () {}, function () {})
    }

    Rectangle {
        anchors.fill: parent
        color: root.tealDeep
    }

    // Compact floating chrome — does not shrink the playfield.
    Rectangle {
        id: chrome
        z: 10
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: root.chromeH
        color: Qt.rgba(0.12, 0.18, 0.20, root.tab === "play" ? 0.55 : 0.92)

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 10

            Image {
                source: "lambda.png"
                Layout.preferredWidth: 28
                Layout.preferredHeight: 28
                fillMode: Image.PreserveAspectFit
                smooth: true
            }
            Text {
                text: "Logos Tower"
                color: "white"
                font.pixelSize: 16
                font.bold: true
            }
            Text {
                visible: !root.ready
                text: "Connecting…"
                color: "#ffd39a"
                font.pixelSize: 12
            }
            Item { Layout.fillWidth: true }

            Repeater {
                // Keep keys stable; label for login reacts to loggedIn.
                model: ["play", "login", "board"]
                delegate: Rectangle {
                    required property string modelData
                    readonly property string tabKey: modelData
                    readonly property string tabLabelText: tabKey === "play"
                                                          ? "Play"
                                                          : (tabKey === "board"
                                                             ? "Board"
                                                             : (root.loggedIn ? "Profile" : "Login"))
                    readonly property bool selected: root.tab === tabKey

                    Layout.preferredHeight: 28
                    Layout.preferredWidth: Math.max(56, tabLabel.implicitWidth + 22)
                    radius: 12
                    color: selected ? Qt.rgba(1, 1, 1, 0.22) : "transparent"
                    border.width: selected ? 1 : 0
                    border.color: Qt.rgba(1, 1, 1, 0.35)

                    Text {
                        id: tabLabel
                        anchors.centerIn: parent
                        text: tabLabelText
                        color: "white"
                        font.pixelSize: 12
                        font.bold: selected
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.tab = tabKey
                    }
                }
            }
        }
    }

    StackLayout {
        anchors.fill: parent
        // Play uses the full window under a translucent chrome; other tabs pad below it.
        anchors.topMargin: root.tab === "play" ? 0 : root.chromeH
        currentIndex: root.tab === "login" ? 1 : (root.tab === "board" ? 2 : 0)

        // —— Play (full-bleed) ——
        Item {
            clip: true

            GameCanvas {
                id: game
                anchors.fill: parent
                // Keep HUD / λ clear of the floating chrome.
                topSafe: root.chromeH
                onFell: function (h) {
                    if (!root.ready)
                        return
                    logos.watch(backend.signAndSubmit(h), function () {}, function (err) {
                        console.log("submit error", err)
                    })
                }
            }
        }

        // —— Login / Profile ——
        Item {
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 28
                spacing: 14

                Text {
                    text: root.loggedIn ? "Profile" : "Login"
                    color: "white"
                    font.pixelSize: 28
                    font.bold: true
                }
                Text {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    color: Qt.rgba(1, 1, 1, 0.82)
                    text: root.loggedIn
                          ? "Signed in on this Basecamp profile. Heights are Ed25519-signed with BLAKE2b PoW before they hit the public board."
                          : "Ed25519 persona seed stays in this Basecamp profile (QSettings). Scores are signed here with BLAKE2b PoW — the board never trusts a raw height."
                }
                Text {
                    text: (root.loggedIn ? "Signed in as " : "Persona: ")
                          + (backend ? backend.persona : "—")
                    color: "white"
                    font.pixelSize: 16
                    font.bold: true
                }
                TextField {
                    id: aliasField
                    Layout.fillWidth: true
                    Layout.maximumWidth: 520
                    Layout.preferredHeight: 40
                    placeholderText: "Display alias (optional)"
                    color: "white"
                    placeholderTextColor: Qt.rgba(1, 1, 1, 0.5)
                    background: Rectangle {
                        radius: 8
                        color: Qt.rgba(1, 1, 1, 0.12)
                        border.color: Qt.rgba(1, 1, 1, 0.28)
                    }
                }
                RowLayout {
                    spacing: 8

                    Rectangle {
                        Layout.preferredHeight: 36
                        Layout.preferredWidth: saveLabel.implicitWidth + 28
                        radius: 16
                        color: "white"
                        opacity: root.ready ? 1 : 0.5

                        Text {
                            id: saveLabel
                            anchors.centerIn: parent
                            text: root.loggedIn ? "Update alias" : "Save / create persona"
                            color: root.tealDeep
                            font.bold: true
                        }
                        MouseArea {
                            anchors.fill: parent
                            enabled: root.ready
                            cursorShape: Qt.PointingHandCursor
                            onClicked: logos.watch(backend.ensurePersona(aliasField.text), function () {}, function () {})
                        }
                    }

                    Rectangle {
                        visible: root.loggedIn
                        Layout.preferredHeight: 36
                        Layout.preferredWidth: logoutLabel.implicitWidth + 20
                        radius: 16
                        color: "transparent"
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.35)

                        Text {
                            id: logoutLabel
                            anchors.centerIn: parent
                            text: "Log out"
                            color: "white"
                        }
                        MouseArea {
                            anchors.fill: parent
                            enabled: root.ready
                            cursorShape: Qt.PointingHandCursor
                            onClicked: logos.watch(backend.clearPersona(), function () {}, function () {})
                        }
                    }
                }
                Text {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    color: Qt.rgba(1, 1, 1, 0.75)
                    text: backend ? backend.message : ""
                }
                Item { Layout.fillHeight: true }
            }
        }

        // —— Board ——
        Item {
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 28
                spacing: 12

                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        text: "Leaderboard"
                        color: "white"
                        font.pixelSize: 28
                        font.bold: true
                        Layout.fillWidth: true
                    }
                    Rectangle {
                        Layout.preferredHeight: 32
                        Layout.preferredWidth: refreshLabel.implicitWidth + 24
                        radius: 14
                        color: Qt.rgba(1, 1, 1, 0.14)
                        Text {
                            id: refreshLabel
                            anchors.centerIn: parent
                            text: "Refresh"
                            color: "white"
                            font.bold: true
                            font.pixelSize: 12
                        }
                        MouseArea {
                            anchors.fill: parent
                            enabled: root.ready
                            cursorShape: Qt.PointingHandCursor
                            onClicked: logos.watch(backend.refreshBoard(), function () {}, function () {})
                        }
                    }
                }
                Text {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    color: Qt.rgba(1, 1, 1, 0.8)
                    text: "Public verified heights (logos.dev Waku). Source: "
                          + (backend ? backend.boardSource : "local")
                          + ". Envelope: Ed25519 + BLAKE2b PoW (12 bits)."
                }
                ListView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    model: {
                        try {
                            return JSON.parse(backend ? backend.board : "[]")
                        } catch (e) {
                            return []
                        }
                    }
                    delegate: RowLayout {
                        required property int index
                        required property var modelData
                        width: ListView.view.width
                        spacing: 12
                        Text {
                            text: (index + 1)
                            color: Qt.rgba(1, 1, 1, 0.6)
                            font.bold: true
                            Layout.preferredWidth: 28
                        }
                        Text {
                            text: modelData.author
                            color: "white"
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }
                        Text {
                            text: modelData.height
                            color: "white"
                            font.bold: true
                        }
                    }
                }
            }
        }
    }
}
