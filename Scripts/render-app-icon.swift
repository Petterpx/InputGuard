import AppKit
// 用法: icon <out.png> <size> <topHex> <bottomHex> <symbol> [badgeSymbol]
// macOS 图标规范：1024 画布，圆角方形占 824，圆角 ≈ 22.37%，带柔和投影
let a = CommandLine.arguments
let out = a[1], size = CGFloat(Double(a[2])!), top = a[3], bottom = a[4], symbol = a[5]
let badge: String? = a.count > 6 ? a[6] : nil
func color(_ hex: String) -> NSColor {
    let v = UInt32(hex, radix: 16)!
    return NSColor(red: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255, blue: CGFloat(v & 0xff) / 255, alpha: 1)
}
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
let ctx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = ctx
ctx.imageInterpolation = .high
let s = size / 1024
let tile = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
let path = NSBezierPath(roundedRect: tile, xRadius: 824 * 0.2237 * s, yRadius: 824 * 0.2237 * s)
// 投影
let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.30); shadow.shadowOffset = NSSize(width: 0, height: -12 * s); shadow.shadowBlurRadius = 24 * s
NSGraphicsContext.saveGraphicsState(); shadow.set(); color(bottom).set(); path.fill(); NSGraphicsContext.restoreGraphicsState()
// 渐变底
NSGradient(starting: color(top), ending: color(bottom))!.draw(in: path, angle: -90)
// 顶部高光
NSGraphicsContext.saveGraphicsState(); path.addClip()
NSGradient(starting: NSColor.white.withAlphaComponent(0), ending: NSColor.white.withAlphaComponent(0.16))!.draw(in: tile, angle: 90)
NSGraphicsContext.restoreGraphicsState()
// 主符号
func draw(_ name: String, pointSize: CGFloat, center: NSPoint, alpha: CGFloat = 1) {
    let cfg = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
    guard let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(cfg) else { fatalError("missing \(name)") }
    let sz = img.size
    let tinted = NSImage(size: sz); tinted.lockFocus()
    img.draw(in: NSRect(origin: .zero, size: sz)); NSColor.white.withAlphaComponent(alpha).set(); NSRect(origin: .zero, size: sz).fill(using: .sourceAtop)
    tinted.unlockFocus()
    let sh = NSShadow(); sh.shadowColor = NSColor.black.withAlphaComponent(0.18); sh.shadowOffset = NSSize(width: 0, height: -6 * s); sh.shadowBlurRadius = 10 * s
    NSGraphicsContext.saveGraphicsState(); sh.set()
    tinted.draw(in: NSRect(x: center.x - sz.width / 2, y: center.y - sz.height / 2, width: sz.width, height: sz.height))
    NSGraphicsContext.restoreGraphicsState()
}
if let badge {
    draw(symbol, pointSize: 340 * s, center: NSPoint(x: 512 * s, y: 575 * s))
    draw(badge, pointSize: 170 * s, center: NSPoint(x: 512 * s, y: 330 * s), alpha: 0.92)
} else {
    draw(symbol, pointSize: 400 * s, center: NSPoint(x: 512 * s, y: 512 * s))
}
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
