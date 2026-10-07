// Green: a green stick figure who walks along the bottom of your screen.
// Every so often the Chosen One (the black stick figure) walks in, they fight, and Green loses.
// Or they walk up to a Minecraft icon and open the real Minecraft.
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
    var climb: CGFloat = 0     // 1 = hands and feet on a wall, climbing
    var lift: CGFloat = 0      // how high off the ground he is standing
}

final class Figure {
    var x: CGFloat
    var facing: CGFloat        // 1 = looking right, -1 = looking left
    let color: NSColor
    let halo: NSColor?         // a pale edge, so a black figure still shows on a dark screen
    let name: String
    var alpha: CGFloat = 1
    var pose = Pose()
    var isCrewmate = false     // the red Among Us crewmate is drawn as a bean, not a stick figure

    init(x: CGFloat, facing: CGFloat, color: NSColor, halo: NSColor? = nil, name: String) {
        self.x = x
        self.facing = facing
        self.color = color
        self.halo = halo
        self.name = name
    }
}

/// Makes a real, loud, rumbly burp: a low buzz that slides down, with a gurgle in it. No sound file needed.
private func makeBurp(seconds: Double, pitch: Double) -> Data {
    let rate = 44100.0
    let count = Int(rate * seconds)
    var samples = [Int16]()
    samples.reserveCapacity(count)
    var phase = 0.0
    for i in 0..<count {
        let t = Double(i) / rate
        let f = pitch * (1.0 - 0.55 * t / seconds) * (1 + 0.06 * sin(2 * .pi * 9 * t))
        phase += f / rate
        let saw = 2 * (phase - floor(phase)) - 1
        let square = phase - floor(phase) < 0.5 ? 1.0 : -1.0
        let gurgle = 0.55 + 0.45 * sin(2 * .pi * 26 * t)
        let envelope = min(1, t / 0.04) * min(1, (seconds - t) / 0.25)
        let noise = Double.random(in: -1...1) * 0.15
        let x = (0.6 * saw + 0.4 * square + noise) * gurgle * envelope * 1.6   // pushed hard, so it is loud
        samples.append(Int16(max(-1, min(1, x)) * 32000))
    }
    return wavData(samples)
}

/// Makes a heavy "THUMP": a very low note that drops and dies away fast.
private func makeThump() -> Data {
    let rate = 44100.0
    let seconds = 0.45
    var samples = [Int16]()
    var phase = 0.0
    for i in 0..<Int(rate * seconds) {
        let t = Double(i) / rate
        phase += (30 + 60 * exp(-t * 14)) / rate
        let x = (sin(2 * .pi * phase) + Double.random(in: -1...1) * 0.25 * exp(-t * 40)) * exp(-t * 7) * 2.2
        samples.append(Int16(max(-1, min(1, x)) * 32000))
    }
    return wavData(samples)
}

