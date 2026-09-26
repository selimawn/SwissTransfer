import AppKit

let size = 1024.0
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
let bounds = NSRect(x: 0, y: 0, width: size, height: size).insetBy(dx: 48, dy: 48)
let path = NSBezierPath(roundedRect: bounds, xRadius: 210, yRadius: 210)
NSColor(srgbRed: 0x23 / 255, green: 0xA6 / 255, blue: 0x62 / 255, alpha: 1).setFill()
path.fill()
NSColor.white.setStroke()
let arrow = NSBezierPath()
arrow.lineWidth = 78
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
arrow.move(to: NSPoint(x: 330, y: 330))
arrow.line(to: NSPoint(x: 694, y: 694))
arrow.move(to: NSPoint(x: 470, y: 694))
arrow.line(to: NSPoint(x: 694, y: 694))
arrow.line(to: NSPoint(x: 694, y: 470))
arrow.stroke()
image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fputs("icon render failed\n", stderr)
    exit(1)
}
let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
try png.write(to: URL(fileURLWithPath: output))
