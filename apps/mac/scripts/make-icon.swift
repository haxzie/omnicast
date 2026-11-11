#!/usr/bin/env swift

// Builds Omnicast.icns from a square source image.
//
// macOS icons are not full bleed: the artwork sits on Apple's icon grid — an
// 824pt rounded square centred in a 1024pt canvas — with a soft drop shadow
// baked in. Dropping a square PNG straight into a bundle gives you an icon
// that is visibly too big and too square next to every other app in the Dock.
//
//   usage: swift scripts/make-icon.swift <source.png> <output.icns>

import AppKit
import SwiftUI

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write(
        Data("usage: make-icon.swift <source.png> <output.icns>\n".utf8))
    exit(2)
}

let sourceURL = URL(fileURLWithPath: arguments[1])
let outputURL = URL(fileURLWithPath: arguments[2])

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("make-icon: \(message)\n".utf8))
    exit(1)
}

guard let source = NSImage(contentsOf: sourceURL),
    let artwork = source.cgImage(forProposedRect: nil, context: nil, hints: nil)
else { fail("could not read \(sourceURL.path)") }

// Apple's macOS icon grid, at 1024.
let canvas: CGFloat = 1024
let inset: CGFloat = 100
let side = canvas - inset * 2
// 0.225 of the side is the Big Sur squircle radius.
let cornerRadius = side * 0.225

func renderMaster() -> CGImage {
    guard
        let context = CGContext(
            data: nil, width: Int(canvas), height: Int(canvas), bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { fail("could not create the icon context") }

    context.interpolationQuality = .high

    let square = CGRect(x: inset, y: inset, width: side, height: side)
    // `.continuous` gives Apple's squircle curvature rather than a plain
    // circular corner, which reads as subtly wrong beside system icons.
    let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    let path = shape.path(in: square).cgPath

    // Lay the shadow down by filling the silhouette, then paint the artwork
    // into the same shape — otherwise the shadow traces the artwork's own
    // edges instead of the icon's.
    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -10), blur: 22,
        color: NSColor.black.withAlphaComponent(0.30).cgColor)
    context.addPath(path)
    context.setFillColor(NSColor.black.cgColor)
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(path)
    context.clip()
    context.draw(artwork, in: square)
    context.restoreGState()

    guard let image = context.makeImage() else { fail("could not render the icon") }
    return image
}

func scaled(_ image: CGImage, to pixels: Int) -> CGImage {
    guard
        let context = CGContext(
            data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { fail("could not create a \(pixels)px context") }
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
    guard let scaled = context.makeImage() else { fail("could not scale to \(pixels)px") }
    return scaled
}

func writePNG(_ image: CGImage, to url: URL) {
    let representation = NSBitmapImageRep(cgImage: image)
    guard let data = representation.representation(using: .png, properties: [:]) else {
        fail("could not encode \(url.lastPathComponent)")
    }
    do { try data.write(to: url) } catch { fail("could not write \(url.path): \(error)") }
}

let master = renderMaster()

let iconset = FileManager.default.temporaryDirectory
    .appendingPathComponent("Omnicast-\(UUID().uuidString).iconset")
try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: iconset) }

// Every size the Dock, Finder, Launchpad and Spotlight ask for.
for points in [16, 32, 128, 256, 512] {
    writePNG(
        scaled(master, to: points),
        to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    writePNG(
        scaled(master, to: points * 2),
        to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["--convert", "icns", iconset.path, "--output", outputURL.path]
do { try iconutil.run() } catch { fail("could not run iconutil: \(error)") }
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fail("iconutil failed") }

// Keep a full-size preview beside the icns for eyeballing changes.
writePNG(master, to: outputURL.deletingPathExtension().appendingPathExtension("preview.png"))

print("✓ \(outputURL.lastPathComponent) (\(Int(canvas))px master, 10 sizes)")