private func wavData(_ samples: [Int16]) -> Data {
    var data = Data()
    func put32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
    func put16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
    data.append(contentsOf: Array("RIFF".utf8)); put32(UInt32(36 + samples.count * 2))
    data.append(contentsOf: Array("WAVEfmt ".utf8)); put32(16); put16(1); put16(1)
    put32(44100); put32(88200); put16(2); put16(16)
    data.append(contentsOf: Array("data".utf8)); put32(UInt32(samples.count * 2))
    for v in samples { put16(UInt16(bitPattern: v)) }
    return data
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
        case play    // they walk to a Minecraft icon and open the real Minecraft
        case eat     // they walk to a Minecraft icon and eat it
        case crewTop // the red crewmate walks back and forth along the top of the screen
    }

    var mode = Mode.fight {
        didSet {
            launched = false
            releaseAll()
            reset()
        }
    }

    private let green = Figure(x: 200, facing: 1,
                               color: NSColor(calibratedRed: 0.10, green: 0.85, blue: 0.20, alpha: 1),
                               name: "Green")
    private let chosen = Figure(x: -100, facing: 1, color: .black,
                                halo: NSColor(calibratedWhite: 1, alpha: 0.9), name: "The Chosen One")

    /// The red Among Us crewmate. He pops in, climbs the chocolate, punches them both, and walks off the screen.
    private let crew: Figure = {
        let f = Figure(x: 0, facing: -1, color: NSColor(calibratedRed: 0.77, green: 0.07, blue: 0.07, alpha: 1), name: "Red")
        f.isCrewmate = true
        f.alpha = 0
        return f
    }()

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

    // Opening Minecraft
    private enum PlayPhase { case walkIn, click, cheer, playing }
    private enum Act { case rest, walk, leap, look, dig, crash }
    private var playPhase = PlayPhase.walkIn
    private var pt = 0
    private var launched = false          // the real Minecraft has been opened this time round
    private var iconPulse: CGFloat = 0    // the icon bounces when it gets clicked
    private var act = Act.rest
    private var actLeft = 0
    private var lookDir: Int64 = 1
    private var held = Set<CGKeyCode>()   // keys they are pressing in the real game right now
    private var mouseIsDown = false
    private var status = ""               // what they say while they wait
    private var trusted = false           // a grown-up said yes to controlling the keyboard and mouse
    private var minecraftIsUp = false     // the real game is the window in front
    private var askedForKeys = false
    private var mouseSlide: CGFloat = 0   // the mouse in the Chosen One's hand slides when he looks around
    private var mouseClick: CGFloat = 0   // and flashes when he clicks
    /// Digging means holding down the real mouse button. It stays off until Elduin turns it on from the menu,
    /// because in a menu screen a click could press the wrong button.
    var clicksAllowed = false
    private let keyW: CGKeyCode = 13
    private let keySpace: CGKeyCode = 49
    private let keyF3: CGKeyCode = 99
    private let keyC: CGKeyCode = 8
    /// Holding F3 and C together for ten seconds is Minecraft's own "crash the game on purpose" shortcut.
    var crashWanted = false
    private var upTicks = 0               // how long the real game has been in front
    // Eating Minecraft
    private enum EatPhase { case walkIn, climb, topWalk, crewVisit, munch, burp, gone }
    private enum CrewStep { case spawn, run, climb, cross, hitChosen, hitGreen, goBack, descend, leave }
    private struct Crumb {
        var x: CGFloat
        var y: CGFloat
        var vx: CGFloat
        var vy: CGFloat
        var life: Int
        let color: NSColor
    }
    private var eatPhase = EatPhase.walkIn
    private var bites = 0                 // 6 bites and the whole icon is gone
    private var crumbs: [Crumb] = []
    private var shake: CGFloat = 0         // how hard the screen is shaking right now
    private var crewStep = CrewStep.spawn
    private var crewT = 0                  // ticks into the current crewmate step
    private var knock: [CGFloat] = [0, 0]  // how far Green and the Chosen One are knocked back by a punch
    private var landT = [0, 0]             // how long each of them has been lying flat after landing
    private var flyV: [CGFloat] = [0, 0]   // how fast each of them is flying up from the big burp
    private let biteCount = 64   // a whole stack
    private let chocolateWidth: CGFloat = 220
    private var chocolateFull: CGFloat { max(120, min(300, bounds.height - ground - 110)) }   // as tall as the screen allows
    private var chocolateHeight: CGFloat { chocolateFull * (1 - CGFloat(bites) / CGFloat(biteCount)) }
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
            iconPulse = 0
            act = .rest
            actLeft = 0
            status = ""
        case .crewTop:
            crew.x = margin
            crew.facing = 1
            crew.alpha = 1
            crew.pose = Pose()
        case .eat:
            green.x = margin
            green.facing = 1
            chosen.x = w - margin
            chosen.facing = -1
            eatPhase = .walkIn
            bites = 0
            pt = 0
            iconPulse = 0
            crumbs = []
            flyV = [0, 0]
            landT = [0, 0]
            crew.alpha = 0
            crew.pose = Pose()
            crewStep = .spawn
            crewT = 0
            knock = [0, 0]
            shake = 0
            status = ""
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
        case .eat:
            eatStep()
            needsDisplay = true
            return
        case .crewTop:
            // He walks along the very top of the screen, and turns around at the edges.
            crew.x += crew.facing * 2.4
            crew.pose.phase += 0.17
            crew.pose.walk = 1
            crew.pose.hop = abs(sin(crew.pose.phase)) * 2
            if crew.x > bounds.width - margin { crew.facing = -1 }
            if crew.x < margin { crew.facing = 1 }
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

    // MARK: opening Minecraft

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

    /// Opens the real Minecraft launcher, once.
    private func launchMinecraft() {
        guard !launched else { return }
        launched = true
        let url = URL(fileURLWithPath: "/Applications/Minecraft.app")
        if FileManager.default.fileExists(atPath: url.path) { NSWorkspace.shared.open(url) }
    }

    private func playStep() {
        let cx = bounds.midX
        iconPulse = max(0, iconPulse - 0.08)
        switch playPhase {
        case .walkIn:
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
            if pt >= 60 {
                green.pose.punch = 0
                pt = 0
                playPhase = .cheer
            }

        case .cheer:
            // They cheer while the game opens.
            pt += 1
            for f in [green, chosen] {
                f.pose.cheer = true
                f.pose.phase += 0.25
                f.pose.hop = abs(sin(CGFloat(pt) * 0.16 + (f === chosen ? 1.5 : 0))) * 7
            }
            if pt >= 240 {
                pt = 0
                act = .rest
                actLeft = 0
                playPhase = .playing
            }

        case .playing:
            playTheGame()
        }
    }

    // MARK: really playing

    private func pointerPosition() -> CGPoint {
        let m = NSEvent.mouseLocation
        let screenHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGPoint(x: m.x, y: screenHeight - m.y)
    }

    private func setKey(_ code: CGKeyCode, _ down: Bool) {
        guard down != held.contains(code) else { return }
        if down { held.insert(code) } else { held.remove(code) }
        CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)?.post(tap: .cghidEventTap)
    }

    private func setMouseButton(_ down: Bool) {
        guard down != mouseIsDown else { return }
        mouseIsDown = down
        CGEvent(mouseEventSource: nil, mouseType: down ? .leftMouseDown : .leftMouseUp,
                mouseCursorPosition: pointerPosition(), mouseButton: .left)?.post(tap: .cghidEventTap)
    }

    private func look(dx: Int64) {
        let e = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                        mouseCursorPosition: pointerPosition(), mouseButton: .left)
        e?.setIntegerValueField(.mouseEventDeltaX, value: dx)
        e?.post(tap: .cghidEventTap)
    }

    /// Lets go of every key and the mouse button. Always called before they stop.
    func releaseAll() {
        for key in Array(held) { setKey(key, false) }
        setMouseButton(false)
    }

    /// Only the real game ever gets their key presses: it runs from Minecraft's own Java.
    private func minecraftIsInFront() -> Bool {
        guard let path = NSWorkspace.shared.frontmostApplication?.executableURL?.path else { return false }
        return path.contains("/minecraft/runtime/")
    }

    private func chooseAct() {
        var options: [Act] = [.walk, .walk, .leap, .look, .look, .rest]
        if clicksAllowed { options += [.dig, .dig] }
        act = options.randomElement() ?? .rest
        switch act {
        case .rest: actLeft = 60
        case .walk: actLeft = Int.random(in: 120...240)
        case .leap: actLeft = Int.random(in: 120...200)
        case .look: actLeft = Int.random(in: 40...100)
        case .dig: actLeft = Int.random(in: 90...160)
        case .crash: actLeft = 780
        }
        lookDir = Bool.random() ? 1 : -1
    }

    /// Green works the keyboard (walk, jump). The Chosen One works the mouse (look around, dig).
    private func playTheGame() {
        pt += 1
        mouseClick = max(0, mouseClick - 0.1)
        if pt % 30 == 1 {
            let t = AXIsProcessTrusted(), up = minecraftIsInFront()
            if t != trusted || up != minecraftIsUp || pt == 1 {
                FileHandle.standardError.write(Data("trusted=\(t) minecraftInFront=\(up) front=\(NSWorkspace.shared.frontmostApplication?.localizedName ?? "none")\n".utf8))
            }
            trusted = t
            minecraftIsUp = up
        }
        for f in [green, chosen] {
            f.pose.walk = 0
            f.pose.cheer = false
            f.pose.hop = 0
            f.pose.punch = 0
            f.pose.stance = 0
        }
        chosen.pose.punch = 0.3          // his arm is out, holding the mouse
        chosen.pose.punchArm = 1

        if !trusted {
            releaseAll()
            status = "A grown-up has to say yes first!"
            if !askedForKeys {
                askedForKeys = true
                // This shows the Mac's own "allow Green to control your computer?" box.
                _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
            }
            return
        }
        if !minecraftIsUp {
            releaseAll()
            upTicks = 0
            if act == .crash {
                // The game is gone. They did it!
                crashWanted = false
                act = .rest
                pt = 0
                playPhase = .cheer
                return
            }
            act = .rest
            actLeft = 0
            status = "Press Play in Minecraft, then open a world!"
            return
        }
        status = ""

        if crashWanted && act != .crash {
            upTicks += 1
            if upTicks > 300 {      // after a few seconds of playing, they go for it
                releaseAll()
                act = .crash
                actLeft = 780
            }
        }
        actLeft -= 1
        if actLeft <= 0 {
            releaseAll()
            if act == .crash {      // it did not crash. Stop trying.
                crashWanted = false
                upTicks = 0
            }
            chooseAct()
        }
        switch act {
        case .rest:
            break
        case .walk:
            setKey(keyW, true)
            walkTogether()
        case .leap:
            setKey(keyW, true)
            walkTogether()
            let beat = actLeft % 40
            setKey(keySpace, beat > 28)
            green.pose.hop = beat > 28 ? 14 : 0
        case .look:
            look(dx: lookDir * 7)
            mouseSlide = CGFloat(lookDir) * sin(CGFloat(pt) * 0.2) * 9
            chosen.pose.phase += 0.1
        case .crash:
            // Green holds F3, the Chosen One holds C, and they strain until the game gives up.
            setKey(keyF3, true)
            setKey(keyC, true)
            for f in [green, chosen] {
                f.pose.stance = 1
                f.pose.hop = CGFloat.random(in: 0...3)
            }
            status = "Breaking Minecraft..."
        case .dig:
            setMouseButton(clicksAllowed)
            mouseClick = 1
            chosen.pose.punch = 0.3 + 0.2 * abs(sin(CGFloat(pt) * 0.25))
        }
    }

    /// The little computer mouse the Chosen One holds.
    private func drawMouse() {
        let hand = NSPoint(x: chosen.x + chosen.facing * 33 + mouseSlide * chosen.facing, y: ground + 47)
        let body = NSBezierPath(roundedRect: NSRect(x: hand.x - 8, y: hand.y - 11, width: 16, height: 22), xRadius: 8, yRadius: 8)
        NSColor(calibratedWhite: 0.95, alpha: 1).setFill()
        body.fill()
        if mouseClick > 0 {
            NSColor(calibratedRed: 1, green: 0.85, blue: 0.1, alpha: mouseClick).setFill()
            NSBezierPath(roundedRect: NSRect(x: hand.x - 7, y: hand.y + 1, width: 14, height: 9), xRadius: 4, yRadius: 4).fill()
        }
        NSColor(calibratedWhite: 0.15, alpha: 1).setStroke()
        body.lineWidth = 2
        body.stroke()
        let line = NSBezierPath()
        line.lineWidth = 1.5
        line.move(to: NSPoint(x: hand.x - 8, y: hand.y + 1))
        line.line(to: NSPoint(x: hand.x + 8, y: hand.y + 1))
        line.move(to: NSPoint(x: hand.x, y: hand.y + 1))
        line.line(to: NSPoint(x: hand.x, y: hand.y + 11))
        line.stroke()
    }

    private func drawStatus() {
        let big = ["BURP", "WHEE", "THUMP", "BOW", "POW"].contains { status.contains($0) }   // burps are written big, and they shake
        let text = NSAttributedString(string: status, attributes: [
            .font: NSFont.boldSystemFont(ofSize: big ? 54 : 18),
            .foregroundColor: NSColor(calibratedWhite: 0.1, alpha: 1),
            .strokeColor: NSColor.white,
            .strokeWidth: -4,
        ])
        let size = text.size()
        let shake: CGFloat = big ? 4 : 0
        text.draw(at: NSPoint(x: bounds.midX - size.width / 2 + CGFloat.random(in: -shake...shake),
                              y: (mode == .eat ? ground + chocolateFull + 24 : ground + 130) + CGFloat.random(in: -shake...shake)))
    }

    // MARK: eating Minecraft

    private func eatStep() {
        let cx = bounds.midX
        let side = chocolateWidth / 2 + 14     // where they stand to climb: just outside the chocolate
        pt += 1
        iconPulse = max(0, iconPulse - 0.08)
        shake = shake < 0.4 ? 0 : shake * 0.94
        for i in crumbs.indices {
            crumbs[i].x += crumbs[i].vx
            crumbs[i].y += crumbs[i].vy
            crumbs[i].vy -= 0.15   // crumbs fall
            crumbs[i].life -= 1
        }
        crumbs.removeAll { $0.life <= 0 || $0.y < ground - 4 }
        for f in [green, chosen, crew] {
            f.pose.punch = 0
            f.pose.hop = 0
            f.pose.cheer = false
            f.pose.climb = 0
        }
        hit = max(0, hit - 0.06)
        for i in knock.indices { knock[i] = knock[i] < 0.02 ? 0 : knock[i] * 0.9 }
        // As the chocolate gets lower, they sink down with it.
        func settle() {
            for f in [green, chosen] { f.pose.lift += (chocolateHeight - f.pose.lift) * 0.12 }
        }

        switch eatPhase {
        case .walkIn:
            let a = approach(green, to: cx - side)
            let b = approach(chosen, to: cx + side)
            if a { green.facing = 1 }
            if b { chosen.facing = -1 }
            if a && b {
                pt = 0
                eatPhase = .climb
            }

        case .climb:
            // Hands and feet on the chocolate, all the way up.
            for f in [green, chosen] {
                f.pose.walk = 0
                f.pose.climb = 1
                f.pose.phase += 0.12
                f.pose.lift = min(chocolateHeight, f.pose.lift + 1.1)
            }
            if green.pose.lift >= chocolateHeight { eatPhase = .topWalk }

        case .topWalk:
            let a = approach(green, to: cx - chocolateWidth / 4)
            let b = approach(chosen, to: cx + chocolateWidth / 4)
            if a { green.facing = 1 }
            if b { chosen.facing = -1 }
            if a && b {
                pt = 0
                crewStep = .spawn
                eatPhase = .crewVisit
            }

        case .crewVisit:
            crewVisit(cx: cx, side: side)

        case .munch:
            // They take turns: grab, bite, chew. 64 bites and the chocolate Minecraft is gone.
            settle()
            green.pose.walk = 0
            chosen.pose.walk = 0
            let slot = pt / 30, beat = pt % 30
            if slot >= biteCount {
                pt = 0
                eatPhase = .burp
                return
            }
            let eater = slot % 2 == 0 ? green : chosen
            eater.pose.punch = sin(.pi * CGFloat(beat) / 30)
            if beat == 15 {
                let top = ground + 4 + chocolateHeight
                bites += 1
                status = ["Nom!", "Chomp!", "Yum!"].randomElement() ?? "Nom!"
                NSSound(named: NSSound.Name("Pop"))?.play()
                for _ in 0..<16 {
                    let color = Bool.random() ? NSColor(calibratedRed: 0.33, green: 0.17, blue: 0.08, alpha: 1)
                                              : NSColor(calibratedRed: 0.45, green: 0.25, blue: 0.12, alpha: 1)
                    crumbs.append(Crumb(x: eater.x + eater.facing * CGFloat.random(in: 0...50), y: top + CGFloat.random(in: 0...10),
                                        vx: CGFloat.random(in: -1.5...1.5), vy: CGFloat.random(in: 1...3.5),
                                        life: Int.random(in: 25...45), color: color))
                }
            }
            if beat > 15 { eater.pose.hop = abs(sin(CGFloat(beat) * 0.5)) * 4 }   // chewing
            if beat == 28 { status = "" }

        case .burp:
            // Full tummies. The second burp is so big it blows them into the air.
            if pt < 100 { settle() }
            if pt == 1 { status = "So yummy!" }
            if pt == 40 {
                status = "BURP!"
                burp(pitch: 95, seconds: 0.9)
            }
            if pt == 100 {
                status = "BURRRRP!!"
                burp(pitch: 70, seconds: 1.5)
                flyV = [15, 12]
            }
            if (40..<80).contains(pt) { shake = max(shake, 5) }     // the burps rumble
            if (100..<130).contains(pt) { shake = max(shake, 9) }
            if pt == 130 { status = "WHEEEE!" }
            if pt >= 100 {
                for (i, f) in [green, chosen].enumerated() where f.pose.lift > 0 || flyV[i] > 0 {
                    f.pose.lift += flyV[i]
                    flyV[i] -= 0.35                        // and gravity pulls them back
                    if f.pose.lift <= 0 {
                        f.pose.lift = 0
                        flyV[i] = 0
                        thump(at: f, index: i)
                    }
                    f.pose.cheer = true
                    f.pose.walk = 0
                    f.pose.phase += 0.4                    // arms flapping
                    f.x = min(max(f.x + (i == 0 ? -0.8 : 0.8), margin), bounds.width - margin)
                }
            }
            for f in [green, chosen] {
                f.pose.hop = abs(sin(CGFloat(pt) * 0.2 + (f === chosen ? 1 : 0))) * 4
                // They shake with every burp.
                if (40..<80).contains(pt) { f.pose.hop += CGFloat.random(in: 0...7) }
            }
            // After the landing they lie flat for a moment, then get up.
            for (i, f) in [green, chosen].enumerated() where landT[i] > 0 && f.pose.lift == 0 && flyV[i] == 0 {
                landT[i] -= 1
                f.pose.fall = (.pi / 2) * min(1, CGFloat(landT[i]) / 14)
                f.pose.cheer = false
                f.pose.hop = 0
            }
            if pt >= 270 {
                pt = 0
                status = ""
                eatPhase = .gone
            }

        case .gone:
            // They walk out from where the chocolate was. Then a brand new one appears, and up they go again.
            settle()
            let a = approach(green, to: cx - side)
            let b = approach(chosen, to: cx + side)
            if a { green.facing = 1 }
            if b { chosen.facing = -1 }
            if a && b && pt >= 90 {
                for f in [green, chosen] { f.pose.lift = 0 }
                bites = 0
                iconPulse = 1
                pt = 0
                eatPhase = .climb
            }
        }
    }

    /// The red crewmate pops in, climbs the chocolate, punches the Chosen One and then Green, and walks off the screen.
    private func crewVisit(cx: CGFloat, side: CGFloat) {
        crew.pose.walk = 0
        // A punch lands: a burst, a loud word, and the one who got hit tips over backwards.
        func landPunch(on victim: Figure, index: Int, word: String) {
            knock[index] = 1
            status = word
            shake = 7
            hit = 1
            hitPoint = NSPoint(x: victim.x, y: ground + victim.pose.lift + 60)
            NSSound(named: NSSound.Name("Funk"))?.play()
        }
        crewT += 1
        switch crewStep {
        case .spawn:
            crew.x = cx + side + 90
            crew.facing = -1
            crew.alpha = 1
            crew.pose = Pose()
            NSSound(named: NSSound.Name("Pop"))?.play()
            for _ in 0..<16 {   // a puff where he pops in
                let shade = CGFloat.random(in: 0.85...1)
                crumbs.append(Crumb(x: crew.x + CGFloat.random(in: -20...20), y: ground + CGFloat.random(in: 5...50),
                                    vx: CGFloat.random(in: -1.5...1.5), vy: CGFloat.random(in: 0...1.5),
                                    life: Int.random(in: 20...35),
                                    color: NSColor(calibratedWhite: shade, alpha: 1)))
            }
            crewStep = .run

        case .run:
            if approach(crew, to: cx + side) { crewStep = .climb }

        case .climb:
            // Up the side of the chocolate, legs running.
            crew.facing = -1
            crew.pose.walk = 1
            crew.pose.climb = 1
            crew.pose.phase += 0.3
            crew.pose.lift = min(chocolateHeight, crew.pose.lift + 1.6)
            crew.pose.hop = abs(sin(crew.pose.phase)) * 3
            if crew.pose.lift >= chocolateHeight { crewStep = .cross }

        case .cross:
            // Along the top, to stand between them.
            if approach(crew, to: cx) {
                crew.facing = 1
                crewT = 0
                crewStep = .hitChosen
            }

        case .hitChosen:
            if crewT <= 24 { crew.pose.punch = sin(.pi * CGFloat(crewT) / 24) }
            if crewT == 12 { landPunch(on: chosen, index: 1, word: "BOW!") }
            if crewT >= 40 {
                crew.facing = -1
                crewT = 0
                crewStep = .hitGreen
            }

        case .hitGreen:
            if crewT <= 24 { crew.pose.punch = sin(.pi * CGFloat(crewT) / 24) }
            if crewT == 12 { landPunch(on: green, index: 0, word: "POW!") }
            if crewT >= 40 {
                status = "Done!"
                crewStep = .goBack
            }

        case .goBack:
            if approach(crew, to: cx + side) {
                status = ""
                crewStep = .descend
            }

        case .descend:
            // Back down the side.
            crew.facing = -1
            crew.pose.walk = 1
            crew.pose.climb = 1
            crew.pose.phase += 0.3
            crew.pose.lift = max(0, crew.pose.lift - 2.2)
            crew.pose.hop = abs(sin(crew.pose.phase)) * 3
            if crew.pose.lift <= 0 { crewStep = .leave }

        case .leave:
            // Right off the side of the screen.
            crew.facing = 1
            crew.x += 3.2
            crew.pose.phase += 0.2
            crew.pose.walk = 1
            if crew.x > bounds.width + 60 {
                crew.alpha = 0
                knock = [0, 0]
                green.pose.fall = 0
                chosen.pose.fall = 0
                status = ""
                pt = 0
                crewStep = .spawn
                eatPhase = .munch
            }
        }
        // The two who got punched tip over backwards, then stand back up.
        green.pose.fall = knock[0] * 0.7
        chosen.pose.fall = knock[1] * 0.7
    }

    /// The landing: a loud thump, a puff of dust, and they lie flat.
    private func thump(at f: Figure, index: Int) {
        landT[index] = 50
        shake = 22
        status = "THUMP!"
        let sound = NSSound(data: makeThump())
        sound?.volume = 1
        sound?.play()
        for _ in 0..<14 {
            let shade = CGFloat.random(in: 0.5...0.75)
            crumbs.append(Crumb(x: f.x + CGFloat.random(in: -22...22), y: ground + 2,
                                vx: CGFloat.random(in: -2.2...2.2), vy: CGFloat.random(in: 0.5...2.2),
                                life: Int.random(in: 20...34),
                                color: NSColor(calibratedRed: shade, green: shade * 0.95, blue: shade * 0.85, alpha: 1)))
        }
    }

    /// Plays a burp, twice on top of itself so it is extra loud.
    private func burp(pitch: Double, seconds: Double) {
        let data = makeBurp(seconds: seconds, pitch: pitch)
        for _ in 0..<2 {
            let sound = NSSound(data: data)
            sound?.volume = 1
            sound?.play()
        }
    }

    private func drawCrumbs() {
        for c in crumbs {
            c.color.setFill()
            NSRect(x: c.x - 2, y: c.y - 2, width: 4, height: 4).fill()
        }
    }

    /// A giant bar of chocolate with Minecraft on the wrapper. It gets lower with every bite.
    private func drawChocolate() {
        let h = chocolateHeight
        guard h > 1 else { return }
        let w = chocolateWidth
        let rect = NSRect(x: bounds.midX - w / 2, y: ground + 4, width: w, height: h)
        let body = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
        NSColor(calibratedRed: 0.33, green: 0.17, blue: 0.08, alpha: 1).setFill()
        body.fill()

        // Squares of chocolate, each with a shiny corner.
        NSGraphicsContext.saveGraphicsState()
        body.addClip()
        let cell = w / 4
        var y = rect.minY
        while y < rect.maxY {
            for col in 0..<4 {
                let square = NSRect(x: rect.minX + CGFloat(col) * cell, y: y, width: cell, height: cell).insetBy(dx: 3, dy: 3)
                NSColor(calibratedRed: 0.43, green: 0.23, blue: 0.11, alpha: 1).setFill()
                NSBezierPath(roundedRect: square, xRadius: 4, yRadius: 4).fill()
                NSColor(calibratedWhite: 1, alpha: 0.22).setFill()
                NSBezierPath(ovalIn: NSRect(x: square.minX + 5, y: square.maxY - 13, width: 10, height: 6)).fill()
            }
            y += cell
        }
        NSGraphicsContext.restoreGraphicsState()
        NSColor(calibratedWhite: 0.1, alpha: 0.7).setStroke()
        body.lineWidth = 3
        body.stroke()

        // Chewed edge: bites out of the top.
        if bites > 0 {
            let offsets: [CGFloat] = [-70, -25, 30, 75, -45, 55]
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current?.compositingOperation = .clear
            for k in 0..<3 {
                let r = w / 9
                NSBezierPath(ovalIn: NSRect(x: rect.midX + offsets[(bites + k * 2) % 6] - r, y: rect.maxY - r * 0.6,
                                            width: r * 2, height: r * 2)).fill()
            }
            NSGraphicsContext.restoreGraphicsState()
        }

        if h > chocolateFull * 0.3 {
            let label = NSAttributedString(string: "Minecraft", attributes: [
                .font: NSFont.boldSystemFont(ofSize: 24),
                .foregroundColor: NSColor(calibratedWhite: 1, alpha: 1),
                .strokeColor: NSColor(calibratedWhite: 0.1, alpha: 1),
                .strokeWidth: -4,
            ])
            let size = label.size()
            label.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.minY + chocolateFull * 0.12))
        }
    }

    /// The Minecraft icon: a little grass block with its name on top.
    private func drawIcon() {
        let c = iconCenter
        let size: CGFloat = 44 * (1 + 0.18 * iconPulse)
        let rect = NSRect(x: c.x - size / 2, y: c.y - size / 2, width: size, height: size)
        let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        NSColor(calibratedRed: 0.55, green: 0.38, blue: 0.22, alpha: 1).setFill()
        path.fill()
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        NSColor(calibratedRed: 0.30, green: 0.65, blue: 0.20, alpha: 1).setFill()
        NSRect(x: rect.minX, y: rect.maxY - size * 0.32, width: size, height: size * 0.32).fill()
        NSGraphicsContext.restoreGraphicsState()
        NSColor(calibratedWhite: 0.1, alpha: 0.6).setStroke()
        path.lineWidth = 2
        path.stroke()
        let label = NSAttributedString(string: "Minecraft", attributes: [
            .font: NSFont.boldSystemFont(ofSize: 11),
            .foregroundColor: NSColor(calibratedWhite: 0.1, alpha: 1),
            .strokeColor: NSColor.white,
            .strokeWidth: -2,
        ])
        let labelSize = label.size()
        label.draw(at: NSPoint(x: c.x - labelSize.width / 2, y: rect.maxY + 4))
    }

    // MARK: drawing

    override func draw(_ dirtyRect: NSRect) {
        dirtyRect.fill(using: .clear)

        // Everything they draw shakes. (Other windows on the Mac can't be shaken from here.)
        NSGraphicsContext.saveGraphicsState()
        if shake > 0 {
            let move = NSAffineTransform()
            move.translateX(by: CGFloat.random(in: -shake...shake), yBy: CGFloat.random(in: -shake...shake))
            move.concat()
        }
        defer { NSGraphicsContext.restoreGraphicsState() }

        if mode == .play, playPhase != .playing { drawIcon() }
        if mode == .eat { drawChocolate() }
        if mode == .eat { drawCrumbs() }
        if green.alpha > 0, mode != .crewTop { draw(green) }
        if mode != .crewTop, mode != .fight || scene == .approach || scene == .fight || scene == .aftermath { draw(chosen) }
        if mode == .eat || mode == .crewTop, crew.alpha > 0 { draw(crew) }
        if mode == .play, playPhase == .cheer || playPhase == .playing { drawMouse() }
        if mode == .play || mode == .eat, !status.isEmpty { drawStatus() }
        if hit > 0 { drawBurst(at: hitPoint, size: hit) }
        drawSparks()
    }

    /// The red Among Us crewmate: a bean with a little backpack and a shiny blue visor.
    private func drawCrewmate(_ f: Figure) {
        let p = f.pose
        let ground = mode == .crewTop ? bounds.height - 90 : self.ground   // up at the top of the screen, or on the ground
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let move = NSAffineTransform()
        move.translateX(by: f.x + f.facing * p.punch * 16, yBy: ground + p.lift + p.hop + sin(p.fall) * 20)
        // Falling flat tips him over backwards. Cheering makes him wiggle.
        move.rotate(byRadians: f.facing * p.fall + (p.cheer ? sin(p.phase * 2) * 0.15 : 0))
        move.scaleX(by: f.facing, yBy: 1)
        move.concat()

        let red = NSColor(calibratedRed: 0.77, green: 0.07, blue: 0.07, alpha: f.alpha)
        let dark = NSColor(calibratedRed: 0.55, green: 0.04, blue: 0.05, alpha: f.alpha)
        let edge = NSColor(calibratedWhite: 0.1, alpha: f.alpha)
        func fillAndEdge(_ path: NSBezierPath, _ fill: NSColor) {
            fill.setFill()
            path.fill()
            edge.setStroke()
            path.lineWidth = 3
            path.stroke()
        }

        let swing = sin(p.phase) * p.walk
        // Hands! One arm in front, one behind. They swing when he walks, reach up when he climbs or cheers, and punch.
        func hand(_ side: CGFloat) -> NSPoint {
            var x = side * 28 + swing * side * 9, y: CGFloat = 28    // out at his sides, where you can see them
            if p.climb > 0 { x = 16; y = 64 + sin(side == 1 ? p.phase : p.phase + .pi) * 6 }
            if p.cheer { x = 12 + side * 8; y = 74 + sin(p.phase * 2 + side) * 3 }
            if side == 1 && p.punch > 0 { x = 18 + 30 * p.punch; y = 40 }
            return NSPoint(x: x, y: y)
        }
        func arm(_ side: CGFloat, _ color: NSColor) {
            let h = hand(side)
            let limb = NSBezierPath()
            limb.lineCapStyle = .round
            limb.move(to: NSPoint(x: side * 14, y: 32))
            limb.line(to: h)
            edge.setStroke()
            limb.lineWidth = 13
            limb.stroke()
            color.setStroke()
            limb.lineWidth = 7
            limb.stroke()
        }
        fillAndEdge(NSBezierPath(roundedRect: NSRect(x: -31, y: 22, width: 14, height: 26), xRadius: 6, yRadius: 6), dark)   // backpack
        arm(-1, dark)   // the far arm, behind him
        // legs
        for (i, left) in [-22.0, 4.0].enumerated() {
            let lift = max(0, (i == 0 ? swing : -swing)) * 6
            fillAndEdge(NSBezierPath(roundedRect: NSRect(x: left, y: lift, width: 18, height: 24), xRadius: 7, yRadius: 7), red)
        }
        let bean = NSBezierPath(roundedRect: NSRect(x: -22, y: 14, width: 44, height: 50), xRadius: 22, yRadius: 22)
        fillAndEdge(bean, red)
        // a darker shadow down the back and along the bottom, like the real one
        NSGraphicsContext.saveGraphicsState()
        bean.addClip()
        dark.setFill()
        NSBezierPath(ovalIn: NSRect(x: -44, y: -2, width: 52, height: 50)).fill()
        NSGraphicsContext.restoreGraphicsState()
        edge.setStroke()
        bean.lineWidth = 3
        bean.stroke()
        // visor: big and shiny, with a light shine at the top and a darker blue below
        let visor = NSBezierPath(roundedRect: NSRect(x: -2, y: 36, width: 30, height: 21), xRadius: 10, yRadius: 10)
        fillAndEdge(visor, NSColor(calibratedRed: 0.55, green: 0.80, blue: 0.93, alpha: f.alpha))
        NSGraphicsContext.saveGraphicsState()
        visor.addClip()
        NSColor(calibratedRed: 0.30, green: 0.55, blue: 0.75, alpha: f.alpha).setFill()
        NSBezierPath(ovalIn: NSRect(x: -10, y: 26, width: 50, height: 16)).fill()
        NSGraphicsContext.restoreGraphicsState()
        edge.setStroke()
        visor.lineWidth = 3
        visor.stroke()
        NSColor(calibratedWhite: 1, alpha: 0.85 * f.alpha).setFill()
        NSBezierPath(roundedRect: NSRect(x: 8, y: 48, width: 14, height: 5), xRadius: 2.5, yRadius: 2.5).fill()
        arm(1, red)     // the near arm, in front

        // the name, while standing up (drawn upright, so undo the flip)
        if p.fall == 0 {
            move.invert()
            move.concat()
            let label = NSAttributedString(string: f.name, attributes: [
                .font: NSFont.boldSystemFont(ofSize: 11),
                .foregroundColor: red,
            ])
            let size = label.size()
            label.draw(at: NSPoint(x: f.x - size.width / 2, y: ground + p.lift + p.hop + 70))
        }
    }

    private func draw(_ f: Figure) {
        if f.isCrewmate { drawCrewmate(f); return }
        let p = f.pose
        let c = cos(p.fall), s = sin(p.fall)

        // Places a point given as (forward, up) from the figure's feet. A fall turns it over backwards.
        func at(_ forward: CGFloat, _ up: CGFloat) -> NSPoint {
            let u = up + p.hop
            return NSPoint(x: f.x + f.facing * (forward * c - u * s), y: ground + p.lift + sin(p.fall) * 9 + forward * s + u * c)
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
            if p.climb > 0 {
                footX = 7
                footY = max(0, 6 + sin(side == 1 ? p.phase : p.phase + .pi) * 8)
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
            if p.climb > 0 {
                handX = 8
                handY = shoulderY + 14 + sin(side == 1 ? p.phase : p.phase + .pi) * 12
            }
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

    @objc func toggleClicks(_ sender: NSMenuItem) {
        view.clicksAllowed.toggle()
        sender.state = view.clicksAllowed ? .on : .off
    }

    @objc func crashIt(_ sender: NSMenuItem) {
        view.crashWanted = true
    }

    func applicationWillTerminate(_ notification: Notification) {
        view.releaseAll()   // never leave a key or the mouse button stuck down in the game
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
        // `open Green.app --args play` starts them off opening Minecraft.
        if CommandLine.arguments.contains("dig") { view.clicksAllowed = true }   // `--args play dig` also lets them break blocks
        if CommandLine.arguments.contains("crew") { view.mode = .crewTop }     // `--args crew`
        if CommandLine.arguments.contains("eat") { view.mode = .eat }          // `--args eat`
        if CommandLine.arguments.contains("crash") { view.crashWanted = true }   // `--args play crash`
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
            ("Open Minecraft", .play),
            ("Eat Minecraft", .eat),
            ("Crewmate on top", .crewTop),
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
        let clicks = NSMenuItem(title: "Let them click (only inside a world)", action: #selector(toggleClicks(_:)), keyEquivalent: "")
        clicks.target = self
        clicks.state = view.clicksAllowed ? .on : .off
        menu.addItem(clicks)
        let crash = NSMenuItem(title: "Crash Minecraft", action: #selector(crashIt(_:)), keyEquivalent: "")
        crash.target = self
        menu.addItem(crash)
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
