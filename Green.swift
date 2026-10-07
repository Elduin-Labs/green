// Green: a green stick figure who walks along the bottom of your screen.
// Every so often the Chosen One (the black stick figure) walks in, they fight, and Green loses.
// Or they walk up to a Minecraft icon, open the game, and play it.
// They float above everything and never get in the way of your mouse.
import Cocoa

/// How a stick figure is standing right now. The scene changes these; drawing reads them.
struct Pose {
    var phase: CGFloat = 0     // walk cycle
    var walk: CGFloat = 0      // 0 = standing still, 1 = full walking swing
    var stance: CGFloat = 0    // 1 = fists up, ready to fight
    var punchArm: CGFloat = 1  // which arm throws the punch: 1 or -1
    var punch: CGFloat = 0     // 0...1, how far the fist is out
    var kick: CGFloat = 0      // 0...1, how high the foot is
    var fall: CGFloat = 0      // 0 = upright, pi/2 = lying flat on his back
    var cheer = false          // both arms up
    var hop: CGFloat = 0       // little jumps
}

final class Figure {
    var x: CGFloat
    var facing: CGFloat        // 1 = looking right, -1 = looking left
    let color: NSColor
    let halo: NSColor?         // a pale edge, so a black figure still shows on a dark screen
    let name: String
    var alpha: CGFloat = 1
    var pose = Pose()

    init(x: CGFloat, facing: CGFloat, color: NSColor, halo: NSColor? = nil, name: String) {
        self.x = x
        self.facing = facing
        self.color = color
        self.halo = halo
        self.name = name
    }
}

private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }
private func sign(_ v: CGFloat) -> CGFloat { v < 0 ? -1 : 1 }

/// One piece of flame. They are made at the Chosen One's hand and drift off, shrinking and cooling.
struct Spark {
    var x: CGFloat
    var y: CGFloat
    var vx: CGFloat
    var vy: CGFloat
    var life: Int
    let maxLife: Int
    let size: CGFloat
}

final class StageView: NSView {
    enum Scene { case solo, approach, fight, aftermath, gap }

    private let margin: CGFloat = 40
    private let fightLength = 240
    private var ground: CGFloat { bounds.height / 2 - 50 }

    enum Mode {
        case stand   // both stand in the middle of the screen
        case walk    // both walk together back and forth across the middle
        case fight   // they fight right away, and the Chosen One wins. Then it starts over.
        case play    // they walk to a Minecraft icon, open the game, and play it together
    }

    var mode = Mode.fight {
        didSet {
            launched = false
            reset()
        }
    }

    private let green = Figure(x: 200, facing: 1,
                               color: NSColor(calibratedRed: 0.10, green: 0.85, blue: 0.20, alpha: 1),
                               name: "Green")
    private let chosen = Figure(x: -100, facing: 1, color: .black,
                                halo: NSColor(calibratedWhite: 1, alpha: 0.9), name: "The Chosen One")

    private var scene = Scene.solo
    private var soloLeft = Int.random(in: 480...900)   // Green walks alone for a while first
    private var t = 0                                  // ticks into the current scene
    private var originFacing: CGFloat = 1              // which way the Chosen One walks home
    private var greenBase: CGFloat = 0
    private var chosenBase: CGFloat = 0
    private var greenKnock: CGFloat = 0
    private var chosenKnock: CGFloat = 0
    private var sparks: [Spark] = []
    private var hit: CGFloat = 0                       // how big the "pow" is right now
    private var hitPoint = NSPoint.zero

    // Playing Minecraft
    private enum PlayPhase { case walkIn, click, opening, playing }
    private struct Chip {
        var x: CGFloat
        var y: CGFloat
        var vx: CGFloat
        var vy: CGFloat
        var life: Int
        let color: NSColor
    }
    private var playPhase = PlayPhase.walkIn
    private var pt = 0                       // ticks into the current play phase (or turn)
    private var launched = false             // the real Minecraft has been opened this time round
    private var windowGrow: CGFloat = 0      // 0 = no game window yet, 1 = fully open
    private var iconPulse: CGFloat = 0       // the icon bounces when it gets clicked
    private var world: [[Int]] = []          // blocks in each column, bottom first: 0 stone, 1 dirt, 2 grass, 3 planks
    private var actor = 0                    // whose turn: 0 = Green digs, 1 = the Chosen One builds
    private var target = 0                   // which column they are working on
    private var placeFlash: CGFloat = 0
    private var chips: [Chip] = []
    private let blockSize: CGFloat = 20
    private let worldColumns = 15
    private let worldRows = 7
    private var windowRect: NSRect { NSRect(x: bounds.midX - 150, y: ground + 4, width: 300, height: 180) }
    private var iconCenter: NSPoint { NSPoint(x: bounds.midX, y: ground + 26) }

