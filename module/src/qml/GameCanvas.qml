import QtQuick

Item {
    id: root
    signal fell(int height)

    property string phase: "ready" // ready | playing | over
    property int score: 0
    property int best: 0

    readonly property int worldW: 360
    readonly property int worldH: 640
    readonly property real gravity: 0.42
    readonly property real jumpV: -11.2
    readonly property real moveA: 0.55
    readonly property real friction: 0.86
    readonly property real maxVx: 6.2
    readonly property int playerSize: 36

    property real px: worldW / 2 - playerSize / 2
    property real py: worldH - 140
    property real vx: 0
    property real vy: 0
    property real cam: 0
    property real maxHeight: 0
    property var platforms: []
    property bool leftHeld: false
    property bool rightHeld: false

    function resetWorld() {
        px = worldW / 2 - playerSize / 2
        py = worldH - 140
        vx = 0
        vy = 0
        cam = 0
        maxHeight = 0
        platforms = [{ x: worldW / 2 - 50, y: worldH - 60, w: 100 }]
        var y = worldH - 140
        for (var i = 0; i < 12; i++) {
            y -= 70 + Math.random() * 30
            platforms.push(randomPlatform(y))
        }
        platformsChanged()
    }

    function randomPlatform(y) {
        var w = 70 + Math.random() * 50
        var x = 16 + Math.random() * (worldW - w - 32)
        return { x: x, y: y, w: w }
    }

    function startGame() {
        resetWorld()
        phase = "playing"
        vy = jumpV
        root.forceActiveFocus()
    }

    function step() {
        if (phase !== "playing")
            return

        if (leftHeld)
            vx -= moveA
        if (rightHeld)
            vx += moveA
        vx *= friction
        if (vx > maxVx)
            vx = maxVx
        if (vx < -maxVx)
            vx = -maxVx
        vy += gravity
        px += vx
        py += vy

        if (px < -playerSize)
            px = worldW
        if (px > worldW)
            px = -playerSize

        if (vy > 0) {
            for (var i = 0; i < platforms.length; i++) {
                var p = platforms[i]
                var prevBottom = py - vy + playerSize
                var feet = py + playerSize
                if (prevBottom <= p.y && feet >= p.y && px + playerSize > p.x && px < p.x + p.w) {
                    py = p.y - playerSize
                    vy = jumpV
                    break
                }
            }
        }

        var worldY = cam + (worldH - py)
        if (worldY / 10 > maxHeight)
            maxHeight = worldY / 10
        score = Math.floor(maxHeight)

        var targetCam = Math.max(0, py - worldH * 0.45)
        if (targetCam < cam) {
            var dy = cam - targetCam
            cam = targetCam
            for (var j = 0; j < platforms.length; j++)
                platforms[j].y += dy
            py += dy
        }

        if (maxHeight > 20) {
            var rise = Math.min(1.1, 0.15 + maxHeight / 800)
            cam -= rise
            for (var k = 0; k < platforms.length; k++)
                platforms[k].y += rise
            py += rise
        }

        platforms = platforms.filter(function (p) { return p.y < worldH + 40 })
        while (platforms.length < 14) {
            var top = platforms[0].y
            for (var t = 1; t < platforms.length; t++) {
                if (platforms[t].y < top)
                    top = platforms[t].y
            }
            platforms.push(randomPlatform(top - (70 + Math.random() * 40)))
        }
        platformsChanged()

        if (py > worldH + 40) {
            phase = "over"
            if (score > best)
                best = score
            root.fell(score)
        }
        canvas.requestPaint()
    }

    Component.onCompleted: resetWorld()

    focus: true
    activeFocusOnTab: true
    Keys.onPressed: function (e) {
        if (e.key === Qt.Key_Left || e.key === Qt.Key_A)
            leftHeld = true
        if (e.key === Qt.Key_Right || e.key === Qt.Key_D)
            rightHeld = true
        if (e.key === Qt.Key_Space || e.key === Qt.Key_Up || e.key === Qt.Key_W) {
            if (phase === "ready" || phase === "over")
                startGame()
            e.accepted = true
        }
    }
    Keys.onReleased: function (e) {
        if (e.key === Qt.Key_Left || e.key === Qt.Key_A)
            leftHeld = false
        if (e.key === Qt.Key_Right || e.key === Qt.Key_D)
            rightHeld = false
    }

    Timer {
        interval: 16
        running: true
        repeat: true
        onTriggered: step()
    }

    Rectangle {
        anchors.fill: parent
        radius: 14
        color: "#5f7881"
        clip: true

        // Focus grab sits UNDER the overlay/button so it cannot steal clicks.
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            onPressed: root.forceActiveFocus()
        }

        Canvas {
            id: canvas
            anchors.fill: parent
            // Let presses fall through to the focus MouseArea / overlay button.
            enabled: false
            onPaint: {
                var ctx = getContext("2d")
                var sx = width / root.worldW
                var sy = height / root.worldH
                ctx.reset()
                ctx.scale(sx, sy)
                var g = ctx.createLinearGradient(0, 0, 0, root.worldH)
                g.addColorStop(0, "#5f7881")
                g.addColorStop(1, "#7a939b")
                ctx.fillStyle = g
                ctx.fillRect(0, 0, root.worldW, root.worldH)

                ctx.fillStyle = "rgba(255,255,255,0.04)"
                for (var x = 0; x < root.worldW; x += 48)
                    ctx.fillRect(x, 0, 1, root.worldH)

                for (var i = 0; i < root.platforms.length; i++) {
                    var p = root.platforms[i]
                    ctx.fillStyle = "#f7fafb"
                    ctx.fillRect(p.x, p.y, p.w, 10)
                }
            }
        }

        Image {
            id: lambda
            source: "lambda.png"
            width: root.playerSize + 8
            height: root.playerSize + 8
            x: root.px * (parent.width / root.worldW) - 4
            y: root.py * (parent.height / root.worldH) - 4
            smooth: true
            visible: root.phase === "playing" || root.phase === "ready"
        }

        Row {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 12
            z: 1
            Text {
                text: "HEIGHT " + root.score
                color: "white"
                font.bold: true
                font.pixelSize: 12
            }
            Item { width: parent.width - 160; height: 1 }
            Text {
                text: "BEST " + Math.max(root.best, root.score)
                color: "white"
                font.bold: true
                font.pixelSize: 12
            }
        }

        // Ready / game-over overlay — above focus MouseArea so Play/Again works.
        Rectangle {
            anchors.fill: parent
            z: 2
            color: "#1c2a2f6b"
            visible: root.phase !== "playing"

            Column {
                anchors.centerIn: parent
                spacing: 12
                width: parent.width - 48

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.phase === "ready" ? "Logos Tower" : ("Fell at " + root.score)
                    color: "white"
                    font.pixelSize: 26
                    font.bold: true
                }
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                    color: "#dfe8eb"
                    text: root.phase === "ready"
                          ? "Jump the rising platforms. ← → or A D. Space to start."
                          : "Height is signed before it hits the board."
                }

                // Forumer-style button (Rectangle + MouseArea), not Controls Button.
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 96
                    height: 36
                    radius: 16
                    color: "white"

                    Text {
                        anchors.centerIn: parent
                        text: root.phase === "ready" ? "Play" : "Again"
                        color: "#4F6670"
                        font.bold: true
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.startGame()
                    }
                }
            }
        }
    }
}
