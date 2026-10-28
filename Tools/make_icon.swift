import AppKit
import CoreGraphics

// Renders the Simple Snip app icon at 1024×1024: a dashed freeform snip outline,
// a highlighter swash, and a pair of scissors on an indigo-to-sky gradient.

let size: CGFloat = 1024
let outPath = CommandLine.arguments[1]

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(
    data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
)!

// Body: Apple's macOS icon grid, 824pt squircle centered on a 1024 canvas.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let bodyPath = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185).cgPath

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.35))
ctx.addPath(bodyPath)
ctx.setFillColor(color(0x5B4FE0))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(bodyPath)
ctx.clip()
let gradient = CGGradient(
    colorsSpace: space,
    colors: [color(0x6A4FE6), color(0x3F7BF0), color(0x1FC0EA)] as CFArray,
    locations: [0, 0.5, 1]
)!
ctx.drawLinearGradient(gradient, start: CGPoint(x: 140, y: 920), end: CGPoint(x: 900, y: 110), options: [])

// Soft top sheen.
let sheen = CGGradient(
    colorsSpace: space,
    colors: [color(0xFFFFFF, 0.18), color(0xFFFFFF, 0)] as CFArray,
    locations: [0, 1]
)!
ctx.drawLinearGradient(sheen, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 560), options: [])

// Freeform snip: an organic closed loop.
let blob = CGMutablePath()
blob.move(to: CGPoint(x: 250, y: 600))
blob.addCurve(to: CGPoint(x: 470, y: 800), control1: CGPoint(x: 240, y: 720), control2: CGPoint(x: 340, y: 810))
blob.addCurve(to: CGPoint(x: 720, y: 690), control1: CGPoint(x: 600, y: 790), control2: CGPoint(x: 700, y: 780))
blob.addCurve(to: CGPoint(x: 640, y: 450), control1: CGPoint(x: 745, y: 590), control2: CGPoint(x: 700, y: 500))
blob.addCurve(to: CGPoint(x: 380, y: 360), control1: CGPoint(x: 570, y: 390), control2: CGPoint(x: 460, y: 330))
blob.addCurve(to: CGPoint(x: 250, y: 600), control1: CGPoint(x: 290, y: 395), control2: CGPoint(x: 258, y: 500))
blob.closeSubpath()

ctx.addPath(blob)
ctx.setFillColor(color(0xFFFFFF, 0.16))
ctx.fillPath()

// Highlighter swash inside the snip.
ctx.saveGState()
ctx.addPath(blob)
ctx.clip()
let swash = CGMutablePath()
swash.move(to: CGPoint(x: 330, y: 560))
swash.addCurve(to: CGPoint(x: 640, y: 640), control1: CGPoint(x: 430, y: 610), control2: CGPoint(x: 540, y: 560))
ctx.addPath(swash)
ctx.setLineCap(.round)
ctx.setLineWidth(70)
ctx.setStrokeColor(color(0xFFE14D, 0.9))
ctx.strokePath()
ctx.restoreGState()

ctx.addPath(blob)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
ctx.setLineWidth(24)
ctx.setLineDash(phase: 0, lengths: [50, 34])
ctx.setStrokeColor(color(0xFFFFFF))
ctx.strokePath()
ctx.setLineDash(phase: 0, lengths: [])

// Scissors, built pointing up around the pivot, then placed at the lower right.
func scissorsHalf(mirrored: Bool) -> CGPath {
    let s: CGFloat = mirrored ? -1 : 1
    let path = CGMutablePath()
    // Blade: wide at the pivot, tapering to a point.
    path.move(to: CGPoint(x: -22 * s, y: -10))
    path.addCurve(to: CGPoint(x: 6 * s, y: 300), control1: CGPoint(x: -30 * s, y: 120), control2: CGPoint(x: -14 * s, y: 240))
    path.addCurve(to: CGPoint(x: 24 * s, y: 0), control1: CGPoint(x: 26 * s, y: 200), control2: CGPoint(x: 30 * s, y: 90))
    path.closeSubpath()
    // Shank down to the ring.
    path.move(to: CGPoint(x: -20 * s, y: 0))
    path.addLine(to: CGPoint(x: 18 * s, y: 0))
    path.addLine(to: CGPoint(x: 70 * s, y: -110))
    path.addLine(to: CGPoint(x: 36 * s, y: -120))
    path.closeSubpath()
    var rotate = CGAffineTransform(rotationAngle: 0.20 * s)
    return path.copy(using: &rotate)!
}

func ring(mirrored: Bool) -> CGPath {
    let s: CGFloat = mirrored ? -1 : 1
    let center = CGPoint(x: 98 * s, y: -165)
    var rotate = CGAffineTransform(rotationAngle: 0.20 * s)
    return CGPath(ellipseIn: CGRect(x: center.x - 62, y: center.y - 62, width: 124, height: 124), transform: &rotate)
}

ctx.saveGState()
ctx.translateBy(x: 640, y: 400)
ctx.rotate(by: 0.85)
ctx.scaleBy(x: 0.68, y: 0.68)
ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 14, color: color(0x1B1464, 0.35))
ctx.beginTransparencyLayer(auxiliaryInfo: nil)
for mirrored in [false, true] {
    ctx.addPath(scissorsHalf(mirrored: mirrored))
    ctx.setFillColor(color(0xFFFFFF))
    ctx.fillPath()
    ctx.addPath(ring(mirrored: mirrored))
    ctx.setLineWidth(30)
    ctx.setStrokeColor(color(0xFFFFFF))
    ctx.strokePath()
}
ctx.endTransparencyLayer()
// Pivot screw.
ctx.addEllipse(in: CGRect(x: -15, y: -15, width: 30, height: 30))
ctx.setFillColor(color(0x4A63EA))
ctx.fillPath()
ctx.restoreGState()

ctx.restoreGState()

let image = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: outPath))
