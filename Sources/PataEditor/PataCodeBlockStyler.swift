import SwiftUI
import AppKit
import ObjectiveC
import MarkdownEngine

// MARK: - Code Block Styler & Swizzling

/// Manages rounded-corner styling for fenced code blocks in Pata Markdown Note Editor.
public final class PataCodeBlockStyler: @unchecked Sendable {
    public static let shared = PataCodeBlockStyler()

    public static let codeBlockLightBackground = NSColor(calibratedRed: 237/255, green: 233/255, blue: 227/255, alpha: 1.0)
    public static let codeBlockDarkBackground = NSColor(calibratedRed: 40/255, green: 38/255, blue: 36/255, alpha: 1.0)

    public static func isCodeBlockColor(_ color: NSColor) -> Bool {
        guard let colorRGB = color.usingColorSpace(.deviceRGB) else { return false }
        let candidates = [codeBlockLightBackground, codeBlockDarkBackground]
        for bg in candidates {
            guard let bgRGB = bg.usingColorSpace(.deviceRGB) else { continue }
            let tolerance: CGFloat = 0.03
            if abs(colorRGB.redComponent - bgRGB.redComponent) < tolerance &&
               abs(colorRGB.greenComponent - bgRGB.greenComponent) < tolerance &&
               abs(colorRGB.blueComponent - bgRGB.blueComponent) < tolerance {
                return true
            }
        }
        return false
    }

    private static let swizzleOnce: Void = {
        guard let targetClass = NSClassFromString("MarkdownEngine.MarkdownTextLayoutFragment") else {
            return
        }

        let originalSelector = #selector(NSTextLayoutFragment.draw(at:in:))
        let swizzledSelector = #selector(NSTextLayoutFragment.pata_codeBlock_draw(at:in:))

        guard let targetMethod = class_getInstanceMethod(targetClass, originalSelector),
              let swizzledMethod = class_getInstanceMethod(NSTextLayoutFragment.self, swizzledSelector) else {
            return
        }

        let didAdd = class_addMethod(
            targetClass,
            swizzledSelector,
            method_getImplementation(swizzledMethod),
            method_getTypeEncoding(swizzledMethod)
        )

        if didAdd, let newMethod = class_getInstanceMethod(targetClass, swizzledSelector) {
            method_exchangeImplementations(targetMethod, newMethod)
        } else {
            method_exchangeImplementations(targetMethod, swizzledMethod)
        }
    }()

    public static func installSwizzleIfNeeded() {
        _ = swizzleOnce
    }

