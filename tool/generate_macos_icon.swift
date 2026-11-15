// Generates the macOS app icon (AppIcon.appiconset) from the in-app MegaLogo
// mark: a white geometric "M" in a MEGA Red circle, glowing red, on a dark
// squircle that follows Apple's icon grid (824×824 body on a 1024 canvas).
//
//   swift tool/generate_macos_icon.swift
//
// Each size is drawn from vectors (not downscaled) so small sizes stay crisp.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let outDir = CommandLine.arguments.count > 1
  ? CommandLine.arguments[1]
  : "macos/Runner/Assets.xcassets/AppIcon.appiconset"

let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
  CGColor(colorSpace: srgb, components: [
    CGFloat((hex >> 16) & 0xFF) / 255,
    CGFloat((hex >> 8) & 0xFF) / 255,
    CGFloat(hex & 0xFF) / 255,
    a,
  ])!
}

// Palette — lib/app_theme.dart
let megaRed = rgb(0xD9272E)
let megaRedHover = rgb(0xC22026)
let megaRedLight = rgb(0xEE3A40)

/// Apple-style squircle (superellipse, n = 5) centred in the canvas.
func squircle(center c: CGPoint, half a: CGFloat, n: CGFloat = 5) -> CGPath {
  let p = CGMutablePath()
  let steps = 720
  for i in 0...steps {
    let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
    let ct = cos(t), st = sin(t)
    let x = c.x + a * (ct < 0 ? -1 : 1) * pow(abs(ct), 2 / n)
    let y = c.y + a * (st < 0 ? -1 : 1) * pow(abs(st), 2 / n)
    i == 0 ? p.move(to: CGPoint(x: x, y: y)) : p.addLine(to: CGPoint(x: x, y: y))
  }
  p.closeSubpath()
  return p
}

func render(px: Int) -> CGImage {
  let ctx = CGContext(
    data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
    space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  ctx.interpolationQuality = .high
  ctx.setShouldAntialias(true)

  // Design in a 1024 space, y-down like the SVG/Flutter painter.
  let k = CGFloat(px) / 1024
  ctx.translateBy(x: 0, y: CGFloat(px))
  ctx.scaleBy(x: k, y: -k)
  // Shadows ignore the CTM: scale blur/offset by k; offsets are y-up.
  func shadow(_ dy: CGFloat, _ blur: CGFloat, _ color: CGColor) {
    ctx.setShadow(offset: CGSize(width: 0, height: -dy * k), blur: blur * k, color: color)
  }

  let center = CGPoint(x: 512, y: 512)
  let body = squircle(center: center, half: 412)

  // 1. Squircle body with Apple's soft drop shadow.
  ctx.saveGState()
  shadow(10, 22, rgb(0x000000, 0.45))
  ctx.addPath(body)
  ctx.setFillColor(rgb(0x0B0B0C))
  ctx.fillPath()
  ctx.restoreGState()

  // 2. Fill: near-black vertical gradient + red glow behind the mark.
  ctx.saveGState()
  ctx.addPath(body)
  ctx.clip()
  let bg = CGGradient(
    colorsSpace: srgb,
    colors: [rgb(0x1E1E21), rgb(0x0A0A0B), rgb(0x000000)] as CFArray,
    locations: [0, 0.55, 1])!
  ctx.drawLinearGradient(
    bg, start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])
  let halo = CGGradient(
    colorsSpace: srgb,
    colors: [rgb(0xD9272E, 0.55), rgb(0xD9272E, 0.18), rgb(0xD9272E, 0)] as CFArray,
    locations: [0, 0.55, 1])!
  ctx.drawRadialGradient(
    halo, startCenter: CGPoint(x: 512, y: 540), startRadius: 0,
    endCenter: CGPoint(x: 512, y: 540), endRadius: 430, options: [])
  ctx.restoreGState()

  // 3. Hairline rim so the icon reads on dark Docks / wallpapers.
  ctx.saveGState()
  ctx.addPath(body)
  ctx.clip()
  ctx.addPath(body)
  ctx.setStrokeColor(rgb(0xFFFFFF, 0.10))
  ctx.setLineWidth(max(4, 1.5 / k))
  ctx.strokePath()
  ctx.restoreGState()

  // 4. The MegaLogo mark: circle r=48 in a 100-unit box → here r = 270.
  let r: CGFloat = 270
  let s = r / 48
  let disc = CGPath(
    ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r),
    transform: nil)

  // Glow: a wide soft bloom plus a tighter, brighter one (like glow: true),
  // kept inside the squircle.
  for (dy, blur, alpha) in [(24.0, 150.0, 0.85), (12.0, 60.0, 0.75)] {
    ctx.saveGState()
    ctx.addPath(body)
    ctx.clip()
    shadow(dy, blur, rgb(0xFF2A31, alpha))
    ctx.addPath(disc)
    ctx.setFillColor(megaRed)
    ctx.fillPath()
    ctx.restoreGState()
  }

  // Disc fill: subtle top-lit gradient over MEGA Red.
  ctx.saveGState()
  ctx.addPath(disc)
  ctx.clip()
  let discFill = CGGradient(
    colorsSpace: srgb, colors: [megaRedLight, megaRed, megaRedHover] as CFArray,
    locations: [0, 0.5, 1])!
  ctx.drawLinearGradient(
    discFill, start: CGPoint(x: 512, y: center.y - r),
    end: CGPoint(x: 512, y: center.y + r), options: [])
  ctx.restoreGState()

  // White "M": path M25 68 V32 L50 55 L75 32 V68, stroke 10, round caps/joins.
  func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
    CGPoint(x: center.x + (x - 50) * s, y: center.y + (y - 50) * s)
  }
  let m = CGMutablePath()
  m.move(to: pt(25, 68))
  m.addLine(to: pt(25, 32))
  m.addLine(to: pt(50, 55))
  m.addLine(to: pt(75, 32))
  m.addLine(to: pt(75, 68))
  ctx.saveGState()
  shadow(6, 14, rgb(0x5A0005, 0.45))
  ctx.addPath(m)
  ctx.setStrokeColor(rgb(0xFFFFFF))
  ctx.setLineWidth(10 * s)
  ctx.setLineCap(.round)
  ctx.setLineJoin(.round)
  ctx.strokePath()
  ctx.restoreGState()

  return ctx.makeImage()!
}

func writePNG(_ img: CGImage, to path: String) {
  let url = URL(fileURLWithPath: path) as CFURL
  let dest = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil)!
  CGImageDestinationAddImage(dest, img, nil)
  guard CGImageDestinationFinalize(dest) else { fatalError("write failed: \(path)") }
}

try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
for px in [16, 32, 64, 128, 256, 512, 1024] {
  let path = "\(outDir)/app_icon_\(px).png"
  writePNG(render(px: px), to: path)
  print("wrote \(path)")
}
