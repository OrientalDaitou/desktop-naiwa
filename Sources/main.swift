// 桌面奶蛙 —— Desktop Goose 风格的桌面恶搞小程序，主角是奶蛙。
// 素材：sandytruant/codex-pet-naiwa（MIT License）。
import AppKit

// MARK: - 设置

enum Frequency: Int, CaseIterable {
    case low, normal, high, crazy

    var title: String {
        switch self {
        case .low: return "佛系（约 2 分钟一次）"
        case .normal: return "正常（约 1 分钟一次）"
        case .high: return "捣蛋（约 15 秒一次）"
        case .crazy: return "疯狂（约 5 秒一次）"
        }
    }

    /// 两次恶搞之间的平均间隔（秒）
    var interval: Double {
        switch self {
        case .low: return 120
        case .normal: return 60
        case .high: return 15
        case .crazy: return 5
        }
    }
}

final class Settings {
    static let shared = Settings()
    private let d = UserDefaults.standard

    init() {
        d.register(defaults: [
            "frequency": Frequency.normal.rawValue,
            "grabCursor": true, "notes": true, "memes": true,
            "footprints": true, "sound": true, "scale": 0.6,
        ])
    }

    var frequency: Frequency {
        get { Frequency(rawValue: d.integer(forKey: "frequency")) ?? .normal }
        set { d.set(newValue.rawValue, forKey: "frequency") }
    }
    var grabCursor: Bool { get { d.bool(forKey: "grabCursor") } set { d.set(newValue, forKey: "grabCursor") } }
    var notes: Bool { get { d.bool(forKey: "notes") } set { d.set(newValue, forKey: "notes") } }
    var memes: Bool { get { d.bool(forKey: "memes") } set { d.set(newValue, forKey: "memes") } }
    var footprints: Bool { get { d.bool(forKey: "footprints") } set { d.set(newValue, forKey: "footprints") } }
    var sound: Bool { get { d.bool(forKey: "sound") } set { d.set(newValue, forKey: "sound") } }
    var scale: CGFloat { get { CGFloat(d.double(forKey: "scale")) } set { d.set(Double(newValue), forKey: "scale") } }
}

// MARK: - 工具函数

func now() -> Double { CACurrentMediaTime() }
func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }
func rand(_ r: ClosedRange<Double>) -> Double { Double.random(in: r) }
func randf(_ r: ClosedRange<CGFloat>) -> CGFloat { CGFloat.random(in: r) }

func screen(containing p: CGPoint) -> NSScreen {
    NSScreen.screens.first { $0.frame.insetBy(dx: -1, dy: -1).contains(p) } ?? NSScreen.main ?? NSScreen.screens[0]
}

/// AppKit 坐标（左下角为原点）→ CoreGraphics 坐标（主屏左上角为原点）
func toCG(_ p: CGPoint) -> CGPoint {
    let h = NSScreen.screens.first?.frame.height ?? 0
    return CGPoint(x: p.x, y: h - p.y)
}

func appSupportDir() -> URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    return base.appendingPathComponent("桌面奶蛙", isDirectory: true)
}

