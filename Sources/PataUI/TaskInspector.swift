import SwiftUI
import AppKit
import PataCore

public struct TaskInspector: View {
    @ObservedObject var state: AppState
    let taskId: String

    @State private var newActivityText: String = ""
    @State private var showDuePopover: Bool = false
    @State private var showDeleteConfirm: Bool = false
    @State private var copiedForAgent: Bool = false
    @State private var newTagInput: String = ""
    @State private var isAddingTag: Bool = false

    public init(state: AppState, taskId: String) {
        self.state = state
        self.taskId = taskId
    }

    private var task: Task? {
        state.vault?.index.getTask(taskId)
    }

    private var isTaskInTodayPlan: Bool {
        guard let v = state.vault else { return false }
        let plan = v.getDayPlan(date: state.todayDateString)
        return plan.taskIds.contains(taskId)
    }

    public var body: some View {
        VStack(spacing: 0) {
            if let t = task {
                // Top Navigation Bar
                topHeaderBar(t)

                Divider()

                // Scrollable Content
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Title
                        titleView(t)

                        // Properties: Status, Due Date, Tags
                        propertiesView(t)

                        // Description
                        descriptionView(t)

                        Divider()

                        // Activity Timeline
                        activitiesSection(t)
                    }
                    .padding(20)
                }

                Divider()

                // Bottom Composer
                VStack(spacing: 8) {
                    ActivityComposer(text: $newActivityText, placeholder: "添加活动或评论... (⌘+Enter 发送)") {
                        submitActivity(t)
                    }
                }
                .padding(12)
                .background(Color(nsColor: .windowBackgroundColor))
            } else {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "checkmark.seal")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text("任务已删除或不存在")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 320, maxWidth: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .alert("确认删除任务？", isPresented: $showDeleteConfirm) {
            Button("删除", role: .destructive) {
                deleteTask()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除后无法恢复，确定要永久删除该任务吗？")
        }
    }

    // MARK: - Top Header Bar

    private func topHeaderBar(_ t: Task) -> some View {
        HStack(spacing: 10) {
            Button(action: { state.closeTaskInspector() }) {
                Image(systemName: "arrow.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(4)
            }
            .buttonStyle(.plain)
            .help("关闭详情")

            Spacer()

            if copiedForAgent {
                Text("已复制")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Menu {
                Button(action: copyForAgent) {
                    Label("复制给 Agent", systemImage: "doc.on.doc")
                }

                if isTaskInTodayPlan {
                    Button(action: removeFromTodayPlan) {
                        Label("移出今日计划", systemImage: "calendar.badge.minus")
                    }
                }

                Divider()

                Button(role: .destructive, action: { showDeleteConfirm = true }) {
                    Label("删除任务", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 20, height: 20)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 24)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Title

    private func titleView(_ t: Task) -> some View {
        TextField("任务标题...", text: Binding(
            get: { t.title },
            set: { updateTitle(t, $0) }
        ))
        .font(.system(size: 18, weight: .bold))
        .textFieldStyle(.plain)
    }

    // MARK: - Properties

    private func propertiesView(_ t: Task) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                // Status Toggle Button
                Button(action: { toggleStatus(t) }) {
                    HStack(spacing: 6) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(t.status == .done ? Color.green : Color.secondary.opacity(0.6), lineWidth: 1.2)
                                .frame(width: 14, height: 14)

                            if t.status == .done {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.green)
                                    .frame(width: 10, height: 10)
                            }
                        }

                        Text(t.status == .done ? "已完成" : "待办")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(t.status == .done ? .green : .primary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(t.status == .done ? Color.green.opacity(0.12) : Color.secondary.opacity(0.1))
                    )
                }
                .buttonStyle(.plain)

                // Due Date Button & Popover
                Button(action: { showDuePopover.toggle() }) {
                    HStack(spacing: 5) {
                        Image(systemName: "calendar")
                            .font(.system(size: 12))
                        Text(formatDueDisplay(t.due))
                            .font(.system(size: 12))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.1)))
                    .foregroundColor(t.due != nil ? (isOverdue(t.due!) ? .red : .primary) : .secondary)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showDuePopover) {
                    duePickerPopover(t)
                }
            }

