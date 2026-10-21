// Draws the app icon: swift tools/make-icon.swift Bench/Assets.xcassets/AppIcon.appiconset
import AppKit

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func render(_ path: String, dark: Bool) {
    let n = 1024
    let ctx = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let top = dark ? color(0x0B2321) : color(0x14B8A6), bottom = dark ? color(0x041312) : color(0x0F766E)
    let g = CGGradient(colorsSpace: nil, colors: [top, bottom] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: CGFloat(n)), end: CGPoint(x: 0, y: 0), options: [])

    let glass = dark ? color(0x2DD4BF) : color(0xFFFFFF)
    let fill = dark ? color(0x2DD4BF, 0.85) : color(0xCCFBF1)
    // Coordinates with the origin bottom-left.
    let cx: CGFloat = 512
    let bodyW: CGFloat = 380, bodyH: CGFloat = 470, bodyY: CGFloat = 170
    let neckW: CGFloat = 200, neckH: CGFloat = 70
    let capW: CGFloat = 270, capH: CGFloat = 120
    let line: CGFloat = 34

    // Body outline with shoulders into the neck.
    let body = CGMutablePath()
    let l = cx - bodyW / 2, r = cx + bodyW / 2, b = bodyY, t = bodyY + bodyH
    let nl = cx - neckW / 2, nr = cx + neckW / 2, nt = t + 60 + neckH
    body.move(to: CGPoint(x: l + 60, y: b))
    body.addLine(to: CGPoint(x: r - 60, y: b))
    body.addQuadCurve(to: CGPoint(x: r, y: b + 60), control: CGPoint(x: r, y: b))
    body.addLine(to: CGPoint(x: r, y: t))
    body.addQuadCurve(to: CGPoint(x: nr, y: t + 60), control: CGPoint(x: r, y: t + 60))
    body.addLine(to: CGPoint(x: nr, y: nt))
    body.addLine(to: CGPoint(x: nl, y: nt))
    body.addLine(to: CGPoint(x: nl, y: t + 60))
    body.addQuadCurve(to: CGPoint(x: l, y: t), control: CGPoint(x: l, y: t + 60))
    body.addLine(to: CGPoint(x: l, y: b + 60))
    body.addQuadCurve(to: CGPoint(x: l + 60, y: b), control: CGPoint(x: l, y: b))
    body.closeSubpath()

    // Liquid: the lower part of the body, clipped to it.
    ctx.saveGState()
    ctx.addPath(body)
    ctx.clip()
    ctx.setFillColor(fill)
    ctx.fill(CGRect(x: l, y: b, width: bodyW, height: bodyH * 0.52))
    ctx.restoreGState()

    ctx.setStrokeColor(glass)
    ctx.setLineWidth(line)
    ctx.setLineJoin(.round)
    ctx.addPath(body)
    ctx.strokePath()

    // Graduations on the right of the body.
    ctx.setLineCap(.round)
    ctx.setLineWidth(22)
    for (i, w) in [CGFloat(110), 70, 110, 70].enumerated() {
        let y = b + 110 + CGFloat(i) * 80
        ctx.move(to: CGPoint(x: r - 50 - w, y: y))
        ctx.addLine(to: CGPoint(x: r - 50, y: y))
    }
    ctx.strokePath()

    // Cap.
    let cap = CGPath(roundedRect: CGRect(x: cx - capW / 2, y: nt + 10, width: capW, height: capH), cornerWidth: 28, cornerHeight: 28, transform: nil)
    ctx.setFillColor(glass)
    ctx.addPath(cap)
    ctx.fillPath()

    let image = ctx.makeImage()!
    let rep = NSBitmapImageRep(cgImage: image)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

let out = CommandLine.arguments[1]
render(out + "/AppIcon.png", dark: false)
render(out + "/AppIcon-dark.png", dark: true)
