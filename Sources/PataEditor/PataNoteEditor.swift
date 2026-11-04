import SwiftUI
import AppKit
import MarkdownEngine
#if canImport(MarkdownEngineCodeBlocks)
import MarkdownEngineCodeBlocks
#endif
import PataCore
import ObjectiveC

// MARK: - Bus Notification Names for Transcript Navigation

public extension Notification.Name {
    static let pataEditorScrollToRange = Notification.Name("PataEditorScrollToRange")
    static let pataEditorClearHighlights = Notification.Name("PataEditorClearHighlights")
}

// MARK: - Timestamp Parsing & Transcript Locator

public enum PataTimestampParser: Sendable {
    public static func parseMilliseconds(_ str: String) -> Int? {
        var clean = str.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.contains("#t=") {
            clean = clean.components(separatedBy: "#t=").last ?? clean
        }
        if let queryIdx = clean.firstIndex(of: "?") {
            clean = String(clean[..<queryIdx])
        }
        if let slashIdx = clean.firstIndex(of: "/") {
            clean = String(clean[..<slashIdx])
        }
        let parts = clean.components(separatedBy: ":")
        guard parts.count == 3 else { return nil }
        guard let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
        let secParts = parts[2].components(separatedBy: ".")
        guard let s = Int(secParts[0]) else { return nil }
        let ms: Int
        if secParts.count > 1 {
            let frac = secParts[1].prefix(3)
            ms = (Int(frac) ?? 0) * (frac.count == 1 ? 100 : (frac.count == 2 ? 10 : 1))
        } else {
            ms = 0
        }
        return (h * 3600 + m * 60 + s) * 1000 + ms
    }
}

public enum PataTranscriptLocator: Sendable {
    public static func findSentenceRange(in body: String, targetMs: Int) -> NSRange? {
        let lines = body.components(separatedBy: "\n")
        var bestRange: NSRange? = nil
        var bestMs = -1
        var firstTimedRange: NSRange? = nil

        var currentOffset = 0
        for line in lines {
            let lineLength = (line as NSString).length
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") && trimmed.contains("](#t=") {
                if let tPart = trimmed.components(separatedBy: "#t=").dropFirst().first?.components(separatedBy: ")").first,
                   let ms = PataTimestampParser.parseMilliseconds(tPart) {
                    let r = NSRange(location: currentOffset, length: lineLength)
                    if firstTimedRange == nil {
                        firstTimedRange = r
                    }
                    if ms <= targetMs {
                        if bestMs == -1 || ms >= bestMs {
                            bestMs = ms
                            bestRange = r
                        }
                    }
                }
            }
            currentOffset += lineLength + 1
        }

        return bestRange ?? firstTimedRange
    }

    public static func scrollToSentence(in body: String, targetMs: Int) {
        guard let range = findSentenceRange(in: body, targetMs: targetMs) else { return }
        NotificationCenter.default.post(
            name: .pataEditorScrollToRange,
            object: nil,
            userInfo: [
                "currentIndex": 0,
                "allRanges": [range]
            ]
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            NotificationCenter.default.post(
                name: .pataEditorClearHighlights,
                object: nil
            )
        }
    }
}

// MARK: - Swizzling for Audio Timestamp Links (#t=...)

public struct PataEditorLinkHandler: Sendable {
    @MainActor public static var onSeekAudio: ((Int) -> Void)?

    private static let swizzleOnce: Void = {
        let originalSelector = #selector(NSTextViewDelegate.textView(_:clickedOnLink:at:))
        let swizzledSelector = #selector(NativeTextViewCoordinator.pata_textView(_:clickedOnLink:at:))

        guard let originalMethod = class_getInstanceMethod(NativeTextViewCoordinator.self, originalSelector),
              let swizzledMethod = class_getInstanceMethod(NativeTextViewCoordinator.self, swizzledSelector) else {
            return
        }

        method_exchangeImplementations(originalMethod, swizzledMethod)
    }()

    public static func installSwizzleIfNeeded() {
        _ = swizzleOnce
    }
}

extension NativeTextViewCoordinator {
    @objc func pata_textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        let linkStr: String
        if let url = link as? URL {
            linkStr = url.absoluteString
        } else if let nsUrl = link as? NSURL {
            linkStr = nsUrl.absoluteString ?? ""
        } else if let s = link as? String {
            linkStr = s
        } else {
            linkStr = ""
        }