    override var isFlipped: Bool { false }

    // MARK: story

    private func reset() {
        let w = bounds.width
        green.alpha = 1
        green.pose = Pose()
        chosen.alpha = 1
        chosen.pose = Pose()
        hit = 0
        sparks = []
        switch mode {
        case .stand:
            green.x = w / 2 - 55
            green.facing = 1
            chosen.x = w / 2 + 55
            chosen.facing = -1
        case .walk:
            green.x = w / 2 - 55
            chosen.x = w / 2 + 55
            green.facing = 1
            chosen.facing = 1
            chosen.pose.phase = 2   // so their legs don't swing in exactly the same step
        case .fight:
            // They start fighting right here in the middle.
            green.x = w / 2 - 38
            chosen.x = w / 2 + 38
            originFacing = 1
            startFight()
        case .play:
            green.x = margin
            green.facing = 1
            chosen.x = w - margin
            chosen.facing = -1
            playPhase = .walkIn
            pt = 0
            windowGrow = 0
            iconPulse = 0
            placeFlash = 0
            actor = 0
            chips = []
            buildWorld()
        }
        needsDisplay = true
    }

    private var laidOutSize = NSSize.zero

    override func layout() {
        super.layout()
        // Only start over when the screen size is first known or changes, not on every layout.
        if bounds.size != laidOutSize {
            laidOutSize = bounds.size
            reset()
        }
    }

    /// Both of them walk the same way, side by side, and turn around together at the edges.
    private func walkTogether() {
        let w = bounds.width
        for f in [green, chosen] {
            f.x += f.facing * 2.2
            f.pose.phase += 0.16
            f.pose.walk = 1
        }
        let right = max(green.x, chosen.x), left = min(green.x, chosen.x)
        if right > w - margin { green.facing = -1; chosen.facing = -1 }
        if left < margin { green.facing = 1; chosen.facing = 1 }
    }

    func step() {
        switch mode {
        case .stand: return
        case .walk:
            walkTogether()
            needsDisplay = true
            return
        case .play:
            playStep()
            needsDisplay = true
            return
        case .fight: break
        }
        let w = bounds.width
        moveSparks()
        switch scene {
        case .solo:
            walkGreen(width: w)
            soloLeft -= 1
            if soloLeft <= 0 { sendInChosenOne(width: w) }

        case .approach:
            chosen.pose.phase += 0.2
            chosen.pose.walk = 1
            chosen.x += chosen.facing * 3.2
            let distance = abs(chosen.x - green.x)
            if distance > 220 {
                walkGreen(width: w)
            } else {
                // Green sees him coming, stops, and turns to face him.
                green.pose.walk = 0
                green.facing = sign(chosen.x - green.x)
            }
            if distance <= 76 { startFight() }

        case .fight:
            fight()

        case .aftermath:
            aftermath(width: w)

        case .gap:
            t += 1
            if t >= 150 { bringBackGreen(width: w) }
        }
        needsDisplay = true
    }

    private func walkGreen(width w: CGFloat) {
        green.x += green.facing * 2.2
        green.pose.phase += 0.16
        green.pose.walk = 1
        if green.x > w - margin { green.facing = -1 }
        if green.x < margin { green.facing = 1 }
    }

    private func sendInChosenOne(width w: CGFloat) {
        // He comes in from the side Green is walking toward, so they meet head on.
        let side = green.facing
        chosen.x = side > 0 ? w + 30 : -30
        chosen.facing = -side
        chosen.pose = Pose()
        chosen.alpha = 1
        originFacing = side
        scene = .approach
    }

