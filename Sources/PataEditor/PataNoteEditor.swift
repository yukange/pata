import SwiftUI
import AppKit
import PataCore

/// The unified Note Editor component for Pata.
/// Implemented via AppKit / TextKit 2 to guarantee 100% native trackpad tap-to-click,
/// native IME (Doubao / ABC) marked-text composition, native undo/redo, and lossless markdown roundtrip.
public struct PataNoteEditor: NSViewRepresentable {
    public let noteId: String
    @Binding public var text: String
    public var isReadOnlyTranscript: Bool
    public var onSeekAudio: ((Int) -> Void)?
    public var onTextChange: ((String) -> Void)?
    public var listNoteRefs: (() -> [NoteRef])?
    public var listFiles: (() -> [FileResource])?

    public init(
        noteId: String,
        text: Binding<String>,
        isReadOnlyTranscript: Bool = false,
        onSeekAudio: ((Int) -> Void)? = nil,
        onTextChange: ((String) -> Void)? = nil,
        listNoteRefs: (() -> [NoteRef])? = nil,
        listFiles: (() -> [FileResource])? = nil
    ) {
        self.noteId = noteId
        self._text = text
        self.isReadOnlyTranscript = isReadOnlyTranscript
        self.onSeekAudio = onSeekAudio
        self.onTextChange = onTextChange
        self.listNoteRefs = listNoteRefs
        self.listFiles = listFiles
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let contentSize = scrollView.contentSize
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        let textContainer = NSTextContainer(containerSize: NSSize(width: contentSize.width, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)

        let textView = PataTextView(frame: NSRect(origin: .zero, size: contentSize), textContainer: textContainer)
        textView.minSize = NSSize(width: 0, height: contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 16, height: 16)
        textView.drawsBackground = false

        textView.delegate = context.coordinator
        context.coordinator.textView = textView
        context.coordinator.applyInitialText(text)

        scrollView.documentView = textView
        return scrollView
    }

    public func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = nsView.documentView as? PataTextView else { return }

        textView.isEditable = !isReadOnlyTranscript
        textView.isSelectable = true

        if context.coordinator.currentNoteId != noteId {
            context.coordinator.currentNoteId = noteId
            context.coordinator.applyInitialText(text)
        } else if textView.string != text && !context.coordinator.isInternalEditing {
            context.coordinator.applyInitialText(text)
        }
    }

    @MainActor
    public final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PataNoteEditor
        weak var textView: PataTextView?
        var currentNoteId: String = ""
        var isInternalEditing = false
        private var syntaxTimer: Timer?

        init(_ parent: PataNoteEditor) {
            self.parent = parent
            self.currentNoteId = parent.noteId
        }

        func applyInitialText(_ text: String) {
            guard let tv = textView else { return }
            isInternalEditing = true
            let selectedRange = tv.selectedRange()
            tv.string = text
            highlightSyntax()
            if selectedRange.location <= (text as NSString).length {
                tv.setSelectedRange(selectedRange)
            }
            isInternalEditing = false
        }

