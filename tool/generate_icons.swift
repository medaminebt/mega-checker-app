// Generates every app icon from the in-app MegaLogo mark: a white geometric
// "M" in a glowing MEGA Red circle on a near-black body.
//
//   swift tool/generate_icons.swift          (run from the repo root)
//
// Writes:
//   macOS    macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_*.png
//            (squircle on Apple's icon grid: 824×824 body on a 1024 canvas)
//   Web      web/favicon.png, web/favicon.ico, web/icons/Icon-*.png,
//            web/icons/Icon-maskable-*.png, web/icons/apple-touch-icon.png
//   Windows  windows/runner/resources/app_icon.ico
//
// Each size is drawn from vectors (not downscaled) so small sizes stay crisp.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let root = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

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

/// Icon shapes.
///  - macos:   Apple squircle with margins + drop shadow (Dock icon)
///  - rounded: squircle filling the canvas (favicons, Windows, PWA "any")
///  - square:  full-bleed square, mark inside the safe zone (PWA "maskable",
///             apple-touch-icon: the OS applies its own mask)
enum Style { case macos, rounded, square }

struct Geometry {
  let bodyHalf: CGFloat  // squircle half-size in the 1024 design space
  let dropShadow: Bool
  let discRadius: CGFloat  // red disc radius in the 1024 design space
}

func geometry(_ style: Style) -> Geometry {
  switch style {
  case .macos: return Geometry(bodyHalf: 412, dropShadow: true, discRadius: 270)
  case .rounded: return Geometry(bodyHalf: 508, dropShadow: false, discRadius: 336)
  case .square: return Geometry(bodyHalf: 512, dropShadow: false, discRadius: 270)
  }
}

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

func render(px: Int, style: Style = .macos) -> CGImage {
  let g = geometry(style)
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
  let body = style == .square
    ? CGPath(rect: CGRect(x: 0, y: 0, width: 1024, height: 1024), transform: nil)
    : squircle(center: center, half: g.bodyHalf)
  // Glow sizes were tuned for the macOS disc (r = 270); scale with the disc.
  let u = g.discRadius / 270

  // 1. Body (with Apple's soft drop shadow on macOS).
  ctx.saveGState()
  if g.dropShadow { shadow(10, 22, rgb(0x000000, 0.45)) }
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
    bg, start: CGPoint(x: 512, y: 512 - g.bodyHalf), end: CGPoint(x: 512, y: 512 + g.bodyHalf),
    options: [])
  let halo = CGGradient(
    colorsSpace: srgb,
    colors: [rgb(0xD9272E, 0.55), rgb(0xD9272E, 0.18), rgb(0xD9272E, 0)] as CFArray,
    locations: [0, 0.55, 1])!
  ctx.drawRadialGradient(
    halo, startCenter: CGPoint(x: 512, y: 512 + 28 * u), startRadius: 0,
    endCenter: CGPoint(x: 512, y: 512 + 28 * u), endRadius: 430 * u, options: [])
  ctx.restoreGState()

  // 3. Hairline rim so the icon reads on dark Docks / wallpapers / tabs.
  if style != .square {
    ctx.saveGState()
    ctx.addPath(body)
    ctx.clip()
    ctx.addPath(body)
    ctx.setStrokeColor(rgb(0xFFFFFF, 0.10))
    ctx.setLineWidth(max(4, 1.5 / k))
    ctx.strokePath()
    ctx.restoreGState()
  }

  // 4. The MegaLogo mark: circle r=48 in a 100-unit box.
  let r = g.discRadius
  let s = r / 48
  let disc = CGPath(
    ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r),
    transform: nil)

  // Glow: a wide soft bloom plus a tighter, brighter one (like glow: true),
  // kept inside the body.
  for (dy, blur, alpha) in [(24.0, 150.0, 0.85), (12.0, 60.0, 0.75)] {
    ctx.saveGState()
    ctx.addPath(body)
    ctx.clip()
    shadow(dy * u, blur * u, rgb(0xFF2A31, alpha))
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
  shadow(6 * u, 14 * u, rgb(0x5A0005, 0.45))
  ctx.addPath(m)
  ctx.setStrokeColor(rgb(0xFFFFFF))
  ctx.setLineWidth(10 * s)
  ctx.setLineCap(.round)
  ctx.setLineJoin(.round)
  ctx.strokePath()
  ctx.restoreGState()

  return ctx.makeImage()!
}

