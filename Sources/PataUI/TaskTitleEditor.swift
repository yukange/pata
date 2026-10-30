import SwiftUI
import AppKit

// MARK: - In-Place Task Title Editor

public struct InPlaceTitleEditor: View {
    @Binding var text: String
    var placeholder: String = "任务标题"
    var isDone: Bool = false
    @Binding var isFocused: Bool
    var onTextChange: ((String) -> Void)? = nil
    var onCommit: (() -> Void)? = nil

    @State private var contentHeight: CGFloat = 26

    public init(
        text: Binding<String>,
        placeholder: String = "任务标题",
        isDone: Bool = false,
        isFocused: Binding<Bool>,
        onTextChange: ((String) -> Void)? = nil,
        onCommit: (() -> Void)? = nil
    ) {
        self._text = text
        self.placeholder = placeholder
        self.isDone = isDone
        self._isFocused = isFocused
        self.onTextChange = onTextChange
        self.onCommit = onCommit
    }

    public var body: some View {
        TitleTextViewRepresentable(
            text: $text,
            placeholder: placeholder,
            isDone: isDone,
            isFocused: $isFocused,
            contentHeight: $contentHeight,
            onTextChange: onTextChange,
            onCommit: onCommit
        )
        .frame(height: max(contentHeight, 26))
    }
}

// MARK: - TitleTextViewRepresentable

@MainActor
struct TitleTextViewRepresentable: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var isDone: Bool
    @Binding var isFocused: Bool
    @Binding var contentHeight: CGFloat
    var onTextChange: ((String) -> Void)?
    var onCommit: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> TitleNSTextView {
        let textView = TitleNSTextView()
        textView.placeholderText = placeholder
        textView.isDone = isDone
        textView.delegate = context.coordinator
        textView.onEscape = { [weak textView] in
            textView?.window?.makeFirstResponder(nil)
        }
        textView.onEnter = { [weak textView] in
            textView?.window?.makeFirstResponder(nil)
            context.coordinator.parent.onCommit?()
        }
        textView.string = text
        textView.updateTextColor()
        context.coordinator.updateHeight(for: textView)
        return textView
    }

    func updateNSView(_ textView: TitleNSTextView, context: Context) {
        textView.placeholderText = placeholder
        if textView.isDone != isDone {
            textView.isDone = isDone
        }
        if textView.string != text {
            textView.string = text
            textView.updateTextColor()
            textView.needsDisplay = true
            context.coordinator.updateHeight(for: textView)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: TitleTextViewRepresentable

        init(_ parent: TitleTextViewRepresentable) {
            self.parent = parent
        }

        func textDidBeginEditing(_ notification: Notification) {
            self.parent.isFocused = true
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? TitleNSTextView else { return }
            let raw = tv.string
            // Sanitize newlines to preserve single-line semantic
            let sanitized = raw.replacingOccurrences(of: "\r\n", with: " ")
                               .replacingOccurrences(of: "\n", with: " ")
                               .replacingOccurrences(of: "\r", with: " ")
            if sanitized != raw {
                tv.string = sanitized
            }
            updateHeight(for: tv)
            self.parent.text = sanitized
            self.parent.onTextChange?(sanitized)
        }

        func textDidEndEditing(_ notification: Notification) {
            self.parent.isFocused = false
            self.parent.onCommit?()
        }

        func updateHeight(for textView: TitleNSTextView) {
            let finalHeight = textView.calculateHeight()
            if abs(parent.contentHeight - finalHeight) > 1.0 {
                self.parent.contentHeight = finalHeight
            }
        }
    }
}

// MARK: - AppKit Title TextView

public final class TitleNSTextView: NSTextView {
    public var placeholderText: String = "任务标题"
    public var onEscape: (() -> Void)?
    public var onEnter: (() -> Void)?

    public var isDone: Bool = false {
        didSet {
            updateTextColor()
            needsDisplay = true
        }
    }

    public override init(frame frameRect: NSRect, textContainer: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: textContainer)
        setup()
    }

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        self.drawsBackground = false
        self.font = .systemFont(ofSize: 18, weight: .bold)
        self.focusRingType = .none
        self.isRichText = false
        self.importsGraphics = false
        self.isAutomaticQuoteSubstitutionEnabled = false
        self.isAutomaticDashSubstitutionEnabled = false
        self.textContainerInset = NSSize(width: 0, height: 1)
        self.textContainer?.lineFragmentPadding = 0
        self.textContainer?.widthTracksTextView = true
        self.isHorizontallyResizable = false
        self.isVerticallyResizable = true
        updateTextColor()
    }

    public func updateTextColor() {
        // When completed, only lower text brightness slightly (0.68 opacity), no strikethrough
        let color = isDone ? NSColor.labelColor.withAlphaComponent(0.68) : NSColor.labelColor
        self.textColor = color
        var attrs = self.typingAttributes
        attrs[.foregroundColor] = color
        attrs.removeValue(forKey: .strikethroughStyle)
        self.typingAttributes = attrs
        if let storage = self.textStorage {
            storage.addAttribute(.foregroundColor, value: color, range: NSRange(location: 0, length: storage.length))
            storage.removeAttribute(.strikethroughStyle, range: NSRange(location: 0, length: storage.length))
        }
    }

    public override func insertNewline(_ sender: Any?) {
        // IME marked text support: when composing Chinese Pinyin, Enter confirms the latin text
        if hasMarkedText() {
            super.insertNewline(sender)
            return
        }
        // When not composing, Enter commits and finishes editing
        if let onEnter = onEnter {
            onEnter()
        } else {
            self.window?.makeFirstResponder(nil)
        }
    }

    public override func cancelOperation(_ sender: Any?) {
        if let onEscape = onEscape {
            onEscape()
        } else {
            self.window?.makeFirstResponder(nil)
        }
    }

    public override func didChangeText() {
        super.didChangeText()
        needsDisplay = true
    }

    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if string.isEmpty && (textStorage?.length ?? 0) == 0 && markedRange().length == 0 {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font ?? NSFont.systemFont(ofSize: 18, weight: .bold),
                .foregroundColor: NSColor.placeholderTextColor
            ]
            let rect = NSRect(
                x: textContainerInset.width,
                y: textContainerInset.height,
                width: max(0, bounds.width - textContainerInset.width * 2),
                height: max(0, bounds.height - textContainerInset.height * 2)
            )
            (placeholderText as NSString).draw(in: rect, withAttributes: attrs)
        }
    }

    public func calculateHeight() -> CGFloat {
        guard let layoutManager = self.layoutManager,
              let textContainer = self.textContainer else {
            return 26
        }
        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        let padding = self.textContainerInset.height * 2
        let calculated = ceil(usedRect.height + padding)
        return max(26, calculated)
    }
}
