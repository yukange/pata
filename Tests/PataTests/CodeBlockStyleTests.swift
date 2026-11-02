import Testing
@testable import PataEditor
import AppKit
import MarkdownEngine

@Suite("Code Block Styling & Copy Tests")
struct CodeBlockStyleTests {

    @Test("Code block background color recognition")
    func codeBlockColorRecognition() {
        let lightBg = PataCodeBlockStyler.codeBlockLightBackground
        let darkBg = PataCodeBlockStyler.codeBlockDarkBackground

        #expect(PataCodeBlockStyler.isCodeBlockColor(lightBg))
        #expect(PataCodeBlockStyler.isCodeBlockColor(darkBg))

        // Slight color variance within 0.03 tolerance
        let nearLight = NSColor(calibratedRed: 237/255 + 0.01, green: 233/255, blue: 227/255, alpha: 1.0)
        #expect(PataCodeBlockStyler.isCodeBlockColor(nearLight))

        // Non-code colors must be rejected
        #expect(!PataCodeBlockStyler.isCodeBlockColor(NSColor.white))
        #expect(!PataCodeBlockStyler.isCodeBlockColor(NSColor.black))
        #expect(!PataCodeBlockStyler.isCodeBlockColor(NSColor.systemRed))
        #expect(!PataCodeBlockStyler.isCodeBlockColor(NSColor.systemBlue))
    }

    @Test("Rounded block path geometry for single-line, first, middle, and last lines")
    func roundedBlockPathGeometry() {
        let rect = CGRect(x: 0, y: 0, width: 300, height: 40)
        let radius: CGFloat = 8.0

        // 1. Single line: all 4 corners rounded
        let singlePath = PataCodeBlockStyler.roundedBlockPath(rect: rect, radius: radius, isFirst: true, isLast: true)
        #expect(singlePath.boundingBoxOfPath.equalTo(rect))

        // 2. First line of multi-line
        let firstPath = PataCodeBlockStyler.roundedBlockPath(rect: rect, radius: radius, isFirst: true, isLast: false)
        #expect(firstPath.boundingBoxOfPath.equalTo(rect))

        // 3. Middle line
        let midPath = PataCodeBlockStyler.roundedBlockPath(rect: rect, radius: radius, isFirst: false, isLast: false)
        #expect(midPath.boundingBoxOfPath.equalTo(rect))

        // 4. Last line
        let lastPath = PataCodeBlockStyler.roundedBlockPath(rect: rect, radius: radius, isFirst: false, isLast: true)
        #expect(lastPath.boundingBoxOfPath.equalTo(rect))
    }

    @Test("Rounded block border stroke path geometry")
    func roundedBlockBorderPathGeometry() {
        let rect = CGRect(x: 0.5, y: 0.5, width: 299, height: 39)
        let radius: CGFloat = 8.0

        let borderSingle = PataCodeBlockStyler.roundedBlockBorderPath(rect: rect, radius: radius, isFirst: true, isLast: true)
        #expect(borderSingle.boundingBoxOfPath.equalTo(rect))

        let borderFirst = PataCodeBlockStyler.roundedBlockBorderPath(rect: rect, radius: radius, isFirst: true, isLast: false)
        #expect(borderFirst.boundingBoxOfPath.equalTo(rect))

        let borderMid = PataCodeBlockStyler.roundedBlockBorderPath(rect: rect, radius: radius, isFirst: false, isLast: false)
        #expect(borderMid.boundingBoxOfPath.equalTo(rect))

        let borderLast = PataCodeBlockStyler.roundedBlockBorderPath(rect: rect, radius: radius, isFirst: false, isLast: true)
        #expect(borderLast.boundingBoxOfPath.equalTo(rect))
    }

    @Test("Swizzle install is idempotent")
    func swizzleInstallIdempotent() {
        PataCodeBlockStyler.installSwizzleIfNeeded()
        PataCodeBlockStyler.installSwizzleIfNeeded()
        // Must execute cleanly without error
    }

