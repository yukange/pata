import SwiftUI
import AppKit
import PataCore

public struct TaskInspector: View {
    @ObservedObject var state: AppState
    let taskId: String

    @State private var newActivityBody: String = ""
    @State private var showDeleteConfirm: Bool = false

    // In-place title editing & auto-save
    @State private var titleDraft: String = ""
    @State private var isTitleFocused: Bool = false
    @State private var titleAutoSaveWorkItem: DispatchWorkItem? = nil
    @State private var titleSaveError: String? = nil

    // In-place description editing & auto-save
    @State private var descDraft: String = ""
    @State private var isDescFocused: Bool = false
    @State private var descAutoSaveWorkItem: DispatchWorkItem? = nil
    @State private var descSaveError: String? = nil
    @State private var currentEditingTaskId: String = ""

    // In-place tag editing
    @State private var isAddingTag: Bool = false
    @State private var newTagInput: String = ""
    @FocusState private var isTagInputFocused: Bool
    @State private var highlightedCandidateIndex: Int? = nil

    // Activity editing & hover states
    @State private var editingActivityId: String? = nil
    @State private var editingActivityDraft: String = ""
    @State private var hoveredActivityId: String? = nil

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
                    VStack(alignment: .leading, spacing: 14) {
                        // Title & Status (Unified Row)
                        titleAndStatusRow(t)

                        if let err = titleSaveError {
                            Text(err)
                                .font(.system(size: 10))
                                .foregroundColor(.red)
                                .lineLimit(1)
                                .help(err)
                        }

                        // Tags & Due Row
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
                ActivityComposerBox(
                    text: $newActivityBody,
                    placeholder: "记录进展...",
                    fontSize: 12,
                    inputHeight: 52,
                    state: state,
                    onSubmit: { body in submitActivity(body) }
                )
                .padding(12)
            }
            .onAppear {
                currentEditingTaskId = taskId
                titleDraft = task?.title ?? ""
                descDraft = task?.description ?? ""
            }
            .onChange(of: taskId) {
                flushTitleAutoSave()
                flushDescriptionAutoSave()
                currentEditingTaskId = taskId
                titleDraft = task?.title ?? ""
                descDraft = task?.description ?? ""
                titleSaveError = nil
                descSaveError = nil
                cancelAddTag()
            }
            .onChange(of: task?.title) {
                if !isTitleFocused && titleAutoSaveWorkItem == nil {
                    if let newTitle = task?.title, newTitle != titleDraft {
                        titleDraft = newTitle
                    }
                }
            }
            .onChange(of: task?.description) {
                if !isDescFocused && descAutoSaveWorkItem == nil {
                    if let d = task?.description, d != descDraft {
                        descDraft = d
                    }
                }
            }
            .onDisappear {
                flushTitleAutoSave()
                flushDescriptionAutoSave()
            }
            .alert("确认删除任务？", isPresented: $showDeleteConfirm) {
                Button("删除", role: .destructive) {
                    if let t = task {
                        deleteTask(t)
                    }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("删除后无法恢复，确定要永久删除该任务吗？")
            }
        }
    }

    // MARK: - Header Bar

    private func inspectorHeader(_ t: Task) -> some View {
        HStack {
            Button(action: { state.closeTaskInspector() }) {
                Image(systemName: "arrow.right")
                    .font(.system(size: 13, weight: .medium))
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
                    Button("移出今日") {
                        removeFromTodayPlan()
                    }
                }

                Divider()

                Button("删除", role: .destructive) {
                    showDeleteConfirm = true
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .padding(8)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .frame(height: 44)
        .padding(.horizontal, 8)
    }

    // MARK: - Tags Row (In-place TextField + @FocusState + Lightweight Suggestions)

    private func tagsRow(_ t: Task) -> some View {
        HStack(spacing: 6) {
            if let due = t.due {
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.system(size: 10))
                    Text(isOverdue ? "\(due) (已逾期)" : "\(due) 截止")
                        .font(.system(size: 11, weight: isOverdue ? .medium : .regular))
                }
                .foregroundColor(isOverdue ? Color(red: 220/255, green: 38/255, blue: 38/255) : .secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4).fill(isOverdue ? Color.red.opacity(0.08) : Color.primary.opacity(0.04)))
            }

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
                .foregroundColor(.accentColor)
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

    // MARK: - Title & Status Row

    private func titleAndStatusRow(_ t: Task) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: { toggleStatus(t) }) {
                Image(systemName: t.status == .done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundColor(t.status == .done ? (state.customAccentColor ?? Color.emeraldColor) : .secondary)
                    .contentShape(Rectangle())
                    .padding(.top, 4)
            }
            .buttonStyle(.plain)
            .help(t.status == .done ? "重新打开" : "标记完成")

            InPlaceTitleEditor(
                text: $titleDraft,
                placeholder: "任务标题",
                isDone: t.status == .done,
                isFocused: $isTitleFocused,
                onTextChange: { newText in
                    scheduleTitleAutoSave(newText)
                },
                onCommit: {
                    flushTitleAutoSave()
                }
            )
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isTitleFocused ? Color.primary.opacity(0.02) : Color.clear)
            )
        }
    }

    private func scheduleTitleAutoSave(_ newText: String) {
        titleAutoSaveWorkItem?.cancel()
        let clean = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        let targetTaskId = currentEditingTaskId.isEmpty ? taskId : currentEditingTaskId
        let item = DispatchWorkItem { [weak state] in
            guard let s = state, let v = s.vault else { return }
            guard let t = v.index.getTask(targetTaskId) else { return }
            if t.title != clean {
                var updated = t
                updated.title = clean
                do {
                    _ = try v.updateTask(updated)
                    DispatchQueue.main.async {
                        self.titleSaveError = nil
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.titleSaveError = "标题保存失败: \(error.localizedDescription)"
                    }
                }
            }
        }
        titleAutoSaveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: item)
    }

    private func flushTitleAutoSave() {
        titleAutoSaveWorkItem?.cancel()
        titleAutoSaveWorkItem = nil
        let targetTaskId = currentEditingTaskId.isEmpty ? taskId : currentEditingTaskId
        guard let v = state.vault, let t = v.index.getTask(targetTaskId) else { return }
        let clean = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty {
            titleDraft = t.title
            return
        }
        if t.title != clean {
            var updated = t
            updated.title = clean
            do {
                _ = try v.updateTask(updated)
                titleSaveError = nil
            } catch {
                titleSaveError = "标题保存失败: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Description Section

    private func descriptionSection(_ t: Task) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("描述")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)

                Spacer()

                if let err = descSaveError {
                    Text(err)
                        .font(.system(size: 10))
                        .foregroundColor(.red)
                        .lineLimit(1)
                        .help(err)
                }
            }

            InPlaceDescriptionEditor(
                text: $descDraft,
                placeholder: "添加描述...",
                isFocused: $isDescFocused,
                minHeight: 22,
                maxHeight: 180,
                onTextChange: { newText in
                    scheduleDescriptionAutoSave(newText)
                },
                onCommit: {
                    flushDescriptionAutoSave()
                }
            )
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isDescFocused ? Color.primary.opacity(0.02) : Color.clear)
            )
        }
    }

    private func scheduleDescriptionAutoSave(_ newText: String) {
        descAutoSaveWorkItem?.cancel()
        let targetTaskId = currentEditingTaskId.isEmpty ? taskId : currentEditingTaskId
        let item = DispatchWorkItem { [weak state] in
            guard let s = state, let v = s.vault else { return }
            guard let t = v.index.getTask(targetTaskId) else { return }
            if t.description != newText {
                var updated = t
                updated.description = newText
                do {
                    _ = try v.updateTask(updated)
                    DispatchQueue.main.async {
                        self.descSaveError = nil
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.descSaveError = "保存失败: \(error.localizedDescription)"
                    }
                }
            }
        }
        descAutoSaveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: item)
    }

    private func flushDescriptionAutoSave() {
        descAutoSaveWorkItem?.cancel()
        descAutoSaveWorkItem = nil
        let targetTaskId = currentEditingTaskId.isEmpty ? taskId : currentEditingTaskId
        guard let v = state.vault, let t = v.index.getTask(targetTaskId) else { return }
        if t.description != descDraft {
            var updated = t
            updated.description = descDraft
            do {
                _ = try v.updateTask(updated)
                descSaveError = nil
            } catch {
                descSaveError = "保存失败: \(error.localizedDescription)"
            }
        }
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
                VStack(alignment: .leading, spacing: 4) {
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

                        if editingActivityId != item.id {
                            HStack(spacing: 6) {
                                Button(action: {
                                    editingActivityDraft = item.text
                                    editingActivityId = item.id
                                }) {
                                    Image(systemName: "pencil")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help("编辑评论")

                                Button(action: {
                                    deleteActivity(id: item.id)
                                }) {
                                    Image(systemName: "trash")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help("删除评论")
                            }
                            .opacity(hoveredActivityId == item.id ? 1.0 : 0.0)
                        }
                    }

                    if editingActivityId == item.id {
                        VStack(alignment: .trailing, spacing: 6) {
                            TextEditor(text: $editingActivityDraft)
                                .font(.system(size: 12))
                                .frame(minHeight: 48, maxHeight: 120)
                                .scrollContentBackground(.hidden)
                                .padding(6)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.primary.opacity(0.03))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(borderColor, lineWidth: 1)
                                )

                            HStack(spacing: 8) {
                                Button("取消") {
                                    editingActivityId = nil
                                    editingActivityDraft = ""
                                }
                                .buttonStyle(.plain)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)

                                Button(action: {
                                    updateActivity(id: item.id, body: editingActivityDraft)
                                }) {
                                    Text("保存")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(state.effectiveAccentOnColor)
                                        .padding(.horizontal, 9)
                                        .padding(.vertical, 3)
                                        .background(RoundedRectangle(cornerRadius: 5).fill(state.effectiveAccentColor))
                                }
                                .buttonStyle(.plain)
                                .disabled(editingActivityDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        }
                        .padding(.top, 2)
                    } else {
                        ActivityTextView(text: item.text, state: state)
                            .padding(.top, 1)
                    }
                }
                .padding(.vertical, 3)
                .padding(.horizontal, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(hoveredActivityId == item.id ? Color.primary.opacity(0.02) : Color.clear)
                )
                .onHover { h in
                    hoveredActivityId = h ? item.id : nil
                }
                .contextMenu {
                    Button("编辑") {
                        editingActivityDraft = item.text
                        editingActivityId = item.id
                    }
                    Button("删除", role: .destructive) {
                        deleteActivity(id: item.id)
                    }
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
        flushTitleAutoSave()
        flushDescriptionAutoSave()
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

    private func submitActivity(_ bodyText: String? = nil) {
        let textToUse = bodyText ?? newActivityBody
        let clean = textToUse.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, let v = state.vault else { return }

        do {
            _ = try v.createActivity(taskId: taskId, date: state.todayDateString, body: clean)
            newActivityBody = ""
            state.objectWillChange.send()
        } catch {
            print("Failed to add activity:", error)
        }
    }

    private func updateActivity(id: String, body: String) {
        let clean = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, let v = state.vault else { return }
        do {
            _ = try v.updateActivity(id: id, body: clean)
            editingActivityId = nil
            editingActivityDraft = ""
            state.objectWillChange.send()
        } catch {
            print("Failed to update activity:", error)
        }
    }

    private func deleteActivity(id: String) {
        guard let v = state.vault else { return }
        do {
            try v.deleteActivity(id: id)
            if editingActivityId == id {
                editingActivityId = nil
                editingActivityDraft = ""
            }
            state.objectWillChange.send()
        } catch {
            print("Failed to delete activity:", error)
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
        titleAutoSaveWorkItem?.cancel()
        titleAutoSaveWorkItem = nil
        descAutoSaveWorkItem?.cancel()
        descAutoSaveWorkItem = nil
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
