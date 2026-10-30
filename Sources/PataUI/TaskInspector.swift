import SwiftUI
import AppKit
import PataCore

public struct TaskInspector: View {
    @ObservedObject var state: AppState
    let taskId: String

    @State private var newActivityBody: String = ""
    @State private var isEditingDesc: Bool = false
    @State private var descDraft: String = ""

    // In-place tag editing
    @State private var isAddingTag: Bool = false
    @State private var newTagInput: String = ""
    @FocusState private var isTagInputFocused: Bool
    @State private var highlightedCandidateIndex: Int? = nil

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

    private var isTaskInTodayPlan: Bool {
        guard let v = state.vault else { return false }
        let plan = v.getDayPlan(date: state.todayDateString)
        return plan.taskIds.contains(taskId)
    }

    private var borderColor: Color {
        switch state.themePreference {
        case "dark": return Color(red: 41/255, green: 37/255, blue: 36/255)
        default: return Color(red: 231/255, green: 229/255, blue: 228/255)
        }
    }

    private var cardBg: Color {
        switch state.themePreference {
        case "dark": return Color(red: 28/255, green: 25/255, blue: 23/255)
        default: return Color.white
        }
    }

    private var suggestedTags: [String] {
        guard let v = state.vault, let t = task else { return [] }
        let current = Set(t.tags.map { $0.lowercased() })
        let q = newTagInput.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "").lowercased()
        let allTags = v.index.listTags().map { $0.name }
        return allTags
            .filter { !current.contains($0.lowercased()) }
            .filter { q.isEmpty || $0.lowercased().contains(q) }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
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

                        // Tags Row (In-place editing with focus & suggestions)
                        tagsRow(t)
                            .zIndex(50)

                        Divider()

                        // Description Section (in-place viewing & editing)
                        descriptionSection(t)

                        Divider()

