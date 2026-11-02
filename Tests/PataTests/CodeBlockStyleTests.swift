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
}
