import AppKit
import Foundation

// Synthetic, legible daily form for repeatable real PhotosPicker tests. No family data.
let output = URL(fileURLWithPath: CommandLine.arguments[1])
let width = 800, height = 900
let image = NSImage(size: NSSize(width: width, height: height))
image.lockFocus()
NSColor.white.setFill()
NSRect(x: 0, y: 0, width: width, height: height).fill()
func text(_ value: String, _ x: Double, _ top: Double, size: Double = 26) {
    (value as NSString).draw(at: NSPoint(x: x, y: Double(height) - top - size - 5),
        withAttributes: [.font: NSFont.systemFont(ofSize: size), .foregroundColor: NSColor.black])
}
text("幼儿园亲子桥", 240, 40, size: 32)
let calendar = Calendar.current
let parts = calendar.dateComponents([.year, .month, .day], from: .now)
text("今天是\(parts.year!)年\(parts.month!)月\(parts.day!)日", 60, 110)
text("上午点心", 130, 210); text("水果", 520, 210)
text("食量 90%", 130, 290); text("食量 100%", 490, 290)
text("中午午餐", 130, 380); text("下午点心", 490, 380)
text("食量 80%", 130, 460); text("食量 70%", 490, 460)
text("睡眠", 60, 550); text("12时10分—14时00分", 230, 600)
text("早上：36.6°C", 60, 710); text("中午：36.7°C", 420, 710)
image.unlockFocus()
let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
try bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.95])!.write(to: output)
