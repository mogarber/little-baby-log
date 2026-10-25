// Renders the 1024x1024 Little Baby Log app icon (opaque PNG).
// Usage: swift scripts/make-icon.swift <out.png>
// Works with just the Command Line Tools (AppKit + CoreGraphics).

import AppKit
import CoreGraphics

let size = 1024
guard CommandLine.arguments.count >= 2 else {
    FileHandle.standardError.write(Data("usage: swift make-icon.swift <out.png>\n".utf8))
    exit(1)
}
let outPath = CommandLine.arguments[1]

let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
// noneSkipLast => no alpha channel in the output (App Store requires an opaque icon).
guard let ctx = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
    space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
) else { fatalError("could not create context") }

func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
    CGColor(colorSpace: colorSpace, components: [r / 255, g / 255, b / 255, a])!
}

let s = CGFloat(size)

// 1. Night-sky gradient: deep indigo at the top, lavender, then a hint of peach at the bottom.
let sky = CGGradient(
    colorsSpace: colorSpace,
    colors: [
        rgb(27, 24, 82),     // deep indigo
        rgb(66, 55, 136),    // indigo
        rgb(138, 118, 197),  // lavender
        rgb(246, 187, 176),  // peach
    ] as CFArray,
    locations: [0.0, 0.38, 0.75, 1.0]
)!
// CoreGraphics origin is bottom-left, so "top" is y = s.
ctx.drawLinearGradient(sky, start: CGPoint(x: s * 0.35, y: s), end: CGPoint(x: s * 0.65, y: 0),
                       options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])

// 2. Soft glow behind the moon.
let glow = CGGradient(
    colorsSpace: colorSpace,
    colors: [rgb(255, 244, 235, 0.38), rgb(255, 244, 235, 0.0)] as CFArray,
    locations: [0, 1]
)!
let moonCenter = CGPoint(x: s * 0.50, y: s * 0.52)
let moonRadius = s * 0.285
ctx.drawRadialGradient(glow, startCenter: moonCenter, startRadius: moonRadius * 0.6,
                       endCenter: moonCenter, endRadius: moonRadius * 2.1, options: [.drawsBeforeStartLocation])

// 3. Crescent: clip to the moon circle, then even-odd fill (everything + an offset circle).
//    The even-odd rule leaves only the part of the moon NOT covered by the offset circle.
//    (Using a big rect instead of a second moon circle avoids a faint antialiasing seam.)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 40, color: rgb(20, 14, 70, 0.35))
ctx.beginTransparencyLayer(auxiliaryInfo: nil)
let moonRect = CGRect(x: moonCenter.x - moonRadius, y: moonCenter.y - moonRadius,
                      width: moonRadius * 2, height: moonRadius * 2)
ctx.addEllipse(in: moonRect)
ctx.clip()
let biteRadius = moonRadius * 0.82
let biteCenter = CGPoint(x: moonCenter.x + moonRadius * 0.46, y: moonCenter.y + moonRadius * 0.30)
ctx.addRect(CGRect(x: 0, y: 0, width: s, height: s))  // inside the clip, so only the moon circle shows
ctx.addEllipse(in: CGRect(x: biteCenter.x - biteRadius, y: biteCenter.y - biteRadius,
                          width: biteRadius * 2, height: biteRadius * 2))
ctx.setFillColor(rgb(255, 252, 247))
ctx.fillPath(using: .evenOdd)
ctx.endTransparencyLayer()
ctx.restoreGState()

// 4. Stars: four-point sparkles.
func star(at c: CGPoint, radius r: CGFloat, alpha: Double) {
    let inner = r * 0.22
    let path = CGMutablePath()
    for i in 0..<8 {
        let angle = CGFloat(i) * .pi / 4 - .pi / 2
        let rad = i % 2 == 0 ? r : inner
        let p = CGPoint(x: c.x + cos(angle) * rad, y: c.y + sin(angle) * rad)
        if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
    }
    path.closeSubpath()
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: r * 0.5, color: rgb(255, 245, 230, 0.6 * alpha))
    ctx.setFillColor(rgb(255, 252, 247, alpha))
    ctx.addPath(path)
    ctx.fillPath()
    ctx.restoreGState()
}
func dot(at c: CGPoint, radius r: CGFloat, alpha: Double) {
    ctx.setFillColor(rgb(255, 252, 247, alpha))
    ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
}
star(at: CGPoint(x: s * 0.755, y: s * 0.715), radius: s * 0.062, alpha: 1.0)
star(at: CGPoint(x: s * 0.835, y: s * 0.470), radius: s * 0.034, alpha: 0.9)
star(at: CGPoint(x: s * 0.255, y: s * 0.235), radius: s * 0.040, alpha: 0.85)
dot(at: CGPoint(x: s * 0.185, y: s * 0.760), radius: s * 0.009, alpha: 0.8)
dot(at: CGPoint(x: s * 0.640, y: s * 0.865), radius: s * 0.007, alpha: 0.7)
dot(at: CGPoint(x: s * 0.785, y: s * 0.200), radius: s * 0.008, alpha: 0.6)

// 5. Write the PNG.
guard let image = ctx.makeImage() else { fatalError("could not make image") }
let rep = NSBitmapImageRep(cgImage: image)
guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("could not encode PNG") }
try png.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath) (\(size)x\(size))")