// ---- encoders ---------------------------------------------------------------

func pngData(_ img: CGImage) -> Data {
  let data = NSMutableData()
  let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
  CGImageDestinationAddImage(dest, img, nil)
  guard CGImageDestinationFinalize(dest) else { fatalError("PNG encode failed") }
  return data as Data
}

func write(_ data: Data, to path: String) {
  let url = URL(fileURLWithPath: "\(root)/\(path)")
  try! FileManager.default.createDirectory(
    at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
  try! data.write(to: url)
  print("wrote \(path)")
}

extension Data {
  mutating func u8(_ v: Int) { append(UInt8(truncatingIfNeeded: v)) }
  mutating func u16(_ v: Int) { u8(v); u8(v >> 8) }
  mutating func u32(_ v: Int) { u16(v); u16(v >> 16) }
}

/// 32-bit BGRA DIB (+ empty AND mask) — the classic .ico entry format, used
/// for sizes below 256 so every Windows tool and browser reads them.
func dibData(_ img: CGImage) -> Data {
  let w = img.width, h = img.height
  var rgba = [UInt8](repeating: 0, count: w * h * 4)  // premultiplied, top row first
  rgba.withUnsafeMutableBytes { p in
    let c = CGContext(
      data: p.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
      space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
  }
  let maskRow = ((w + 31) / 32) * 4
  var d = Data()
  d.u32(40); d.u32(w); d.u32(h * 2); d.u16(1); d.u16(32)  // BITMAPINFOHEADER
  d.u32(0); d.u32(w * h * 4 + maskRow * h); d.u32(0); d.u32(0); d.u32(0); d.u32(0)
  for y in (0..<h).reversed() {  // DIB rows are bottom-up
    for x in 0..<w {
      let i = (y * w + x) * 4
      let a = Int(rgba[i + 3])
      func straight(_ v: UInt8) -> Int { a == 0 ? 0 : min(255, (Int(v) * 255 + a / 2) / a) }
      d.u8(straight(rgba[i + 2])); d.u8(straight(rgba[i + 1])); d.u8(straight(rgba[i])); d.u8(a)
    }
  }
  d.append(Data(count: maskRow * h))
  return d
}

func icoData(sizes: [Int], style: Style) -> Data {
  let images = sizes.map { px -> Data in
    let img = render(px: px, style: style)
    return px >= 256 ? pngData(img) : dibData(img)
  }
  var d = Data()
  d.u16(0); d.u16(1); d.u16(sizes.count)  // ICONDIR
  var offset = 6 + 16 * sizes.count
  for (px, img) in zip(sizes, images) {  // ICONDIRENTRY
    d.u8(px >= 256 ? 0 : px); d.u8(px >= 256 ? 0 : px); d.u8(0); d.u8(0)
    d.u16(1); d.u16(32); d.u32(img.count); d.u32(offset)
    offset += img.count
  }
  images.forEach { d.append($0) }
  return d
}

// ---- outputs ----------------------------------------------------------------

for px in [16, 32, 64, 128, 256, 512, 1024] {
  write(
    pngData(render(px: px, style: .macos)),
    to: "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_\(px).png")
}

write(pngData(render(px: 32, style: .rounded)), to: "web/favicon.png")
write(icoData(sizes: [16, 32, 48], style: .rounded), to: "web/favicon.ico")
for px in [192, 512] {
  write(pngData(render(px: px, style: .rounded)), to: "web/icons/Icon-\(px).png")
  write(pngData(render(px: px, style: .square)), to: "web/icons/Icon-maskable-\(px).png")
}
write(pngData(render(px: 180, style: .square)), to: "web/icons/apple-touch-icon.png")

write(
  icoData(sizes: [16, 20, 24, 32, 40, 48, 64, 256], style: .rounded),
  to: "windows/runner/resources/app_icon.ico")