func customMemeDir() -> URL {
    let dir = appSupportDir().appendingPathComponent("自定义表情包", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

// MARK: - 精灵图集

/// 图集：8 列 × 11 行，每格 192×208 像素，透明背景。
final class SpriteSheet {
    static let cellW = 192, cellH = 208
    /// 站立帧脚底在第 202 行；爬行帧（第 1、2 行）脚底在第 164 行，要往下挪 38 像素对齐。
    static let feetRow = 202
    static func yShift(row: Int) -> Int { (row == 1 || row == 2) ? 38 : 0 }

    let frames: [[CGImage]]
    private let alpha: [UInt8]
    private let width: Int

    init?(url: URL) {
        guard let img = NSImage(contentsOf: url),
              let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        width = cg.width
        // 先把整张图集解码成像素，再把每一帧拷贝成独立的小图（避免系统反复解码整张大图）
        var px = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
        let ctx = CGContext(data: &px, width: cg.width, height: cg.height, bitsPerComponent: 8,
                            bytesPerRow: cg.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        let decoded = ctx.makeImage()!
        var f: [[CGImage]] = []
        for r in 0..<11 {
            var row: [CGImage] = []
            for c in 0..<8 {
                let rect = CGRect(x: c * Self.cellW, y: r * Self.cellH, width: Self.cellW, height: Self.cellH)
                let cell = decoded.cropping(to: rect)!
                let fc = CGContext(data: nil, width: Self.cellW, height: Self.cellH, bitsPerComponent: 8, bytesPerRow: 0,
                                   space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                fc.draw(cell, in: CGRect(x: 0, y: 0, width: Self.cellW, height: Self.cellH))
                row.append(fc.makeImage()!)
            }
            f.append(row)
        }
        frames = f
        // 留一份透明度数据，用来判断鼠标是不是真的点在奶蛙身上
        alpha = stride(from: 3, to: px.count, by: 4).map { px[$0] }
    }

    /// 某一帧在格子内 (x, yTop) 像素处是否不透明
    func opaque(row: Int, col: Int, x: Int, yTop: Int) -> Bool {
        guard x >= 0, x < Self.cellW, yTop >= 0, yTop < Self.cellH else { return false }
        return alpha[(row * Self.cellH + yTop) * width + col * Self.cellW + x] > 40
    }
}

struct Anim: Equatable {
    let row: Int
    let frames: [Int]
    let fps: Double
    var loop = true

    static let idle = Anim(row: 0, frames: [0, 0, 0, 1, 2, 1, 0, 0, 3, 0, 4, 5, 4, 0], fps: 6)
    static let crawlRight = Anim(row: 1, frames: Array(0..<8), fps: 10)
    static let crawlLeft = Anim(row: 2, frames: Array(0..<8), fps: 10)
    static let wave = Anim(row: 3, frames: [0, 1, 2, 1, 2, 1, 2, 0], fps: 8, loop: false)
    static let laugh = Anim(row: 4, frames: [0, 1, 2, 3, 4, 3, 2, 1], fps: 12)
    static let sad = Anim(row: 5, frames: Array(0..<8), fps: 7, loop: false)
    static let dangle = Anim(row: 5, frames: [2, 3, 4, 3], fps: 6)
    static let think = Anim(row: 6, frames: [0, 1, 2, 3, 4, 5, 4, 3, 2, 1], fps: 5)
}

// MARK: - 声音（代码合成的「呱」）

final class Croak {
    private var players: [NSSound] = []

    func play(pitch: Double = 1.0, count: Int = 2) {
        guard Settings.shared.sound else { return }
        let sound = NSSound(data: Self.wav(pitch: pitch * rand(0.92...1.08), count: count))
        sound?.volume = 0.55
        sound?.play()
        if let s = sound { players.append(s) }
        players.removeAll { !$0.isPlaying && $0 !== sound }
    }

    /// 生成一段「呱呱」声的 WAV 数据：下滑的音高 + 粗糙的颤音
    static func wav(pitch: Double, count: Int) -> Data {
        let sr = 44100.0
        let croakLen = 0.15, gap = 0.07
        let total = Double(count) * (croakLen + gap)
        let n = Int(total * sr)
        var samples = [Int16](repeating: 0, count: n)
        var phase = 0.0
        for i in 0..<n {
            let t = Double(i) / sr
            let k = Int(t / (croakLen + gap))
            let lt = t - Double(k) * (croakLen + gap)
            guard lt < croakLen else { continue }
            let p = lt / croakLen
            let f = (430 - 200 * p) * pitch * (k % 2 == 0 ? 1.0 : 0.9)
            phase += 2 * .pi * f / sr
            let env = min(1, lt / 0.012) * pow(1 - p, 1.4)
            let rasp = 0.55 + 0.45 * sin(2 * .pi * 48 * lt)
            let wave = tanh(2.6 * sin(phase)) * 0.7 + 0.3 * sin(2 * phase + 0.5)
            samples[i] = Int16(max(-1, min(1, wave * env * rasp * 0.8)) * 32000)
        }
        var data = Data()
        func put<T>(_ v: T) { withUnsafeBytes(of: v) { data.append(contentsOf: $0) } }
        let bytes = UInt32(n * 2)
        data.append("RIFF".data(using: .ascii)!); put(UInt32(36 + bytes).littleEndian)
        data.append("WAVEfmt ".data(using: .ascii)!); put(UInt32(16).littleEndian)
        put(UInt16(1).littleEndian); put(UInt16(1).littleEndian)
        put(UInt32(44100).littleEndian); put(UInt32(88200).littleEndian)
        put(UInt16(2).littleEndian); put(UInt16(16).littleEndian)
        data.append("data".data(using: .ascii)!); put(bytes.littleEndian)
        samples.withUnsafeBufferPointer { data.append(Data(buffer: $0)) }
        return data
    }
}

// MARK: - 窗口基类

/// 无边框、透明、不抢焦点、所有桌面空间都显示的浮动面板
class FloatingPanel: NSPanel {
    init(level: NSWindow.Level) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        self.level = level
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

enum Levels {
    static let footprints = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.floatingWindow)) + 1)
    static let items = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.floatingWindow)) + 2)
    static let frog = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.overlayWindow)))
    static let bubble = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.overlayWindow)) + 1)
}

// MARK: - 奶蛙窗口

final class FrogView: NSView {
    weak var controller: Frog?
    let sprite = CALayer()
    private var dragOffset = CGPoint.zero
    private var downAt = CGPoint.zero
    private var moved = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        sprite.magnificationFilter = .nearest
        sprite.contentsGravity = .resize
        layer?.addSublayer(sprite)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard let c = controller else { return }
        let m = NSEvent.mouseLocation
        downAt = m
        dragOffset = CGPoint(x: c.pos.x - m.x, y: c.pos.y - m.y)
        moved = false
        c.beginHold()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let c = controller else { return }
        let m = NSEvent.mouseLocation
        if dist(m, downAt) > 4 { moved = true }
        c.pos = CGPoint(x: m.x + dragOffset.x, y: m.y + dragOffset.y)
        c.layoutWindow()
    }

    override func mouseUp(with event: NSEvent) {
        controller?.endHold(wasDragged: moved)
    }

    /// 在奶蛙身上点右键，弹出和菜单栏一样的菜单（里面有「退出」）
    override func rightMouseDown(with event: NSEvent) {
        guard let menu = controller?.contextMenu else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
}

// MARK: - 对话气泡

final class Bubble {
    let panel = FloatingPanel(level: Levels.bubble)
    private let label = NSTextField(labelWithString: "")
    private var hideAt = 0.0

    init() {
        panel.ignoresMouseEvents = true
        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor(white: 1, alpha: 0.95).cgColor
        v.layer?.cornerRadius = 10
        v.layer?.borderColor = NSColor(calibratedRed: 0.42, green: 0.29, blue: 0.1, alpha: 1).cgColor
        v.layer?.borderWidth = 2
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = NSColor(calibratedRed: 0.3, green: 0.2, blue: 0.05, alpha: 1)
        label.alignment = .center
        v.addSubview(label)
        panel.contentView = v
    }

    func say(_ text: String, seconds: Double) {
        hideAt = now() + seconds
        if panel.isVisible, label.stringValue == text { return }
        label.stringValue = text
        label.sizeToFit()
        let size = NSSize(width: label.frame.width + 22, height: label.frame.height + 12)
        panel.setContentSize(size)
        label.frame.origin = NSPoint(x: 11, y: 6)
        hideAt = now() + seconds
        panel.orderFrontRegardless()
    }

    func hide() { hideAt = 0; panel.orderOut(nil) }

    /// 跟在奶蛙头顶
    func follow(headTop: CGPoint) {
        guard panel.isVisible else { return }
        if now() > hideAt { panel.orderOut(nil); return }
        let s = panel.frame.size
        let origin = NSPoint(x: (headTop.x - s.width / 2).rounded(), y: (headTop.y + 4).rounded())
        if panel.frame.origin != origin { panel.setFrameOrigin(origin) }
    }
}

