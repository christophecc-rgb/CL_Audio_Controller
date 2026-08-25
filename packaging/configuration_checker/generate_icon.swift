import AppKit
import Foundation

guard CommandLine.arguments.count == 3 else {
    fputs("usage: generate_icon.swift BASE_PNG OUTPUT_PNG\n", stderr)
    exit(2)
}

let baseURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
guard let base = NSImage(contentsOf: baseURL) else {
    fputs("unable to load base CL AUDIO icon\n", stderr)
    exit(3)
}

let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()
base.draw(in: NSRect(origin: .zero, size: size),
          from: NSRect(origin: .zero, size: base.size),
          operation: .copy,
          fraction: 1)

// Replace the product subtitle while retaining the established CL AUDIO family.
let subtitlePlate = NSBezierPath(roundedRect: NSRect(x: 175, y: 45, width: 674, height: 150),
                                 xRadius: 34, yRadius: 34)
NSColor(calibratedRed: 0.055, green: 0.075, blue: 0.10, alpha: 0.98).setFill()
subtitlePlate.fill()

let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .center
let subtitle = NSAttributedString(string: "CONFIG CHECK", attributes: [
    .font: NSFont.systemFont(ofSize: 64, weight: .semibold),
    .foregroundColor: NSColor.white,
    .kern: 9,
    .paragraphStyle: paragraph
])
subtitle.draw(in: NSRect(x: 185, y: 82, width: 654, height: 78))

// A compact green verification badge makes the checker distinct in Finder/Dock.
let badgeRect = NSRect(x: 645, y: 300, width: 205, height: 205)
let badge = NSBezierPath(ovalIn: badgeRect)
NSColor(calibratedRed: 0.06, green: 0.72, blue: 0.48, alpha: 1).setFill()
badge.fill()
NSColor.white.withAlphaComponent(0.9).setStroke()
badge.lineWidth = 8
badge.stroke()

let check = NSBezierPath()
check.move(to: NSPoint(x: 690, y: 398))
check.line(to: NSPoint(x: 735, y: 350))
check.line(to: NSPoint(x: 813, y: 452))
check.lineWidth = 22
check.lineCapStyle = .round
check.lineJoinStyle = .round
NSColor.white.setStroke()
check.stroke()

image.unlockFocus()
guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("unable to render icon PNG\n", stderr)
    exit(4)
}
try png.write(to: outputURL, options: .atomic)
