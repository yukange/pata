import SwiftUI
import AppKit
import PataCore

public struct ActivityComposer: View {
    @Binding public var text: String
    public var placeholder: String = "记录今天的进展或思考... (支持 [[笔记引用]], ⌘+Enter 发送)"
    public var onSubmit: () -> Void

    public init(text: Binding<String>, placeholder: String = "记录今天的进展或思考... (支持 [[笔记引用]], ⌘+Enter 发送)", onSubmit: @escaping () -> Void) {
        self._text = text
        self.placeholder = placeholder
        self.onSubmit = onSubmit
    }

    public var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            TextEditor(text: $text)
                .font(.system(size: 14))
                .frame(minHeight: 56, maxHeight: 120)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text(placeholder)
                            .foregroundColor(.secondary)
                            .font(.system(size: 14))
                            .allowsHitTesting(false)
                            .padding(.top, 2)
                    }
                }

            HStack {
                Spacer()
                Button(action: onSubmit) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.circle.fill")
                        Text("发送")
                    }
                    .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(nsColor: .separatorColor), lineWidth: 1))
    }
}

public struct ActivityItemView: View {
    public let activity: Activity
    public var taskTitle: String?
    public var onTaskClick: (() -> Void)?
    public var onNoteClick: ((String) -> Void)?
    public var onSaveEdit: ((String) -> Void)?
    public var onDelete: (() -> Void)?

    @State private var isHovered: Bool = false
    @State private var isEditing: Bool = false
    @State private var editText: String = ""

    public init(
        activity: Activity,
        taskTitle: String? = nil,
        onTaskClick: (() -> Void)? = nil,
        onNoteClick: ((String) -> Void)? = nil,
        onSaveEdit: ((String) -> Void)? = nil,
        onDelete: (() -> Void)? = nil
    ) {
        self.activity = activity
        self.taskTitle = taskTitle
        self.onTaskClick = onTaskClick
        self.onNoteClick = onNoteClick
        self.onSaveEdit = onSaveEdit
        self.onDelete = onDelete
    }

    private var timeString: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: activity.at)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header: Time + Task title + Action buttons
            HStack(spacing: 8) {
                Text(timeString)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundColor(.secondary)

                if let title = taskTitle, !title.isEmpty {
                    Button(action: { onTaskClick?() }) {
                        Text(title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                }

                if activity.by == SourceAgent {
                    Text("Agent")
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.orange.opacity(0.2)))
                        .foregroundColor(.orange)
                }

                Spacer()

                if isHovered && !isEditing {
                    HStack(spacing: 4) {
                        Button(action: {
                            editText = activity.body
                            isEditing = true
                        }) {
                            Image(systemName: "pencil")
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.secondary)

                        if let onDelete = onDelete {
                            Button(action: onDelete) {
                                Image(systemName: "trash")
                                    .font(.system(size: 12))
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.secondary)
                        }
                    }
                }
            }

            // Body or In-place Editor
            if isEditing {
                VStack(alignment: .trailing, spacing: 8) {
                    TextEditor(text: $editText)
                        .font(.system(size: 14))
                        .frame(minHeight: 48)
                        .padding(4)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))

                    HStack(spacing: 8) {
                        Button("取消") {
                            isEditing = false
                        }
                        .buttonStyle(.bordered)

                        Button("保存") {
                            onSaveEdit?(editText)
                            isEditing = false
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(editText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .padding(4)
            } else {
                Text(activity.body)
                    .font(.system(size: 14))
                    .foregroundColor(.primary)
                    .textSelection(.enabled)
                    .lineSpacing(3)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(isHovered ? RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .quaternaryLabelColor).opacity(0.3)) : RoundedRectangle(cornerRadius: 6).fill(Color.clear))
        .onHover { h in
            isHovered = h
        }
    }
}

public struct ActivityTextView: View {
    public let text: String
    @ObservedObject public var state: AppState

    public init(text: String, state: AppState) {
        self.text = text
        self.state = state
    }

    public var body: some View {
        Text(attributedText)
            .font(.system(size: 13))
            .foregroundColor(.primary)
            .lineSpacing(3)
            .textSelection(.enabled)
            .environment(\.openURL, OpenURLAction { url in
                if url.scheme == "pata", url.host == "note" {
                    let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    let decoded = path.removingPercentEncoding ?? path
                    if let v = state.vault {
                        if v.index.getNote(decoded) != nil {
                            state.navigateToNote(noteId: decoded)
                            return .handled
                        }
                        let notesMap = v.index.listNotes().reduce(into: [String: Note]()) { $0[$1.id] = $1 }
                        if let targetId = Links.resolveTextRef(name: decoded, noteRefs: [:], notes: notesMap) {
                            state.navigateToNote(noteId: targetId)
                            return .handled
                        }
                    }
                    return .handled
                }
                return .systemAction
            })
    }

    private var attributedText: AttributedString {
        let converted = convertWikilinksToMarkdown(text: text)
        if let attr = try? AttributedString(markdown: converted, options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return attr
        }
        return AttributedString(text)
    }

    private func convertWikilinksToMarkdown(text: String) -> String {
        let pattern = #"\\?\[\[([^\[\]\n]+)\]\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }

        let nsText = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))
        var result = ""
        var lastIndex = 0

        for match in matches {
            let fullRange = match.range(at: 0)
            let titleRange = match.range(at: 1)
            let fullStr = nsText.substring(with: fullRange)

            if fullStr.hasPrefix("\\") {
                continue
            }

            if fullRange.location > lastIndex {
                result += nsText.substring(with: NSRange(location: lastIndex, length: fullRange.location - lastIndex))
            }

            let title = nsText.substring(with: titleRange)
            let encoded = title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? title
            result += "[\\[[\(title)]\\]](pata://note/\(encoded))"
            lastIndex = fullRange.location + fullRange.length
        }

        if lastIndex < nsText.length {
            result += nsText.substring(with: NSRange(location: lastIndex, length: nsText.length - lastIndex))
        }

        return result
    }
}

extension Color {
    public static var emeraldColor: Color {
        Color(red: 4/255, green: 120/255, blue: 87/255)
    }
    public static var stoneBadgeBg: Color {
        Color(nsColor: .separatorColor).opacity(0.3)
    }
    public static var stoneSelectedBg: Color {
        Color(nsColor: .selectedContentBackgroundColor).opacity(0.2)
    }
    public static var stoneTagBg: Color {
        Color(red: 4/255, green: 120/255, blue: 87/255).opacity(0.1)
    }
}
