import SwiftUI
import PataCore

public struct TodayView: View {
    @ObservedObject var state: AppState
    @State private var quickCreateText: String = ""
    @State private var quickActivityText: String = ""
    @State private var isCreatingActivity: Bool = false

    public init(state: AppState) {
        self.state = state
    }

    private var todayStr: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    private var isToday: Bool {
        state.todayDateString == todayStr
    }

    private var planWord: String {
        isToday ? "今日" : "当日"
    }

    private var dayPlan: DayPlan {
        state.vault?.getDayPlan(date: state.todayDateString) ?? DayPlan(date: state.todayDateString)
    }

    private var planTasks: [Task] {
        guard let v = state.vault else { return [] }
        return dayPlan.taskIds.compactMap { v.index.getTask($0) }
    }

    private var completedPlanTasksCount: Int {
        planTasks.filter { $0.status == .done }.count
    }

    private var displayDateString: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: state.todayDateString) else { return state.todayDateString }
        let calendar = Calendar.current
        let month = calendar.component(.month, from: d)
        let day = calendar.component(.day, from: d)
        let weekdayIdx = calendar.component(.weekday, from: d)
        let weekdays = ["日", "一", "二", "三", "四", "五", "六"]
        let weekdayStr = weekdays[(weekdayIdx - 1) % 7]
        return "\(month) 月 \(day) 日 · 星期\(weekdayStr)"
    }

    private struct TimelineItem: Identifiable {
        let id: String
        let time: String
        let at: Date
        let author: String
        let taskTitle: String?
        let taskId: String?
        let text: String
        let tags: [String]
    }

    private var timelineItems: [TimelineItem] {
        guard let v = state.vault else { return [] }
        var rows: [TimelineItem] = []
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let tf = DateFormatter()
        tf.dateFormat = "HH:mm"

        // 1. DayPlan standalone activities
        for act in dayPlan.activities {
            let tStr = tf.string(from: act.at)
            rows.append(TimelineItem(
                id: act.id,
                time: tStr,
                at: act.at,
                author: "我",
                taskTitle: nil,
                taskId: nil,
                text: act.body,
                tags: act.tags
            ))
        }

        // 2. Tasks
        for t in v.index.listTasks() {
            // Activities on task
            for act in t.activities {
                if df.string(from: act.at) == state.todayDateString {
                    let isCompletion = act.body.hasPrefix("完成任务：")
                    rows.append(TimelineItem(
                        id: act.id,
                        time: tf.string(from: act.at),
                        at: act.at,
                        author: isCompletion ? "我" : "我",
                        taskTitle: t.title,
                        taskId: t.id,
                        text: act.body,
                        tags: act.tags
                    ))
                }
            }

            // Task completion event if not recorded
            for ev in t.statusEvents {
                if df.string(from: ev.at) == state.todayDateString && ev.action == .completed {
                    let evId = "ev-\(t.id)-\(ev.at.timeIntervalSince1970)"
                    rows.append(TimelineItem(
                        id: evId,
                        time: tf.string(from: ev.at),
                        at: ev.at,
                        author: "由我完成",
                        taskTitle: t.title,
                        taskId: t.id,
                        text: "",
                        tags: []
                    ))
                }
            }

            // Creation event
            if df.string(from: t.createdAt) == state.todayDateString {
                rows.append(TimelineItem(
                    id: "created-\(t.id)",
                    time: tf.string(from: t.createdAt),
                    at: t.createdAt,
                    author: "由我创建",
                    taskTitle: t.title,
                    taskId: t.id,
                    text: "",
                    tags: []
                ))
            }
        }

        return rows.sorted { $0.at > $1.at }
    }

    private var borderColor: Color {
        switch state.themePreference {
        case "dark": return Color(red: 41/255, green: 37/255, blue: 36/255)
        default: return Color(red: 231/255, green: 229/255, blue: 228/255)
        }
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Top Date Bar
                dateBar

                // Section: Plan
                planSection

                // Thin separator
                Rectangle()
                    .fill(borderColor)
                    .frame(height: 1)
                    .padding(.vertical, 4)

                // Section: Activity Timeline
                activitySection
            }
            .padding(.horizontal, 48)
            .padding(.top, 24)
            .padding(.bottom, 64)
            .frame(maxWidth: 860)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Date Bar

    private var dateBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 0) {
                Button(action: {
                    shiftDay(-1)
                }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 26, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button(action: {
                    shiftDay(1)
                }) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 26, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Text(displayDateString)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.primary)

            Spacer()

            if !isToday {
                Button(action: {
                    state.todayDateString = todayStr
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 11))
                        Text("回到今天")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.04)))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(borderColor, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func shiftDay(_ delta: Int) {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        if let d = f.date(from: state.todayDateString),
           let next = Calendar.current.date(byAdding: .day, value: delta, to: d) {
            state.todayDateString = f.string(from: next)
        }
    }

    // MARK: - Plan Section

    private var planSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(planWord)计划")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)

                Text("\(completedPlanTasksCount) / \(dayPlan.taskIds.count)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            // Quick Create Input
            HStack(spacing: 0) {
                TextField("添加任务或搜索...", text: $quickCreateText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .padding(.horizontal, 12)
                    .onSubmit {
                        submitQuickCreate()
                    }

                Button(action: submitQuickCreate) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .bold))
                        Text("添加")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(red: 168/255, green: 184/255, blue: 174/255)))
                }
                .buttonStyle(.plain)
                .padding(.trailing, 6)
            }
            .frame(height: 36)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.02)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(borderColor, lineWidth: 1))

            Text("仅安排今天推进的任务，不改变任务的截止日期。")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .padding(.bottom, 2)

            // Task List
            if !planTasks.isEmpty {
                VStack(spacing: 0) {
                    ForEach(planTasks) { task in
                        planTaskRow(task)
                        if task.id != planTasks.last?.id {
                            Rectangle()
                                .fill(borderColor)
                                .frame(height: 1)
                        }
                    }
                }
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.02)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(borderColor, lineWidth: 1))
            }
        }
    }

    private func planTaskRow(_ task: Task) -> some View {
        let isDone = task.status == .done
        let isOverdue = isTaskOverdue(task)

        return HStack(spacing: 10) {
            Button(action: { toggleStatus(task) }) {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundColor(isDone ? Color.emeraldColor : Color.secondary.opacity(0.5))
            }
            .buttonStyle(.plain)

            Text(task.title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(isDone ? .secondary : .primary)
                .strikethrough(isDone, color: .secondary)

            if let due = task.due {
                if isOverdue {
                    Text("逾期 \(due)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(red: 220/255, green: 38/255, blue: 38/255))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color(red: 254/255, green: 226/255, blue: 226/255)))
                } else {
                    Text("due \(due)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }

            ForEach(task.tags, id: \.self) { tag in
                Text("#\(tag)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            state.openTaskInspector(taskId: task.id)
        }
    }

    private func isTaskOverdue(_ task: Task) -> Bool {
        guard let due = task.due, task.status != .done else { return false }
        return due < state.todayDateString
    }

    private func toggleStatus(_ task: Task) {
        let next: TaskStatus = task.status == .done ? .todo : .done
        try? state.vault?.setTaskStatus(id: task.id, status: next)
        state.objectWillChange.send()
    }

    private func submitQuickCreate() {
        let clean = quickCreateText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, let v = state.vault else { return }

        // Create task and add to day plan
        do {
            let t = try v.createTask(title: clean, status: .todo, tags: [])
            var plan = v.getDayPlan(date: state.todayDateString)
            if !plan.taskIds.contains(t.id) {
                plan.taskIds.append(t.id)
                try? v.updateDayPlan(plan)
            }
            quickCreateText = ""
            state.objectWillChange.send()
        } catch {
            print("Create task failed:", error)
        }
    }

    // MARK: - Activity Timeline Section

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(planWord)记录")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)

                Text("\(timelineItems.count)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            // Activity Composer Box
            VStack(alignment: .trailing, spacing: 8) {
                TextEditor(text: $quickActivityText)
                    .font(.system(size: 13))
                    .frame(height: 72)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .overlay(
                        Group {
                            if quickActivityText.isEmpty {
                                Text("记录进展...")
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary.opacity(0.6))
                                    .padding(.leading, 12)
                                    .padding(.top, 14)
                                    .allowsHitTesting(false)
                            }
                        },
                        alignment: .topLeading
                    )

                Button(action: submitActivity) {
                    HStack(spacing: 5) {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 10))
                        Text("发送 ⌘↵")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(red: 154/255, green: 178/255, blue: 167/255)))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: .command)
                .padding(.trailing, 10)
                .padding(.bottom, 8)
            }
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.02)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(borderColor, lineWidth: 1))

            Text("记录将记入 \(state.todayDateString) 的日计划")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            // Timeline Items
            if timelineItems.isEmpty {
                Text("该日期暂无记录。")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(timelineItems.enumerated()), id: \.element.id) { idx, item in
                        timelineRow(item)
                        if idx < timelineItems.count - 1 {
                            Rectangle()
                                .fill(borderColor.opacity(0.6))
                                .frame(height: 1)
                                .padding(.vertical, 8)
                        }
                    }
                }
            }
        }
    }

    private func timelineRow(_ item: TimelineItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(item.time)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)

                Image(systemName: "person.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)

                Text(item.author)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                if let taskTitle = item.taskTitle {
                    Text(taskTitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(red: 71/255, green: 110/255, blue: 88/255))
                }

                Spacer()
            }

            if !item.text.isEmpty {
                Text(item.text)
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                    .lineSpacing(3)
                    .padding(.top, 2)
            }

            if !item.tags.isEmpty {
                HStack(spacing: 6) {
                    ForEach(item.tags, id: \.self) { t in
                        Text("#\(t)")
                            .font(.system(size: 11))
                            .foregroundColor(Color(red: 71/255, green: 110/255, blue: 88/255))
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
    }

    private func submitActivity() {
        let clean = quickActivityText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, let v = state.vault else { return }

        do {
            _ = try v.createActivity(date: state.todayDateString, body: clean)
            quickActivityText = ""
            state.objectWillChange.send()
        } catch {
            print("Create activity failed:", error)
        }
    }
}

public struct TodayToolbarDateBar: View {
    @ObservedObject var state: AppState

    public init(state: AppState) {
        self.state = state
    }

    private var todayStr: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    private var isToday: Bool {
        state.todayDateString == todayStr
    }

    private var displayDateString: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: state.todayDateString) else { return state.todayDateString }
        let calendar = Calendar.current
        let month = calendar.component(.month, from: d)
        let day = calendar.component(.day, from: d)
        let weekdayIdx = calendar.component(.weekday, from: d)
        let weekdays = ["日", "一", "二", "三", "四", "五", "六"]
        let weekdayStr = weekdays[(weekdayIdx - 1) % 7]
        return "\(month) 月 \(day) 日 · 星期\(weekdayStr)"
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 8) {
            HStack(spacing: 2) {
                Button(action: { shiftDay(-1) }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button(action: { shiftDay(1) }) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Text(displayDateString)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)

            if !isToday {
                Button(action: {
                    state.todayDateString = todayStr
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 9))
                        Text("回到今天")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.04)))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(nsColor: .separatorColor), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func shiftDay(_ delta: Int) {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        if let d = f.date(from: state.todayDateString),
           let next = Calendar.current.date(byAdding: .day, value: delta, to: d) {
            state.todayDateString = f.string(from: next)
        }
    }
}