// MARK: - 脚印层（每块屏幕一个，完全不接收点击）

final class FootprintLayer {
    private var overlays: [(screen: NSRect, panel: FloatingPanel)] = []
    private lazy var footprintImage: CGImage = Self.makeFootprint()

    init() { rebuild() }

    func rebuild() {
        overlays.forEach { $0.panel.close() }
        overlays = NSScreen.screens.map { s in
            let p = FloatingPanel(level: Levels.footprints)
            p.ignoresMouseEvents = true
            p.setFrame(s.frame, display: false)
            let v = NSView(frame: NSRect(origin: .zero, size: s.frame.size))
            v.wantsLayer = true
            p.contentView = v
            p.orderFrontRegardless()
            return (s.frame, p)
        }
    }

    func stamp(at p: CGPoint, angle: CGFloat, scale: CGFloat) {
        guard let o = overlays.first(where: { $0.screen.contains(p) }),
              let root = o.panel.contentView?.layer else { return }
        let l = CALayer()
        l.contents = footprintImage
        let w = 16 * scale / 0.6, h = 18 * scale / 0.6
        l.bounds = CGRect(x: 0, y: 0, width: w, height: h)
        l.position = CGPoint(x: p.x - o.screen.minX, y: p.y - o.screen.minY)
        l.setAffineTransform(CGAffineTransform(rotationAngle: angle - .pi / 2))
        l.opacity = 0
        CATransaction.begin()
        CATransaction.setCompletionBlock { l.removeFromSuperlayer() }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.75
        fade.toValue = 0
        fade.duration = 8
        l.add(fade, forKey: "fade")
        root.addSublayer(l)
        CATransaction.commit()
    }

    /// 用代码画一个三趾的蛙脚印（脚趾朝上）
    static func makeFootprint() -> CGImage {
        let w = 32, h = 36
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(NSColor(calibratedRed: 0.42, green: 0.29, blue: 0.1, alpha: 1).cgColor)
        ctx.fillEllipse(in: CGRect(x: 8, y: 2, width: 16, height: 15))
        for (dx, dy) in [(-9.0, 15.0), (0.0, 20.0), (9.0, 15.0)] {
            ctx.move(to: CGPoint(x: 16, y: 10))
            ctx.addLine(to: CGPoint(x: 16 + dx, y: 10 + dy))
            ctx.setLineWidth(4)
            ctx.setStrokeColor(NSColor(calibratedRed: 0.42, green: 0.29, blue: 0.1, alpha: 1).cgColor)
            ctx.strokePath()
            ctx.fillEllipse(in: CGRect(x: 16 + dx - 3.5, y: 10 + dy - 3, width: 7, height: 7))
        }
        return ctx.makeImage()!
    }
}

// MARK: - 被拖出来的便签 / 表情包

final class ItemView: NSView {
    weak var panel: ItemPanel?
    let image: NSImage
    let angle: CGFloat
    let cardSize: NSSize
    private var dragOffset = CGPoint.zero
    private var hoverClose = false

    init(image: NSImage, angle: CGFloat) {
        self.image = image
        self.angle = angle
        self.cardSize = image.size
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError() }

    var closeRect: NSRect {
        let r = cardRect
        return NSRect(x: r.maxX - 22, y: r.maxY - 22, width: 18, height: 18)
    }
    var cardRect: NSRect {
        NSRect(x: (bounds.width - cardSize.width) / 2, y: (bounds.height - cardSize.height) / 2,
               width: cardSize.width, height: cardSize.height)
    }

    /// 把视图坐标反向旋转回卡片坐标
    func unrotate(_ p: CGPoint) -> CGPoint {
        let c = CGPoint(x: bounds.midX, y: bounds.midY)
        let t = CGAffineTransform(translationX: c.x, y: c.y).rotated(by: -angle).translatedBy(x: -c.x, y: -c.y)
        return p.applying(t)
    }

    func containsCard(_ p: CGPoint) -> Bool { cardRect.contains(unrotate(p)) }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.translateBy(x: bounds.midX, y: bounds.midY)
        ctx.rotate(by: angle)
        ctx.translateBy(x: -bounds.midX, y: -bounds.midY)
        ctx.setShadow(offset: CGSize(width: 2, height: -4), blur: 10, color: NSColor(white: 0, alpha: 0.35).cgColor)
        image.draw(in: cardRect)
        ctx.setShadow(offset: .zero, blur: 0, color: nil)
        // 右上角的小 ×
        let cr = closeRect
        NSColor(white: 0, alpha: hoverClose ? 0.55 : 0.25).setFill()
        NSBezierPath(ovalIn: cr).fill()
        let x = NSBezierPath()
        x.move(to: NSPoint(x: cr.minX + 5.5, y: cr.minY + 5.5)); x.line(to: NSPoint(x: cr.maxX - 5.5, y: cr.maxY - 5.5))
        x.move(to: NSPoint(x: cr.minX + 5.5, y: cr.maxY - 5.5)); x.line(to: NSPoint(x: cr.maxX - 5.5, y: cr.minY + 5.5))
        x.lineWidth = 1.8
        NSColor.white.setStroke()
        x.stroke()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        let local = unrotate(convert(event.locationInWindow, from: nil))
        if event.clickCount >= 2 || closeRect.insetBy(dx: -3, dy: -3).contains(local) {
            panel?.dismiss()
            return
        }
        panel?.userGrabbed = true
        let m = NSEvent.mouseLocation
        dragOffset = CGPoint(x: window!.frame.minX - m.x, y: window!.frame.minY - m.y)
    }

    override func mouseDragged(with event: NSEvent) {
        let m = NSEvent.mouseLocation
        window?.setFrameOrigin(NSPoint(x: m.x + dragOffset.x, y: m.y + dragOffset.y))
    }

    func updateHover(_ screenPoint: CGPoint) {
        guard let w = window else { return }
        let local = unrotate(CGPoint(x: screenPoint.x - w.frame.minX, y: screenPoint.y - w.frame.minY))
        let h = closeRect.insetBy(dx: -3, dy: -3).contains(local)
        if h != hoverClose { hoverClose = h; needsDisplay = true }
    }
}