    public static func roundedBlockPath(rect: CGRect, radius: CGFloat, isFirst: Bool, isLast: Bool) -> CGPath {
        if isFirst && isLast {
            return CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        }

        let path = CGMutablePath()
        if isFirst && !isLast {
            // Rounded top corners, square bottom corners
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
            path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY),
                        tangent2End: CGPoint(x: rect.minX + radius, y: rect.minY),
                        radius: radius)
            path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
            path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY),
                        tangent2End: CGPoint(x: rect.maxX, y: rect.minY + radius),
                        radius: radius)
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.closeSubpath()
            return path
        } else if !isFirst && isLast {
            // Square top corners, rounded bottom corners
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
            path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY),
                        tangent2End: CGPoint(x: rect.maxX - radius, y: rect.maxY),
                        radius: radius)
            path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
            path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY),
                        tangent2End: CGPoint(x: rect.minX, y: rect.maxY - radius),
                        radius: radius)
            path.closeSubpath()
            return path
        } else {
            // Middle lines: plain rectangle
            return CGPath(rect: rect, transform: nil)
        }
    }

    public static func roundedBlockBorderPath(rect: CGRect, radius: CGFloat, isFirst: Bool, isLast: Bool) -> CGPath {
        if isFirst && isLast {
            return CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        }

        let path = CGMutablePath()
        if isFirst && !isLast {
            // Stroke top-left arc, top line, top-right arc, left and right edges down to maxY
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
            path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY),
                        tangent2End: CGPoint(x: rect.minX + radius, y: rect.minY),
                        radius: radius)
            path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
            path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY),
                        tangent2End: CGPoint(x: rect.maxX, y: rect.minY + radius),
                        radius: radius)
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            return path
        } else if !isFirst && isLast {
            // Stroke left edge down to bottom-left arc, bottom line, bottom-right arc, right edge up to minY
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - radius))
            path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY),
                        tangent2End: CGPoint(x: rect.minX + radius, y: rect.maxY),
                        radius: radius)
            path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.maxY))
            path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY),
                        tangent2End: CGPoint(x: rect.maxX, y: rect.maxY - radius),
                        radius: radius)
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            return path
        } else {
            // Middle line: vertical left edge and vertical right edge only
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))

            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            return path
        }
    }

    // MARK: - Super Draw IMP

    typealias SuperDrawIMP = @convention(c) (AnyObject, Selector, CGPoint, CGContext) -> Void

    static let superDrawIMP: SuperDrawIMP? = {
        guard let method = class_getInstanceMethod(NSTextLayoutFragment.self, #selector(NSTextLayoutFragment.draw(at:in:))) else {
            return nil
        }
        return unsafeBitCast(method_getImplementation(method), to: SuperDrawIMP.self)
    }()

    // MARK: - Selection Rects Calculation & Merging

    public static func selectionRectsInDrawCoordinates(
        layoutFragment: NSTextLayoutFragment,
        textLayoutManager: NSTextLayoutManager,
        drawPoint: CGPoint,
        effectiveHeight: CGFloat,
        snappedY: CGFloat,
        snappedMaxY: CGFloat,
        scale: CGFloat
    ) -> [CGRect] {
        var rects: [CGRect] = []
        let dx = drawPoint.x - layoutFragment.layoutFragmentFrame.origin.x
        let dy = drawPoint.y - layoutFragment.layoutFragmentFrame.origin.y
        let myRange = layoutFragment.rangeInElement

        let lineFragments = layoutFragment.textLineFragments
        let lineCount = lineFragments.count

        // Pre-calculate line vertical spans [top, bottom] in draw coordinates so adjacent lines
        // share exact boundary seams without any gaps or overlapping pixels.
        var lineSpans: [(top: CGFloat, bottom: CGFloat)] = []
        if lineCount > 0 {
            var seams: [CGFloat] = [snappedY]
            if lineCount > 1 {
                for i in 1..<lineCount {
                    let rawSeam = drawPoint.y + lineFragments[i].typographicBounds.origin.y
                    seams.append(round(rawSeam * scale) / scale)
                }
            }
            seams.append(snappedMaxY)

            for i in 0..<lineCount {
                lineSpans.append((top: seams[i], bottom: seams[i + 1]))
            }
        }

        for selection in textLayoutManager.textSelections {
            for textRange in selection.textRanges {
                let interStart = textRange.location.compare(myRange.location) == .orderedAscending
                    ? myRange.location : textRange.location
                let interEnd = textRange.endLocation.compare(myRange.endLocation) == .orderedDescending
                    ? myRange.endLocation : textRange.endLocation
                guard interStart.compare(interEnd) == .orderedAscending,
                      let intersection = NSTextRange(location: interStart, end: interEnd) else { continue }

                textLayoutManager.enumerateTextSegments(in: intersection, type: .selection, options: []) { _, segFrame, _, _ in
                    let rawX = segFrame.origin.x + dx
                    let rawMaxX = rawX + segFrame.width
                    let snappedX = floor(rawX * scale) / scale
                    let snappedMaxX = ceil(rawMaxX * scale) / scale
                    let segWidth = max(0, snappedMaxX - snappedX)

                    var segTop = snappedY
                    var segBottom = snappedMaxY

                    if lineCount > 1 {
                        let segLocalY = segFrame.origin.y - layoutFragment.layoutFragmentFrame.origin.y
                        var matchedIndex = -1
                        var minDiff = CGFloat.greatestFiniteMagnitude
                        for i in 0..<lineCount {
                            let diff = abs(lineFragments[i].typographicBounds.origin.y - segLocalY)
                            if diff < minDiff {
                                minDiff = diff
                                matchedIndex = i
                            }
                        }
                        if matchedIndex >= 0 && minDiff < 4.0 {
                            segTop = lineSpans[matchedIndex].top
                            segBottom = lineSpans[matchedIndex].bottom
                        } else {
                            let rawY = segFrame.origin.y + dy
                            segTop = floor(rawY * scale) / scale
                            segBottom = ceil((rawY + segFrame.height) * scale) / scale
                        }
                    }

                    let drawRect = CGRect(
                        x: snappedX,
                        y: segTop,
                        width: segWidth,
                        height: max(0, segBottom - segTop)
                    )
                    rects.append(drawRect)
                    return true
                }
            }
        }
        return mergeOverlappingRects(rects)
    }

    public static func mergeOverlappingRects(_ rects: [CGRect]) -> [CGRect] {
        guard rects.count > 1 else { return rects }
        var result: [CGRect] = []
        for rect in rects {
            var merged = false
            for (idx, existing) in result.enumerated() {
                if abs(rect.minY - existing.minY) < 0.5 && abs(rect.maxY - existing.maxY) < 0.5 {
                    if rect.minX <= existing.maxX && rect.maxX >= existing.minX {
                        result[idx] = existing.union(rect)
                        merged = true
                        break
                    }
                }
            }
            if !merged {
                result.append(rect)
            }
        }
        return result
    }
}