    private func startFight() {
        let g = sign(chosen.x - green.x)
        let mid = (green.x + chosen.x) / 2
        green.x = mid - 38 * g
        chosen.x = mid + 38 * g
        green.facing = g
        chosen.facing = -g
        greenBase = green.x
        chosenBase = chosen.x
        greenKnock = 0
        chosenKnock = 0
        green.pose = Pose(stance: 1)
        chosen.pose = Pose(stance: 1)
        t = 0
        scene = .fight
    }

    private func fight() {
        t += 1
        let g = green.facing
        hit = max(0, hit - 0.08)

        // The Chosen One: fire, a punch, fire, a kick, and then one long blast of fire at the end.
        let cycle = t / 30
        let frac = CGFloat(t % 30) / 30
        let swing = sin(.pi * frac)
        chosen.pose.punch = 0
        chosen.pose.kick = 0
        chosen.pose.punchArm = 1
        var landed = false
        if t >= 170 {
            // the big finish: his arm stays out and the fire keeps coming
            chosen.pose.punch = min(1, CGFloat(t - 170) / 8)
            shootFire(amount: 4)
            landed = t >= 180
        } else {
            switch cycle % 4 {
            case 0, 2:
                chosen.pose.punch = min(1, swing * 2)
                if frac > 0.15 && frac < 0.8 { shootFire(amount: 3) }
                landed = frac > 0.45 && frac < 0.85
            case 1:
                chosen.pose.punchArm = -1
                chosen.pose.punch = swing
                if swing > 0.75 {
                    landed = true
                    hit = 1
                    hitPoint = NSPoint(x: (green.x + chosen.x) / 2, y: ground + 62)
                }
            default:
                chosen.pose.kick = swing
                if swing > 0.75 {
                    landed = true
                    hit = 1
                    hitPoint = NSPoint(x: (green.x + chosen.x) / 2, y: ground + 40)
                }
            }
        }

        // Green fights back, but not as well, and only every other round.
        let gCycle = (t + 15) / 30
        let gSwing = sin(.pi * CGFloat((t + 15) % 30) / 30) * 0.7
        green.pose.punch = 0
        if gCycle % 2 == 0 && t < 200 {
            green.pose.punchArm = gCycle % 4 == 0 ? 1 : -1
            green.pose.punch = gSwing
        }

        // Green gets pushed back by every hit. The Chosen One just rocks a little.
        greenKnock += ((landed ? 7 : 0) - greenKnock) * 0.35
        chosenKnock += ((gSwing > 0.45 ? 2 : 0) - chosenKnock) * 0.35
        green.x = greenBase - g * greenKnock
        chosen.x = chosenBase + g * chosenKnock

        if t >= fightLength {
            t = 0
            scene = .aftermath
        }
    }

    private func aftermath(width w: CGFloat) {
        t += 1
        let g = green.facing
        hit = max(0, hit - 0.08)

        // Green is knocked over and lies flat, then fades away.
        let k = min(1, CGFloat(t) / 28)
        green.pose = Pose(fall: (.pi / 2) * (1 - (1 - k) * (1 - k)))
        if t < 28 { green.x -= g * 1.2 }
        if t > 70 { green.alpha = max(0, 1 - CGFloat(t - 70) / 80) }

        // Flames lick up around Green while he lies there.
        if t < 90 {
            for _ in 0..<2 {
                addSpark(x: green.x - g * CGFloat.random(in: 0...60), y: ground + CGFloat.random(in: 2...12),
                         vx: CGFloat.random(in: -0.3...0.3), vy: CGFloat.random(in: 0.8...2))
            }
        }

        // The Chosen One cheers, then turns and walks home.
        chosen.pose.punch = 0
        chosen.pose.kick = 0
        chosen.pose.stance = 0
        if t < 110 {
            chosen.pose.cheer = true
            chosen.pose.walk = 0
            chosen.pose.phase += 0.25
            chosen.pose.hop = abs(sin(CGFloat(t) * 0.16)) * 7
        } else {
            chosen.pose.cheer = false
            chosen.pose.hop = 0
            chosen.facing = originFacing
            chosen.pose.walk = 1
            chosen.pose.phase += 0.2
            chosen.x += chosen.facing * 3
        }

        let gone = chosen.x < -50 || chosen.x > w + 50
        if t >= 150 && gone {
            t = 0
            scene = .gap
        }
    }

