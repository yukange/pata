import SwiftUI
import AppKit

// MARK: - In-Place Task Description Editor

public struct InPlaceDescriptionEditor: View {
    @Binding var text: String
    var placeholder: String = "添加描述..."
    @Binding var isFocused: Bool
    var minHeight: CGFloat = 22
    var maxHeight: CGFloat = 180
    var onTextChange: ((String) -> Void)? = nil
    var onCommit: (() -> Void)? = nil

    @State private var contentHeight: CGFloat = 22

    public init(
        text: Binding<String>,
        placeholder: String = "添加描述...",
        isFocused: Binding<Bool>,
        minHeight: CGFloat = 22,
        maxHeight: CGFloat = 180,
        onTextChange: ((String) -> Void)? = nil,
        onCommit: (() -> Void)? = nil
    ) {
        self._text = text
        self.placeholder = placeholder
        self._isFocused = isFocused
        self.minHeight = minHeight
        self.maxHeight = maxHeight
        self.onTextChange = onTextChange
        self.onCommit = onCommit
    }

    public var body: some View {
        AutoSizingTextViewRepresentable(
            text: $text,
            placeholder: placeholder,
            isFocused: $isFocused,
            contentHeight: $contentHeight,
            minHeight: minHeight,
            maxHeight: maxHeight,
            onTextChange: onTextChange,
            onCommit: onCommit
        )
        .frame(height: min(max(contentHeight, minHeight), maxHeight))
    }
}

// MARK: - AutoSizingTextViewRepresentable

@MainActor
struct AutoSizingTextViewRepresentable: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    @Binding var isFocused: Bool
    @Binding var contentHeight: CGFloat
    var minHeight: CGFloat
    var maxHeight: CGFloat
    var onTextChange: ((String) -> Void)?
    var onCommit: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> DescriptionScrollView {
        let scrollView = DescriptionScrollView()
        scrollView.textView.placeholderText = placeholder
        scrollView.textView.delegate = context.coordinator
        scrollView.textView.onEscape = { [weak scrollView] in
            scrollView?.window?.makeFirstResponder(nil)
        }
        // 高度随宽度变化（换行数变了），宽度只在 layout 里才能得知
        scrollView.onWidthChange = { [weak scrollView, weak coordinator = context.coordinator] in
            guard let scrollView, let coordinator else { return }
            coordinator.updateHeight(for: scrollView)
        }
        scrollView.textView.string = text
        context.coordinator.updateHeight(for: scrollView)
        return scrollView
    }

    func updateNSView(_ scrollView: DescriptionScrollView, context: Context) {
        context.coordinator.parent = self
        scrollView.textView.placeholderText = placeholder
        // 组字中不要用绑定值覆盖：输入法未上屏的内容只在 NSTextView 里，覆盖会直接打断输入
        if !scrollView.textView.hasMarkedText(), scrollView.textView.string != text {
            scrollView.textView.string = text
            scrollView.textView.needsDisplay = true
        }
        context.coordinator.updateHeight(for: scrollView)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: AutoSizingTextViewRepresentable

        init(_ parent: AutoSizingTextViewRepresentable) {
            self.parent = parent
        }

        func textDidBeginEditing(_ notification: Notification) {
            self.parent.isFocused = true
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            // 拼音/候选未上屏，不写回绑定，避免半成品被自保存
            guard !tv.hasMarkedText(), let scrollView = tv.enclosingScrollView as? DescriptionScrollView else { return }
            updateHeight(for: scrollView)
            let newText = tv.string
            self.parent.text = newText
            self.parent.onTextChange?(newText)
        }

        func textDidEndEditing(_ notification: Notification) {
            self.parent.isFocused = false
            self.parent.onCommit?()
        }

        func updateHeight(for scrollView: DescriptionScrollView) {
            let finalHeight = scrollView.calculateHeight(minHeight: parent.minHeight)
            guard abs(parent.contentHeight - finalHeight) > 1.0 else { return }
            // 在 SwiftUI 更新循环内直接写 @State 会被丢弃（外部载入多行描述时高度就不展开）
            DispatchQueue.main.async { [weak self] in
                guard let self, abs(self.parent.contentHeight - finalHeight) > 1.0 else { return }
                self.parent.contentHeight = finalHeight
            }
        }
    }
}

// MARK: - AppKit ScrollView & TextView

public final class DescriptionScrollView: NSScrollView {
    public let textView = DescriptionNSTextView()

    /// 宽度变化（换行数变化）时回调，用于重新测量高度
    public var onWidthChange: (() -> Void)?
    private var lastLayoutWidth: CGFloat = -1

    public init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 200, height: 22))
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

    public override func layout() {
        super.layout()
        guard abs(bounds.width - lastLayoutWidth) > 0.5 else { return }
        lastLayoutWidth = bounds.width
        onWidthChange?()
    }

    public override func mouseDown(with event: NSEvent) {
        if window?.firstResponder != textView {
            window?.makeFirstResponder(textView)
        }
        super.mouseDown(with: event)
    }

    public func calculateHeight(minHeight: CGFloat = 22) -> CGFloat {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return minHeight
        }
        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        let padding = textView.textContainerInset.height * 2
        let calculated = ceil(usedRect.height + padding)
        return max(minHeight, calculated)
    }
}

public final class DescriptionNSTextView: NSTextView {
    public var placeholderText: String = "添加描述..."
    public var onEscape: (() -> Void)?

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
        self.font = .systemFont(ofSize: 14)
        self.textColor = .labelColor
        self.focusRingType = .none
        self.isRichText = false
        self.importsGraphics = false
        self.isAutomaticQuoteSubstitutionEnabled = false
        self.isAutomaticDashSubstitutionEnabled = false
        self.textContainerInset = NSSize(width: 0, height: 3)
        self.textContainer?.lineFragmentPadding = 0
        self.textContainer?.widthTracksTextView = true
        self.isHorizontallyResizable = false
        self.isVerticallyResizable = true
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
                .font: font ?? NSFont.systemFont(ofSize: 14),
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