final class ItemPanel: FloatingPanel {
    let view: ItemView
    var userGrabbed = false
    var onDismiss: ((ItemPanel) -> Void)?

    init(image: NSImage) {
        view = ItemView(image: image, angle: randf(-0.12...0.12))
        super.init(level: Levels.items)
        let s = image.size
        let side = ceil(hypot(s.width, s.height)) + 30
        setContentSize(NSSize(width: side, height: side))
        view.frame = NSRect(x: 0, y: 0, width: side, height: side)
        view.panel = self
        contentView = view
        ignoresMouseEvents = true
    }

    /// 鼠标是否落在卡片上（只有卡片部分能点，四周透明区域点击穿透）
    func hit(_ p: CGPoint) -> Bool {
        guard frame.contains(p) else { return false }
        return view.containsCard(CGPoint(x: p.x - frame.minX, y: p.y - frame.minY))
    }

    /// 卡片靠近奶蛙那一侧边缘的中点（相对窗口中心）
    func attachOffset(toward edge: Facing) -> CGFloat { view.cardSize.width / 2 - 12 }

    func dismiss() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self else { return }
            self.close()
            self.onDismiss?(self)
        })
    }
}

enum Facing { case left, right }

// MARK: - 便签和表情包内容

enum Content {
    static let notes = [
        "呱！\n你的鼠标\n归我了",
        "今天也要\n捧腹大笑哦",
        "别看了\n快去写作业",
        "ddl 是\n第一生产力",
        "我只是一只\n小头大肚的蛙",
        "喝口水吧\n呱～",
        "你已经盯着\n屏幕很久了",
        "这张便签\n没有任何用处",
        "奶蛙\n到此一游",
        "肚子饿了\n有虫子吗",
        "按住 Esc\n三秒我就走\n……才怪",
        "摸鱼时间到！",
        "今日运势：\n呱呱大吉",
        "蛙生苦短\n及时摸鱼",
        "站起来\n伸个懒腰",
        "别关我\n（关也行）",
    ]

    static let memes: [(row: Int, col: Int, caption: String)] = [
        (4, 2, "哈哈哈哈哈哈"),
        (4, 0, "笑死，根本停不下来"),
        (5, 4, "我裂开了"),
        (5, 3, "破防了家人们"),
        (6, 2, "让我想想……不想了"),
        (3, 2, "嗨～是我"),
        (9, 4, "？"),
        (10, 0, "盯——"),
        (1, 3, "溜了溜了"),
    ]

    static func noteFont(_ size: CGFloat) -> NSFont {
        for name in ["HannotateSC-W7", "HanziPenSC-W5", "Yuppy SC Regular"] {
            if let f = NSFont(name: name, size: size) { return f }
        }
        return .systemFont(ofSize: size, weight: .bold)
    }

    static func makeNote() -> NSImage {
        let text = notes.randomElement()!
        let size = NSSize(width: 170, height: 150)
        let colors: [NSColor] = [
            NSColor(calibratedRed: 1.0, green: 0.93, blue: 0.45, alpha: 1),
            NSColor(calibratedRed: 0.72, green: 0.93, blue: 0.62, alpha: 1),
            NSColor(calibratedRed: 1.0, green: 0.78, blue: 0.82, alpha: 1),
            NSColor(calibratedRed: 0.7, green: 0.86, blue: 1.0, alpha: 1),
        ]
        let bg = colors.randomElement()!
        return NSImage(size: size, flipped: false) { r in
            bg.setFill()
            NSBezierPath(rect: r).fill()
            NSColor(white: 0, alpha: 0.06).setFill()
            NSBezierPath(rect: NSRect(x: 0, y: r.height - 22, width: r.width, height: 22)).fill()
            let p = NSMutableParagraphStyle()
            p.alignment = .center
            p.lineSpacing = 2
            let attrs: [NSAttributedString.Key: Any] = [
                .font: noteFont(20), .foregroundColor: NSColor(white: 0.15, alpha: 1), .paragraphStyle: p,
            ]
            let s = NSAttributedString(string: text, attributes: attrs)
            let b = s.boundingRect(with: NSSize(width: r.width - 20, height: r.height), options: .usesLineFragmentOrigin)
            s.draw(in: NSRect(x: 10, y: (r.height - 22 - b.height) / 2, width: r.width - 20, height: b.height))
            return true
        }
    }

    static func makeMeme(sheet: SpriteSheet) -> NSImage {
        if let custom = randomCustomImage(), Bool.random() { return custom }
        let m = memes.randomElement()!
        let frame = sheet.frames[m.row][m.col]
        let size = NSSize(width: 180, height: 210)
        return NSImage(size: size, flipped: false) { r in
            NSColor.white.setFill()
            NSBezierPath(rect: r).fill()
            NSColor(calibratedRed: 0.98, green: 0.95, blue: 0.86, alpha: 1).setFill()
            NSBezierPath(rect: NSRect(x: 10, y: 44, width: 160, height: 156)).fill()
            if let ctx = NSGraphicsContext.current {
                ctx.imageInterpolation = .none
                let yShift = CGFloat(SpriteSheet.yShift(row: m.row)) * 0.75
                ctx.cgContext.draw(frame, in: CGRect(x: 18, y: 46 - yShift + 6, width: 144, height: 156))
            }
            let p = NSMutableParagraphStyle()
            p.alignment = .center
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 17, weight: .heavy), .foregroundColor: NSColor.black, .paragraphStyle: p,
            ]
            NSAttributedString(string: m.caption, attributes: attrs).draw(in: NSRect(x: 6, y: 10, width: 168, height: 26))
            return true
        }
    }

    /// 用户自己放进「自定义表情包」文件夹的图片
    static func randomCustomImage() -> NSImage? {
        let exts: Set = ["png", "jpg", "jpeg", "gif", "webp", "heic", "bmp", "tiff"]
        guard let files = try? FileManager.default.contentsOfDirectory(at: customMemeDir(), includingPropertiesForKeys: nil)
            .filter({ exts.contains($0.pathExtension.lowercased()) }),
            let url = files.randomElement(), let img = NSImage(contentsOf: url), img.size.width > 0 else { return nil }
        let maxSide: CGFloat = 230
        let k = min(1, maxSide / max(img.size.width, img.size.height))
        let size = NSSize(width: img.size.width * k + 16, height: img.size.height * k + 16)
        return NSImage(size: size, flipped: false) { r in
            NSColor.white.setFill()
            NSBezierPath(rect: r).fill()
            img.draw(in: r.insetBy(dx: 8, dy: 8))
            return true
        }
    }
}

