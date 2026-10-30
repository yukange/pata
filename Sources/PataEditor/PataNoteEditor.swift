import SwiftUI
import AppKit
import MarkdownEngine
import PataCore

/// The unified Markdown IR (Instant Rendering) Note Editor component for Pata.
/// Backed by TextKit 2 via MarkdownEngine to deliver 100% native trackpad tap-to-click,
/// native IME (Doubao / ABC) marked-text composition, native undo/redo, dynamic inline markdown syntax rendering/hiding (IR mode),
/// and lossless markdown roundtrip.
public struct PataNoteEditor: View {
    public let noteId: String
    @Binding public var text: String
    public var isReadOnlyTranscript: Bool
    public var isFocused: Binding<Bool>?
    public var onSeekAudio: ((Int) -> Void)?
    public var onTextChange: ((String) -> Void)?
    public var onOpenLink: ((String) -> Void)?
    public var listNoteRefs: (() -> [NoteRef])?
    public var listFiles: (() -> [FileResource])?

    private static let defaultConfiguration: MarkdownEditorConfiguration = {
        var config = MarkdownEditorConfiguration.default
        config.extensions = [HighlightExtension(), StrikethroughExtension()]
        return config
    }()

    public init(
        noteId: String,
        text: Binding<String>,
        isReadOnlyTranscript: Bool = false,
        isFocused: Binding<Bool>? = nil,
        onSeekAudio: ((Int) -> Void)? = nil,
        onTextChange: ((String) -> Void)? = nil,
        onOpenLink: ((String) -> Void)? = nil,
        listNoteRefs: (() -> [NoteRef])? = nil,
        listFiles: (() -> [FileResource])? = nil
    ) {
        self.noteId = noteId
        self._text = text
        self.isReadOnlyTranscript = isReadOnlyTranscript
        self.isFocused = isFocused
        self.onSeekAudio = onSeekAudio
        self.onTextChange = onTextChange
        self.onOpenLink = onOpenLink
        self.listNoteRefs = listNoteRefs
        self.listFiles = listFiles
    }

    public var body: some View {
        NativeTextViewWrapper(
            text: $text,
            configuration: Self.defaultConfiguration,
            fontSize: 15,
            documentId: noteId,
            isEditable: !isReadOnlyTranscript,
            isFocused: isFocused,
            onLinkClick: { target in
                handleLinkClick(target)
            },
            placeholder: NSAttributedString(
                string: "开始记录内容...（支持 Markdown 语法、表格、代码块）",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 15),
                    .foregroundColor: NSColor.placeholderTextColor
                ]
            )
        )
        .onChange(of: text) { newText in
            onTextChange?(newText)
        }
    }

    private func handleLinkClick(_ target: String) {
        // 1. Audio seek timestamp: e.g. "files/audio.mp3#t=00:01:23.456" or "#t=00:01:23.456"
        if target.contains("#t=") {
            if let anchor = target.components(separatedBy: "#t=").last,
               let ms = parseTimestampMs(anchor) {
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

    private func parseTimestampMs(_ str: String) -> Int? {
        let parts = str.components(separatedBy: ":")
        guard parts.count == 3 else { return nil }
        guard let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
        let secParts = parts[2].components(separatedBy: ".")
        guard let s = Int(secParts[0]) else { return nil }
        let ms = secParts.count > 1 ? (Int(secParts[1].prefix(3)) ?? 0) : 0
        return (h * 3600 + m * 60 + s) * 1000 + ms
    }
}