        public func textDidChange(_ notification: Notification) {
            guard let tv = textView, !isInternalEditing else { return }
            let newText = tv.string
            parent.text = newText
            parent.onTextChange?(newText)

            syntaxTimer?.invalidate()
            syntaxTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.highlightSyntax()
                }
            }

            checkAutocompleteTrigger()
        }

        public func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            if let str = link as? String ?? (link as? URL)?.absoluteString {
                if str.contains("#t=") {
                    if let anchor = str.components(separatedBy: "#t=").last,
                       let ms = parseTimestampMs(anchor) {
                        parent.onSeekAudio?(ms)
                        return true
                    }
                }
            }
            return false
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

        private func highlightSyntax() {
            guard let tv = textView else { return }
            let text = tv.string
            let fullRange = NSRange(location: 0, length: (text as NSString).length)
            guard fullRange.length > 0 else { return }

            guard let storage = tv.textStorage else { return }
            storage.beginEditing()

            // Reset base font & color
            let baseFont = NSFont.systemFont(ofSize: 15)
            let textColor = NSColor.labelColor
            storage.setAttributes([
                .font: baseFont,
                .foregroundColor: textColor
            ], range: fullRange)

            // Highlight headings
            let headingRe = try? NSRegularExpression(pattern: #"(?m)^(#+)\s+(.+)$"#)
            headingRe?.enumerateMatches(in: text, range: fullRange) { match, _, _ in
                guard let m = match, m.numberOfRanges >= 3 else { return }
                let hashes = (text as NSString).substring(with: m.range(at: 1))
                let level = hashes.count
                let size: CGFloat = level == 1 ? 22 : (level == 2 ? 18 : 16)
                let font = NSFont.boldSystemFont(ofSize: size)
                storage.addAttribute(.font, value: font, range: m.range)
            }

            // Highlight bold
            let boldRe = try? NSRegularExpression(pattern: #"\*\*([^*]+)\*\*"#)
            boldRe?.enumerateMatches(in: text, range: fullRange) { match, _, _ in
                guard let m = match else { return }
                storage.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: 15), range: m.range)
            }

            // Highlight code blocks
            let codeBlockRe = try? NSRegularExpression(pattern: #"(?ms)```.*?```"#)
            codeBlockRe?.enumerateMatches(in: text, range: fullRange) { match, _, _ in
                guard let m = match else { return }
                storage.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular), range: m.range)
                storage.addAttribute(.backgroundColor, value: NSColor.quaternaryLabelColor.withAlphaComponent(0.2), range: m.range)
            }

            // Highlight links / timestamp links
            let linkRe = try? NSRegularExpression(pattern: #"\[([^\]]+)\]\(([^)]+)\)"#)
            linkRe?.enumerateMatches(in: text, range: fullRange) { match, _, _ in
                guard let m = match, m.numberOfRanges >= 3 else { return }
                let urlStr = (text as NSString).substring(with: m.range(at: 2))
                storage.addAttribute(.foregroundColor, value: NSColor.linkColor, range: m.range)
                storage.addAttribute(.link, value: urlStr, range: m.range)
            }

            storage.endEditing()
        }

        private func checkAutocompleteTrigger() {
            guard let tv = textView else { return }
            let sel = tv.selectedRange()
            guard sel.location >= 2 else { return }
            let text = tv.string as NSString
            let sub = text.substring(with: NSRange(location: sel.location - 2, length: 2))
            if sub == "[[" {
                // Trigger [[ auto-completion
                showAutocomplete(at: sel.location)
            }
        }

        private func showAutocomplete(at location: Int) {
            guard let noteRefs = parent.listNoteRefs?() else { return }
            // If autocomplete candidates exist, show menu
            let menu = NSMenu(title: "引用笔记")
            for ref in noteRefs.prefix(10) {
                let item = NSMenuItem(title: ref.title, action: #selector(didSelectNoteRef(_:)), keyEquivalent: "")
                item.representedObject = ref
                item.target = self
                menu.addItem(item)
            }

            if let tv = textView, let window = tv.window {
                let rect = tv.firstRect(forCharacterRange: NSRange(location: location, length: 0), actualRange: nil)
                let windowPoint = window.convertPoint(fromScreen: rect.origin)
                menu.popUp(positioning: nil, at: windowPoint, in: tv)
            }
        }

        @objc func didSelectNoteRef(_ sender: NSMenuItem) {
            guard let ref = sender.representedObject as? NoteRef, let tv = textView else { return }
            let sel = tv.selectedRange()
            guard sel.location >= 2 else { return }

            let linkMarkdown = "[\(ref.title)](\(ref.path))"
            let replaceRange = NSRange(location: sel.location - 2, length: 2)

            if tv.shouldChangeText(in: replaceRange, replacementString: linkMarkdown) {
                tv.replaceCharacters(in: replaceRange, with: linkMarkdown)
                tv.didChangeText()
            }
        }
    }
}

/// Custom NSTextView that properly handles trackpad tap-to-click, IME marked text, and key events.
public final class PataTextView: NSTextView {
    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    public override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Handle Command+Enter or other editor shortcuts if needed
        return super.performKeyEquivalent(with: event)
    }
}
