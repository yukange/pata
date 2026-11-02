import Testing
@testable import PataUI
import SwiftUI
import AppKit

@Suite("Theme Accent Color Tests")
struct ThemeTests {
    @Test("Hex parsing and roundtrip conversion")
    func hexRoundtrip() {
        // Valid hex with hash
        let hex1 = "#007aff"
        let c1 = Color(hex: hex1)
        #expect(c1 != nil)
        #expect(c1?.toHex()?.lowercased() == hex1.lowercased())

        // Valid hex without hash
        let hex2 = "af52de"
        let c2 = Color(hex: hex2)
        #expect(c2 != nil)
        #expect(c2?.toHex()?.lowercased() == "#\(hex2.lowercased())")

        // Invalid hex
        #expect(Color(hex: "invalid") == nil)
        #expect(Color(hex: "#123") == nil)
        #expect(Color(hex: "#1234567") == nil)
        #expect(Color(hex: "") == nil)

        // Preset hex colors
        let presets = ["#007aff", "#af52de", "#27836b", "#ff9500", "#ff2d55", "#8e8e93"]
        for p in presets {
            let color = Color(hex: p)
            #expect(color != nil)
            #expect(color?.toHex()?.lowercased() == p.lowercased())
        }
    }

    @Test("onAccent contrast calculation follows WCAG AA")
    func onAccentContrast() {
        // White or light background -> dark text
        let white = Color(hex: "#ffffff")!
        #expect(white.onAccent == Color(red: 24/255, green: 24/255, blue: 27/255))

        let lightYellow = Color(hex: "#ffff00")!
        #expect(lightYellow.onAccent == Color(red: 24/255, green: 24/255, blue: 27/255))

        // Dark or saturated background -> white text
        let black = Color(hex: "#000000")!
        #expect(black.onAccent == .white)

        let blue = Color(hex: "#007aff")!
        #expect(blue.onAccent == .white)

        let purple = Color(hex: "#af52de")!
        #expect(purple.onAccent == .white)

        let green = Color(hex: "#27836b")!
        #expect(green.onAccent == .white)
    }

    @Test("AppState effective accent color fallback and custom resolution")
    @MainActor
    func appStateAccent() {
        let state = AppState()

        // 1. Default / Follow system
        state.accentColorHex = ""
        #expect(state.customAccentColor == nil)
        #expect(state.effectiveAccentColor == Color(nsColor: .controlAccentColor))

        // 2. Custom color
        state.accentColorHex = "#007aff"
        #expect(state.customAccentColor != nil)
        #expect(state.customAccentColor?.toHex()?.lowercased() == "#007aff")
        #expect(state.effectiveAccentColor == Color(hex: "#007aff"))
        #expect(state.effectiveAccentOnColor == .white)

        state.accentColorHex = "#ff9500"
        #expect(state.effectiveAccentOnColor == Color(red: 24/255, green: 24/255, blue: 27/255))

        // 3. Reset
        state.accentColorHex = ""
        #expect(state.customAccentColor == nil)
    }
}