                        // Activities & Status Events Section
                        activitiesSection(t)
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
            .onChange(of: taskId) { _ in
                isEditingDesc = false
                descDraft = ""
                cancelAddTag()
            }
        }
    }

    // MARK: - Header Bar

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
                Button("复制给 Agent") {
                    copyForAgent(t)
                }

                if isTaskInTodayPlan {
                    Button("移出今日计划") {
                        removeFromTodayPlan()
                    }
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

    // MARK: - Tags Row (In-place TextField + @FocusState + Lightweight Suggestions)

    private func tagsRow(_ t: Task) -> some View {
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

            if isAddingTag {
                HStack(spacing: 2) {
                    Text("#")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)

                    TextField("新标签...", text: $newTagInput)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .focused($isTagInputFocused)
                        .frame(minWidth: 50, maxWidth: 100)
                        .onSubmit {
                            if IMECompositionTracker.shared.isComposingOrJustCommitted() {
                                return
                            }
                            if let idx = highlightedCandidateIndex, idx >= 0, idx < suggestedTags.count {
                                addTag(t, suggestedTags[idx])
                            } else {
                                submitNewTag(t)
                            }
                        }
                        .onExitCommand {
                            cancelAddTag()
                        }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.02)))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.accentColor.opacity(0.7), lineWidth: 1))
                .overlay(alignment: .topLeading) {
                    if !suggestedTags.isEmpty {
                        tagCandidateDropdown(t)
                            .offset(y: 26)
                    }
                }
            } else {
                Button(action: {
                    newTagInput = ""
                    isAddingTag = true
                    DispatchQueue.main.async {
                        isTagInputFocused = true
                    }
                }) {
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
            }
        }
        .onChange(of: isTagInputFocused) { focused in
            if !focused {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    if !isTagInputFocused {
                        if newTagInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            isAddingTag = false
                        }
                    }
                }
            }
        }
    }

    private func tagCandidateDropdown(_ t: Task) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("已有标签")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)

            ForEach(Array(suggestedTags.prefix(6).enumerated()), id: \.element) { idx, tag in
                Button(action: {
                    addTag(t, tag)
                }) {
                    HStack(spacing: 4) {
                        Text("#\(tag)")
                            .font(.system(size: 11))
                            .foregroundColor(.primary)
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(highlightedCandidateIndex == idx ? Color.primary.opacity(0.08) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .frame(width: 130)
        .background(cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(borderColor, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.1), radius: 6, x: 0, y: 3)
        .zIndex(100)
    }

    private func submitNewTag(_ t: Task) {
        let clean = newTagInput.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        guard !clean.isEmpty else {
            cancelAddTag()
            return
        }
        addTag(t, clean)
    }

    private func addTag(_ t: Task, _ tagName: String) {
        let clean = tagName.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        guard !clean.isEmpty else { return }
        var updated = t
        if !updated.tags.contains(where: { $0.lowercased() == clean.lowercased() }) {
            updated.tags.append(clean)
            try? state.vault?.updateTask(updated)
            state.objectWillChange.send()
        }
        cancelAddTag()
    }

    private func cancelAddTag() {
        isAddingTag = false
        newTagInput = ""
        highlightedCandidateIndex = nil
        isTagInputFocused = false
    }

    // MARK: - Description Section

    private func descriptionSection(_ t: Task) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("描述")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)

                Spacer()

                if !isEditingDesc && !t.description.isEmpty {
                    Button(action: {
                        descDraft = t.description
                        isEditingDesc = true
                    }) {
                        Image(systemName: "pencil")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .padding(4)
                    }
                    .buttonStyle(.plain)
                    .help("编辑描述")
                }
            }

            if isEditingDesc {
                VStack(alignment: .leading, spacing: 8) {
                    TextEditor(text: $descDraft)
                        .font(.system(size: 13))
                        .frame(minHeight: 68, maxHeight: 180)
                        .scrollContentBackground(.hidden)
                        .padding(6)
                        .background(Color.primary.opacity(0.02))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(borderColor, lineWidth: 1)
                        )

                    HStack(spacing: 8) {
                        Spacer()

                        Button("取消") {
                            isEditingDesc = false
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)

                        Button(action: { saveDescription(t) }) {
                            Text("保存")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(RoundedRectangle(cornerRadius: 5).fill(Color.emeraldColor))
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut(.return, modifiers: .command)
                    }
                }
            } else {
                if t.description.isEmpty {
                    Button(action: {
                        descDraft = ""
                        isEditingDesc = true
                    }) {
                        Text("添加描述...")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary.opacity(0.6))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(t.description)
                        .font(.system(size: 13))
                        .foregroundColor(.primary)
                        .lineSpacing(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            descDraft = t.description
                            isEditingDesc = true
                        }
                }
            }
        }
    }

    private func saveDescription(_ t: Task) {
        var updated = t
        updated.description = descDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        try? state.vault?.updateTask(updated)
        isEditingDesc = false
        state.objectWillChange.send()
    }

    // MARK: - Activities & Status Events Section

    private struct TaskTimelineItem: Identifiable {
        let id: String
        let at: Date
        let isSystemEvent: Bool
        let author: String
        let icon: String
        let text: String
    }

    private func timelineEntries(for t: Task) -> [TaskTimelineItem] {
        var items: [TaskTimelineItem] = []

        // 1. Creation event
        items.append(TaskTimelineItem(
            id: "created-\(t.id)",
            at: t.createdAt,
            isSystemEvent: true,
            author: t.createdBy == "agent" ? "由 Agent 创建" : "由我创建",
            icon: t.createdBy == "agent" ? "cpu" : "person.fill",
            text: ""
        ))

        // 2. Status events (completed, reopened)
        var events = t.statusEvents
        if t.status == .done, let comp = t.completedAt, !events.contains(where: { $0.action == .completed && $0.at == comp }) {
            events.append(StatusEvent(action: .completed, at: comp))
        }

        for (idx, ev) in events.enumerated() {
            let isComp = ev.action == .completed
            let authorStr: String
            if isComp {
                authorStr = ev.by == "agent" ? "由 Agent 完成" : "由我完成"
            } else {
                authorStr = ev.by == "agent" ? "由 Agent 重新打开" : "由我重新打开"
            }
            items.append(TaskTimelineItem(
                id: "status-\(t.id)-\(idx)-\(ev.at.timeIntervalSince1970)",
                at: ev.at,
                isSystemEvent: true,
                author: authorStr,
                icon: ev.by == "agent" ? "cpu" : "person.fill",
                text: ""
            ))
        }

        // 3. User activities
        for act in t.activities {
            items.append(TaskTimelineItem(
                id: act.id,
                at: act.at,
                isSystemEvent: false,
                author: act.by == "agent" ? "Agent" : "我",
                icon: act.by == "agent" ? "cpu" : "person.fill",
                text: act.body
            ))
        }

        return items.sorted { a, b in
            if a.at != b.at {
                return a.at < b.at
            }
            return a.id < b.id
        }
    }

    private func activitiesSection(_ t: Task) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("活动")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)

            let entries = timelineEntries(for: t)
            if entries.isEmpty {
                Text("暂无活动记录")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
            } else {
                ForEach(entries) { entry in
                    timelineRow(entry)
                }
            }
        }
    }

    private func timelineRow(_ item: TaskTimelineItem) -> some View {
        Group {
            if item.isSystemEvent {
                HStack(spacing: 6) {
                    Text(formatTime(item.at))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                    Image(systemName: item.icon)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                    Text(item.author)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.vertical, 2)
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(formatTime(item.at))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                        Image(systemName: item.icon)
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                        Text(item.author)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Spacer()
                    }

                    Text(item.text)
                        .font(.system(size: 13))
                        .foregroundColor(.primary)
                        .lineSpacing(3)
                        .textSelection(.enabled)
                        .padding(.top, 1)
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - Actions & Helpers

    private func formatTime(_ d: Date) -> String {
        let calendar = Calendar.current
        let f = DateFormatter()
        if calendar.isDateInToday(d) {
            f.dateFormat = "HH:mm"
        } else {
            f.dateFormat = "MM-dd HH:mm"
        }
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

    private func removeFromTodayPlan() {
        guard let v = state.vault else { return }
        var plan = v.getDayPlan(date: state.todayDateString)
        plan.taskIds.removeAll { $0 == taskId }
        try? v.updateDayPlan(plan)
        state.objectWillChange.send()
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

// MARK: - IME Composition Tracker

@MainActor
final class IMECompositionTracker {
    static let shared = IMECompositionTracker()
    private var lastIMEReturnTime: Date = .distantPast

    private init() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 36 { // Return key
                if let client = NSApp.keyWindow?.firstResponder as? NSTextInputClient, client.hasMarkedText() {
                    self?.lastIMEReturnTime = Date()
                }
            }
            return event
        }
    }

    func isComposingOrJustCommitted() -> Bool {
        if let client = NSApp.keyWindow?.firstResponder as? NSTextInputClient, client.hasMarkedText() {
            return true
        }
        return Date().timeIntervalSince(lastIMEReturnTime) < 0.25
    }
}
