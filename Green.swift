// Green: a green stick figure who walks along the bottom of your screen.
// Every so often the Chosen One (the black stick figure) walks in, they fight, and Green loses.
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

final class StageView: NSView {
    enum Scene { case solo, approach, fight, aftermath, gap }

    private let margin: CGFloat = 40
    private let fightLength = 240
    private var ground: CGFloat { mode == .fight ? 6 : bounds.height / 2 - 50 }

    enum Mode {
        case stand   // both stand in the middle of the screen
        case walk    // both walk together back and forth across the middle
        case fight   // Green walks along the bottom, and the Chosen One comes and beats him
    }

    var mode = Mode.walk {
        didSet { reset() }
    }

    private let green = Figure(x: 200, facing: 1,
                               color: NSColor(calibratedRed: 0.10, green: 0.85, blue: 0.20, alpha: 1),
                               name: "Green")
    private let chosen = Figure(x: -100, facing: 1, color: .black,
                                halo: NSColor(calibratedWhite: 1, alpha: 0.9), name: "The Chosen One")

    private var scene = Scene.solo
    private var soloLeft = Int.random(in: 480...900)   // 8 to 15 seconds of Green alone
    private var t = 0                                  // ticks into the current scene
    private var originFacing: CGFloat = 1              // which way the Chosen One walks home
    private var greenBase: CGFloat = 0
    private var chosenBase: CGFloat = 0
    private var greenKnock: CGFloat = 0
    private var chosenKnock: CGFloat = 0
    private var hit: CGFloat = 0                       // how big the "pow" is right now
    private var hitPoint = NSPoint.zero

    override var isFlipped: Bool { false }

    // MARK: story

    private func reset() {
        let w = bounds.width
        green.alpha = 1
        green.pose = Pose()
        chosen.alpha = 1
        chosen.pose = Pose()
        hit = 0
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
            green.x = 200
            green.facing = 1
            soloLeft = Int.random(in: 480...900)
            t = 0
            scene = .solo
        }
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        if mode != .fight { reset() }
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
        case .fight: break
        }
        let w = bounds.width
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

        // The Chosen One: punch, punch, kick, and a big kick at the end.
        let cycle = t / 30
        let frac = CGFloat(t % 30) / 30
        let swing = sin(.pi * frac)
        chosen.pose.punch = 0
        chosen.pose.kick = 0
        if t >= 210 {
            chosen.pose.kick = swing
        } else if cycle % 3 == 2 {
            chosen.pose.kick = swing
        } else {
            chosen.pose.punchArm = cycle % 3 == 0 ? 1 : -1
            chosen.pose.punch = swing
        }
        let landed = swing > 0.75
        if landed {
            hit = 1
            hitPoint = NSPoint(x: (green.x + chosen.x) / 2, y: ground + (chosen.pose.kick > 0 ? 40 : 62))
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

    private func bringBackGreen(width w: CGFloat) {
        let side: CGFloat = Bool.random() ? 1 : -1
        green.x = side > 0 ? margin : w - margin
        green.facing = side
        green.pose = Pose()
        green.alpha = 1
        soloLeft = Int.random(in: 480...900)
        t = 0
        scene = .solo
    }

    // MARK: drawing

    override func draw(_ dirtyRect: NSRect) {
        dirtyRect.fill(using: .clear)

        if green.alpha > 0 { draw(green) }
        if mode != .fight || scene == .approach || scene == .fight || scene == .aftermath { draw(chosen) }
        if hit > 0 { drawBurst(at: hitPoint, size: hit) }
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
            ("Walk together", .walk),
            ("Stand in the middle", .stand),
            ("Walk and fight", .fight),
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