    private func addSpark(x: CGFloat, y: CGFloat, vx: CGFloat, vy: CGFloat) {
        let life = Int.random(in: 18...34)
        sparks.append(Spark(x: x, y: y, vx: vx, vy: vy, life: life, maxLife: life, size: CGFloat.random(in: 5...10)))
    }

    /// Fire streams out of the Chosen One's outstretched hand toward Green.
    private func shootFire(amount: Int) {
        let hand = NSPoint(x: chosen.x + chosen.facing * 38, y: ground + 55)
        for _ in 0..<amount {
            addSpark(x: hand.x, y: hand.y + CGFloat.random(in: -3...3),
                     vx: chosen.facing * CGFloat.random(in: 3.5...5.5), vy: CGFloat.random(in: -0.4...0.7))
        }
    }

    private func moveSparks() {
        for i in sparks.indices {
            sparks[i].x += sparks[i].vx
            sparks[i].y += sparks[i].vy
            sparks[i].vy += 0.04          // flames drift upward
            sparks[i].life -= 1
            // When the fire reaches Green it splashes on him and climbs up.
            if scene == .fight, (green.x - sparks[i].x) * chosen.facing < 4, sparks[i].vx * chosen.facing > 1 {
                sparks[i].vx *= 0.15
                sparks[i].vy = CGFloat.random(in: 0.8...2)
            }
        }
        sparks.removeAll { $0.life <= 0 }
    }

    private func bringBackGreen(width w: CGFloat) {
        let side: CGFloat = Bool.random() ? 1 : -1
        green.x = side > 0 ? margin : w - margin
        green.facing = side
        green.pose = Pose()
        green.alpha = 1
        soloLeft = Int.random(in: 120...300)   // a few seconds, then the Chosen One comes again
        t = 0
        scene = .solo
    }

    // MARK: playing Minecraft

    private func buildWorld() {
        world = (0..<worldColumns).map { i in
            let h = 3 + Int((sin(Double(i) * 0.7) + 1) * 1.5)   // gentle hills, 3 to 6 blocks tall
            return (0..<h).map { r in r == h - 1 ? 2 : (r >= h - 3 ? 1 : 0) }
        }
    }

    /// Walks a figure toward x. Says true once he is there.
    private func approach(_ f: Figure, to x: CGFloat) -> Bool {
        let d = x - f.x
        if abs(d) < 3 {
            f.pose.walk = 0
            return true
        }
        f.facing = sign(d)
        f.x += f.facing * 2.4
        f.pose.phase += 0.17
        f.pose.walk = 1
        return false
    }

    private func launchMinecraft() {
        guard !launched else { return }
        launched = true
        let url = URL(fileURLWithPath: "/Applications/Minecraft.app")
        if FileManager.default.fileExists(atPath: url.path) { NSWorkspace.shared.open(url) }
    }