// MARK: - 奶蛙本体（行为状态机）

enum ItemKind { case note, meme }

final class Frog {
    enum Mode {
        case enter(target: CGPoint)
        case idle(until: Double, look: Bool)
        case wander(target: CGPoint)
        case chase(deadline: Double)
        case dragCursor(target: CGPoint, until: Double)
        case toEdge(target: CGPoint, edge: Facing, kind: ItemKind)
        case pull(item: ItemPanel, target: CGPoint, edge: Facing)
        case emote(until: Double)
        case held
        case leaving(until: Double)
    }

    let sheet: SpriteSheet
    let window = FloatingPanel(level: Levels.frog)
    let view = FrogView(frame: .zero)
    let bubble = Bubble()
    let footprints = FootprintLayer()
    let croak = Croak()

    var pos = CGPoint.zero
    var mode: Mode = .idle(until: 0, look: false)
    var facing: Facing = .right
    var paused = false
    var items: [ItemPanel] = []
    var contextMenu: NSMenu?

    private var anim = Anim.idle
    private var animStart = 0.0
    private var reverse = false
    private var row = 0, col = 0
    private var nextPrank = 0.0
    private var lastTick = now()
    private var strideDist: CGFloat = 0
    private var leftFoot = false
    private var hoverSince: Double?
    private var escSince: Double?

    var scale: CGFloat { Settings.shared.scale }

    init(sheet: SpriteSheet) {
        self.sheet = sheet
        view.controller = self
        window.contentView = view
        window.ignoresMouseEvents = true
        applyScale()

        // 从主屏幕左边缘爬进来
        let s = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        pos = CGPoint(x: s.minX - 120, y: s.minY + s.height * 0.35)
        mode = .enter(target: CGPoint(x: s.minX + s.width * 0.3, y: pos.y))
        nextPrank = now() + 10
        layoutWindow()
        window.orderFrontRegardless()
        bubble.say("呱！我来了～ 想赶我走：按住 Esc 3 秒，或者右键点我", seconds: 7)
    }

    func applyScale() {
        let s = scale
        window.setContentSize(NSSize(width: CGFloat(SpriteSheet.cellW) * s, height: CGFloat(SpriteSheet.cellH) * s))
        view.frame = NSRect(origin: .zero, size: window.frame.size)
        layoutWindow()
        render()
    }

    // MARK: 几何

    /// 脚底到窗口底边的距离
    var footInset: CGFloat { CGFloat(SpriteSheet.cellH - SpriteSheet.feetRow) * scale }

    func layoutWindow() {
        let origin = NSPoint(x: (pos.x - CGFloat(SpriteSheet.cellW) * scale / 2).rounded(),
                             y: (pos.y - footInset).rounded())
        if window.frame.origin != origin { window.setFrameOrigin(origin) }
        bubble.follow(headTop: CGPoint(x: pos.x, y: pos.y + 200 * scale))
    }

    /// 嘴巴的位置（爬行姿势），用来叼鼠标和拖东西
    var mouth: CGPoint {
        CGPoint(x: pos.x + (facing == .right ? 81 : -81) * scale, y: pos.y + 83 * scale)
    }

    func isOverFrog(_ p: CGPoint) -> Bool {
        let f = window.frame
        guard f.contains(p) else { return false }
        let x = Int((p.x - f.minX) / scale)
        let yTop = Int((f.maxY - p.y) / scale) - SpriteSheet.yShift(row: row)
        return sheet.opaque(row: row, col: col, x: x, yTop: yTop)
    }

    // MARK: 动画

    func play(_ a: Anim, reversed: Bool = false) {
        if a != anim || reversed != reverse {
            anim = a
            reverse = reversed
            animStart = now()
        }
    }

    func render() {
        let t = now() - animStart
        var i = Int(t * anim.fps)
        i = anim.loop ? i % anim.frames.count : min(i, anim.frames.count - 1)
        if reverse { i = anim.frames.count - 1 - i }
        setFrame(row: anim.row, col: anim.frames[i])
    }

    func setFrame(row r: Int, col c: Int) {
        guard r != row || c != col || view.sprite.contents == nil || view.sprite.frame.width != CGFloat(SpriteSheet.cellW) * scale else { return }
        row = r
        col = c
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let s = scale
        view.sprite.contents = sheet.frames[r][c]
        view.sprite.frame = CGRect(x: 0, y: -CGFloat(SpriteSheet.yShift(row: r)) * s,
                                   width: CGFloat(SpriteSheet.cellW) * s, height: CGFloat(SpriteSheet.cellH) * s)
        CATransaction.commit()
    }

    /// 朝鼠标方向张望（16 个方向，第 0 帧朝上，顺时针每帧 22.5°）
    func lookAt(_ p: CGPoint) {
        let head = CGPoint(x: pos.x, y: pos.y + 150 * scale)
        var a = atan2(p.x - head.x, p.y - head.y)
        if a < 0 { a += 2 * .pi }
        let idx = Int((a / (.pi / 8)).rounded()) % 16
        anim = Anim(row: 9 + idx / 8, frames: [idx % 8], fps: 1)
        setFrame(row: 9 + idx / 8, col: idx % 8)
    }

    // MARK: 移动

