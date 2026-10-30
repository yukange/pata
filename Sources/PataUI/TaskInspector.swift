import SwiftUI
import AppKit
import PataCore

public struct TaskInspector: View {
    @ObservedObject var state: AppState
    let taskId: String

    @State private var newActivityBody: String = ""
    @State private var isEditingDesc: Bool = false
    @State private var descDraft: String = ""
    @State private var newTagInput: String = ""
    @State private var showTagPopover: Bool = false
    @State private var showDuePopover: Bool = false

    public init(state: AppState, taskId: String) {
        self.state = state
        self.taskId = taskId
    }

    private var task: Task? {
        state.vault?.index.getTask(taskId)
    }

    private var isOverdue: Bool {
        guard let t = task, let due = t.due, t.status != .done else { return false }
        return due < state.todayDateString
    }

    private var borderColor: Color {
        switch state.themePreference {
        case "dark": return Color(red: 41/255, green: 37/255, blue: 36/255)
        default: return Color(red: 231/255, green: 229/255, blue: 228/255)
        }
    }

    public var body: some View {
        if let t = task {
            VStack(spacing: 0) {
                // Top header bar (close arrow -> and more menu ...)
                inspectorHeader(t)

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Title
                        Text(t.title)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.primary)

                        // Status & Due Date Row
                        HStack(spacing: 12) {
                            Button(action: { toggleStatus(t) }) {
                                HStack(spacing: 6) {
                                    Image(systemName: t.status == .done ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 14))
                                        .foregroundColor(t.status == .done ? Color.emeraldColor : .secondary)
                                    Text(t.status == .done ? "已完成" : "待办")
                                        .font(.system(size: 13))
                                        .foregroundColor(.primary)
                                }
                            }
                            .buttonStyle(.plain)

                            if let due = t.due {
                                HStack(spacing: 4) {
                                    Image(systemName: "calendar")
                                        .font(.system(size: 11))
                                    Text(isOverdue ? "\(due) (已逾期)" : "\(due) 截止")
                                        .font(.system(size: 12, weight: isOverdue ? .medium : .regular))
                                }
                                .foregroundColor(isOverdue ? Color(red: 220/255, green: 38/255, blue: 38/255) : .secondary)
                            }
                        }

                        // Tags Row
                        HStack(spacing: 6) {
                            ForEach(t.tags, id: \.self) { tag in
                                HStack(spacing: 3) {
                                    Text("#\(tag)")
                                        .font(.system(size: 11))
                                    Button(action: { removeTag(t, tag) }) {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 8))
                                    }
                                    .buttonStyle(.plain)
                                }
                                .foregroundColor(Color(red: 71/255, green: 110/255, blue: 88/255))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.04)))
                            }

                            Button(action: { showTagPopover.toggle() }) {
                                HStack(spacing: 3) {
                                    Image(systemName: "plus")
                                        .font(.system(size: 9))
                                    Text("标签")
                                        .font(.system(size: 11))
                                }
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.02)))
                                .overlay(RoundedRectangle(cornerRadius: 4).stroke(borderColor, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .popover(isPresented: $showTagPopover) {
                                tagPopoverContent(t)
                            }
                        }

                        Divider()

                        // Description Section
                        VStack(alignment: .leading, spacing: 6) {
                            Text("描述")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)

                            Text(t.description.isEmpty ? "暂无描述" : t.description)
                                .font(.system(size: 13))
                                .foregroundColor(.primary)
                                .lineSpacing(3)
                        }

                        Divider()

                        // Activities Section
                        VStack(alignment: .leading, spacing: 10) {
                            Text("活动")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)

                            // Created event
                            HStack(spacing: 6) {
                                Text(formatTime(t.createdAt))
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.secondary)
                                Image(systemName: "person.fill")
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                                Text("由我创建")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                Spacer()
                            }

                            // Activities
                            ForEach(t.activities) { act in
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(formatTime(act.at))
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundColor(.secondary)
                                        Image(systemName: "person.fill")
                                            .font(.system(size: 9))
                                            .foregroundColor(.secondary)
                                        Text("我")
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                        Spacer()
                                    }

                                    Text(act.body)
                                        .font(.system(size: 13))
                                        .foregroundColor(.primary)
                                        .padding(.top, 1)
                                }
                            }
                        }
                    }
                    .padding(20)
                }

                // Bottom Activity Composer
                VStack(alignment: .trailing, spacing: 6) {
                    TextEditor(text: $newActivityBody)
                        .font(.system(size: 12))
                        .frame(height: 52)
                        .scrollContentBackground(.hidden)
                        .padding(6)
                        .overlay(
                            Group {
                                if newActivityBody.isEmpty {
                                    Text("记录进展...")
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary.opacity(0.6))
                                        .padding(.leading, 10)
                                        .padding(.top, 10)
                                        .allowsHitTesting(false)
                                }
                            },
                            alignment: .topLeading
                        )

                    Button(action: submitActivity) {
                        HStack(spacing: 4) {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 9))
                            Text("发送 ⌘↵")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color(red: 154/255, green: 178/255, blue: 167/255)))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.return, modifiers: .command)
                    .padding(.trailing, 8)
                    .padding(.bottom, 6)
                }
                .background(Color.primary.opacity(0.02))
                .overlay(
                    Rectangle()
                        .stroke(borderColor, lineWidth: 1)
                )
                .padding(12)
            }
        }
    }

    private func inspectorHeader(_ t: Task) -> some View {
        HStack {
            Button(action: { state.closeTaskInspector() }) {
                Image(systemName: "arrow.right")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .padding(8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("关闭详情")

            Spacer()

            Menu {
                Button("复制给 Agent (⌘⇧C)") {
                    copyForAgent(t)
                }
                Divider()
                Button("删除任务", role: .destructive) {
                    deleteTask(t)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .padding(8)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
        }
        .frame(height: 44)
        .padding(.horizontal, 8)
    }

    private func tagPopoverContent(_ t: Task) -> some View {
        VStack(spacing: 8) {
            TextField("输入标签...", text: $newTagInput)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    addTag(t)
                }
            Button("添加") {
                addTag(t)
            }
        }
        .padding(12)
        .frame(width: 180)
    }

    private func formatTime(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f.string(from: d)
    }

    private func toggleStatus(_ t: Task) {
        let next: TaskStatus = t.status == .done ? .todo : .done
        try? state.vault?.setTaskStatus(id: t.id, status: next)
        state.objectWillChange.send()
    }

    private func removeTag(_ t: Task, _ tag: String) {
        var updated = t
        updated.tags.removeAll { $0.lowercased() == tag.lowercased() }
        try? state.vault?.updateTask(updated)
        state.objectWillChange.send()
    }

    private func addTag(_ t: Task) {
        let clean = newTagInput.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        guard !clean.isEmpty else { return }
        var updated = t
        if !updated.tags.contains(clean) {
            updated.tags.append(clean)
            try? state.vault?.updateTask(updated)
            state.objectWillChange.send()
        }
        newTagInput = ""
        showTagPopover = false
    }

    private func submitActivity() {
        let clean = newActivityBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, let v = state.vault else { return }

        do {
            _ = try v.createActivity(taskId: taskId, date: state.todayDateString, body: clean)
            newActivityBody = ""
            state.objectWillChange.send()
        } catch {
            print("Failed to add activity:", error)
        }
    }

    private func copyForAgent(_ t: Task) {
        let text = """
        [Pata 任务参考]
        ID: \(t.id)
        标题: \(t.title)
        状态: \(t.status == .done ? "done" : "todo")
        URI: pata://task/\(t.id)
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func deleteTask(_ t: Task) {
        try? state.vault?.deleteTask(id: t.id)
        state.closeTaskInspector()
        state.objectWillChange.send()
    }
}
