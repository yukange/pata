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
    public var vaultPath: String?
    public var noteFilePath: String?
    public var onPasteImage: ((NSPasteboard) -> String?)?
    public var onSeekAudio: ((Int) -> Void)?
    public var onTextChange: ((String) -> Void)?
    public var onOpenLink: ((String) -> Void)?
    public var listNoteRefs: (() -> [NoteRef])?
    public var listFiles: (() -> [FileResource])?

    @State private var imageReloadVersion: Int = 0
    @State private var containerWidth: CGFloat = 0

    private static let defaultConfiguration: MarkdownEditorConfiguration = {
        var config = MarkdownEditorConfiguration.default
        config.extensions = [HighlightExtension(), StrikethroughExtension()]
        config.imageEmbed.minimumWidth = 720
        config.imageEmbed.fallbackMaxWidth = 720
        return config
    }()

    private var editorConfiguration: MarkdownEditorConfiguration {
        var config = Self.defaultConfiguration
        let effectiveWidth = containerWidth > 0 ? containerWidth : 720
        config.imageEmbed.minimumWidth = effectiveWidth
        config.imageEmbed.fallbackMaxWidth = effectiveWidth

        let provider = PataEmbeddedImageProvider(
            vaultPath: vaultPath,
            noteFilePath: noteFilePath,
            noteWidth: effectiveWidth,
            onImageLoaded: {
                DispatchQueue.main.async {
                    imageReloadVersion += 1
                }
            }
        )
        config.services.images = provider
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
        listFiles: (() -> [FileResource])? = nil
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
    }

    public var body: some View {
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
            placeholder: NSAttributedString(
                string: "开始记录内容...（支持 Markdown 语法、表格、代码块）",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 15),
                    .foregroundColor: NSColor.placeholderTextColor
                ]
            )
        )
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear {
                        updateContainerWidth(proxy.size.width)
                    }
                    .onChange(of: proxy.size.width) { _, newWidth in
                        updateContainerWidth(newWidth)
                    }
            }
        )
        .onChange(of: text) { _, newText in
            onTextChange?(newText)
        }
    }

    private func updateContainerWidth(_ width: CGFloat) {
        guard width > 0, abs(containerWidth - width) > 1.0 else { return }
        containerWidth = width
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