    /// 朝目标爬一步，到了返回 true
    @discardableResult
    func crawl(to target: CGPoint, speed: CGFloat, dt: CGFloat, backwards: Bool = false) -> Bool {
        let d = dist(pos, target)
        let step = speed * dt
        let dx = target.x - pos.x, dy = target.y - pos.y
        if !backwards, abs(dx) > 6 { facing = dx > 0 ? .right : .left }
        let base: Anim = facing == .right ? .crawlRight : .crawlLeft
        play(Anim(row: base.row, frames: base.frames, fps: Double(10 * speed / 75)), reversed: backwards)
        if d <= step {
            pos = target
        } else {
            pos.x += dx / d * step
            pos.y += dy / d * step
        }
        // 留脚印
        if Settings.shared.footprints {
            strideDist += min(step, d)
            if strideDist > 22 * scale / 0.6 {
                strideDist = 0
                leftFoot.toggle()
                let ang = atan2(dy, dx)
                let off = (leftFoot ? 1 : -1) * 6 * scale / 0.6
                footprints.stamp(at: CGPoint(x: pos.x - sin(ang) * off, y: pos.y + cos(ang) * off),
                                 angle: ang, scale: scale)
            }
        }
        return d <= step
    }

    func randomTarget(near p: CGPoint, minD: CGFloat, maxD: CGFloat) -> CGPoint {
        let s = screen(containing: p).visibleFrame.insetBy(dx: 90 * scale, dy: 40)
        for _ in 0..<20 {
            let a = randf(0...(2 * .pi)), r = randf(minD...maxD)
            let q = CGPoint(x: p.x + cos(a) * r, y: p.y + sin(a) * r * 0.6)
            if s.contains(q) { return q }
        }
        return CGPoint(x: randf(s.minX...s.maxX), y: randf(s.minY...(s.maxY - 160 * scale)))
    }

    func emote(_ a: Anim, seconds: Double) {
        play(a)
        mode = .emote(until: now() + seconds)
    }

    func goIdle() {
        let look = Bool.random()
        play(.idle)
        mode = .idle(until: now() + rand(1.5...4.5), look: look)
    }

    // MARK: 每帧更新

    private var frameCount = 0

    /// 发呆、做表情时不需要 60 帧，省电
    var isCalm: Bool {
        switch mode {
        case .idle, .emote: return true
        default: return false
        }
    }

    func tick() {
        frameCount += 1
        if isCalm, frameCount % 3 != 0 { return }
        let t = now()
        let dt = CGFloat(min(0.05, t - lastTick))
        lastTick = t
        let mouse = NSEvent.mouseLocation

        if frameCount % 6 == 0 { checkEsc(t) }

        switch mode {
        case .enter(let target):
            if crawl(to: target, speed: 90, dt: dt) { play(.wave); mode = .emote(until: t + 1.2) }

        case .idle(let until, let look):
            if paused {
                play(.think)
            } else if look, dist(mouse, pos) < 700 {
                lookAt(mouse)
            } else if case .idle = mode, anim.row >= 9 {
                play(.idle)
            }
            if !paused, t > until {
                if t > nextPrank, startPrank() { break }
                if Double.random(in: 0...1) < 0.15 {
                    emote(Bool.random() ? .think : .wave, seconds: rand(1.2...2.5))
                } else {
                    mode = .wander(target: randomTarget(near: pos, minD: 150, maxD: 550))
                }
            }

        case .wander(let target):
            if paused { goIdle(); break }
            if crawl(to: target, speed: 75, dt: dt) { goIdle() }

        case .chase(let deadline):
            if NSEvent.pressedMouseButtons != 0 { emote(.sad, seconds: 1.2); break }
            if abs(mouse.x - pos.x) > 30 { facing = mouse.x > pos.x ? .right : .left }
            let off = CGPoint(x: mouth.x - pos.x, y: mouth.y - pos.y)
            let target = CGPoint(x: mouse.x - off.x, y: mouse.y - off.y)
            crawl(to: target, speed: 230, dt: dt)
            if dist(mouth, mouse) < 24 {
                croak.play(pitch: 1.1)
                bubble.say(["呱！抓到了！", "这个归我了", "嘿嘿嘿"].randomElement()!, seconds: 2)
                let dest = randomTarget(near: pos, minD: 260, maxD: 520)
                mode = .dragCursor(target: dest, until: t + rand(2...3))
            } else if t > deadline {
                bubble.say("跑太快了呱…", seconds: 1.5)
                emote(.sad, seconds: 1.4)
            }

        case .dragCursor(let target, let until):
            // 用户按着鼠标键（比如正在拖文件）就立刻松口，免得误操作
            if NSEvent.pressedMouseButtons != 0 { emote(.laugh, seconds: 1.2); break }
            let done = crawl(to: target, speed: 150, dt: dt)
            _ = CGWarpMouseCursorPosition(toCG(mouth))
            CGAssociateMouseAndMouseCursorPosition(1)
            if done || t > until { emote(.laugh, seconds: 1.8); croak.play(pitch: 1.25, count: 3) }

        case .toEdge(let target, let edge, let kind):
            if crawl(to: target, speed: 120, dt: dt) {
                facing = edge
                let item = ItemPanel(image: kind == .note ? Content.makeNote() : Content.makeMeme(sheet: sheet))
                item.onDismiss = { [weak self] p in self?.items.removeAll { $0 === p } }
                items.append(item)
                if items.count > 10 { items.first?.dismiss() }
                placeItem(item, edge: edge)
                item.orderFrontRegardless()
                croak.play(pitch: 0.95)
                let s = screen(containing: pos).visibleFrame
                let dx = randf(220...min(520, s.width * 0.45))
                let dest = CGPoint(x: edge == .left ? pos.x + dx : pos.x - dx, y: pos.y + randf(-60...60))
                mode = .pull(item: item, target: dest, edge: edge)
            }

        case .pull(let item, let target, let edge):
            if item.userGrabbed || !item.isVisible { emote(.sad, seconds: 1.2); break }
            facing = edge
            let done = crawl(to: target, speed: 85, dt: dt, backwards: true)
            placeItem(item, edge: edge)
            if done { emote(.laugh, seconds: 1.8) }

        case .emote(let until):
            if t > until { goIdle() }

        case .held:
            break

        case .leaving(let until):
            if t > until { NSApp.terminate(nil) }
        }

        if case .idle = mode, anim.row >= 9 {
            // lookAt 已经设置好帧
        } else {
            render()
        }
        layoutWindow()
        updateMouseThrough(mouse, t)
    }