// MARK: - NSTextLayoutFragment Swizzled Drawing

extension NSTextLayoutFragment {
    @MainActor
    @objc func pata_codeBlock_draw(at point: CGPoint, in context: CGContext) {
        guard let tlm = textLayoutManager,
              let tcs = tlm.textContentManager as? NSTextContentStorage,
              let ts = tcs.textStorage else {
            pata_codeBlock_draw(at: point, in: context)
            return
        }

        let start = tcs.offset(from: tcs.documentRange.location, to: rangeInElement.location)
        let end = tcs.offset(from: tcs.documentRange.location, to: rangeInElement.endLocation)
        guard start != NSNotFound, end != NSNotFound, end > start, start < ts.length else {
            pata_codeBlock_draw(at: point, in: context)
            return
        }

        let fragmentRange = NSRange(location: start, length: end - start)
        guard let color = ts.attribute(.backgroundColor, at: fragmentRange.location, effectiveRange: nil) as? NSColor,
              PataCodeBlockStyler.isCodeBlockColor(color) else {
            pata_codeBlock_draw(at: point, in: context)
            return
        }

        let isFirst: Bool = {
            if fragmentRange.location == 0 { return true }
            guard let prevColor = ts.attribute(.backgroundColor, at: fragmentRange.location - 1, effectiveRange: nil) as? NSColor else {
                return true
            }
            return !PataCodeBlockStyler.isCodeBlockColor(prevColor)
        }()

        let isLast: Bool = {
            let nextIndex = NSMaxRange(fragmentRange)
            if nextIndex >= ts.length { return true }
            guard let nextColor = ts.attribute(.backgroundColor, at: nextIndex, effectiveRange: nil) as? NSColor else {
                return true
            }
            return !PataCodeBlockStyler.isCodeBlockColor(nextColor)
        }()

        let containerWidth = tlm.textContainer?.size.width ?? layoutFragmentFrame.width
        var effectiveHeight = layoutFragmentFrame.height
        if textLineFragments.count > 1,
           let lastLF = textLineFragments.last,
           lastLF.characterRange.length == 0 {
            effectiveHeight -= lastLF.typographicBounds.height
        }

        let scale = tlm.textContainer?.textView?.window?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor ?? 2.0
        let rawY = point.y
        let rawMaxY = point.y + effectiveHeight
        let snappedY = floor(rawY * scale) / scale
        let snappedMaxY = ceil(rawMaxY * scale) / scale

        let bgRect = CGRect(
            x: point.x - layoutFragmentFrame.origin.x,
            y: snappedY,
            width: containerWidth,
            height: snappedMaxY - snappedY
        )

        let radius: CGFloat = 8.0
        let clipPath = PataCodeBlockStyler.roundedBlockPath(
            rect: bgRect,
            radius: radius,
            isFirst: isFirst,
            isLast: isLast
        )

        context.saveGState()
        context.addPath(clipPath)
        context.clip()

        // 1. Draw code block background with non-overlapping selection cutouts
        let selectionRects = PataCodeBlockStyler.selectionRectsInDrawCoordinates(
            layoutFragment: self,
            textLayoutManager: tlm,
            drawPoint: point,
            effectiveHeight: effectiveHeight,
            snappedY: snappedY,
            snappedMaxY: snappedMaxY,
            scale: scale
        )

        NSGraphicsContext.saveGraphicsState()
        let nsContext = NSGraphicsContext(cgContext: context, flipped: true)
        NSGraphicsContext.current = nsContext

        color.setFill()
        if selectionRects.isEmpty {
            NSBezierPath(rect: bgRect).fill()
        } else {
            let path = NSBezierPath()
            path.windingRule = .evenOdd
            path.appendRect(bgRect)
            for r in selectionRects {
                let inter = r.intersection(bgRect)
                if !inter.isNull && !inter.isEmpty {
                    path.appendRect(inter)
                }
            }
            path.fill()
        }
        NSGraphicsContext.restoreGraphicsState()

        // 2. Draw text glyphs
        if let imp = PataCodeBlockStyler.superDrawIMP {
            imp(self, #selector(NSTextLayoutFragment.draw(at:in:)), point, context)
        } else {
            pata_codeBlock_draw(at: point, in: context)
        }

        context.restoreGState()

        // 3. Draw subtle border around code block perimeter
        context.saveGState()
        let isDark: Bool = {
            let appearance = (tlm.textContainer?.textView?.effectiveAppearance ?? NSApp.effectiveAppearance)
            return appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        }()
        let borderColor = isDark
            ? NSColor.white.withAlphaComponent(0.08).cgColor
            : NSColor.black.withAlphaComponent(0.06).cgColor

        context.setStrokeColor(borderColor)
        context.setLineWidth(1.0)

        let strokeRect = bgRect.insetBy(dx: 0.5, dy: 0.5)
        let borderPath = PataCodeBlockStyler.roundedBlockBorderPath(
            rect: strokeRect,
            radius: radius,
            isFirst: isFirst,
            isLast: isLast
        )
        context.addPath(borderPath)
        context.strokePath()
        context.restoreGState()
    }
}

// MARK: - Code Block Copy Button View

/// Top-right corner copy button overlay for fenced code blocks.
public struct PataCodeBlockCopyButton: View {
    public let selection: CodeBlockSelection
    public var onHover: ((Bool) -> Void)?

