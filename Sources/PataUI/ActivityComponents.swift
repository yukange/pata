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
