import AppKit
import CoreGraphics

// Window coordinates from Quartz have their origin at the top left of the main display.
struct Anchor {
    let window: CGWindowID
    let pid: pid_t
    let offset: CGPoint
    func center(in bounds: CGRect) -> CGPoint {
        CGPoint(x: bounds.minX + offset.x, y: bounds.minY + offset.y)
    }
    func near(_ point: CGPoint, bounds: CGRect) -> Bool {
        let c = center(in: bounds)
        return hypot(point.x - c.x, point.y - c.y) <= 90
    }
}

struct Window {
    let id: CGWindowID
    let pid: pid_t
    let bounds: CGRect
    init?(_ info: [String: Any]) {
        guard let id = info[kCGWindowNumber as String] as? UInt32,
              let pid = info[kCGWindowOwnerPID as String] as? Int32,
              let box = info[kCGWindowBounds as String] as? NSDictionary,
              let bounds = CGRect(dictionaryRepresentation: box),
              (info[kCGWindowAlpha as String] as? Double ?? 1) > 0 else { return nil }
        self.id = id
        self.pid = pid
        self.bounds = bounds
    }
}

final class WandView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let line = NSBezierPath()
        line.move(to: NSPoint(x: 5, y: 14))
        line.curve(to: NSPoint(x: 23, y: 35), controlPoint1: NSPoint(x: 14,y: 7), controlPoint2: NSPoint(x: 15,y: 31))
        NSColor(calibratedWhite: 0.22, alpha: 1).setStroke()
        line.lineWidth = 2
        line.stroke()
        let stick = NSBezierPath()
        stick.move(to: NSPoint(x: 23,y: 35))
        stick.line(to: NSPoint(x: 49,y: 6))
        stick.lineCapStyle = .round
        stick.lineWidth = 5
        NSColor(calibratedRed: 0.44, green: 0.22, blue: 0.13, alpha: 1).setStroke()
        stick.stroke()
        stick.lineWidth = 2
        NSColor(calibratedRed: 1, green: 0.74, blue: 0.44, alpha: 1).setStroke()
        stick.stroke()
        let feather = NSBezierPath()
        feather.move(to: NSPoint(x: 5,y: 14))
        feather.curve(to: NSPoint(x: 12,y: 2), controlPoint1: NSPoint(x: 2,y: 8), controlPoint2: NSPoint(x: 5,y: 3))
        feather.curve(to: NSPoint(x: 5,y: 14), controlPoint1: NSPoint(x: 15,y: 9), controlPoint2: NSPoint(x: 10,y: 15))
        feather.close()
        NSColor.systemPink.setFill()
        feather.fill()
    }
}

final class Wand: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let panel = NSPanel(contentRect: CGRect(x: 0,y: 0,width: 54,height: 42),
                                styleMask: [.borderless,.nonactivatingPanel], backing: .buffered, defer: false)
    private var anchor: Anchor?
    private var hidden = false
    private var menuOpen = false
    private var windows: [Window] = []
    private var refreshed: TimeInterval = 0
    private var timer: Timer?
    private var calibration: Timer?
    private let status = NSMenuItem(title: "请选择定位，然后指向猫咪", action: nil, keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary,.ignoresCycle]
        panel.contentView = WandView(frame: panel.contentRect(forFrameRect: panel.frame))
        item.button?.title = "🪶"
        item.button?.toolTip = "猫咪逗猫棒"
        let menu = NSMenu()
        menu.autoenablesItems = false
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(withTitle: "3 秒后定位猫咪", action: #selector(calibrate), keyEquivalent: "").target = self
        menu.addItem(withTitle: "退出逗猫棒", action: #selector(stop), keyEquivalent: "").target = self
        menu.delegate = self
        item.menu = menu
        let tick = Timer(timeInterval: 1.0/45.0, repeats: true) { [weak self] _ in self?.update() }
        RunLoop.main.add(tick, forMode: .common)
        timer = tick
    }

    func menuWillOpen(_ menu: NSMenu) { menuOpen = true; restore() }
    func menuDidClose(_ menu: NSMenu) { menuOpen = false }
    @objc func stop() { restore(); NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) { restore() }
    private func refresh() {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly,.excludeDesktopElements], kCGNullWindowID)
        windows = ((list as? [[String: Any]]) ?? []).compactMap(Window.init)
        refreshed = ProcessInfo.processInfo.systemUptime
    }
    private func isPetHost(_ w: Window) -> Bool {
        let bundle = NSRunningApplication(processIdentifier: w.pid)?.bundleIdentifier ?? ""
        return ["com.openai.codex","com.openai.chat","com.openai.chatgpt"].contains(bundle.lowercased())
    }
    private func front(at point: CGPoint) -> Window? {
        windows.first { $0.pid != ProcessInfo.processInfo.processIdentifier && $0.bounds.contains(point) }
    }
    @objc func calibrate() {
        restore()
        anchor = nil
        calibration?.invalidate()
        item.button?.title = "🪶…"
        calibration = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.item.button?.title = "🪶"
            self.refresh()
            guard let p = CGEvent(source: nil)?.location, let w = self.front(at: p), self.isPetHost(w) else {
                self.status.title = "未找到宠物窗口，请重新定位"
                return
            }
            self.anchor = Anchor(window: w.id, pid: w.pid, offset: CGPoint(x: p.x-w.bounds.minX,y: p.y-w.bounds.minY))
            self.status.title = "已定位 · 靠近猫咪即可玩耍"
        }
    }
    private func restore() {
        if hidden { CGDisplayShowCursor(CGMainDisplayID()); hidden = false }
        if panel.isVisible { panel.orderOut(nil) }
    }
    private func update() {
        guard !menuOpen, let a = anchor, let p = CGEvent(source: nil)?.location else { restore(); return }
        if ProcessInfo.processInfo.systemUptime - refreshed > 0.10 { refresh() }
        guard let w = windows.first(where: { $0.id == a.window && $0.pid == a.pid }),
              a.near(p, bounds: w.bounds), front(at: a.center(in: w.bounds))?.id == w.id else { restore(); return }
        let mouse = NSEvent.mouseLocation
        panel.setFrameOrigin(NSPoint(x: mouse.x-5,y: mouse.y-14))
        if !panel.isVisible { panel.orderFrontRegardless() }
        if !hidden { hidden = CGDisplayHideCursor(CGMainDisplayID()) == .success }
    }
}

if CommandLine.arguments.contains("--self-test") {
    let a = Anchor(window: 1, pid: 1, offset: CGPoint(x: 25,y: 20))
    let w = CGRect(x: -230,y: 80,width: 100,height: 80)
    precondition(a.near(CGPoint(x: -205,y: 100), bounds: w))
    precondition(!a.near(CGPoint(x: -100,y: 100), bounds: w))
    precondition(a.center(in: w.offsetBy(dx: 15,dy: 50)) == CGPoint(x: -190,y: 150))
    print("OK: proximity, retreat, and tracking a moved window")
} else {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let delegate = Wand()
    app.delegate = delegate
    app.run()
}
