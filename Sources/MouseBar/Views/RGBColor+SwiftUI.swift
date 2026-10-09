import AppKit
import MouseCore
import SwiftUI

extension MouseCore.RGBColor {
    var swiftUIColor: Color {
        Color(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
    }

    init?(color: Color) {
        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        func byte(_ v: CGFloat) -> UInt8 { UInt8(max(0, min(255, (v * 255).rounded()))) }
        self.init(r: byte(rgb.redComponent), g: byte(rgb.greenComponent), b: byte(rgb.blueComponent))
    }
}
