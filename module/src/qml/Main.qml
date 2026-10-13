import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root
    // Match working Basecamp ui_qml modules (e.g. storage_ui): give the
    // embedded QQuickWidget a usable preferred size when first mounted.
    implicitWidth: 420
    implicitHeight: 720

    readonly property var backend: logos.module("logos_tower")
    property bool ready: false
    property string tab: "play" // play | login | board

    readonly property color teal: "#6A838B"
    readonly property color tealDeep: "#4F6670"
    readonly property color paper: "#F4F7F8"

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
            Image {
                source: "lambda.png"
                width: 28; height: 28
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
            Repeater {
                model: [
                    { id: "play", label: "Play" },
                    { id: "login", label: "Login" },
                    { id: "board", label: "Board" }
                ]
                delegate: Button {
                    text: modelData.label
                    flat: true
                    onClicked: root.tab = modelData.id
                    background: Rectangle {
                        radius: 14
                        color: root.tab === modelData.id ? Qt.rgba(1,1,1,0.22) : "transparent"
                        border.color: root.tab === modelData.id ? Qt.rgba(1,1,1,0.35) : "transparent"
                    }
                    contentItem: Text {
                        text: parent.text
                        color: "white"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }
        }

        Text {
            visible: !root.ready
            text: "Connecting to Logos Tower backend…"
            color: "#ffd39a"
        }

        // —— Play ——
        Item {
            visible: root.tab === "play"
            Layout.fillWidth: true
            Layout.fillHeight: true

            GameCanvas {
                id: game
                anchors.centerIn: parent
                width: Math.min(parent.width, 380)
                height: Math.min(parent.height, 620)
                onFell: function (h) {
                    if (!root.ready) return
                    logos.watch(backend.signAndSubmit(h), function () {}, function (err) {
                        console.log("submit error", err)
                    })
                }
            }
        }

        // —— Login ——
        ColumnLayout {
            visible: root.tab === "login"
            Layout.fillWidth: true
            Layout.fillHeight: true
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
                color: Qt.rgba(1,1,1,0.82)
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
                placeholderText: "Display alias (optional)"
                color: "white"
                placeholderTextColor: Qt.rgba(1,1,1,0.5)
                background: Rectangle {
                    radius: 8
                    color: Qt.rgba(1,1,1,0.12)
                    border.color: Qt.rgba(1,1,1,0.28)
                }
            }
            RowLayout {
                spacing: 8
                Button {
                    text: "Save / create persona"
                    onClicked: {
                        if (!root.ready) return
                        logos.watch(backend.ensurePersona(aliasField.text), function () {}, function () {})
                    }
                    background: Rectangle { radius: 16; color: "white" }
                    contentItem: Text { text: parent.text; color: root.tealDeep; font.bold: true; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; leftPadding: 12; rightPadding: 12 }
                }
                Button {
                    text: "Log out"
                    flat: true
                    onClicked: {
                        if (!root.ready) return
                        logos.watch(backend.clearPersona(), function () {}, function () {})
                    }
                    contentItem: Text { text: parent.text; color: "white" }
                }
            }
            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Qt.rgba(1,1,1,0.75)
                text: backend ? backend.message : ""
            }
            Item { Layout.fillHeight: true }
        }

        // —— Board ——
        ColumnLayout {
            visible: root.tab === "board"
            Layout.fillWidth: true
            Layout.fillHeight: true
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
                color: Qt.rgba(1,1,1,0.8)
                text: "Best verified signed heights on this device. Envelope: Ed25519 + BLAKE2b PoW (12 bits)."
            }
            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: {
                    try { return JSON.parse(backend ? backend.board : "[]") } catch (e) { return [] }
                }
                delegate: RowLayout {
                    width: ListView.view.width
                    spacing: 12
                    Text { text: (index + 1); color: Qt.rgba(1,1,1,0.6); font.bold: true; Layout.preferredWidth: 28 }
                    Text { text: modelData.author; color: "white"; Layout.fillWidth: true; elide: Text.ElideRight }
                    Text { text: modelData.height; color: "white"; font.bold: true }
                }
            }
        }
    }
}