        let decoded = linkStr.removingPercentEncoding ?? linkStr
        if decoded.contains("#t=") {
            if let anchor = decoded.components(separatedBy: "#t=").last,
               let ms = PataTimestampParser.parseMilliseconds(anchor) {
                DispatchQueue.main.async {
                    PataEditorLinkHandler.onSeekAudio?(ms)
                }
                return true
            }
        }

        return self.pata_textView(textView, clickedOnLink: link, at: charIndex)
    }
}

/// The unified Markdown IR (Instant Rendering) Note Editor component for Pata.
/// Backed by TextKit 2 via MarkdownEngine to deliver 100% native trackpad tap-to-click,
/// native IME (Doubao / ABC) marked-text composition, native undo/redo, dynamic inline markdown syntax rendering/hiding (IR mode),
/// and lossless markdown roundtrip.
// MARK: - Safe Fallback Syntax Highlighter

public struct PataCodeSyntaxHighlighter: SyntaxHighlighter {
    private let lightBg: NSColor
    private let darkBg: NSColor

    public init(
        lightBackground: NSColor = NSColor(calibratedRed: 237/255, green: 233/255, blue: 227/255, alpha: 1.0),
        darkBackground: NSColor = NSColor(calibratedRed: 40/255, green: 38/255, blue: 36/255, alpha: 1.0)
    ) {
        self.lightBg = lightBackground
        self.darkBg = darkBackground
    }

    public func codeFont(size: CGFloat) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    public func backgroundColor() -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark ? self.darkBg : self.lightBg
        }
    }

    public func highlight(code: String, language: String?) -> NSAttributedString? {
        nil
    }

    public var appearanceDidChangeNotification: Notification.Name? { nil }
}

public struct PataNoteEditor: View {
    public let noteId: String
    @Binding public var text: String
    public var isReadOnlyTranscript: Bool
    public var isFocused: Binding<Bool>?
    public var vaultPath: String?
    public var noteFilePath: String?
    public var onPasteImage: ((NSPasteboard) -> String?)?
    public var onSeekAudio: ((Int) -> Void)?
    public var onTextChange: ((String) -> Void)?
    public var onOpenLink: ((String) -> Void)?
    public var listNoteRefs: (() -> [NoteRef])?
    public var listFiles: (() -> [FileResource])?
    public var isCursorExcluded: ((CGPoint) -> Bool)?

    @State private var imageReloadVersion: Int = 0
    @State private var codeBlockSelections: [CodeBlockSelection] = []
    @State private var isHoveringCopyButton: Bool = false

    private static let defaultConfiguration: MarkdownEditorConfiguration = {
        var config = MarkdownEditorConfiguration.default
        config.extensions = [HighlightExtension(), StrikethroughExtension()]
        config.services.bus.findScrollToRange = .pataEditorScrollToRange
        config.services.bus.findClearHighlights = .pataEditorClearHighlights
        config.textInsets = TextInsets(horizontal: 24, vertical: 8)

        let lightBg = PataCodeBlockStyler.codeBlockLightBackground
        let darkBg = PataCodeBlockStyler.codeBlockDarkBackground

        #if canImport(MarkdownEngineCodeBlocks)
        let bundleName = "MarkdownEngine_MarkdownEngineCodeBlocks"
        let hasBundle: Bool = {
            if let resourceURL = Bundle.main.resourceURL {
                let bundleURL = resourceURL.appendingPathComponent("\(bundleName).bundle")
                if FileManager.default.fileExists(atPath: bundleURL.path) {
                    return true
                }
            }
            if Bundle.main.url(forResource: bundleName, withExtension: "bundle") != nil {
                return true
            }
            return false
        }()

        if hasBundle {
            let bridge = HighlightJSBridge(
                lightBackground: lightBg,
                darkBackground: darkBg
            )
            config.services.syntaxHighlighter = bridge
        } else {
            config.services.syntaxHighlighter = PataCodeSyntaxHighlighter(
                lightBackground: lightBg,
                darkBackground: darkBg
            )
        }
        #else
        config.services.syntaxHighlighter = PataCodeSyntaxHighlighter(
            lightBackground: lightBg,
            darkBackground: darkBg
        )
        #endif

        return config
    }()

