#!/usr/bin/env swift
//
//  generate_icon.swift
//  GitKeys — app icon generator
//
//  Standalone script (no package dependencies). Renders the GitKeys app icon
//  natively at every macOS iconset size with CoreGraphics, writes a complete
//  AppIcon.iconset, and compiles it to Assets/AppIcon.icns with `iconutil`.
//
//  Usage:  swift scripts/generate_icon.swift
//

import AppKit
import Foundation

// MARK: - Paths (resolved relative to this script, so cwd does not matter)

let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
let repoRoot = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let assetsDir = repoRoot.appendingPathComponent("Assets")
let iconsetDir = assetsDir.appendingPathComponent("AppIcon.iconset")
let icnsURL = assetsDir.appendingPathComponent("AppIcon.icns")
let previewURL = assetsDir.appendingPathComponent("icon-preview.png")

// MARK: - Color helpers

let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

func srgb(_ hex: UInt32, _ alpha: CGFloat = 1.0) -> CGColor {
    let r = CGFloat((hex >> 16) & 0xFF) / 255.0
    let g = CGFloat((hex >> 8) & 0xFF) / 255.0
    let b = CGFloat(hex & 0xFF) / 255.0
    return CGColor(colorSpace: colorSpace, components: [r, g, b, alpha])!
}

// Palette
let slateDeep = 0x0F172A as UInt32   // deep slate (bottom-left)
let indigoMid = 0x312E81 as UInt32   // indigo (middle)
let indigoHi  = 0x4F46E5 as UInt32   // indigo (top-right)
let cyan      = 0x22D3EE as UInt32   // accent cyan
let white     = 0xFFFFFF as UInt32

// MARK: - Rendering
//
// All geometry is authored in a 1024x1024 reference space (CG coordinates,
// origin bottom-left, y up) and multiplied by `f = pixels / 1024` so every
// iconset size is rendered natively rather than downscaled.

func renderIcon(pixels: Int) -> CGImage {
    let side = CGFloat(pixels)
    let f = side / 1024.0

    let ctx = CGContext(
        data: nil,
        width: pixels,
        height: pixels,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high

    // ---- Rounded square plate (Apple icon-grid margins: ~100px inset @1024) ----
    let inset = 100 * f
    let corner = 185 * f
    let plate = CGRect(x: inset, y: inset, width: side - 2 * inset, height: side - 2 * inset)
    let platePath = CGPath(roundedRect: plate, cornerWidth: corner, cornerHeight: corner, transform: nil)

    ctx.saveGState()
    ctx.addPath(platePath)
    ctx.clip()

    // Diagonal background gradient: deep slate (bottom-left) -> indigo (top-right)
    let bgGradient = CGGradient(
        colorsSpace: colorSpace,
        colors: [srgb(slateDeep), srgb(indigoMid), srgb(indigoHi)] as CFArray,
        locations: [0.0, 0.55, 1.0]
    )!
    ctx.drawLinearGradient(
        bgGradient,
        start: CGPoint(x: plate.minX, y: plate.minY),
        end: CGPoint(x: plate.maxX, y: plate.maxY),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )

    // Soft cyan radial glow near the top-right
    let glowGradient = CGGradient(
        colorsSpace: colorSpace,
        colors: [srgb(cyan, 0.30), srgb(cyan, 0.0)] as CFArray,
        locations: [0.0, 1.0]
    )!
    let glowCenter = CGPoint(x: 800 * f, y: 810 * f)
    ctx.drawRadialGradient(
        glowGradient,
        startCenter: glowCenter, startRadius: 0,
        endCenter: glowCenter, endRadius: 560 * f,
        options: []
    )

    // Subtle top inner highlight for depth (white, low alpha, top third)
    let highlight = CGGradient(
        colorsSpace: colorSpace,
        colors: [srgb(white, 0.08), srgb(white, 0.0)] as CFArray,
        locations: [0.0, 1.0]
    )!
    ctx.drawLinearGradient(
        highlight,
        start: CGPoint(x: side / 2, y: plate.maxY),
        end: CGPoint(x: side / 2, y: plate.maxY - plate.height * 0.36),
        options: []
    )

    // ---- Terminal chevron '>' accent, bottom-left (skipped at small sizes) ----
    if pixels >= 64 {
        let chevron = CGMutablePath()
        chevron.move(to: CGPoint(x: 224 * f, y: 320 * f))
        chevron.addLine(to: CGPoint(x: 292 * f, y: 262 * f))
        chevron.addLine(to: CGPoint(x: 224 * f, y: 204 * f))

        ctx.saveGState()
        ctx.addPath(chevron)
        ctx.setStrokeColor(srgb(cyan, 0.85))
        ctx.setLineWidth(32 * f)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.strokePath()
        ctx.restoreGState()
    }

    // ---- Key glyph ----
    //
    // Authored along the +x axis in local coordinates (ring/head at the
    // origin, shaft toward +x, teeth toward -y), then rotated -45 degrees so
    // the head sits top-left and the shaft points bottom-right.

    // Slightly thicken strokes at tiny sizes so the glyph stays legible.
    let strokeBoost: CGFloat
    switch pixels {
    case ..<32:   strokeBoost = 1.70
    case ..<64:   strokeBoost = 1.35
    case ..<128:  strokeBoost = 1.12
    default:      strokeBoost = 1.0
    }
    let lineWidth = 62 * f * strokeBoost

    let ringRadius: CGFloat = 120   // centerline radius of the key head ring
    let shaftEnd: CGFloat = 480     // tip of the shaft
    let toothA: CGFloat = 480       // tooth at the tip
    let toothB: CGFloat = 372       // second tooth
    let toothALen: CGFloat = 105
    let toothBLen: CGFloat = 86

    let key = CGMutablePath()
    key.addEllipse(in: CGRect(x: -ringRadius * f, y: -ringRadius * f,
                              width: 2 * ringRadius * f, height: 2 * ringRadius * f))
    key.move(to: CGPoint(x: ringRadius * f, y: 0))
    key.addLine(to: CGPoint(x: shaftEnd * f, y: 0))
    key.move(to: CGPoint(x: toothA * f, y: 0))
    key.addLine(to: CGPoint(x: toothA * f, y: -toothALen * f))
    key.move(to: CGPoint(x: toothB * f, y: 0))
    key.addLine(to: CGPoint(x: toothB * f, y: -toothBLen * f))

    // Center the glyph: local x extent is [-151, 511] -> midpoint ~180.
    ctx.saveGState()
    ctx.translateBy(x: side / 2, y: side / 2)
    ctx.rotate(by: -.pi / 4)
    ctx.translateBy(x: -180 * f, y: 14 * f)

    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.setLineWidth(lineWidth)
    ctx.setStrokeColor(srgb(white))

    // Pass 1: faint cyan outer glow (zero-offset shadow).
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 46 * f, color: srgb(cyan, 0.55))
    ctx.addPath(key)
    ctx.strokePath()
    ctx.restoreGState()

    // Pass 2: soft dark drop shadow + crisp white glyph on top.
    // (Shadow offsets live in base space, so "down" stays down despite the rotation.)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -16 * f), blur: 30 * f,
                  color: srgb(0x000000, 0.45))
    ctx.addPath(key)
    ctx.strokePath()
    ctx.restoreGState()

    ctx.restoreGState() // key transform
    ctx.restoreGState() // plate clip

    return ctx.makeImage()!
}