    @State private var isCopied: Bool = false
    @State private var isButtonHovered: Bool = false

    public init(selection: CodeBlockSelection, onHover: ((Bool) -> Void)? = nil) {
        self.selection = selection
        self.onHover = onHover
    }

    public var body: some View {
        Color.clear
            .frame(width: max(0, selection.rect.width), height: max(0, selection.rect.height))
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 6) {
                    if let lang = selection.language, !lang.isEmpty {
                        Text(lang.uppercased())
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 2)
                    }

                    Button {
                        copyCode()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 10, weight: .medium))
                            if isCopied {
                                Text("已复制")
                                    .font(.system(size: 10, weight: .medium))
                            }
                        }
                        .foregroundStyle(isCopied ? Color.green : Color.primary.opacity(0.75))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(isButtonHovered ? Color.primary.opacity(0.08) : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                    .help(isCopied ? "已复制" : "复制代码")
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.85))
                        .shadow(color: .black.opacity(0.06), radius: 2, x: 0, y: 1)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                )
                .onHover { hovered in
                    isButtonHovered = hovered
                    onHover?(hovered)
                }
                .onDisappear {
                    onHover?(false)
                }
                .padding(.top, 6)
                .padding(.trailing, 8)
            }
            .position(
                x: selection.rect.midX,
                y: selection.rect.midY
            )
    }

    private func copyCode() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(selection.code, forType: .string)
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
            isCopied = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeInOut(duration: 0.2)) {
                isCopied = false
            }
        }
    }
}
