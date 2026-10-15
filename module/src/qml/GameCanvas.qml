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

    // Authentic Icy Tower feel: modest base hop; edge timing extends the arc.
    // Combo rewards pace (helps beat the floor) but is NEVER required to land.
    readonly property real gravity: 0.60
    readonly property real jumpV: -13.0
    readonly property real edgeJumpExtra: -3.4
    readonly property real springJumpExtra: -4.0
    readonly property real moveA: 1.20
    readonly property real friction: 0.86
    readonly property real maxVx: 11.5
    readonly property real wallRestitution: 0.94
    // Collision box stays modest; drawn λ is a bit larger (noticeable, not huge).
    readonly property int playerSize: 44
    readonly property int playerVisualSize: 62
    readonly property int platformH: 14
    readonly property real landSlopY: 5
    readonly property real landSlopX: 3
    readonly property real edgeZoneFrac: 0.24
    // Generation safety margins (never spawn at the mathematical limit).
    readonly property real gapPeakFracBase: 0.78
    readonly property real gapPeakFracEdge: 0.86
    readonly property real horizBudgetFrac: 0.78

    property real px: 0
    property real py: 0
    property real vx: 0
    property real vy: 0
    // cam decreases as the world scrolls up (camera follow / floor rise).
    property real cam: 0
    // Spawn screen-Y; altitude is measured above this pose in world space.
    property real startPy: 0
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

    // Edge boost only — combo must not appear in spawn math.
    function edgeJumpV0() {
        return jumpV + edgeJumpExtra
    }

    function edgeJumpV(comboBonus) {
        var c = Math.min(12, Math.max(0, comboBonus || 0))
        return edgeJumpV0() - c * 0.16
    }

    // Steady air steer speed (no ice). Used for generation budgets.
    function cruiseSpeed() {
        var s = (moveA * friction) / Math.max(0.001, 1 - friction)
        return Math.min(maxVx, s)
    }

    // Time to land on a ledge `gapY` above takeoff (descent landing).
    function airTimeForGap(gapY, vJump) {
        var u0 = -vJump
        var peak = maxJumpHeightFrom(vJump)
        var g = gravity
        var dy = Math.max(0, Math.min(gapY, peak * 0.96))
        var tPeak = u0 / g
        var tFall = Math.sqrt(2 * Math.max(0, peak - dy) / g)
        return Math.max(10, tPeak + tFall)
    }

    function maxHorizTravel(gapY, vJump) {
        return cruiseSpeed() * airTimeForGap(gapY, vJump) * horizBudgetFrac
    }

    // Minimum horizontal travel from a standable pose on `prev` to overlap `next`.
    function horizClearance(prevX, prevW, nextX, nextW) {
        var pL = prevX
        var pR = prevX + Math.max(0, prevW - playerSize)
        var nL = nextX
        var nR = nextX + Math.max(0, nextW - playerSize)
        if (pR >= nL && pL <= nR)
            return 0
        if (nL > pR)
            return nL - pR
        return pL - nR
    }

    // Classic Icy Tower curve: gentle open, spicy late. Near-full ~height 360.
    function difficulty() {
        if (maxHeight < 20)
            return Math.min(0.12, maxHeight / 160)
        return Math.min(1, 0.12 + (maxHeight - 20) / 340)
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
        // Shift screen coords together — world altitude must stay invariant
        // (see altitudePx). Previously `cam + (worldH - py)` lost 2*amount per scroll.
        py += amount
        for (var i = 0; i < platforms.length; i++)
            platforms[i].y += amount
        cam -= amount
    }

    // Climbed distance in px above spawn. Invariant under scrollWorld:
    //   cam -= a, py += a  ⇒  (-cam) + (startPy - py) unchanged.
    function altitudePx() {
        return (-cam) + (startPy - py)
    }

    function noteHeight() {
        var h = altitudePx() / 10 // ~Icy Tower “floors” (10 px ≈ 1 unit)
        if (h > maxHeight)
            maxHeight = h
        score = Math.max(0, Math.floor(maxHeight))
    }

    function followPlayerUp() {
        var followLine = topSafe + worldH * 0.30
        if (py < followLine)
            scrollWorld(followLine - py)
        var topLimit = topSafe + Math.max(28, worldH * 0.06)
        if (py < topLimit)
            scrollWorld(topLimit - py)
    }

    // Rising floor — slow creep at open, authentic late-game rush (classic IT pacing).
    function floorRiseSpeed() {
        var d = difficulty()
        // ~10s almost-idle, then ~100s to full time contribution.
        var t = Math.min(1, Math.max(0, (runFrames - 60 * 10) / (60 * 100)))
        // Open ~0.20–0.35, mid ~1.3–2.0, late cap ~3.7.
        return Math.min(3.7, 0.20 + d * 1.85 + t * 1.15 + maxHeight / 480)
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
        var bestP = null
        for (var i = 0; i < platforms.length; i++) {
            var p = platforms[i]
            if (!p.alive)
                continue
            if (!bestP || p.y < bestP.y)
                bestP = p
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

    function makePlatform(x, y, w, kind, amp, speed, phase) {
        return {
            x: x,
            y: y,
            w: w,
            kind: kind || "normal",
            baseX: x,
            phase: phase !== undefined ? phase : Math.random() * Math.PI * 2,
            amp: amp || 0,
            speed: speed || 0,
            alive: true
        }
    }

    function platformSurfaceX(p, frame) {
        if (p.kind === "moving")
            return p.baseX + Math.sin(p.phase + frame * p.speed) * p.amp
        return p.x
    }

    function syncMovingPlatforms() {
        for (var i = 0; i < platforms.length; i++) {
            var p = platforms[i]
            if (p.kind === "moving")
                p.x = platformSurfaceX(p, runFrames)
        }
    }

    function pickKind(diff, index, stretch) {
        var r = Math.random()
        // Opening tower: wide normal ledges only.
        if (index < 6 || diff < 0.22) {
            if (r < 0.08 && diff > 0.12)
                return "narrow"
            return "normal"
        }
        // Stretch jumps stay on solid footing (no movers/crumbs on the hard arc).
        if (stretch) {
            if (r < 0.16)
                return "narrow"
            if (r < 0.28)
                return "spring"
            if (r < 0.38)
                return "ice"
            return "normal"
        }
        // Obstacle variety scales with difficulty — scarce early, common late.
        if (r < 0.06 + diff * 0.12)
            return "moving"
        if (r < 0.12 + diff * 0.10)
            return "crumb"
        if (r < 0.22 + diff * 0.12)
            return "ice"
        if (r < 0.30 + diff * 0.10)
            return "spring"
        if (r < 0.42 + diff * 0.18)
            return "narrow"
        return "normal"
    }

    function resetWorld() {
        if (worldW < 100 || worldH < 100)
            return
        px = worldW / 2 - playerSize / 2
        py = worldH - Math.max(160, worldH * 0.22)
        startPy = py
        vx = 0
        vy = 0
        cam = 0
        maxHeight = 0
        score = 0
        runFrames = 0
        iceFrames = 0
        combo = 0
        shout = ""
        shoutFrames = 0
        var groundW = Math.min(laneWidth() * 0.50, 220)
        var ground = clampPlatformInLane(worldW / 2 - groundW / 2, groundW)
        platforms = [makePlatform(ground.x, worldH - Math.max(48, worldH * 0.08), ground.w, "normal")]
        var prev = platforms[0]
        for (var i = 0; i < 22; i++) {
            // Seed a gentle on-ramp by index — do not force mid-game difficulty at start.
            var d = Math.min(0.55, 0.04 + i * 0.018)
            var next = nextReachablePlatform(prev, d, i)
            platforms.push(next)
            prev = next
        }
        platformsChanged()
        canvas.requestPaint()
    }

    // Place one landable ledge. Stretch uses edgeJumpV0 only (never combo).
    // Retries until horiz+vert clearance passes; falls back to a safe hop.
    function nextReachablePlatform(prev, diff, index) {
        // Stretch almost absent at open; common only once difficulty ramps.
        var stretchChance = Math.max(0, diff - 0.15) * 0.55
        var stretch = Math.random() < stretchChance
        var vJump = stretch ? edgeJumpV0() : jumpV
        var peak = maxJumpHeightFrom(vJump)
        var peakFrac = stretch ? gapPeakFracEdge : gapPeakFracBase
        // Early gaps sit low in the envelope; late gaps push the skill band.
        var maxGapY = peak * (stretch ? peakFrac : (0.55 + 0.23 * diff))
        var minGapY = peak * (stretch ? (0.48 + 0.10 * diff) : (0.28 + 0.14 * diff))
        if (minGapY > maxGapY - 12)
            minGapY = maxGapY - 12

        var kind = pickKind(diff, index, stretch)
        var attempt = 0
        var placed = null
        var gapY = minGapY
        var w = 80

        while (attempt < 14) {
            attempt++
            gapY = minGapY + Math.random() * (maxGapY - minGapY)
            // Bias stretch toward the upper band (feels long, still landable).
            if (stretch)
                gapY = minGapY + (0.55 + Math.random() * 0.45) * (maxGapY - minGapY)

            var budget = maxHorizTravel(gapY, vJump)
            // Wider ledges early; narrows as difficulty rises.
            var wideBonus = Math.max(0, 0.22 - diff) * laneWidth()
            if (kind === "narrow")
                w = Math.max(48, laneWidth() * (0.10 - 0.02 * diff)) + Math.random() * Math.max(8, laneWidth() * 0.04)
            else if (kind === "spring")
                w = Math.max(64, laneWidth() * (0.14 - 0.02 * diff)) + Math.random() * Math.max(10, laneWidth() * 0.06) + wideBonus * 0.35
            else
                w = Math.max(70, laneWidth() * (0.16 - 0.04 * diff)) + Math.random() * Math.max(12, laneWidth() * 0.09) + wideBonus

            var side = Math.random() < 0.5 ? -1 : 1
            // Early hops stay close; later hops use more of the budget.
            var targetClear = budget * ((0.18 + 0.20 * diff) + Math.random() * (0.35 + 0.20 * diff))
            var prevCx = prev.x + prev.w / 2
            var cx = prevCx + side * (targetClear + w / 2)
            var cand = clampPlatformInLane(cx - w / 2, w)
            var clear = horizClearance(prev.x, prev.w, cand.x, cand.w)

            var amp = 0
            var speed = 0
            var phase = Math.random() * Math.PI * 2
            if (kind === "moving") {
                // Farthest swing must remain inside the horizontal budget.
                var slack = Math.max(0, budget - clear)
                amp = Math.min(14 + diff * 10, slack * 0.45)
                var maxAmp = Math.max(0, Math.min(cand.x - laneLeft(), laneRight() - (cand.x + cand.w)))
                amp = Math.min(amp, maxAmp)
                if (amp < 6) {
                    kind = "normal"
                    amp = 0
                } else {
                    speed = 0.028 + Math.random() * 0.03 + diff * 0.015
                    // Re-check clearance at both extremes.
                    var leftX = cand.x - amp
                    var rightX = cand.x + amp
                    var cL = horizClearance(prev.x, prev.w, leftX, cand.w)
                    var cR = horizClearance(prev.x, prev.w, rightX, cand.w)
                    if (Math.max(cL, cR) > budget) {
                        amp = 0
                        kind = "normal"
                        speed = 0
                    } else {
                        clear = Math.max(cL, cR)
                    }
                }
            }

            if (gapY <= peak * 0.92 && clear <= budget) {
                placed = makePlatform(cand.x, prev.y - gapY, cand.w, kind, amp, speed, phase)
                break
            }
        }

        if (!placed) {
            // Guaranteed safe hop — base envelope, short gap, near prev.
            gapY = maxJumpHeightFrom(jumpV) * 0.48
            w = Math.max(72, laneWidth() * 0.16)
            var safeCx = prev.x + prev.w / 2
            var safe = clampPlatformInLane(safeCx - w / 2, w)
            // Nudge toward center if somehow extreme.
            if (horizClearance(prev.x, prev.w, safe.x, safe.w) > maxHorizTravel(gapY, jumpV)) {
                safe = clampPlatformInLane(prev.x + (prev.w - w) / 2, w)
            }
            placed = makePlatform(safe.x, prev.y - gapY, safe.w, "normal")
        }

        return placed
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
        if (onLeft && vx <= -2.0)
            return true
        if (onRight && vx >= 2.0)
            return true
        return Math.abs(vx) >= 7.2 && (onLeft || onRight)
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
            var surfX = (p.kind === "moving") ? platformSurfaceX(p, runFrames) : p.x
            if (p.kind === "moving")
                p.x = surfX
            if (prevFeet <= p.y + landSlopY && feet >= p.y
                    && px + playerSize > surfX - landSlopX
                    && px < surfX + p.w + landSlopX) {
                py = p.y - playerSize
                var edged = isEdgeLand(p, surfX)
                combo += edged ? 2 : 1
                if (combo > bestCombo)
                    bestCombo = combo

                var jump = jumpV
                if (p.kind === "spring")
                    jump = jumpV + springJumpExtra - Math.min(5, combo) * 0.10
                else if (edged)
                    jump = edgeJumpV(combo)
                else if (combo >= 6)
                    jump = jumpV - Math.min(2.0, (combo - 5) * 0.18)

                if (edged) {
                    var boost = 1.12 + Math.min(2.2, combo * 0.07)
                    if (vx >= 0)
                        vx = Math.min(maxVx * 1.12, Math.max(vx, 4.0) * boost / 1.4 + 1.0)
                    else
                        vx = Math.max(-maxVx * 1.12, Math.min(vx, -4.0) * boost / 1.4 - 1.0)
                }

                if (p.kind === "ice")
                    iceFrames = 50
                if (p.kind === "crumb")
                    p.alive = false

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

        var a = iceFrames > 0 ? moveA * 1.15 : moveA
        var f = iceFrames > 0 ? 0.90 : friction
        var cap = iceFrames > 0 ? maxVx * 1.12 : maxVx
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
        // Sample after physics + camera catch-up (scroll-invariant).
        noteHeight()

        // Floor rise squeezes stalls; must not alter climbed altitude.
        scrollWorld(floorRiseSpeed())
        followPlayerUp()
        noteHeight()

        platforms = platforms.filter(function (p) {
            return p.alive && p.y < worldH + 80
        })

        var minCount = Math.max(22, Math.round(worldH / 44))
        var diff = difficulty()
        while (platforms.length < minCount) {
            var prev = highestPlatform()
            if (!prev)
                break
            platforms.push(nextReachablePlatform(prev, diff, platforms.length))
        }
        platformsChanged()

        if (py > worldH + 60) {
            noteHeight()
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
                    ctx.fillStyle = root.platformFill(p.kind)
                    ctx.fillRect(p.x, p.y, p.w, root.platformH)
                    if (p.kind === "spring") {
                        ctx.fillStyle = "#6a838b"
                        ctx.fillRect(p.x + p.w * 0.2, p.y - 3, p.w * 0.6, 3)
                    } else if (p.kind === "ice") {
                        ctx.fillStyle = "rgba(255,255,255,0.35)"
                        ctx.fillRect(p.x + 2, p.y + 2, Math.max(4, p.w - 4), 3)
                    } else if (p.kind === "moving") {
                        ctx.fillStyle = "#6a838b"
                        ctx.fillRect(p.x + 4, p.y + 5, Math.max(6, p.w - 8), 3)
                    } else if (p.kind === "crumb") {
                        ctx.fillStyle = "rgba(90,70,40,0.35)"
                        ctx.fillRect(p.x + 3, p.y + 4, Math.max(4, p.w - 6), 2)
                    }
                }
            }
        }

        Image {
            id: lambda
            source: "player-lambda.png"
            // Visual scale above the collision box; centered so landings stay fair.
            width: root.playerVisualSize * (parent.width / Math.max(1, root.worldW))
            height: root.playerVisualSize * (parent.height / Math.max(1, root.worldH))
            x: (root.px + (root.playerSize - root.playerVisualSize) / 2)
               * (parent.width / Math.max(1, root.worldW))
            y: (root.py + (root.playerSize - root.playerVisualSize) / 2)
               * (parent.height / Math.max(1, root.worldH))
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
                          ? "Start easy — the floor and gaps ramp as you climb. Edge jumps beat the late tower. ← → or A D. Space to start."
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