// MARK: - PNG encoding

func pngData(for image: CGImage) -> Data {
    let rep = NSBitmapImageRep(cgImage: image)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("Failed to encode PNG")
    }
    return data
}

// MARK: - Main

let fm = FileManager.default

do {
    try fm.createDirectory(at: assetsDir, withIntermediateDirectories: true)
    if fm.fileExists(atPath: iconsetDir.path) {
        try fm.removeItem(at: iconsetDir)
    }
    try fm.createDirectory(at: iconsetDir, withIntermediateDirectories: true)
} catch {
    fputs("error: could not prepare output directories: \(error)\n", stderr)
    exit(1)
}

// (points, scale) pairs required by iconutil.
let iconsetEntries: [(points: Int, scale: Int)] = [
    (16, 1), (16, 2),
    (32, 1), (32, 2),
    (128, 1), (128, 2),
    (256, 1), (256, 2),
    (512, 1), (512, 2),
]

// Render each unique pixel size once, natively.
var renderedBySize: [Int: Data] = [:]
for entry in iconsetEntries {
    let pixels = entry.points * entry.scale
    if renderedBySize[pixels] == nil {
        renderedBySize[pixels] = pngData(for: renderIcon(pixels: pixels))
    }
}

for entry in iconsetEntries {
    let pixels = entry.points * entry.scale
    let suffix = entry.scale == 2 ? "@2x" : ""
    let name = "icon_\(entry.points)x\(entry.points)\(suffix).png"
    let url = iconsetDir.appendingPathComponent(name)
    do {
        try renderedBySize[pixels]!.write(to: url)
        print("wrote \(name) (\(pixels)x\(pixels))")
    } catch {
        fputs("error: could not write \(name): \(error)\n", stderr)
        exit(1)
    }
}

// 256px preview for humans.
do {
    try renderedBySize[256]!.write(to: previewURL)
    print("wrote \(previewURL.path)")
} catch {
    fputs("error: could not write preview: \(error)\n", stderr)
    exit(1)
}

// Compile the .icns with iconutil.
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconsetDir.path, "-o", icnsURL.path]
do {
    try iconutil.run()
    iconutil.waitUntilExit()
} catch {
    fputs("error: failed to launch iconutil: \(error)\n", stderr)
    exit(1)
}
guard iconutil.terminationStatus == 0 else {
    fputs("error: iconutil exited with status \(iconutil.terminationStatus)\n", stderr)
    exit(1)
}

let icnsSize = (try? fm.attributesOfItem(atPath: icnsURL.path)[.size] as? Int).flatMap { $0 } ?? 0
print("wrote \(icnsURL.path) (\(icnsSize) bytes)")
guard icnsSize > 0 else {
    fputs("error: AppIcon.icns is empty\n", stderr)
    exit(1)
}
print("done")
