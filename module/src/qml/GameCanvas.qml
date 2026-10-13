import QtQuick

Item {
    id: root
    signal fell(int height)

    // Space reserved for Main.qml's floating chrome when play is full-bleed.
    property int topSafe: 0

    property string phase: "ready" // ready | playing | over
    property int score: 0
    property int best: 0
    property int combo: 0
    property int bestCombo: 0
    property string shout: ""
    property int shoutFrames: 0

    // World matches the visible canvas (1 unit ≈ 1 px).
    property int worldW: 720
    property int worldH: 900

    // Icy Tower–style: base jump is modest; edge/combo boosts clear the long gaps.
    readonly property real gravity: 0.58
    readonly property real jumpV: -12.6
    readonly property real edgeJumpExtra: -3.8
    readonly property real springJumpExtra: -5.2
    readonly property real moveA: 1.15
    readonly property real friction: 0.86
    readonly property real maxVx: 11.2
    readonly property real wallRestitution: 0.94
    readonly property int playerSize: 44
    readonly property int platformH: 14
    readonly property real landSlopY: 5
    readonly property real landSlopX: 2
    readonly property real edgeZoneFrac: 0.22

    property real px: 0
    property real py: 0
    property real vx: 0
    property real vy: 0
    property real cam: 0
    property real maxHeight: 0
    property int runFrames: 0
    property int iceFrames: 0
    property var platforms: []
    property bool leftHeld: false
    property bool rightHeld: false

    function maxJumpHeightFrom(vJump) {
        return (vJump * vJump) / (2 * gravity)
    }

    function maxJumpHeight() {
        return maxJumpHeightFrom(jumpV)
    }

    function edgeJumpV(comboBonus) {
        var c = Math.min(12, Math.max(0, comboBonus || 0))
        return jumpV + edgeJumpExtra - c * 0.18
    }

    function holdSpeed() {
        var a = iceFrames > 0 ? moveA * 1.15 : moveA
        var f = iceFrames > 0 ? Math.min(0.92, friction + 0.04) : friction
        var s = (a * f) / Math.max(0.001, 1 - f)
        var cap = iceFrames > 0 ? maxVx * 1.12 : maxVx
        return Math.min(cap, s)
    }

    function airTimeForGap(gapY, vJump) {
        var v = -vJump
        var peak = maxJumpHeightFrom(vJump)
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
        // Spicy early; near-cap by ~height 160.
        return Math.min(1, maxHeight / 160)
    }

    // Platforms live only in the center 60% (20% empty gutter each side).
    // Gutters act as tower walls (bounce).
    function laneLeft() { return worldW * 0.20 }
    function laneRight() { return worldW * 0.80 }
    function laneWidth() { return worldW * 0.60 }

    function clampPlatformInLane(x, w) {
        var L = laneLeft()
        var R = laneRight()
        if (w > laneWidth())
            w = laneWidth()
        if (x < L)
            x = L
        if (x + w > R)
            x = R - w
        return { x: x, w: w }
    }

    function scrollWorld(amount) {
        if (amount <= 0)
            return
        py += amount
        for (var i = 0; i < platforms.length; i++)
            platforms[i].y += amount
        cam -= amount
    }

    function followPlayerUp() {
        var followLine = topSafe + worldH * 0.30
        if (py < followLine)
            scrollWorld(followLine - py)
        var topLimit = topSafe + Math.max(28, worldH * 0.06)
        if (py < topLimit)
            scrollWorld(topLimit - py)
    }

    function floorRiseSpeed() {
        var d = difficulty()
        var t = Math.min(1, runFrames / (60 * 55)) // ~55s to full time ramp
        return Math.min(3.35, 0.62 + d * 1.55 + t * 1.15 + maxHeight / 380)
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

    function shoutForCombo(c, edged) {
        if (edged && c >= 8)
            return "EXTREME"
        if (edged && c >= 5)
            return "AWESOME"
        if (edged)
            return "EDGE!"
        if (c >= 12)
            return "FANTASTIC"
        if (c >= 8)
            return "SWEET"
        if (c >= 4)
            return "GOOD"
        return ""
    }

    function flashShout(text) {
        if (!text || text.length === 0)
            return
        shout = text
        shoutFrames = 48
    }

    function makePlatform(x, y, w, kind) {
        var p = {
            x: x,
            y: y,
            w: w,
            kind: kind || "normal",
            baseX: x,
            phase: Math.random() * Math.PI * 2,
            amp: 0,
            speed: 0,
            alive: true,
            crumTimer: 0
        }
        if (kind === "moving") {
            p.amp = 18 + Math.random() * 36
            p.speed = 0.035 + Math.random() * 0.04 + difficulty() * 0.02
            // Keep travel inside the lane.
            var maxAmp = Math.max(8, Math.min(p.x - laneLeft(), laneRight() - (p.x + p.w)))
            p.amp = Math.min(p.amp, maxAmp)
        }
        return p
    }

    function platformSurfaceX(p) {
        if (p.kind === "moving")
            return p.baseX + Math.sin(p.phase + runFrames * p.speed) * p.amp
        return p.x
    }

    function syncMovingPlatforms() {
        for (var i = 0; i < platforms.length; i++) {
            var p = platforms[i]
            if (p.kind === "moving")
                p.x = platformSurfaceX(p)
        }
    }

    function pickKind(diff, index) {
        var r = Math.random()
        // Early climb: mostly normal; spice in gradually.
        if (index < 3 || diff < 0.2) {
            if (r < 0.12)
                return "narrow"
            return "normal"
        }
        if (r < 0.10 + diff * 0.06)
            return "spike"
        if (r < 0.22 + diff * 0.08)
            return "moving"
        if (r < 0.34 + diff * 0.06)
            return "crumb"
        if (r < 0.46 + diff * 0.05)
            return "ice"
        if (r < 0.56 + diff * 0.04)
            return "spring"
        if (r < 0.72)
            return "narrow"
        return "normal"
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
        runFrames = 0
        iceFrames = 0
        combo = 0
        shout = ""
        shoutFrames = 0
        var groundW = Math.min(laneWidth() * 0.50, 220)
        var ground = clampPlatformInLane(worldW / 2 - groundW / 2, groundW)
        platforms = [makePlatform(ground.x, worldH - Math.max(48, worldH * 0.08), ground.w, "normal")]
        var prev = platforms[0]
        for (var i = 0; i < 20; i++) {
            var d = i < 2 ? 0.12 : Math.max(0.40, difficulty())
            var batch = nextReachableBatch(prev, d, i)
            for (var j = 0; j < batch.length; j++) {
                platforms.push(batch[j])
                prev = batch[j]
            }
        }
        platformsChanged()
        canvas.requestPaint()
    }

    // One or two ledges (chained pair) reachable with skill; stretch gaps need edge boosts.
    function nextReachableBatch(prev, diff, index) {
        var kind = pickKind(diff, index)
        var useEdgeEnvelope = Math.random() < (0.28 + diff * 0.45)
        var vJump = useEdgeEnvelope ? edgeJumpV(Math.min(6, Math.floor(diff * 8))) : jumpV
        // Springs after a stretch are slightly more common.
        if (useEdgeEnvelope && Math.random() < 0.18)
            kind = "spring"
        if (kind === "spike" && index < 5)
            kind = "narrow"

        var peak = maxJumpHeightFrom(vJump)
        var maxGapY = peak * (0.62 + 0.28 * diff)   // ~62–90% of chosen envelope
        var minGapY = peak * (0.42 + 0.18 * diff)   // ~42–60%
        if (minGapY > maxGapY - 10)
            minGapY = maxGapY - 10
        var gapY = minGapY + (0.50 + Math.random() * 0.50) * (maxGapY - minGapY)

        var airT = airTimeForGap(gapY, vJump)
        var hs = holdSpeed()
        var maxDx = hs * airT * (0.88 - 0.10 * diff)
        maxDx = Math.min(maxDx, laneWidth() * 0.88)

        var minW
        var maxW
        if (kind === "narrow") {
            minW = Math.max(42, laneWidth() * (0.08 - 0.02 * diff))
            maxW = Math.max(minW + 8, laneWidth() * (0.14 - 0.03 * diff))
        } else if (kind === "spike" || kind === "spring") {
            minW = Math.max(56, laneWidth() * (0.12 - 0.02 * diff))
            maxW = Math.max(minW + 10, laneWidth() * (0.22 - 0.04 * diff))
        } else {
            minW = Math.max(58, laneWidth() * (0.12 - 0.03 * diff))
            maxW = Math.max(minW + 12, laneWidth() * (0.24 - 0.06 * diff))
        }
        var w = minW + Math.random() * (maxW - minW)

        var prevCx = prev.x + prev.w / 2
        var side = Math.random() < 0.5 ? -1 : 1
        var dx = side * (0.50 + Math.random() * 0.50) * maxDx
        var cx = prevCx + dx
        var placed = clampPlatformInLane(cx - w / 2, w)
        var y = prev.y - gapY
        var main = makePlatform(placed.x, y, placed.w, kind)

        var batch = [main]
        // Chained twin ledge — tight second footing at nearly the same height.
        if (kind !== "spike" && Math.random() < (0.16 + diff * 0.14)) {
            var twinW = Math.max(40, w * (0.45 + Math.random() * 0.25))
            var gapBetween = 16 + Math.random() * 28
            var twinX
            if (main.x + main.w + gapBetween + twinW <= laneRight())
                twinX = main.x + main.w + gapBetween
            else if (main.x - gapBetween - twinW >= laneLeft())
                twinX = main.x - gapBetween - twinW
            else
                twinX = NaN
            if (!isNaN(twinX)) {
                var twinKind = Math.random() < 0.35 ? "narrow" : (Math.random() < 0.25 ? "ice" : "normal")
                var twinPlaced = clampPlatformInLane(twinX, twinW)
                batch.push(makePlatform(twinPlaced.x, y - (4 + Math.random() * 14), twinPlaced.w, twinKind))
            }
        }
        return batch
    }

    function startGame() {
        syncWorldSize()
        resetWorld()
        phase = "playing"
        vy = jumpV
        root.forceActiveFocus()
    }

    function bounceLaneWalls() {
        var L = laneLeft()
        var R = laneRight()
        var bounced = false
        if (px < L) {
            px = L
            if (vx < 0)
                vx = -vx * wallRestitution
            if (vx < 2.5)
                vx = 2.5
            bounced = true
        } else if (px + playerSize > R) {
            px = R - playerSize
            if (vx > 0)
                vx = -vx * wallRestitution
            if (vx > -2.5)
                vx = -2.5
            bounced = true
        }
        // Soft upward kiss on a committed wall slap — classic recovery feel.
        if (bounced && vy > -2 && Math.abs(vx) > 4)
            vy -= 1.1
        return bounced
    }

    function isEdgeLand(p, surfX) {
        var feetCx = px + playerSize / 2
        var zone = Math.max(10, p.w * edgeZoneFrac)
        var onLeft = feetCx <= surfX + zone
        var onRight = feetCx >= surfX + p.w - zone
        if (!onLeft && !onRight)
            return false
        // Edge must be taken with outward (or strong) horizontal speed.
        if (onLeft && vx <= -2.2)
            return true
        if (onRight && vx >= 2.2)
            return true
        // Near-edge with high speed still counts (risk).
        return Math.abs(vx) >= 7.5 && (onLeft || onRight)
    }

    function tryLand() {
        if (vy <= 0)
            return false
        var feet = py + playerSize
        var prevFeet = feet - vy
        for (var i = 0; i < platforms.length; i++) {
            var p = platforms[i]
            if (!p.alive)
                continue
            var surfX = (p.kind === "moving") ? platformSurfaceX(p) : p.x
            if (p.kind === "moving")
                p.x = surfX
            if (prevFeet <= p.y + landSlopY && feet >= p.y
                    && px + playerSize > surfX - landSlopX
                    && px < surfX + p.w + landSlopX) {
                if (p.kind === "spike") {
                    py = p.y - playerSize
                    vy = 0
                    phase = "over"
                    if (score > best)
                        best = score
                    root.fell(score)
                    return true
                }

                py = p.y - playerSize
                var edged = isEdgeLand(p, surfX)
                combo += edged ? 2 : 1
                if (combo > bestCombo)
                    bestCombo = combo

                var jump = jumpV
                if (p.kind === "spring")
                    jump = jumpV + springJumpExtra - Math.min(6, combo) * 0.12
                else if (edged)
                    jump = edgeJumpV(combo)
                else if (combo >= 6)
                    jump = jumpV - Math.min(2.2, (combo - 5) * 0.22)

                // Carry a little horizontal snap on edge landings.
                if (edged) {
                    var boost = 1.15 + Math.min(2.4, combo * 0.08)
                    if (vx >= 0)
                        vx = Math.min(maxVx * 1.15, Math.max(vx, 4.2) * boost / 1.4 + 1.1)
                    else
                        vx = Math.max(-maxVx * 1.15, Math.min(vx, -4.2) * boost / 1.4 - 1.1)
                }

                if (p.kind === "ice")
                    iceFrames = 55
                if (p.kind === "crumb") {
                    p.alive = false
                    p.crumTimer = 1
                }

                vy = jump
                flashShout(shoutForCombo(combo, edged || p.kind === "spring"))
                return true
            }
        }
        return false
    }

    function step() {
        if (phase !== "playing")
            return

        if (shoutFrames > 0) {
            shoutFrames--
            if (shoutFrames <= 0)
                shout = ""
        }
        if (iceFrames > 0)
            iceFrames--

        var a = iceFrames > 0 ? moveA * 1.2 : moveA
        var f = iceFrames > 0 ? 0.90 : friction
        var cap = iceFrames > 0 ? maxVx * 1.15 : maxVx
        if (leftHeld)
            vx -= a
        if (rightHeld)
            vx += a
        vx *= f
        if (vx > cap)
            vx = cap
        if (vx < -cap)
            vx = -cap

        runFrames++
        vy += gravity
        px += vx
        py += vy
        bounceLaneWalls()
        syncMovingPlatforms()
        tryLand()
        if (phase !== "playing") {
            canvas.requestPaint()
            return
        }

        followPlayerUp()

        var worldY = cam + (worldH - py)
        if (worldY / 10 > maxHeight)
            maxHeight = worldY / 10
        // Height drives the board; combo is style feedback (and jump power).
        score = Math.floor(maxHeight)

        if (maxHeight > 6)
            scrollWorld(floorRiseSpeed())

        followPlayerUp()

        // Crumble cleanup + cull below view.
        platforms = platforms.filter(function (p) {
            if (!p.alive)
                return false
            return p.y < worldH + 80
        })

        var minCount = Math.max(20, Math.round(worldH / 46))
        var diff = Math.max(0.42, difficulty())
        while (platforms.length < minCount) {
            var prev = highestPlatform()
            if (!prev)
                break
            var batch = nextReachableBatch(prev, diff, platforms.length)
            for (var b = 0; b < batch.length; b++)
                platforms.push(batch[b])
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

    function platformFill(kind) {
        if (kind === "ice")
            return "#b9d2dc"
        if (kind === "moving")
            return "#c8d8de"
        if (kind === "crumb")
            return "#d2c2a6"
        if (kind === "spring")
            return "#a7c4b4"
        if (kind === "narrow")
            return "#e7eef1"
        if (kind === "spike")
            return "#f0f4f6"
        return "#f7fafb"
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

                var L = root.worldW * 0.20
                var R = root.worldW * 0.80
                // Tower walls / gutters.
                ctx.fillStyle = "rgba(0,0,0,0.16)"
                ctx.fillRect(0, 0, L, root.worldH)
                ctx.fillRect(R, 0, root.worldW - R, root.worldH)
                ctx.fillStyle = "rgba(255,255,255,0.10)"
                ctx.fillRect(L - 3, 0, 3, root.worldH)
                ctx.fillRect(R, 0, 3, root.worldH)

                ctx.fillStyle = "rgba(255,255,255,0.04)"
                var stepX = Math.max(40, root.worldW / 18)
                for (var x = L; x < R; x += stepX)
                    ctx.fillRect(x, 0, 1, root.worldH)

                for (var i = 0; i < root.platforms.length; i++) {
                    var p = root.platforms[i]
                    if (!p.alive)
                        continue
                    var drawX = p.x
                    ctx.fillStyle = root.platformFill(p.kind)
                    ctx.fillRect(drawX, p.y, p.w, root.platformH)
                    if (p.kind === "spike") {
                        ctx.fillStyle = "#c45b5b"
                        var teeth = Math.max(2, Math.floor(p.w / 10))
                        var tw = p.w / teeth
                        for (var t = 0; t < teeth; t++) {
                            ctx.beginPath()
                            ctx.moveTo(drawX + t * tw, p.y)
                            ctx.lineTo(drawX + t * tw + tw / 2, p.y - 7)
                            ctx.lineTo(drawX + (t + 1) * tw, p.y)
                            ctx.closePath()
                            ctx.fill()
                        }
                    } else if (p.kind === "spring") {
                        ctx.fillStyle = "#6a838b"
                        ctx.fillRect(drawX + p.w * 0.2, p.y - 3, p.w * 0.6, 3)
                    } else if (p.kind === "ice") {
                        ctx.fillStyle = "rgba(255,255,255,0.35)"
                        ctx.fillRect(drawX + 2, p.y + 2, Math.max(4, p.w - 4), 3)
                    } else if (p.kind === "moving") {
                        ctx.fillStyle = "#6a838b"
                        ctx.fillRect(drawX + 4, p.y + 5, Math.max(6, p.w - 8), 3)
                    }
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
            Item { width: 18; height: 1 }
            Text {
                text: root.combo > 0 ? ("COMBO x" + root.combo) : ""
                color: "#dfe8eb"
                font.bold: true
                font.pixelSize: 14
            }
            Item { width: Math.max(12, parent.width - 300); height: 1 }
            Text {
                text: "BEST " + Math.max(root.best, root.score)
                color: "white"
                font.bold: true
                font.pixelSize: 14
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: Math.max(48, root.topSafe + 40)
            z: 2
            text: root.shout
            color: "white"
            font.bold: true
            font.pixelSize: 22
            opacity: root.shoutFrames > 0 ? Math.min(1, root.shoutFrames / 16) : 0
            visible: opacity > 0.05
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
                          ? "Edge jumps and combos clear the long gaps. Bounce the lane walls. ← → or A D. Space to start."
                          : (root.bestCombo > 0
                             ? ("Best combo x" + root.bestCombo + ". Height is signed before it hits the board.")
                             : "Height is signed before it hits the board.")
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
