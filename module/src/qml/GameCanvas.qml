import QtQuick

Item {
    id: root
    signal fell(int height)

    // Space reserved for Main.qml's floating chrome when play is full-bleed.
    property int topSafe: 0

    property string phase: "ready" // ready | playing | over
    property int score: 0
    property int best: 0

    // World matches the visible canvas (1 unit ≈ 1 px).
    property int worldW: 720
    property int worldH: 900

    // Icy Tower–style feel: strong jump, snappy air control, fair reach.
    readonly property real gravity: 0.52
    readonly property real jumpV: -14.2
    readonly property real moveA: 0.95
    readonly property real friction: 0.86
    readonly property real maxVx: 9.0
    readonly property int playerSize: 44
    readonly property int platformH: 14
    // Landing forgiveness (px) so visually landable ledges register.
    readonly property real landSlopY: 6
    readonly property real landSlopX: 4

    property real px: 0
    property real py: 0
    property real vx: 0
    property real vy: 0
    property real cam: 0
    property real maxHeight: 0
    property var platforms: []
    property bool leftHeld: false
    property bool rightHeld: false

    function maxJumpHeight() {
        return (jumpV * jumpV) / (2 * gravity)
    }

    // Equilibrium horizontal speed while holding a direction (add then friction).
    function holdSpeed() {
        var s = (moveA * friction) / Math.max(0.001, 1 - friction)
        return Math.min(maxVx, s)
    }

    // Frames in the air when jumping up by gapY (continuous approx).
    function airTimeForGap(gapY) {
        var v = -jumpV
        var peak = maxJumpHeight()
        var g = gravity
        var dy = Math.max(0, Math.min(gapY, peak * 0.98))
        var disc = v * v - 2 * g * dy
        if (disc < 0)
            disc = 0
        var tUp = (v - Math.sqrt(disc)) / g
        var tDown = Math.sqrt(2 * Math.max(0, peak - dy) / g)
        return Math.max(12, tUp + tDown)
    }

    function difficulty() {
        // 0 → early (easy), 1 → later (still capped fair).
        return Math.min(1, maxHeight / 500)
    }

    function syncWorldSize() {
        var nw = Math.max(520, Math.round(width))
        var nh = Math.max(640, Math.round(height))
        if (nw === worldW && nh === worldH)
            return
        worldW = nw
        worldH = nh
        if (phase !== "playing")
            resetWorld()
    }

    function highestPlatform() {
        if (!platforms.length)
            return null
        var bestP = platforms[0]
        for (var i = 1; i < platforms.length; i++) {
            if (platforms[i].y < bestP.y)
                bestP = platforms[i]
        }
        return bestP
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
        var groundW = Math.min(worldW * 0.32, 260)
        platforms = [{
            x: worldW / 2 - groundW / 2,
            y: worldH - Math.max(48, worldH * 0.08),
            w: groundW
        }]
        var prev = platforms[0]
        for (var i = 0; i < 18; i++) {
            prev = nextReachablePlatform(prev, i < 3 ? 0 : difficulty())
            platforms.push(prev)
        }
        platformsChanged()
        canvas.requestPaint()
    }

    // Place a platform reachable from `prev` with a normal jump (+ air steer).
    function nextReachablePlatform(prev, diff) {
        var peak = maxJumpHeight()
        // Vertical gap: always under ~70% of peak; early game even shorter.
        var maxGapY = peak * (0.52 + 0.18 * diff)   // ~52–70% of peak
        var minGapY = peak * (0.22 + 0.06 * diff)   // ~22–28%
        var gapY = minGapY + Math.random() * (maxGapY - minGapY)

        var airT = airTimeForGap(gapY)
        var hs = holdSpeed()
        // Horizontal budget with margin for imperfect steering / rising floor.
        var maxDx = hs * airT * (0.78 - 0.12 * diff)

        var minW = Math.max(100, worldW * 0.14)
        var maxW = Math.max(minW + 24, worldW * (0.24 - 0.04 * diff))
        var w = minW + Math.random() * (maxW - minW)

        var prevCx = prev.x + prev.w / 2
        var dx = (Math.random() * 2 - 1) * maxDx
        // Bias toward center early so the first climbs aren't edge-trapped.
        if (diff < 0.25)
            dx *= 0.7
        var cx = prevCx + dx
        var margin = Math.max(20, worldW * 0.025)
        var x = cx - w / 2
        if (x < margin)
            x = margin
        if (x + w > worldW - margin)
            x = worldW - margin - w

        return { x: x, y: prev.y - gapY, w: w }
    }

    function startGame() {
        syncWorldSize()
        resetWorld()
        phase = "playing"
        vy = jumpV
        root.forceActiveFocus()
    }

    function clampPlayerX() {
        if (px < 0)
            px = 0
        if (px > worldW - playerSize)
            px = worldW - playerSize
    }

    function tryLand() {
        if (vy <= 0)
            return false
        var feet = py + playerSize
        var prevFeet = feet - vy
        for (var i = 0; i < platforms.length; i++) {
            var p = platforms[i]
            // Crossed the platform top this frame (with vertical slop).
            if (prevFeet <= p.y + landSlopY && feet >= p.y
                    && px + playerSize > p.x - landSlopX
                    && px < p.x + p.w + landSlopX) {
                py = p.y - playerSize
                vy = jumpV
                return true
            }
        }
        return false
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
        tryLand()

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

        // Gentle scroll — stay below a jump so it doesn't outrun landings.
        if (maxHeight > 25) {
            var rise = Math.min(0.85, 0.10 + maxHeight / 1200)
            cam -= rise
            for (var k = 0; k < platforms.length; k++)
                platforms[k].y += rise
            py += rise
        }

        platforms = platforms.filter(function (p) { return p.y < worldH + 80 })
        var minCount = Math.max(18, Math.round(worldH / 50))
        var diff = difficulty()
        while (platforms.length < minCount) {
            var prev = highestPlatform()
            if (!prev)
                break
            platforms.push(nextReachablePlatform(prev, diff))
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