    /// 把被拖的东西摆在奶蛙嘴边
    func placeItem(_ item: ItemPanel, edge: Facing) {
        let m = mouth
        let off = item.attachOffset(toward: edge)
        let cx = edge == .left ? m.x - off : m.x + off
        let size = item.frame.size
        item.setFrameOrigin(NSPoint(x: cx - size.width / 2, y: m.y - size.height / 2 - 10))
    }

    /// 只有鼠标在奶蛙（或便签）不透明的地方才接收点击，其余地方点击穿透
    func updateMouseThrough(_ mouse: CGPoint, _ t: Double) {
        if case .held = mode { return }
        let over = isOverFrog(mouse)
        if window.ignoresMouseEvents == over { window.ignoresMouseEvents = !over }
        // 按着鼠标键时（比如正在拖便签）不切换，免得拖到一半松手
        let buttonDown = NSEvent.pressedMouseButtons & 1 != 0
        for item in items where !buttonDown {
            let hit = item.hit(mouse)
            if item.ignoresMouseEvents == hit { item.ignoresMouseEvents = !hit }
            if hit { item.view.updateHover(mouse) }
        }
        // 鼠标停在奶蛙身上一会儿，它会捧腹大笑（和 Codex 宠物一样）
        if over {
            if hoverSince == nil { hoverSince = t }
            if let h = hoverSince, t - h > 0.35 {
                switch mode {
                case .idle, .wander: emote(.laugh, seconds: 1.5); croak.play(pitch: 1.3, count: 1)
                default: break
                }
                hoverSince = t + 2
            }
        } else {
            hoverSince = nil
        }
    }

    // MARK: 恶搞

    @discardableResult
    func startPrank() -> Bool {
        let st = Settings.shared
        var options: [(Int, () -> Void)] = []
        if st.grabCursor, NSEvent.pressedMouseButtons == 0 {
            options.append((4, { [self] in
                mode = .chase(deadline: now() + 7)
                bubble.say("呱？那是什么？", seconds: 1.5)
            }))
        }
        if st.notes { options.append((3, { [self] in fetch(.note) })) }
        if st.memes { options.append((3, { [self] in fetch(.meme) })) }
        scheduleNextPrank()
        guard !options.isEmpty else { return false }
        var r = Int.random(in: 0..<options.reduce(0) { $0 + $1.0 })
        for (w, act) in options {
            if r < w { act(); return true }
            r -= w
        }
        return false
    }

    func scheduleNextPrank() {
        nextPrank = now() + Settings.shared.frequency.interval * rand(0.6...1.4)
    }

    func fetch(_ kind: ItemKind) {
        let s = screen(containing: pos).visibleFrame
        let edge: Facing = pos.x < s.midX ? .left : .right
        let y = randf((s.minY + 60)...(s.maxY - 220 * scale - 60))
        let x = edge == .left ? s.minX + 30 + 81 * scale : s.maxX - 30 - 81 * scale
        mode = .toEdge(target: CGPoint(x: x, y: y), edge: edge, kind: kind)
    }

    // MARK: 用户操作

    func beginHold() {
        window.ignoresMouseEvents = false
        if case .leaving = mode { return }
        mode = .held
        play(.dangle)
        croak.play(pitch: 1.4, count: 1)
        bubble.say(["放我下来呱！", "呱呱呱！", "别拎我！"].randomElement()!, seconds: 1.5)
    }

    func endHold(wasDragged: Bool) {
        if case .leaving = mode { return }
        if wasDragged {
            emote(.sad, seconds: 1.2)
        } else {
            emote(.laugh, seconds: 1.5)
            croak.play(pitch: 1.2)
        }
    }

    func summon() {
        let m = NSEvent.mouseLocation
        pos = CGPoint(x: m.x + 60, y: m.y - 60)
        layoutWindow()
        emote(.wave, seconds: 1.2)
        bubble.say("叫我干嘛呱？", seconds: 2)
    }

    func clearItems() {
        items.forEach { $0.dismiss() }
    }

    func setPaused(_ p: Bool) {
        paused = p
        if p {
            goIdle()
            bubble.say("好吧，我先想想蛙生……", seconds: 2)
        } else {
            scheduleNextPrank()
            bubble.say("呱！继续捣蛋！", seconds: 2)
        }
    }

    // MARK: 按住 Esc 3 秒退出

    func checkEsc(_ t: Double) {
        if case .leaving = mode { return }
        let down = CGEventSource.keyState(.combinedSessionState, key: 53)
        guard down else {
            if escSince != nil { escSince = nil; bubble.hide() }
            return
        }
        if escSince == nil { escSince = t }
        let held = t - escSince!
        if held >= 3 {
            leave()
        } else {
            let left = Int(ceil(3 - held))
            bubble.say("再按住 \(left) 秒我就走了…", seconds: 0.3)
        }
    }

    func leave() {
        bubble.say("拜拜呱～", seconds: 2)
        play(.sad)
        croak.play(pitch: 0.8, count: 1)
        mode = .leaving(until: now() + 0.9)
    }
}

