import SwiftUI
import AppKit

extension NSColor {
    public convenience init?(hex: String) {
        var clean = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasPrefix("#") {
            clean.removeFirst()
        }
        guard clean.count == 6, let rgb = UInt64(clean, radix: 16) else {
            return nil
        }
        let r = CGFloat((rgb >> 16) & 0xFF) / 255.0
        let g = CGFloat((rgb >> 8) & 0xFF) / 255.0
        let b = CGFloat(rgb & 0xFF) / 255.0
        self.init(srgbRed: r, green: g, blue: b, alpha: 1.0)
    }

    public func toHex() -> String {
        guard let srgb = self.usingColorSpace(.sRGB) else {
            return "#007aff"
        }
        let r = Int(round(srgb.redComponent * 255))
        let g = Int(round(srgb.greenComponent * 255))
        let b = Int(round(srgb.blueComponent * 255))
        return String(format: "#%02x%02x%02x", min(max(r, 0), 255), min(max(g, 0), 255), min(max(b, 0), 255))
    }
}

extension Color {
    public init?(hex: String) {
        guard let nsColor = NSColor(hex: hex) else { return nil }
        self.init(nsColor: nsColor)
    }

    public func toHex() -> String? {
        let nsColor = NSColor(self)
        return nsColor.toHex()
    }

    /// 自动计算适合当前强调色背景的高对比度前景文字颜色（遵循 WCAG 2.2 AA 标准）
    public var onAccent: Color {
        let nsColor = NSColor(self)
        guard let srgb = nsColor.usingColorSpace(.sRGB) else { return .white }
        let lum = 0.2126 * srgb.redComponent + 0.7152 * srgb.greenComponent + 0.0722 * srgb.blueComponent
        return lum > 0.6 ? Color(red: 24/255, green: 24/255, blue: 27/255) : .white
    }
}
