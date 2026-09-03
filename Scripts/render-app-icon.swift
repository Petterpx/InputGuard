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
/// 渐变在某个 y 处的近似颜色（角标缺口和镂空符号用它填，视觉上等于露出背景）
func bg(at y: CGFloat) -> NSColor {
    let t = max(0, min(1, (y - tile.minY) / tile.height))
    return color(bottom).blended(withFraction: t, of: color(top))!.blended(withFraction: 0.16 * t, of: .white)!
}
func tinted(_ name: String, pointSize: CGFloat, weight: NSFont.Weight, tint: NSColor) -> NSImage {
    let cfg = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
    let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)!.withSymbolConfiguration(cfg)!
    let t = NSImage(size: img.size); t.lockFocus()
    img.draw(in: NSRect(origin: .zero, size: img.size)); tint.set(); NSRect(origin: .zero, size: img.size).fill(using: .sourceAtop)
    t.unlockFocus(); return t
}
// 键盘严格居中（pointSize 400 → 600x400）；角标是右上角一个小的带缺口实心圆，圆内镂空符号
let kbCenter = NSPoint(x: 512 * s, y: 512 * s)
draw(symbol, pointSize: 400 * s, center: kbCenter)
if let badge {
    let u = 25 * s, r = 3.0 * u, gap = 1.1 * u
    let kb = tinted(symbol, pointSize: 400 * s, weight: .medium, tint: .white)
    let corner = NSPoint(x: kbCenter.x + kb.size.width / 2, y: kbCenter.y + kb.size.height / 2)
    let c = NSPoint(x: corner.x - 1.2 * u, y: corner.y - 1.2 * u)
    bg(at: c.y).set(); NSBezierPath(ovalIn: NSRect(x: c.x - r - gap, y: c.y - r - gap, width: (r + gap) * 2, height: (r + gap) * 2)).fill()
    NSColor.white.set(); NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)).fill()
    let g = tinted(badge, pointSize: r * 1.25, weight: .bold, tint: bg(at: c.y))
    g.draw(in: NSRect(x: c.x - g.size.width / 2, y: c.y - g.size.height / 2, width: g.size.width, height: g.size.height))
}
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