    private func playStep() {
        let cx = bounds.midX
        moveChips()
        placeFlash = max(0, placeFlash - 0.05)
        iconPulse = max(0, iconPulse - 0.08)

        switch playPhase {
        case .walkIn:
            // Both walk up to the Minecraft icon.
            let a = approach(green, to: cx - 45)
            let b = approach(chosen, to: cx + 45)
            if a { green.facing = 1 }
            if b { chosen.facing = -1 }
            if a && b {
                pt = 0
                playPhase = .click
            }

        case .click:
            // Green clicks the icon twice. The real Minecraft opens on the second click.
            pt += 1
            green.pose.punch = pt < 50 ? sin(.pi * CGFloat(pt % 25) / 25) : 0
            if pt == 12 || pt == 37 { iconPulse = 1 }
            if pt == 37 { launchMinecraft() }
            chosen.pose.cheer = pt > 12
            chosen.pose.phase += 0.25
            chosen.pose.hop = pt > 12 ? abs(sin(CGFloat(pt) * 0.2)) * 5 : 0
            if pt >= 60 {
                green.pose.punch = 0
                chosen.pose.cheer = false
                chosen.pose.hop = 0
                pt = 0
                playPhase = .opening
            }

        case .opening:
            // The game window pops open from the icon while they step aside to make room.
            pt += 1
            windowGrow = min(1, windowGrow + 1 / 30)
            let a = approach(green, to: cx - 195)
            let b = approach(chosen, to: cx + 195)
            if a { green.facing = 1 }
            if b { chosen.facing = -1 }
            if windowGrow >= 1 && a && b {
                pt = 0
                actor = 0
                pickTarget()
                playPhase = .playing
            }

        case .playing:
            pt += 1
            green.pose.punch = 0
            green.pose.hop = 0
            chosen.pose.punch = 0
            chosen.pose.hop = 0
            let column = world[target]
            let blockX = windowRect.minX + (CGFloat(target) + 0.5) * blockSize
            if actor == 0 {
                // Green digs: swing, swing, swing, and the block breaks.
                green.pose.punch = abs(sin(CGFloat(pt) * 0.2))
                if pt % 9 == 0, let top = column.last {
                    let y = windowRect.minY + (CGFloat(column.count) - 0.5) * blockSize
                    for _ in 0..<2 { addChip(x: blockX, y: y, block: top) }
                }
                if pt >= 60 {
                    if column.count > 2, let top = column.last {
                        world[target].removeLast()
                        let y = windowRect.minY + (CGFloat(column.count) - 0.5) * blockSize
                        for _ in 0..<10 { addChip(x: blockX, y: y, block: top) }
                    }
                    nextTurn()
                }
            } else {
                // The Chosen One builds: reach out, and a plank block appears.
                if pt < 24 { chosen.pose.punch = sin(.pi * CGFloat(pt) / 24) }
                if pt == 14, column.count < worldRows {
                    world[target].append(3)
                    placeFlash = 1
                }
                if pt >= 14 { chosen.pose.hop = abs(sin(CGFloat(pt - 14) * 0.2)) * 6 }
                if pt >= 40 { nextTurn() }
            }
        }
    }

    private func nextTurn() {
        actor = 1 - actor
        pt = 0
        pickTarget()
    }

    private func pickTarget() {
        let options = world.indices.filter { actor == 0 ? world[$0].count > 2 : world[$0].count < worldRows }
        target = options.randomElement() ?? 0
    }

    private func blockColor(_ type: Int) -> NSColor {
        switch type {
        case 0: return NSColor(calibratedWhite: 0.5, alpha: 1)
        case 1, 2: return NSColor(calibratedRed: 0.55, green: 0.38, blue: 0.22, alpha: 1)
        default: return NSColor(calibratedRed: 0.78, green: 0.60, blue: 0.35, alpha: 1)
        }
    }

    private func addChip(x: CGFloat, y: CGFloat, block: Int) {
        let color = block == 2 && Bool.random() ? NSColor(calibratedRed: 0.30, green: 0.65, blue: 0.20, alpha: 1) : blockColor(block)
        chips.append(Chip(x: x + CGFloat.random(in: -8...8), y: y + CGFloat.random(in: -8...8),
                          vx: CGFloat.random(in: -1.2...1.2), vy: CGFloat.random(in: 0.5...2.5),
                          life: Int.random(in: 20...34), color: color))
    }

    private func moveChips() {
        for i in chips.indices {
            chips[i].x += chips[i].vx
            chips[i].y += chips[i].vy
            chips[i].vy -= 0.12   // chips fall
            chips[i].life -= 1
        }
        chips.removeAll { $0.life <= 0 }
    }

    // MARK: drawing

    override func draw(_ dirtyRect: NSRect) {
        dirtyRect.fill(using: .clear)

        if mode == .play { drawPlay() }
        if green.alpha > 0 { draw(green) }
        if mode != .fight || scene == .approach || scene == .fight || scene == .aftermath { draw(chosen) }
        if hit > 0 { drawBurst(at: hitPoint, size: hit) }
        drawSparks()
    }

    // MARK: drawing Minecraft

