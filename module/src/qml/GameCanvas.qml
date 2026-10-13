import QtQuick

Item {
    id: root
    signal fell(int height)

    // Space reserved for Main.qml's floating chrome when play is full-bleed.
    property int topSafe: 0

    property string phase: "ready" // ready | playing | over
    property int score: 0
    property int best: 0

    // World matches the visible canvas (1 unit ≈ 1 px) so the playfield is full-window.
    property int worldW: 720
    property int worldH: 900
    readonly property real gravity: 0.55
    readonly property real jumpV: -13.5
    readonly property real moveA: 0.72
    readonly property real friction: 0.88
    readonly property real maxVx: 8.5
    readonly property int playerSize: 44
    readonly property int platformH: 12

    property real px: 0
    property real py: 0
    property real vx: 0
    property real vy: 0
    property real cam: 0
    property real maxHeight: 0
    property var platforms: []
    property bool leftHeld: false
    property bool rightHeld: false

    function syncWorldSize() {
        var nw = Math.max(520, Math.round(width))
        var nh = Math.max(640, Math.round(height))
        if (nw === worldW && nh === worldH)
            return
        worldW = nw
        worldH = nh
        // Rebuild when idle so platforms match the new bounds; mid-run keep physics stable.
        if (phase !== "playing")
            resetWorld()
    }

    function resetWorld() {
        if (worldW < 100 || worldH < 100)
            return
        px = worldW / 2 - playerSize / 2
        py = worldH - Math.max(160, worldH * 0.22)
        vx = 0
        vy = 0
        cam = 0
        maxHeight = 0
        var groundW = Math.min(worldW * 0.28, 220)
        platforms = [{
            x: worldW / 2 - groundW / 2,
            y: worldH - Math.max(48, worldH * 0.08),
            w: groundW
        }]
        var gap = Math.max(70, Math.min(110, worldH * 0.10))
        var y = platforms[0].y - gap
        for (var i = 0; i < 16; i++) {
            platforms.push(randomPlatform(y))
            y -= gap * (0.85 + Math.random() * 0.35)
        }
        platformsChanged()
        canvas.requestPaint()
    }

    function randomPlatform(y) {
        // Wider ledges on a wide field so the λ stays catchable.
        var minW = Math.max(90, worldW * 0.12)
        var maxW = Math.max(minW + 20, worldW * 0.22)
        var w = minW + Math.random() * (maxW - minW)
        var margin = Math.max(24, worldW * 0.03)
        var x = margin + Math.random() * Math.max(1, worldW - w - margin * 2)
        return { x: x, y: y, w: w }
    }

    function startGame() {
        syncWorldSize()
        resetWorld()
        phase = "playing"
        vy = jumpV
        root.forceActiveFocus()
    }

    function clampPlayerX() {
        // Keep the λ inside the playfield (no wrap-around "outside" the view).
        if (px < 0)
            px = 0
        if (px > worldW - playerSize)
            px = worldW - playerSize
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
        clampPlayerX()

        if (vy > 0) {
            for (var i = 0; i < platforms.length; i++) {
                var p = platforms[i]
                var prevBottom = py - vy + playerSize
                var feet = py + playerSize
                if (prevBottom <= p.y && feet >= p.y
                        && px + playerSize > p.x && px < p.x + p.w) {
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

        var targetCam = Math.max(0, py - worldH * 0.48)
        if (targetCam < cam) {
            var dy = cam - targetCam
            cam = targetCam
            for (var j = 0; j < platforms.length; j++)
                platforms[j].y += dy
            py += dy
        }

        if (maxHeight > 20) {
            var rise = Math.min(1.4, 0.18 + maxHeight / 700)
            cam -= rise
            for (var k = 0; k < platforms.length; k++)
                platforms[k].y += rise
            py += rise
        }

        platforms = platforms.filter(function (p) { return p.y < worldH + 80 })
        var minCount = Math.max(16, Math.round(worldH / 55))
        while (platforms.length < minCount) {
            var top = platforms[0].y
            for (var t = 1; t < platforms.length; t++) {
                if (platforms[t].y < top)
                    top = platforms[t].y
            }
            var gap = Math.max(70, Math.min(110, worldH * 0.10))
            platforms.push(randomPlatform(top - (gap * (0.85 + Math.random() * 0.35))))
        }
        platformsChanged()

        if (py > worldH + 60) {
            phase = "over"
            if (score > best)
                best = score
            root.fell(score)
        }
        canvas.requestPaint()
    }

    onWidthChanged: syncWorldSize()
    onHeightChanged: syncWorldSize()
    Component.onCompleted: {
        syncWorldSize()
        resetWorld()
    }

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
        color: "#5f7881"
        clip: true

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            onPressed: root.forceActiveFocus()
        }

        Canvas {
            id: canvas
            anchors.fill: parent
            enabled: false
            onPaint: {
                var ctx = getContext("2d")
                var sx = width / Math.max(1, root.worldW)
                var sy = height / Math.max(1, root.worldH)
                ctx.reset()
                ctx.scale(sx, sy)
                var g = ctx.createLinearGradient(0, 0, 0, root.worldH)
                g.addColorStop(0, "#5f7881")
                g.addColorStop(1, "#7a939b")
                ctx.fillStyle = g
                ctx.fillRect(0, 0, root.worldW, root.worldH)

                ctx.fillStyle = "rgba(255,255,255,0.04)"
                var stepX = Math.max(40, root.worldW / 18)
                for (var x = 0; x < root.worldW; x += stepX)
                    ctx.fillRect(x, 0, 1, root.worldH)

                for (var i = 0; i < root.platforms.length; i++) {
                    var p = root.platforms[i]
                    ctx.fillStyle = "#f7fafb"
                    ctx.fillRect(p.x, p.y, p.w, root.platformH)
                }
            }
        }

        Image {
            id: lambda
            source: "player-lambda.png"
            width: root.playerSize + 8
            height: root.playerSize + 8
            x: root.px * (parent.width / Math.max(1, root.worldW)) - 4
            y: root.py * (parent.height / Math.max(1, root.worldH)) - 4
            smooth: true
            visible: root.phase === "playing" || root.phase === "ready"
        }

        Row {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.topMargin: Math.max(12, root.topSafe + 8)
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            z: 1
            Text {
                text: "HEIGHT " + root.score
                color: "white"
                font.bold: true
                font.pixelSize: 14
            }
            Item { width: parent.width - 200; height: 1 }
            Text {
                text: "BEST " + Math.max(root.best, root.score)
                color: "white"
                font.bold: true
                font.pixelSize: 14
            }
        }

        Rectangle {
            anchors.fill: parent
            z: 2
            color: "#1c2a2f6b"
            visible: root.phase !== "playing"

            Column {
                anchors.centerIn: parent
                spacing: 14
                width: Math.min(420, parent.width - 64)

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.phase === "ready" ? "Logos Tower" : ("Fell at " + root.score)
                    color: "white"
                    font.pixelSize: 32
                    font.bold: true
                }
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                    color: "#dfe8eb"
                    font.pixelSize: 15
                    text: root.phase === "ready"
                          ? "Jump the rising platforms. ← → or A D. Space to start."
                          : "Height is signed before it hits the board."
                }

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 112
                    height: 40
                    radius: 18
                    color: "white"

                    Text {
                        anchors.centerIn: parent
                        text: root.phase === "ready" ? "Play" : "Again"
                        color: "#4F6670"
                        font.bold: true
                        font.pixelSize: 15
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
