// Draws the background of the macOS installer window (the .dmg):
// title, the app on the left, a red "Drag to install" arrow, a dashed drop
// zone around the Applications folder, and a first-launch tip.
//
//   swift tool/generate_dmg_background.swift
//
// Writes macos/packaging/dmg-background.png (660×460) and @2x. The design
// fills the top 420 pt (what a 452 pt tall Finder window shows under its
// 32 pt title bar); the rest is spare background for Macs whose title bar
// is shorter. The icon positions in macos/packaging/dmg_settings.py must
// match `appX`, `appsX` and `iconY` below.
//
// Light on purpose: once a Finder window has a background picture, Finder
// draws the icon names in black, even in Dark Mode.
import AppKit
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let width: CGFloat = 660
let height: CGFloat = 460
let appX: CGFloat = 160 // icon centres, Finder coordinates (y down)
let appsX: CGFloat = 500
let iconY: CGFloat = 212
let outDir = CommandLine.arguments.count > 1
  ? CommandLine.arguments[1] : "macos/packaging"

// ---- palette (lib/app_theme.dart, light) ----------------------------------
let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
  CGColor(colorSpace: srgb, components: [
    CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255,
    CGFloat(hex & 0xFF) / 255, a,
  ])!
}
let megaRed = rgb(0xD9272E)
let megaRedLight = rgb(0xEE3A40)
let megaRedDark = rgb(0xC22026)
let indigo = rgb(0x3F42C3)
let textPrimary = rgb(0x15151A)
let textSecondary = rgb(0x55555F)
let border = rgb(0xCFD3DA)

// ---- fonts: the app's bundled Lexend ----------------------------------------
func font(_ file: String, _ size: CGFloat) -> CTFont {
  let url = URL(fileURLWithPath: "assets/fonts/\(file).ttf") as CFURL
  guard let descs = CTFontManagerCreateFontDescriptorsFromURL(url) as? [CTFontDescriptor],
    let d = descs.first
  else { fatalError("Run from the repository root (needs assets/fonts/\(file).ttf)") }
  return CTFontCreateWithFontDescriptor(d, size, nil)
}

func line(_ text: String, _ f: CTFont, _ color: CGColor) -> CTLine {
  let attrs: [NSAttributedString.Key: Any] = [
    NSAttributedString.Key(kCTFontAttributeName as String): f,
    NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
  ]
  return CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
}

func lineWidth(_ l: CTLine) -> CGFloat {
  CGFloat(CTLineGetTypographicBounds(l, nil, nil, nil))
}

