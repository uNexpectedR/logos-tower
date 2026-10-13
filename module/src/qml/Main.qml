import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root
    // Preferred size for Basecamp's QQuickWidget host (storage_ui pattern).
    implicitWidth: 420
    implicitHeight: 720

    readonly property var backend: logos.module("logos_tower")
    property bool ready: false
    // play | login | board — do not use object key "id" (reserved in QML).
    property string tab: "play"

    readonly property color teal: "#6A838B"
    readonly property color tealDeep: "#4F6670"

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

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: root.teal }
            GradientStop { position: 1.0; color: root.tealDeep }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            z: 2

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
                font.pixelSize: 20
                font.bold: true
            }
            Item { Layout.fillWidth: true }

            // Forumer-style hit targets: Rectangle + MouseArea (not Controls Button
            // with replaced background/contentItem, which can end up zero-sized).
            Repeater {
                model: [
                    { key: "play", label: "Play" },
                    { key: "login", label: "Login" },
                    { key: "board", label: "Board" }
                ]
                delegate: Rectangle {
                    required property var modelData
                    readonly property bool selected: root.tab === modelData.key

                    Layout.preferredHeight: 32
                    Layout.preferredWidth: Math.max(64, label.implicitWidth + 28)
                    radius: 14
                    color: selected ? Qt.rgba(1, 1, 1, 0.22) : "transparent"
                    border.width: selected ? 1 : 0
                    border.color: Qt.rgba(1, 1, 1, 0.35)

                    Text {
                        id: label
                        anchors.centerIn: parent
                        text: modelData.label
                        color: "white"
                        font.pixelSize: 13
                        font.bold: selected
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.tab = modelData.key
                    }
                }
            }
        }

        Text {
            visible: !root.ready
            text: "Connecting to Logos Tower backend…"
            color: "#ffd39a"
        }

        // Exclusive pages — avoids invisible siblings eating layout/hit space.
        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: root.tab === "login" ? 1 : (root.tab === "board" ? 2 : 0)

            // —— Play ——
            Item {
                clip: true

                GameCanvas {
                    id: game
                    anchors.centerIn: parent
                    width: Math.min(parent.width, 380)
                    height: Math.min(parent.height, 620)
                    onFell: function (h) {
                        if (!root.ready)
                            return
                        logos.watch(backend.signAndSubmit(h), function () {}, function (err) {
                            console.log("submit error", err)
                        })
                    }
                }
            }

            // —— Login ——
            ColumnLayout {
                spacing: 12

                Text {
                    text: "Login"
                    color: "white"
                    font.pixelSize: 28
                    font.bold: true
                }
                Text {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    color: Qt.rgba(1, 1, 1, 0.82)
                    text: "Ed25519 persona seed stays in this Basecamp profile (QSettings). Scores are signed here with BLAKE2b PoW — the board never trusts a raw height."
                }
                Text {
                    text: "Persona: " + (backend ? backend.persona : "—")
                    color: "white"
                    font.pixelSize: 16
                    font.bold: true
                }
                TextField {
                    id: aliasField
                    Layout.fillWidth: true
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
                            text: "Save / create persona"
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
                        Layout.preferredHeight: 36
                        Layout.preferredWidth: logoutLabel.implicitWidth + 20
                        radius: 16
                        color: "transparent"

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

            // —— Board ——
            ColumnLayout {
                spacing: 10

                Text {
                    text: "Leaderboard"
                    color: "white"
                    font.pixelSize: 28
                    font.bold: true
                }
                Text {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    color: Qt.rgba(1, 1, 1, 0.8)
                    text: "Best verified signed heights on this device. Envelope: Ed25519 + BLAKE2b PoW (12 bits)."
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