            // Tags Editor
            HStack(spacing: 6) {
                Image(systemName: "tag")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                ForEach(t.tags, id: \.self) { tag in
                    HStack(spacing: 3) {
                        Text("#\(tag)")
                            .font(.system(size: 11))
                        Button(action: { removeTag(t, tag) }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 9))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.12)))
                    .foregroundColor(.secondary)
                }

                if isAddingTag {
                    TextField("标签名", text: $newTagInput)
                        .font(.system(size: 11))
                        .textFieldStyle(.plain)
                        .frame(width: 70)
                        .onSubmit {
                            addTag(t)
                        }
                } else {
                    Button(action: { isAddingTag = true }) {
                        Text("+ 标签")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Due Picker Popover

    private func duePickerPopover(_ t: Task) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button("今天") {
                setDueDate(t, dateOffset: 0)
            }
            .buttonStyle(.plain)
            .padding(.vertical, 2)

            Button("明天") {
                setDueDate(t, dateOffset: 1)
            }
            .buttonStyle(.plain)
            .padding(.vertical, 2)

            Button("下周一") {
                setDueNextMonday(t)
            }
            .buttonStyle(.plain)
            .padding(.vertical, 2)

            Divider()

            if t.due != nil {
                Button("清除截止日期") {
                    var updated = t
                    updated.due = nil
                    try? state.vault?.updateTask(updated)
                    showDuePopover = false
                }
                .buttonStyle(.plain)
                .foregroundColor(.red)
                .padding(.vertical, 2)
            }
        }
        .font(.system(size: 12))
        .padding(12)
        .frame(width: 140)
    }

    // MARK: - Description

    private func descriptionView(_ t: Task) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("描述")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)

            TextEditor(text: Binding(
                get: { t.description },
                set: { updateDescription(t, $0) }
            ))
            .font(.system(size: 13))
            .frame(minHeight: 64)
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor), lineWidth: 0.8))
        }
    }

    // MARK: - Activities

    private func activitiesSection(_ t: Task) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("活动记录 (\(t.activities.count))")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)

            let sortedActs = t.activities.sorted { $0.at < $1.at }
            if sortedActs.isEmpty {
                Text("尚无活动记录")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
            } else {
                ForEach(sortedActs) { act in
                    ActivityItemView(
                        activity: act,
                        onSaveEdit: { newBody in
                            try? state.vault?.updateActivity(id: act.id, body: newBody)
                        },
                        onDelete: {
                            try? state.vault?.deleteActivity(id: act.id)
                        }
                    )
                }
            }
        }
    }

    // MARK: - Helpers & Actions

    private func formatDueDisplay(_ due: String?) -> String {
        guard let due = due, !due.isEmpty else { return "添加截止日期" }
        let today = state.todayDateString
        if due == today { return "今天截止" }
        if due < today { return "\(due) (已逾期)" }
        return "\(due) 截止"
    }

    private func isOverdue(_ due: String) -> Bool {
        due < state.todayDateString
    }

    private func setDueDate(_ t: Task, dateOffset: Int) {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        if let d = Calendar.current.date(byAdding: .day, value: dateOffset, to: Date()) {
            var updated = t
            updated.due = f.string(from: d)
            try? state.vault?.updateTask(updated)
        }
        showDuePopover = false
    }

    private func setDueNextMonday(_ t: Task) {
        let calendar = Calendar.current
        var comps = DateComponents()
        comps.weekday = 2 // Monday
        if let nextMon = calendar.nextDate(after: Date(), matching: comps, matchingPolicy: .nextTime) {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            var updated = t
            updated.due = f.string(from: nextMon)
            try? state.vault?.updateTask(updated)
        }
        showDuePopover = false
    }

    private func toggleStatus(_ task: Task) {
        let newStatus: TaskStatus = task.status == .done ? .todo : .done
        try? state.vault?.setTaskStatus(id: task.id, status: newStatus)
    }

    private func updateTitle(_ task: Task, _ newTitle: String) {
        var t = task
        t.title = newTitle
        try? state.vault?.updateTask(t)
    }

    private func updateDescription(_ task: Task, _ desc: String) {
        var t = task
        t.description = desc
        try? state.vault?.updateTask(t)
    }

    private func removeTag(_ task: Task, _ tagToRemove: String) {
        var t = task
        t.tags.removeAll { $0.lowercased() == tagToRemove.lowercased() }
        try? state.vault?.updateTask(t)
    }

    private func addTag(_ task: Task) {
        let clean = newTagInput.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        guard !clean.isEmpty else {
            isAddingTag = false
            return
        }
        var t = task
        if !t.tags.contains(where: { $0.lowercased() == clean.lowercased() }) {
            t.tags.append(clean)
            try? state.vault?.updateTask(t)
        }
        newTagInput = ""
        isAddingTag = false
    }

    private func submitActivity(_ task: Task) {
        let text = newActivityText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let v = state.vault else { return }

        _ = try? v.createActivity(taskId: task.id, body: text)
        newActivityText = ""
    }

    private func copyForAgent() {
        let prompt = "处理这个 Pata 任务：pata://task/\(taskId)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prompt, forType: .string)
        copiedForAgent = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copiedForAgent = false
        }
    }

    private func removeFromTodayPlan() {
        guard let v = state.vault else { return }
        var plan = v.getDayPlan(date: state.todayDateString)
        plan.taskIds.removeAll { $0 == taskId }
        try? v.updateDayPlan(plan)
    }

    private func deleteTask() {
        try? state.vault?.deleteTask(id: taskId)
        state.closeTaskInspector()
    }
}