    @Test("Code block selection model properties")
    func codeBlockSelectionModel() {
        let selection = CodeBlockSelection(
            id: 12,
            rect: CGRect(x: 0, y: 100, width: 600, height: 120),
            language: "swift",
            code: "let x = 42\nprint(x)"
        )

        #expect(selection.id == 12)
        #expect(selection.language == "swift")
        #expect(selection.code == "let x = 42\nprint(x)")
        #expect(selection.rect.width == 600)
    }

    @Test("Merge overlapping rects on same line vs distinct vertical lines")
    func mergeOverlappingRectsSemantics() {
        // 1. Horizontally overlapping rects on the exact same line -> merged into one
        let r1 = CGRect(x: 10, y: 100, width: 40, height: 20)
        let r2 = CGRect(x: 35, y: 100, width: 50, height: 20)
        let mergedSameLine = PataCodeBlockStyler.mergeOverlappingRects([r1, r2])
        #expect(mergedSameLine.count == 1)
        #expect(mergedSameLine[0].minX == 10)
        #expect(mergedSameLine[0].maxX == 85)
        #expect(mergedSameLine[0].minY == 100)
        #expect(mergedSameLine[0].height == 20)

        // 2. Vertically adjacent lines (e.g. wrapped line fragments) -> remain disjoint without overlap
        let line0 = CGRect(x: 16, y: 100, width: 300, height: 20)
        let line1 = CGRect(x: 16, y: 120, width: 200, height: 20)
        let multiLine = PataCodeBlockStyler.mergeOverlappingRects([line0, line1])
        #expect(multiLine.count == 2)
        #expect(multiLine[0].maxY == multiLine[1].minY)
        #expect(!multiLine[0].intersects(multiLine[1]))
    }

    @Test("Wrapped line code block selection rects never overlap vertically")
    func wrappedLineCodeBlockSelectionRectsDoNotOverlap() {
        let textStorage = NSTextStorage(string: "A very long line of code that exceeds the container width and wraps onto line two")
        let textContentStorage = NSTextContentStorage()
        textContentStorage.textStorage = textStorage

        let textLayoutManager = NSTextLayoutManager()
        textContentStorage.addTextLayoutManager(textLayoutManager)

        let container = NSTextContainer(size: NSSize(width: 150, height: 1000))
        container.lineFragmentPadding = 0
        textLayoutManager.textContainer = container

        textLayoutManager.ensureLayout(for: textLayoutManager.documentRange)

        guard let firstFrag = textLayoutManager.textLayoutFragment(for: textContentStorage.documentRange.location) else {
            return
        }

        // If wrapped into 2 or more line fragments
        if firstFrag.textLineFragments.count > 1 {
            // Select the entire document range
            let sel = NSTextSelection(range: textContentStorage.documentRange, affinity: .downstream, granularity: .character)
            textLayoutManager.textSelections = [sel]

            let snappedY: CGFloat = 10.0
            let scale: CGFloat = 2.0
            let effectiveHeight = firstFrag.layoutFragmentFrame.height
            let snappedMaxY = snappedY + effectiveHeight

            let rects = PataCodeBlockStyler.selectionRectsInDrawCoordinates(
                layoutFragment: firstFrag,
                textLayoutManager: textLayoutManager,
                drawPoint: CGPoint(x: 0, y: snappedY),
                effectiveHeight: effectiveHeight,
                snappedY: snappedY,
                snappedMaxY: snappedMaxY,
                scale: scale
            )

            // Multiple line fragments must produce multiple rects whose heights sum without overlapping
            #expect(rects.count >= 2)
            for i in 0..<(rects.count - 1) {
                #expect(rects[i].maxY <= rects[i + 1].minY, "Line \(i) and Line \(i+1) must not overlap vertically")
            }
        }
    }
}