// MARK: - 菜单栏和 App

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var frog: Frog!
    var statusItem: NSStatusItem!
    var timer: Timer?
    let menu = NSMenu()

    func applicationDidFinishLaunching(_ note: Notification) {
        // 已经开着一只了就不再开第二只
        if let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id).count > 1 {
            NSApp.terminate(nil)
            return
        }

        guard let url = Bundle.main.url(forResource: "spritesheet", withExtension: "webp")
                ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath + "/spritesheet.webp") as URL?,
              let sheet = SpriteSheet(url: url) else {
            let a = NSAlert()
            a.messageText = "找不到奶蛙的图片素材（spritesheet.webp）"
            a.runModal()
            NSApp.terminate(nil)
            return
        }
        _ = customMemeDir()

        frog = Frog(sheet: sheet)
        setupStatusItem(sheet: sheet)
        frog.contextMenu = menu

        let t = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.frog.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.frog.footprints.rebuild()
        }
    }

    func setupStatusItem(sheet: SpriteSheet) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let head = sheet.frames[0][0].cropping(to: CGRect(x: 44, y: 2, width: 104, height: 104))!
        let icon = NSImage(size: NSSize(width: 20, height: 20), flipped: false) { r in
            NSGraphicsContext.current?.imageInterpolation = .none
            NSGraphicsContext.current?.cgContext.draw(head, in: r)
            return true
        }
        statusItem.button?.image = icon
        statusItem.button?.toolTip = "桌面奶蛙"
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let st = Settings.shared

        let title = NSMenuItem(title: frog.paused ? "奶蛙在发呆 🐸" : "奶蛙正在捣蛋 🐸", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())

        menu.addItem(item(frog.paused ? "继续捣蛋" : "暂停捣蛋", #selector(togglePause)))
        menu.addItem(item("马上捣蛋一次", #selector(prankNow)))

        let freq = NSMenu()
        for f in Frequency.allCases {
            let i = item(f.title, #selector(setFrequency(_:)))
            i.tag = f.rawValue
            i.state = st.frequency == f ? .on : .off
            freq.addItem(i)
        }
        menu.addItem(submenu("恶搞频率", freq))

        let toggles = NSMenu()
        for (name, key, on) in [("抢鼠标", "grabCursor", st.grabCursor), ("拖出便签", "notes", st.notes),
                                ("拖出表情包", "memes", st.memes), ("留下脚印", "footprints", st.footprints),
                                ("呱呱叫声", "sound", st.sound)] {
            let i = item(name, #selector(toggleSetting(_:)))
            i.representedObject = key
            i.state = on ? .on : .off
            toggles.addItem(i)
        }
        menu.addItem(submenu("恶搞项目", toggles))

        let sizes = NSMenu()
        for (name, v) in [("小", 0.45), ("中", 0.6), ("大", 0.8), ("特大", 1.0)] {
            let i = item(name, #selector(setSize(_:)))
            i.representedObject = v
            i.state = abs(Double(st.scale) - v) < 0.01 ? .on : .off
            sizes.addItem(i)
        }
        menu.addItem(submenu("奶蛙大小", sizes))

        menu.addItem(.separator())
        menu.addItem(item("把奶蛙叫到鼠标旁边", #selector(summon)))
        menu.addItem(item("清理桌面上的便签和表情包", #selector(clearItems)))
        menu.addItem(item("打开自定义表情包文件夹…", #selector(openMemeFolder)))
        menu.addItem(item("使用说明", #selector(openReadme)))
        menu.addItem(.separator())
        let quit = item("退出桌面奶蛙", #selector(quit))
        quit.keyEquivalent = "q"
        menu.addItem(quit)
    }

    func item(_ title: String, _ sel: Selector) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: sel, keyEquivalent: "")
        i.target = self
        return i
    }

    func submenu(_ title: String, _ sub: NSMenu) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        i.submenu = sub
        return i
    }

    @objc func togglePause() { frog.setPaused(!frog.paused) }
    @objc func prankNow() {
        if frog.paused { frog.setPaused(false) }
        if !frog.startPrank() { frog.bubble.say("所有恶搞项目都关掉啦", seconds: 2) }
    }
    @objc func setFrequency(_ s: NSMenuItem) {
        Settings.shared.frequency = Frequency(rawValue: s.tag) ?? .normal
        frog.scheduleNextPrank()
    }
    @objc func toggleSetting(_ s: NSMenuItem) {
        guard let key = s.representedObject as? String else { return }
        UserDefaults.standard.set(!UserDefaults.standard.bool(forKey: key), forKey: key)
    }
    @objc func setSize(_ s: NSMenuItem) {
        guard let v = s.representedObject as? Double else { return }
        Settings.shared.scale = CGFloat(v)
        frog.applyScale()
    }
    @objc func summon() { frog.summon() }
    @objc func clearItems() { frog.clearItems() }
    @objc func openMemeFolder() { NSWorkspace.shared.open(customMemeDir()) }
    @objc func openReadme() {
        if let url = Bundle.main.url(forResource: "使用说明", withExtension: "md") {
            NSWorkspace.shared.open(url)
        }
    }
    @objc func quit() { frog.leave() }
}

/// 把便签、表情包和几个动作帧画成一张预览图（README 里的图就是这么来的），不启动奶蛙
/// 用法：DesktopNaiwa --render-samples 输出文件夹
func renderSamples(to dir: String) {
    guard let url = Bundle.main.url(forResource: "spritesheet", withExtension: "webp"),
          let sheet = SpriteSheet(url: url) else { return }
    let ctx = CGContext(data: nil, width: 1200, height: 760, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(red: 0.86, green: 0.93, blue: 0.97, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: 1200, height: 760))
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    for i in 0..<4 {
        let note = Content.makeNote()
        note.draw(in: NSRect(origin: NSPoint(x: 20 + i * 190, y: 560), size: note.size))
        let meme = Content.makeMeme(sheet: sheet)
        meme.draw(in: NSRect(origin: NSPoint(x: 20 + i * 190, y: 320), size: meme.size))
    }
    let fp = FootprintLayer.makeFootprint()
    for i in 0..<6 { ctx.draw(fp, in: CGRect(x: 800 + i * 50, y: 600 + (i % 2) * 14, width: 32, height: 36)) }
    // 几个动作帧并排，脚底对齐在同一条线上
    for (k, (r, c)) in [(0, 0), (1, 0), (2, 3), (4, 2), (5, 4), (9, 4)].enumerated() {
        let x = CGFloat(20 + k * 196)
        let y = CGFloat(20) - CGFloat(SpriteSheet.yShift(row: r))
        ctx.draw(sheet.frames[r][c], in: CGRect(x: x, y: y, width: 192, height: 208))
    }
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir + "/samples.png"))
}

if let i = CommandLine.arguments.firstIndex(of: "--render-samples"), i + 1 < CommandLine.arguments.count {
    renderSamples(to: CommandLine.arguments[i + 1])
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
