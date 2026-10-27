// 用奶蛙捧腹大笑的那一帧生成 App 图标：swift make_icon.swift spritesheet.webp 输出.iconset
import AppKit
let args = CommandLine.arguments
let cg = NSImage(contentsOfFile: args[1])!.cgImage(forProposedRect: nil, context: nil, hints: nil)!
let frame = cg.cropping(to: CGRect(x: 2 * 192, y: 4 * 208, width: 192, height: 208))!
let out = URL(fileURLWithPath: args[2])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
                   ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    let s = CGFloat(px)
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let card = CGRect(x: s * 0.1, y: s * 0.1, width: s * 0.8, height: s * 0.8)
    ctx.addPath(CGPath(roundedRect: card, cornerWidth: s * 0.18, cornerHeight: s * 0.18, transform: nil))
    ctx.setFillColor(CGColor(red: 0.62, green: 0.86, blue: 0.98, alpha: 1))
    ctx.fillPath()
    ctx.interpolationQuality = .none
    let h = s * 0.74, w = h * 192 / 208
    ctx.draw(frame, in: CGRect(x: (s - w) / 2, y: s * 0.1, width: w, height: h))
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try! rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent("icon_\(name).png"))
}
