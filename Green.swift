// Green: a green stick figure who walks along the bottom of your screen.
// He floats above everything and never gets in the way of your mouse.
import Cocoa

final class GreenView: NSView {
    private var x: CGFloat = 200
    private var direction: CGFloat = 1
    private var phase: CGFloat = 0
    private let speed: CGFloat = 2.2
    private let color = NSColor(calibratedRed: 0.10, green: 0.85, blue: 0.20, alpha: 1)

    override var isFlipped: Bool { false }

    func step() {
        x += direction * speed
        phase += 0.16
        let margin: CGFloat = 40
        if x > bounds.width - margin { direction = -1 }
        if x < margin { direction = 1 }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.set()
        dirtyRect.fill()

        let ground: CGFloat = 6
        let hip = NSPoint(x: x, y: ground + 34)
        let neck = NSPoint(x: x, y: hip.y + 34)
        let headRadius: CGFloat = 13
        let headCenter = NSPoint(x: x, y: neck.y + headRadius)

        color.setStroke()
        let path = NSBezierPath()
        path.lineWidth = 5
        path.lineCapStyle = .round

        // body
        path.move(to: hip)
        path.line(to: neck)

        // legs swing against each other
        let swing = sin(phase)
        let legReach: CGFloat = 16
        for side: CGFloat in [1, -1] {
            let lift = max(0, sin(side == 1 ? phase : phase + .pi)) * 4
            let foot = NSPoint(x: hip.x + swing * side * legReach * direction, y: ground + lift)
            path.move(to: hip)
            path.line(to: foot)
        }

        // arms swing the other way
        let shoulder = NSPoint(x: x, y: neck.y - 6)
        for side: CGFloat in [1, -1] {
            let hand = NSPoint(x: shoulder.x - swing * side * 13 * direction, y: shoulder.y - 20)
            path.move(to: shoulder)
            path.line(to: hand)
        }
        path.stroke()

        // head: an empty circle, no face
        let head = NSBezierPath(ovalIn: NSRect(x: headCenter.x - headRadius, y: headCenter.y - headRadius,
                                               width: headRadius * 2, height: headRadius * 2))
        head.lineWidth = 5
        head.stroke()

        // his name
        let name = NSAttributedString(string: "Green", attributes: [
            .font: NSFont.boldSystemFont(ofSize: 11),
            .foregroundColor: color,
        ])
        let size = name.size()
        name.draw(at: NSPoint(x: x - size.width / 2, y: headCenter.y + headRadius + 4))
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var view: GreenView!
    var timer: Timer?
    var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let screen = NSScreen.main else { return }
        let area = screen.visibleFrame
        let frame = NSRect(x: area.minX, y: area.minY, width: area.width, height: 110)

        window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .floating
        window.ignoresMouseEvents = true   // the mouse goes straight through him
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        view = GreenView(frame: NSRect(origin: .zero, size: frame.size))
        window.contentView = view
        window.orderFrontRegardless()

        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.view.step()
        }

        // A little "Green" in the menu bar, so there is always a way to say goodbye to him.
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "Green"
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quit Green", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // no Dock icon
let delegate = AppDelegate()
app.delegate = delegate
app.run()