func render(scale k: CGFloat) -> CGImage {
  let w = Int(width * k), h = Int(height * k)
  let ctx = CGContext(
    data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
    space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  ctx.scaleBy(x: k, y: k)
  // Work in Finder's coordinates (origin top-left, y down).
  func y(_ v: CGFloat) -> CGFloat { height - v }

  // Background: white fading to a soft grey.
  let bg = CGGradient(
    colorsSpace: srgb, colors: [rgb(0xFFFFFF), rgb(0xF1F1F4)] as CFArray,
    locations: [0, 1])!
  ctx.drawLinearGradient(
    bg, start: CGPoint(x: 0, y: y(0)), end: CGPoint(x: 0, y: y(height)), options: [])

  // Red strip along the top, like the app's header.
  ctx.setFillColor(megaRed)
  ctx.fill(CGRect(x: 0, y: y(4), width: width, height: 4))

  // Title with a small red "M" badge, centred.
  let title = line("Install MEGA Keep-Alive", font("Lexend-Bold", 22), textPrimary)
  let badge: CGFloat = 30, gap: CGFloat = 10
  let titleW = lineWidth(title)
  let startX = (width - (badge + gap + titleW)) / 2
  let badgeRect = CGRect(x: startX, y: y(58) - badge / 2, width: badge, height: badge)
  ctx.setFillColor(megaRed)
  ctx.fillEllipse(in: badgeRect)
  let m = line("M", font("Lexend-Bold", 17), rgb(0xFFFFFF))
  ctx.textPosition = CGPoint(x: badgeRect.midX - lineWidth(m) / 2, y: badgeRect.midY - 6)
  CTLineDraw(m, ctx)
  ctx.textPosition = CGPoint(x: startX + badge + gap, y: y(58) - 7.5)
  CTLineDraw(title, ctx)

  let sub = line(
    "Drag the app onto the Applications folder.", font("Lexend-Regular", 14), textSecondary)
  ctx.textPosition = CGPoint(x: (width - lineWidth(sub)) / 2, y: y(94))
  CTLineDraw(sub, ctx)

  // A white card behind the app icon (Finder draws the icon and its name).
  let card = CGRect(x: appX - 86, y: y(iconY + 96), width: 172, height: 182)
  ctx.saveGState()
  ctx.setShadow(offset: CGSize(width: 0, height: -3), blur: 14, color: rgb(0x000000, 0.10))
  ctx.addPath(CGPath(roundedRect: card, cornerWidth: 18, cornerHeight: 18, transform: nil))
  ctx.setFillColor(rgb(0xFFFFFF))
  ctx.fillPath()
  ctx.restoreGState()
  ctx.addPath(CGPath(roundedRect: card, cornerWidth: 18, cornerHeight: 18, transform: nil))
  ctx.setStrokeColor(rgb(0xE6E7EB))
  ctx.setLineWidth(1)
  ctx.strokePath()

  // Dashed drop zone around the Applications folder.
  let zone = CGRect(x: appsX - 86, y: y(iconY + 96), width: 172, height: 182)
  ctx.addPath(CGPath(roundedRect: zone, cornerWidth: 18, cornerHeight: 18, transform: nil))
  ctx.setFillColor(rgb(0x3F42C3, 0.04))
  ctx.fillPath()
  ctx.addPath(CGPath(roundedRect: zone, cornerWidth: 18, cornerHeight: 18, transform: nil))
  ctx.setStrokeColor(rgb(0x3F42C3, 0.55))
  ctx.setLineWidth(1.6)
  ctx.setLineDash(phase: 0, lengths: [7, 5])
  ctx.strokePath()
  ctx.setLineDash(phase: 0, lengths: [])

  // The arrow: a rounded body with the text inside, and a head.
  let x0 = appX + 96, x1 = appsX - 96
  let cy = y(iconY - 4)
  let bodyH: CGFloat = 46, headH: CGFloat = 78, headW: CGFloat = 40
  let xh = x1 - headW
  let r = bodyH / 2
  let arrow = CGMutablePath()
  arrow.move(to: CGPoint(x: x0 + r, y: cy + bodyH / 2))
  arrow.addLine(to: CGPoint(x: xh, y: cy + bodyH / 2))
  arrow.addLine(to: CGPoint(x: xh, y: cy + headH / 2))
  arrow.addLine(to: CGPoint(x: x1, y: cy))
  arrow.addLine(to: CGPoint(x: xh, y: cy - headH / 2))
  arrow.addLine(to: CGPoint(x: xh, y: cy - bodyH / 2))
  arrow.addLine(to: CGPoint(x: x0 + r, y: cy - bodyH / 2))
  arrow.addArc(
    center: CGPoint(x: x0 + r, y: cy), radius: r, startAngle: -.pi / 2,
    endAngle: .pi / 2, clockwise: true)
  arrow.closeSubpath()

  ctx.saveGState()
  ctx.setShadow(offset: CGSize(width: 0, height: -4), blur: 12, color: rgb(0xD9272E, 0.35))
  ctx.addPath(arrow)
  ctx.setFillColor(megaRed)
  ctx.fillPath()
  ctx.restoreGState()
  ctx.saveGState()
  ctx.addPath(arrow)
  ctx.clip()
  let fill = CGGradient(
    colorsSpace: srgb, colors: [megaRedLight, megaRedDark] as CFArray, locations: [0, 1])!
  ctx.drawLinearGradient(
    fill, start: CGPoint(x: 0, y: cy + headH / 2), end: CGPoint(x: 0, y: cy - headH / 2),
    options: [])
  ctx.restoreGState()

  let drag = line("Drag to install", font("Lexend-SemiBold", 13), rgb(0xFFFFFF))
  let bodyMid = (x0 + xh) / 2 + 4
  ctx.textPosition = CGPoint(x: bodyMid - lineWidth(drag) / 2, y: cy - 4.5)
  CTLineDraw(drag, ctx)

  // First-launch tip at the bottom (the app isn't notarized by Apple).
  let tipRect = CGRect(x: 40, y: y(398), width: width - 80, height: 52)
  ctx.addPath(CGPath(roundedRect: tipRect, cornerWidth: 12, cornerHeight: 12, transform: nil))
  ctx.setFillColor(rgb(0xFFFFFF))
  ctx.fillPath()
  ctx.addPath(CGPath(roundedRect: tipRect, cornerWidth: 12, cornerHeight: 12, transform: nil))
  ctx.setStrokeColor(border)
  ctx.setLineWidth(1)
  ctx.strokePath()
  let dot = CGRect(x: tipRect.minX + 16, y: tipRect.midY - 11, width: 22, height: 22)
  ctx.setFillColor(indigo)
  ctx.fillEllipse(in: dot)
  let i = line("i", font("Lexend-Bold", 14), rgb(0xFFFFFF))
  ctx.textPosition = CGPoint(x: dot.midX - lineWidth(i) / 2, y: dot.midY - 5)
  CTLineDraw(i, ctx)
  let tip1 = line(
    "First launch: if macOS says it can't verify the app, open",
    font("Lexend-Regular", 12), textSecondary)
  let tip2 = line(
    "System Settings › Privacy & Security, then click Open Anyway.",
    font("Lexend-SemiBold", 12), textPrimary)
  ctx.textPosition = CGPoint(x: dot.maxX + 12, y: tipRect.midY + 3)
  CTLineDraw(tip1, ctx)
  ctx.textPosition = CGPoint(x: dot.maxX + 12, y: tipRect.midY - 13)
  CTLineDraw(tip2, ctx)

  return ctx.makeImage()!
}

func save(_ img: CGImage, _ name: String, dpi: CGFloat) {
  let url = URL(fileURLWithPath: "\(outDir)/\(name)") as CFURL
  let dest = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil)!
  CGImageDestinationAddImage(
    dest, img, [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi] as CFDictionary)
  CGImageDestinationFinalize(dest)
  print("wrote \(outDir)/\(name)")
}

try FileManager.default.createDirectory(
  atPath: outDir, withIntermediateDirectories: true)
save(render(scale: 1), "dmg-background.png", dpi: 72)
save(render(scale: 2), "dmg-background@2x.png", dpi: 144)