    private func drawPlay() {
        if windowGrow < 1 { drawIcon() }
        if windowGrow > 0 { drawGameWindow() }
        for c in chips {
            c.color.setFill()
            NSRect(x: c.x - 2, y: c.y - 2, width: 4, height: 4).fill()
        }
    }

    /// The Minecraft icon: a little grass block with its name on top.
    private func drawIcon() {
        let c = iconCenter
        let alpha = 1 - windowGrow
        let size = 44 * (1 + 0.18 * iconPulse)
        let rect = NSRect(x: c.x - size / 2, y: c.y - size / 2, width: size, height: size)
        let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        blockColor(1).withAlphaComponent(alpha).setFill()
        path.fill()
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        NSColor(calibratedRed: 0.30, green: 0.65, blue: 0.20, alpha: alpha).setFill()
        NSRect(x: rect.minX, y: rect.maxY - size * 0.32, width: size, height: size * 0.32).fill()
        NSGraphicsContext.restoreGraphicsState()
        NSColor(calibratedWhite: 0.1, alpha: 0.6 * alpha).setStroke()
        path.lineWidth = 2
        path.stroke()
        let label = NSAttributedString(string: "Minecraft", attributes: [
            .font: NSFont.boldSystemFont(ofSize: 11),
            .foregroundColor: NSColor(calibratedWhite: 0.1, alpha: alpha),
            .strokeColor: NSColor(calibratedWhite: 1, alpha: alpha),
            .strokeWidth: -2,
        ])
        let labelSize = label.size()
        label.draw(at: NSPoint(x: c.x - labelSize.width / 2, y: rect.maxY + 4))
    }