    private var editorConfiguration: MarkdownEditorConfiguration {
        var config = Self.defaultConfiguration

        let provider = PataEmbeddedImageProvider(
            vaultPath: vaultPath,
            noteFilePath: noteFilePath,
            onImageLoaded: {
                DispatchQueue.main.async {
                    imageReloadVersion += 1
                }
            }
        )
        config.services.images = provider

        if isReadOnlyTranscript {
            // Transcript notes are read-only long-form documents.
            // 1. readingWidth keeps the text column fixed and centered, bypassing TextKit 2 re-wrap during window resize & sidebar collapse animations.
            // 2. Disabling overscroll eliminates typing padding calculations for read-only texts.
            // 3. Disable table live-resizing to prevent CPU spikes during continuous window frame changes.
            config.readingWidth = 780
            config.overscroll = OverscrollPolicy(percent: 0, maxPoints: 0, minPoints: 0)
            config.rendersTablesDuringLiveResize = false
        }

        return config
    }

    public init(
        noteId: String,
        text: Binding<String>,
        isReadOnlyTranscript: Bool = false,
        isFocused: Binding<Bool>? = nil,
        vaultPath: String? = nil,
        noteFilePath: String? = nil,
        onPasteImage: ((NSPasteboard) -> String?)? = nil,
        onSeekAudio: ((Int) -> Void)? = nil,
        onTextChange: ((String) -> Void)? = nil,
        onOpenLink: ((String) -> Void)? = nil,
        listNoteRefs: (() -> [NoteRef])? = nil,
        listFiles: (() -> [FileResource])? = nil,
        isCursorExcluded: ((CGPoint) -> Bool)? = nil
    ) {
        self.noteId = noteId
        self._text = text
        self.isReadOnlyTranscript = isReadOnlyTranscript
        self.isFocused = isFocused
        self.vaultPath = vaultPath
        self.noteFilePath = noteFilePath
        self.onPasteImage = onPasteImage
        self.onSeekAudio = onSeekAudio
        self.onTextChange = onTextChange
        self.onOpenLink = onOpenLink
        self.listNoteRefs = listNoteRefs
        self.listFiles = listFiles
        self.isCursorExcluded = isCursorExcluded

        PataEditorLinkHandler.installSwizzleIfNeeded()
        PataEditorLinkHandler.onSeekAudio = onSeekAudio
        PataCodeBlockStyler.installSwizzleIfNeeded()
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            NativeTextViewWrapper(
                text: $text,
                configuration: editorConfiguration,
                fontSize: 15,
                documentId: noteId,
                isEditable: !isReadOnlyTranscript,
                isFocused: isFocused,
                onPasteImage: effectiveOnPasteImage,
                onLinkClick: { target in
                    handleLinkClick(target)
                },
                onCodeBlockSelectionChange: { selections in
                    self.codeBlockSelections = selections
                },
                placeholder: NSAttributedString(
                    string: "开始记录内容...（支持 Markdown 语法、表格、代码块）",
                    attributes: [
                        .font: NSFont.systemFont(ofSize: 15),
                        .foregroundColor: NSColor.placeholderTextColor
                    ]
                ),
                isCursorExcluded: { point in
                    isHoveringCopyButton || (isCursorExcluded?(point) ?? false)
                }
            )

            ForEach(codeBlockSelections) { selection in
                PataCodeBlockCopyButton(selection: selection) { hovering in
                    self.isHoveringCopyButton = hovering
                }
            }
        }
        .clipped()
        .onAppear {
            PataEditorLinkHandler.onSeekAudio = onSeekAudio
        }
        .onChange(of: noteId) { _, _ in
            PataEditorLinkHandler.onSeekAudio = onSeekAudio
            codeBlockSelections = []
            isHoveringCopyButton = false
        }
        .onChange(of: text) { _, newText in
            onTextChange?(newText)
        }
    }

    private var effectiveOnPasteImage: ((NSPasteboard) -> String?)? {
        if let onPasteImage = onPasteImage {
            return onPasteImage
        }
        guard let vaultPath = vaultPath, !vaultPath.isEmpty else { return nil }
        return { pasteboard in
            PataImageHelper.handlePasteImage(
                from: pasteboard,
                vaultPath: vaultPath,
                noteFilePath: noteFilePath
            )
        }
    }

    private func handleLinkClick(_ target: String) {
        // 1. Audio seek timestamp: e.g. "files/audio.mp3#t=00:01:23.456" or "#t=00:01:23.456"
        if target.contains("#t=") {
            if let anchor = target.components(separatedBy: "#t=").last,
               let ms = PataTimestampParser.parseMilliseconds(anchor) {
                onSeekAudio?(ms)
                return
            }
        }

        // 2. Web URL: http / https
        if target.hasPrefix("http://") || target.hasPrefix("https://") {
            if let url = URL(string: target) {
                NSWorkspace.shared.open(url)
            }
            return
        }

        // 3. App / Note / File link
        onOpenLink?(target)
    }
}
