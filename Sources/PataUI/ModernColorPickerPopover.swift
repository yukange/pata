import SwiftUI
import AppKit

public struct ModernColorPickerPopover: View {
    @Binding public var accentHex: String
    public var onChanged: () -> Void

    @State private var hexInput: String = ""
    @State private var currentHue: CGFloat = 0.5

    private let modernPalette: [String] = [
        "#ef4444", "#f97316", "#f59e0b", "#10b981",
        "#06b6d4", "#0284c7", "#3b82f6", "#6366f1",
        "#8b5cf6", "#a855f7", "#ec4899", "#f43f5e",
        "#14b8a6", "#84cc16", "#64748b", "#18181b"
    ]

    public init(accentHex: Binding<String>, onChanged: @escaping () -> Void) {
        self._accentHex = accentHex
        self.onChanged = onChanged
    }

    private var activeColor: Color {
        Color(hex: accentHex) ?? .accentColor
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 1. Top row: Preview + Hex input + Eyedropper
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(activeColor)
                    .frame(width: 26, height: 26)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.15), lineWidth: 1))
                    .shadow(color: activeColor.opacity(0.2), radius: 2, y: 1)

                HStack(spacing: 2) {
                    Text("#")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(.secondary)
                    TextField("007AFF", text: $hexInput)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .frame(maxWidth: .infinity)
                        .onSubmit {
                            applyHexInput()
                        }
                }
                .padding(.horizontal, 8)
                .frame(height: 26)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor), lineWidth: 1))

                Button(action: pickScreenColor) {
                    Image(systemName: "eyedropper")
                        .font(.system(size: 11))
                        .foregroundColor(.primary)
                        .frame(width: 26, height: 26)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help("从屏幕任意处吸取颜色")
            }

            // 2. Rainbow Hue Slider
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 1, green: 0, blue: 0),
                                    Color(red: 1, green: 1, blue: 0),
                                    Color(red: 0, green: 1, blue: 0),
                                    Color(red: 0, green: 1, blue: 1),
                                    Color(red: 0, green: 0, blue: 1),
                                    Color(red: 1, green: 0, blue: 1),
                                    Color(red: 1, green: 0, blue: 0)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(height: 10)

                    Circle()
                        .fill(Color.white)
                        .frame(width: 14, height: 14)
                        .shadow(color: Color.black.opacity(0.3), radius: 2, y: 1)
                        .offset(x: max(0, min(w - 14, currentHue * (w - 14))))
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { val in
                            let normalized = max(0, min(1, val.location.x / max(1, w)))
                            currentHue = normalized
                            let c = NSColor(hue: normalized, saturation: 0.85, brightness: 0.95, alpha: 1.0)
                            let hex = c.toHex()
                            accentHex = hex
                            hexInput = hex.replacingOccurrences(of: "#", with: "").uppercased()
                            onChanged()
                        }
                )
            }
            .frame(height: 14)

            // 3. Curated Modern Palette
            VStack(alignment: .leading, spacing: 6) {
                Text("精选色彩")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)

                LazyVGrid(columns: Array(repeating: GridItem(.fixed(22), spacing: 8), count: 8), spacing: 8) {
                    ForEach(modernPalette, id: \.self) { hex in
                        let isSelected = accentHex.lowercased() == hex.lowercased()
                        Button(action: {
                            accentHex = hex
                            hexInput = hex.replacingOccurrences(of: "#", with: "").uppercased()
                            syncHueFromColor(hex: hex)
                            onChanged()
                        }) {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color(hex: hex) ?? .black)
                                .frame(width: 22, height: 22)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5)
                                        .stroke(isSelected ? Color.primary : Color.clear, lineWidth: 1.5)
                                        .padding(-2)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 260)
        .onAppear {
            syncState()
        }
    }

    private func syncState() {
        let clean = accentHex.trimmingCharacters(in: .whitespacesAndNewlines)
        if !clean.isEmpty {
            hexInput = clean.replacingOccurrences(of: "#", with: "").uppercased()
            syncHueFromColor(hex: clean)
        } else {
            hexInput = "007AFF"
            currentHue = 0.58
        }
    }

    private func syncHueFromColor(hex: String) {
        if let nsColor = NSColor(hex: hex)?.usingColorSpace(.sRGB) {
            currentHue = nsColor.hueComponent
        }
    }

    private func applyHexInput() {
        var clean = hexInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasPrefix("#") { clean.removeFirst() }
        guard clean.count == 6, UInt64(clean, radix: 16) != nil else { return }
        let fullHex = "#\(clean.lowercased())"
        accentHex = fullHex
        hexInput = clean.uppercased()
        syncHueFromColor(hex: fullHex)
        onChanged()
    }

    private func pickScreenColor() {
        Task {
            if let color = await NSColorSampler().sample() {
                let hex = color.toHex()
                await MainActor.run {
                    accentHex = hex
                    hexInput = hex.replacingOccurrences(of: "#", with: "").uppercased()
                    syncHueFromColor(hex: hex)
                    onChanged()
                }
            }
        }
    }
}