    /// A small game window with a blocky world in it. It grows out of the icon.
    private func drawGameWindow() {
        let grow = 1 - pow(1 - windowGrow, 3)
        let c = iconCenter
        NSGraphicsContext.saveGraphicsState()
        let move = NSAffineTransform()
        move.translateX(by: c.x, yBy: c.y)
        move.scaleX(by: grow, yBy: grow)
        move.translateX(by: -c.x, yBy: -c.y)
        move.concat()

        let win = windowRect
        let titleBar = NSRect(x: win.minX, y: win.maxY - 18, width: win.width, height: 18)
        let sky = NSRect(x: win.minX, y: win.minY, width: win.width, height: win.height - 18)

        NSColor(calibratedRed: 0.45, green: 0.70, blue: 1.0, alpha: 1).setFill()
        sky.fill()

        for (i, column) in world.enumerated() {
            for (r, type) in column.enumerated() {
                let rect = NSRect(x: win.minX + CGFloat(i) * blockSize, y: win.minY + CGFloat(r) * blockSize,
                                  width: blockSize, height: blockSize)
                blockColor(type).setFill()
                rect.fill()
                if type == 2 {
                    NSColor(calibratedRed: 0.30, green: 0.65, blue: 0.20, alpha: 1).setFill()
                    NSRect(x: rect.minX, y: rect.maxY - 6, width: blockSize, height: 6).fill()
                }
                NSColor(calibratedWhite: 0, alpha: 0.25).setStroke()
                NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5)).stroke()
            }
        }

        // What they are working on right now: a crosshair, and cracks while Green digs.
        if playPhase == .playing, world.indices.contains(target) {
            let height = world[target].count
            let row = actor == 0 ? height - 1 : height
            let rect = NSRect(x: win.minX + CGFloat(target) * blockSize, y: win.minY + CGFloat(row) * blockSize,
                              width: blockSize, height: blockSize)
            if actor == 0 {
                let cracks = NSBezierPath()
                cracks.lineWidth = 1.5
                let n = Int(CGFloat(pt) / 60 * 6)
                for k in 0..<max(0, n) {
                    let fx = CGFloat((k * 7 + 3) % 10) / 10, fy = CGFloat((k * 5 + 1) % 10) / 10
                    cracks.move(to: NSPoint(x: rect.minX + fx * blockSize, y: rect.minY + fy * blockSize))
                    cracks.line(to: NSPoint(x: rect.minX + (1 - fy) * blockSize, y: rect.minY + (1 - fx) * blockSize))
                }
                NSColor(calibratedWhite: 0, alpha: 0.6).setStroke()
                cracks.stroke()
            } else if placeFlash > 0 {
                NSColor(calibratedWhite: 1, alpha: 0.7 * placeFlash).setFill()
                NSRect(x: win.minX + CGFloat(target) * blockSize, y: win.minY + CGFloat(height - 1) * blockSize,
                       width: blockSize, height: blockSize).fill()
            }
            NSColor(calibratedWhite: 1, alpha: 0.9).setStroke()
            let outline = NSBezierPath(rect: rect.insetBy(dx: 1, dy: 1))
            outline.lineWidth = 2
            outline.stroke()
        }

        NSColor(calibratedWhite: 0.88, alpha: 1).setFill()
        titleBar.fill()
        for (k, color) in [NSColor.systemRed, NSColor.systemYellow, NSColor.systemGreen].enumerated() {
            color.setFill()
            NSBezierPath(ovalIn: NSRect(x: titleBar.minX + 7 + CGFloat(k) * 14, y: titleBar.midY - 4.5, width: 9, height: 9)).fill()
        }
        let title = NSAttributedString(string: "Minecraft", attributes: [
            .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: NSColor(calibratedWhite: 0.25, alpha: 1),
        ])
        let titleSize = title.size()
        title.draw(at: NSPoint(x: titleBar.midX - titleSize.width / 2, y: titleBar.midY - titleSize.height / 2))

        NSColor(calibratedWhite: 0.2, alpha: 1).setStroke()
        let border = NSBezierPath(rect: win.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = 2
        border.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }

    private func draw(_ f: Figure) {
        let p = f.pose
        let c = cos(p.fall), s = sin(p.fall)

        // Places a point given as (forward, up) from the figure's feet. A fall turns it over backwards.
        func at(_ forward: CGFloat, _ up: CGFloat) -> NSPoint {
            let u = up + p.hop
            return NSPoint(x: f.x + f.facing * (forward * c - u * s), y: ground + sin(p.fall) * 9 + forward * s + u * c)
        }

        let hipY: CGFloat = 34 - p.stance * 3
        let neckY = hipY + 34
        let shoulderY = neckY - 6
        let swing = sin(p.phase) * p.walk
        // Standing still: legs and arms hang a little apart, so he doesn't look like a lollipop.
        let idle = (1 - p.walk) * (1 - p.stance) * (1 - p.fall / (.pi / 2))

        let body = NSBezierPath()
        body.lineWidth = 5
        body.lineCapStyle = .round
        body.lineJoinStyle = .round

        body.move(to: at(0, hipY))
        body.line(to: at(0, neckY))

        // legs
        for side: CGFloat in [1, -1] {
            var footX = swing * side * 16
            var footY = max(0, sin(side == 1 ? p.phase : p.phase + .pi)) * 4 * p.walk
            footX += side * 8 * idle
            footX = lerp(footX, side == 1 ? 14 : -12, p.stance)
            footY = lerp(footY, 0, p.stance)
            if p.kick > 0 && side == 1 {
                footX = 8 + 30 * p.kick
                footY = 4 + 28 * p.kick
            }
            body.move(to: at(0, hipY))
            body.line(to: at(footX, footY))
        }

        // arms
        for side: CGFloat in [1, -1] {
            var handX = -swing * side * 13
            var handY = shoulderY - 20
            handX += side * 11 * idle
            handX = lerp(handX, 10, p.stance)
            handY = lerp(handY, shoulderY - 14, p.stance)
            if side == p.punchArm && p.punch > 0 {
                handX = 8 + 30 * p.punch
                handY = shoulderY - 16 + 12 * p.punch
            }
            if p.cheer {
                handX = side * 24
                handY = shoulderY + 16 + sin(p.phase * 2 + side) * 3
            }
            body.move(to: at(0, shoulderY))
            body.line(to: at(handX, handY))
        }

        // head: an empty circle, no face
        let headRadius: CGFloat = 13
        let headCenter = at(0, neckY + headRadius)
        let head = NSBezierPath(ovalIn: NSRect(x: headCenter.x - headRadius, y: headCenter.y - headRadius,
                                               width: headRadius * 2, height: headRadius * 2))
        head.lineWidth = 5

        if let halo = f.halo {
            halo.withAlphaComponent(halo.alphaComponent * f.alpha).setStroke()
            body.lineWidth = 9
            head.lineWidth = 9
            body.stroke()
            head.stroke()
            body.lineWidth = 5
            head.lineWidth = 5
        }
        f.color.withAlphaComponent(f.alpha).setStroke()
        body.stroke()
        head.stroke()

        // the name, while standing up
        if p.fall == 0 {
            var attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: 11),
                .foregroundColor: f.color.withAlphaComponent(f.alpha),
            ]
            if f.halo != nil {
                attributes[.strokeColor] = NSColor.white
                attributes[.strokeWidth] = -2
            }
            let label = NSAttributedString(string: f.name, attributes: attributes)
            let size = label.size()
            label.draw(at: NSPoint(x: f.x - size.width / 2, y: headCenter.y + headRadius + 5))
        }
    }

    private func drawSparks() {
        for sp in sparks {
            let age = 1 - CGFloat(sp.life) / CGFloat(sp.maxLife)   // 0 = new, 1 = about to go out
            let color: NSColor
            if age < 0.3 {
                color = NSColor(calibratedRed: 1, green: 0.9, blue: 0.25, alpha: 0.95)
            } else if age < 0.65 {
                color = NSColor(calibratedRed: 1, green: 0.5, blue: 0.05, alpha: 0.85)
            } else {
                color = NSColor(calibratedRed: 0.85, green: 0.15, blue: 0.05, alpha: 0.6 * (1 - age) / 0.35 + 0.1)
            }
            color.setFill()
            let r = sp.size * (1 - 0.55 * age) / 2
            NSBezierPath(ovalIn: NSRect(x: sp.x - r, y: sp.y - r, width: r * 2, height: r * 2)).fill()
        }
    }

    /// A little yellow burst where a hit lands.
    private func drawBurst(at point: NSPoint, size: CGFloat) {
        let rays = NSBezierPath()
        rays.lineWidth = 3
        rays.lineCapStyle = .round
        for i in 0..<8 {
            let angle = CGFloat(i) * .pi / 4
            let inner = 6 + (1 - size) * 8
            let outer = inner + 9 * size
            rays.move(to: NSPoint(x: point.x + cos(angle) * inner, y: point.y + sin(angle) * inner))
            rays.line(to: NSPoint(x: point.x + cos(angle) * outer, y: point.y + sin(angle) * outer))
        }
        NSColor(calibratedRed: 1, green: 0.85, blue: 0.1, alpha: size).setStroke()
        rays.stroke()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var view: StageView!
    var timer: Timer?
    var statusItem: NSStatusItem!
    var items: [(NSMenuItem, StageView.Mode)] = []

    @objc func choose(_ sender: NSMenuItem) {
        guard let mode = items.first(where: { $0.0 === sender })?.1 else { return }
        view.mode = mode
        for (item, m) in items { item.state = m == mode ? .on : .off }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let screen = NSScreen.main else { return }
        let area = screen.visibleFrame
        let frame = NSRect(x: area.minX, y: area.minY, width: area.width, height: area.height)

        window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .floating
        window.ignoresMouseEvents = true   // the mouse goes straight through them
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        view = StageView(frame: NSRect(origin: .zero, size: frame.size))
        // `open Green.app --args play` starts them off playing Minecraft.
        if CommandLine.arguments.contains("play") { view.mode = .play }
        window.contentView = view
        window.orderFrontRegardless()

        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.view.step()
        }

        // A little "Green" in the menu bar, so there is always a way to say goodbye to him.
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "Green"
        let menu = NSMenu()
        let choices: [(String, StageView.Mode)] = [
            ("Fight", .fight),
            ("Play Minecraft", .play),
            ("Walk together", .walk),
            ("Stand in the middle", .stand),
        ]
        for (title, mode) in choices {
            let item = NSMenuItem(title: title, action: #selector(choose(_:)), keyEquivalent: "")
            item.target = self
            item.state = mode == view.mode ? .on : .off
            menu.addItem(item)
            items.append((item, mode))
        }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Green", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // no Dock icon
let delegate = AppDelegate()
app.delegate = delegate
app.run()
