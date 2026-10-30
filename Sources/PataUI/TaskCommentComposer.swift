import SwiftUI
import AppKit

// MARK: - Unified Activity Composer Box

public struct ActivityComposerBox: View {
    @Binding var text: String
    var placeholder: String = "记录进展..."
    var fontSize: CGFloat = 12
    var inputHeight: CGFloat = 52
    var buttonText: String = "发送 ⌘↵"
    @ObservedObject var state: AppState
    var onSubmit: (String) -> Void

    public init(
        text: Binding<String>,
        placeholder: String = "记录进展...",
        fontSize: CGFloat = 12,
        inputHeight: CGFloat = 52,
        buttonText: String = "发送 ⌘↵",
        state: AppState,
        onSubmit: @escaping (String) -> Void
    ) {
        self._text = text
        self.placeholder = placeholder
        self.fontSize = fontSize
        self.inputHeight = inputHeight
        self.buttonText = buttonText
        self.state = state
        self.onSubmit = onSubmit
    }

    public init(
        text: Binding<String>,
        placeholder: String = "记录进展...",
        fontSize: CGFloat = 12,
        inputHeight: CGFloat = 52,
        buttonText: String = "发送 ⌘↵",
        state: AppState,
        onSubmit: @escaping () -> Void
    ) {
        self._text = text
        self.placeholder = placeholder
        self.fontSize = fontSize
        self.inputHeight = inputHeight
        self.buttonText = buttonText
        self.state = state
        self.onSubmit = { _ in onSubmit() }
    }

    private var borderColor: Color {
        switch state.themePreference {
        case "dark": return Color(red: 41/255, green: 37/255, blue: 36/255)
        default: return Color(red: 231/255, green: 229/255, blue: 228/255)
        }
    }

    public var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            CommentTextViewRepresentable(
                text: $text,
                placeholder: placeholder,
                fontSize: fontSize,
                onSubmit: onSubmit
            )
            .frame(height: inputHeight)

            Button(action: {
                let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !clean.isEmpty else { return }
                onSubmit(clean)
                text = ""
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 9))
                    Text(buttonText)
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(state.effectiveAccentOnColor)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 5).fill(state.effectiveAccentColor))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .padding(.trailing, 8)
            .padding(.bottom, 6)
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderColor, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - CommentTextViewRepresentable

@MainActor
struct CommentTextViewRepresentable: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var fontSize: CGFloat
    var onSubmit: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> CommentScrollView {
        let scrollView = CommentScrollView()
        scrollView.textView.fontSize = fontSize
        scrollView.textView.placeholderText = placeholder
        scrollView.textView.delegate = context.coordinator
        scrollView.textView.onSubmit = { [weak scrollView] str in
            context.coordinator.parent.text = str
            context.coordinator.parent.onSubmit(str)
            scrollView?.textView.string = ""
        }
        scrollView.textView.string = text
        return scrollView
    }

    func updateNSView(_ scrollView: CommentScrollView, context: Context) {
        context.coordinator.parent = self
        scrollView.textView.placeholderText = placeholder
        if scrollView.textView.fontSize != fontSize {
            scrollView.textView.fontSize = fontSize
        }
        if scrollView.textView.string != text {
            scrollView.textView.string = text
            scrollView.textView.needsDisplay = true
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CommentTextViewRepresentable

        init(_ parent: CommentTextViewRepresentable) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            self.parent.text = tv.string
        }
    }
}

// MARK: - Comment ScrollView

public final class CommentScrollView: NSScrollView {
    public let textView = CommentNSTextView()

    public init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 200, height: 52))
        self.drawsBackground = false
        self.borderType = .noBorder
        self.focusRingType = .none
        self.hasVerticalScroller = true
        self.autohidesScrollers = true
        self.hasHorizontalScroller = false

        textView.autoresizingMask = [.width]
        self.documentView = textView
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func mouseDown(with event: NSEvent) {
        if window?.firstResponder != textView {
            window?.makeFirstResponder(textView)
        }
        super.mouseDown(with: event)
    }
}

// MARK: - Comment NSTextView

public final class CommentNSTextView: NSTextView {
    public var placeholderText: String = "记录进展..."
    public var fontSize: CGFloat = 12 {
        didSet {
            self.font = .systemFont(ofSize: fontSize)
            needsDisplay = true
        }
    }
    public var onSubmit: ((String) -> Void)?

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
        self.font = .systemFont(ofSize: fontSize)
        self.textColor = .labelColor
        self.focusRingType = .none
        self.isRichText = false
        self.importsGraphics = false
        self.isAutomaticQuoteSubstitutionEnabled = false
        self.isAutomaticDashSubstitutionEnabled = false
        // Precise insets: cursor baseline exactly matches font size text
        self.textContainerInset = NSSize(width: 8, height: 6)
        self.textContainer?.lineFragmentPadding = 0
        self.textContainer?.widthTracksTextView = true
        self.isHorizontallyResizable = false
        self.isVerticallyResizable = true
    }

    private func isSubmitEvent(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command) else { return false }
        if event.keyCode == 36 || event.keyCode == 76 {
            return true
        }
        if let chars = event.charactersIgnoringModifiers {
            if chars == "\r" || chars == "\n" || chars == "\u{3}" {
                return true
            }
        }
        return false
    }

    private func triggerSubmit() {
        let clean = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        onSubmit?(clean)
    }

    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if isSubmitEvent(event) {
            if hasMarkedText() { return false }
            triggerSubmit()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    public override func keyDown(with event: NSEvent) {
        if isSubmitEvent(event) {
            if hasMarkedText() {
                super.keyDown(with: event)
                return
            }
            triggerSubmit()
            return
        }
        super.keyDown(with: event)
    }

    public override func didChangeText() {
        super.didChangeText()
        needsDisplay = true
    }

    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if string.isEmpty && (textStorage?.length ?? 0) == 0 && markedRange().length == 0 {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font ?? NSFont.systemFont(ofSize: fontSize),
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
}
