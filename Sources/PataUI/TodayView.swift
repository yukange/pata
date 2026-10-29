import SwiftUI
import PataCore

public struct TodayView: View {
    @ObservedObject var state: AppState
    @State private var newActivityText: String = ""
    @State private var showTaskPicker: Bool = false

    public init(state: AppState) {
        self.state = state
    }

    private var dayPlan: DayPlan {
        state.vault?.getDayPlan(date: state.todayDateString) ?? DayPlan(date: state.todayDateString)
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

    private var completedPlanTasksCount: Int {
        guard let v = state.vault else { return 0 }
        return dayPlan.taskIds.compactMap { v.index.getTask($0) }.filter { $0.status == .done }.count
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 27) {
                // 1. Page Header (Eyebrow, Title Today / 今天, Subtitle, Tools)
                pageHeader

                // 2. Section: 今日计划
                todayPlanSection

                // Thin separator line
                Rectangle()
                    .fill(Color(red: 238/255, green: 240/255, blue: 235/255))
                    .frame(height: 1)
                    .padding(.vertical, 4)

                // 3. Section: 今日记录
                todayTimelineSection
            }
            .padding(.horizontal, 46)
            .padding(.top, 46)
            .padding(.bottom, 105)
            .frame(maxWidth: 840)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showTaskPicker) {
            TaskPickerSheet(state: state, isPresented: $showTaskPicker)
        }
    }

    // MARK: - Page Header

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("YOUR DAILY SPACE")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(Color(red: 147/255, green: 162/255, blue: 146/255))
                .tracking(1.2)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Today")
                    .font(.system(size: 29, weight: .bold))
                    .foregroundColor(Color(red: 36/255, green: 40/255, blue: 36/255))
                Text("/")
                    .font(.system(size: 29, weight: .regular))
                    .foregroundColor(Color(red: 202/255, green: 215/255, blue: 201/255))
                Text("今天")
                    .font(.system(size: 29, weight: .bold))
                    .foregroundColor(Color(red: 36/255, green: 40/255, blue: 36/255))

                Spacer()

                HStack(spacing: 8) {
                    Button(action: previousDay) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color(red: 89/255, green: 100/255, blue: 88/255))
                            .frame(width: 30, height: 30)
                            .background(RoundedRectangle(cornerRadius: 9).fill(Color.white))
                            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color(red: 229/255, green: 233/255, blue: 225/255), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help("前一天")

                    Button(action: nextDay) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color(red: 89/255, green: 100/255, blue: 88/255))
                            .frame(width: 30, height: 30)
                            .background(RoundedRectangle(cornerRadius: 9).fill(Color.white))
                            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color(red: 229/255, green: 233/255, blue: 225/255), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help("后一天")

                    Button(action: jumpToToday) {
                        Text("回到今天")
                            .font(.system(size: 12))
                            .foregroundColor(Color(red: 137/255, green: 145/255, blue: 136/255))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                }
            }

            Text("\(displayDateString) · 给重要的事留一点空间")
                .font(.system(size: 12))
                .foregroundColor(Color(red: 137/255, green: 145/255, blue: 136/255))
        }
        .padding(.bottom, 6)
    }

    // MARK: - 今日计划 Section

    private var todayPlanSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Heading Row
            HStack(alignment: .center) {
                HStack(spacing: 8) {
                    Text("今日计划")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(Color(red: 36/255, green: 40/255, blue: 36/255))

                    Text("\(completedPlanTasksCount) / \(dayPlan.taskIds.count)")
                        .font(.system(size: 11, design: .monospaced))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color(red: 240/255, green: 242/255, blue: 237/255)))
                        .foregroundColor(Color(red: 164/255, green: 170/255, blue: 162/255))
                }

                Spacer()

                Button(action: { showTaskPicker = true }) {
                    HStack(spacing: 5) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                        Text("添加任务")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 9).fill(Color.white))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color(red: 229/255, green: 233/255, blue: 225/255), lineWidth: 1))
                    .foregroundColor(Color(red: 89/255, green: 100/255, blue: 88/255))
                }
                .buttonStyle(.plain)
            }

            // Task List Unified Card
            if dayPlan.taskIds.isEmpty {
                HStack {
                    Spacer()
                    Text("还没有安排任务。今天可以从一件小事开始。")
                        .font(.system(size: 13))
                        .foregroundColor(Color(red: 161/255, green: 170/255, blue: 160/255))
                    Spacer()
                }
                .padding(.vertical, 36)
                .background(RoundedRectangle(cornerRadius: 13).fill(Color.white))
                .overlay(RoundedRectangle(cornerRadius: 13).stroke(Color(red: 232/255, green: 235/255, blue: 229/255), lineWidth: 1))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(dayPlan.taskIds.enumerated()), id: \.element) { index, tid in
                        if let task = state.vault?.index.getTask(tid) {
                            if index > 0 {
                                Rectangle()
                                    .fill(Color(red: 240/255, green: 241/255, blue: 237/255))
                                    .frame(height: 1)
                            }
                            taskRow(task: task, tid: tid)
                        }
                    }
                }
                .background(RoundedRectangle(cornerRadius: 13).fill(Color.white))
                .overlay(RoundedRectangle(cornerRadius: 13).stroke(Color(red: 232/255, green: 235/255, blue: 229/255), lineWidth: 1))
                .shadow(color: Color.black.opacity(0.03), radius: 10, x: 0, y: 4)
            }

            Text("仅安排今天要推进的任务，不改变任务的截止日期。")
                .font(.system(size: 11))
                .foregroundColor(Color(red: 154/255, green: 163/255, blue: 152/255))
                .padding(.top, 2)
        }
    }

    // MARK: - Task Row View

    @ViewBuilder
    private func taskRow(task: Task, tid: String) -> some View {
        let isDone = task.status == .done

        HStack(spacing: 14) {
            // Rounded Checkbox
            Button(action: { toggleTaskStatus(task) }) {
                ZStack {
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(isDone ? Color(red: 120/255, green: 163/255, blue: 137/255) : Color(red: 174/255, green: 189/255, blue: 175/255), lineWidth: 1.5)
                        .frame(width: 17, height: 17)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color.white))

                    if isDone {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color(red: 120/255, green: 163/255, blue: 137/255))
                            .frame(width: 17, height: 17)
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
            }
            .buttonStyle(.plain)
            .help(isDone ? "恢复为待办" : "标记为完成")

            // Title & Sub-line
            VStack(alignment: .leading, spacing: 3) {
                Button(action: { state.openTaskInspector(taskId: task.id) }) {
                    Text(task.title)
                        .font(.system(size: 13, weight: .medium))
                        .strikethrough(isDone)
                        .foregroundColor(isDone ? Color(red: 167/255, green: 173/255, blue: 165/255) : Color(red: 36/255, green: 40/255, blue: 36/255))
                        .lineLimit(1)
                }
                .buttonStyle(.plain)

                // Sub-line: tags + due date (MM/dd format)
                HStack(spacing: 4) {
                    if !task.tags.isEmpty {
                        Text(task.tags.map { "#\($0)" }.joined(separator: " · "))
                            .font(.system(size: 11))
                            .foregroundColor(Color(red: 130/255, green: 137/255, blue: 128/255))
                    }

                    if let due = task.due {
                        Text("· 截止 \(formatDueShort(due))")
                            .font(.system(size: 11))
                            .foregroundColor(Color(red: 130/255, green: 137/255, blue: 128/255))
                    }
                }
            }

            Spacer()

            // Priority Badge
            if let p = task.extra["priority"], !p.isEmpty {
                priorityPill(p)
            }

            // Ellipsis Menu
            Menu {
                Button(action: { state.openTaskInspector(taskId: task.id) }) {
                    Text("查看详情")
                }
                Button(role: .destructive, action: { removeTaskFromPlan(tid) }) {
                    Text("从今日移出")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12))
                    .foregroundColor(Color(red: 160/255, green: 168/255, blue: 160/255))
                    .frame(width: 24, height: 24)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 24)
        }
        .padding(.horizontal, 20)
        .frame(minHeight: 62)
    }

    private func priorityPill(_ p: String) -> some View {
        let (bg, fg): (Color, Color) = {
            switch p.uppercased() {
            case "P1":
                return (Color(red: 253/255, green: 240/255, blue: 238/255), Color(red: 217/255, green: 83/255, blue: 79/255))
            case "P2":
                return (Color(red: 254/255, green: 246/255, blue: 231/255), Color(red: 217/255, green: 155/255, blue: 38/255))
            case "P3":
                return (Color(red: 240/255, green: 242/255, blue: 237/255), Color(red: 130/255, green: 137/255, blue: 128/255))
            default:
                return (Color(red: 240/255, green: 242/255, blue: 237/255), Color(red: 130/255, green: 137/255, blue: 128/255))
            }
        }()

        return Text(p)
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(fg)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 5).fill(bg))
    }

    private func formatDueShort(_ due: String) -> String {
        let parts = due.split(separator: "-")
        if parts.count == 3 {
            return "\(parts[1])/\(parts[2])"
        }
        return due
    }

    // MARK: - 今日记录 Section

    private var todayTimelineSection: some View {
        let timelineItems = getTimelineItems()

        return VStack(alignment: .leading, spacing: 14) {
            // Heading Row
            HStack {
                HStack(spacing: 8) {
                    Text("今日记录")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(Color(red: 36/255, green: 40/255, blue: 36/255))

                    Text("\(timelineItems.count)")
                        .font(.system(size: 11, design: .monospaced))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color(red: 240/255, green: 242/255, blue: 237/255)))
                        .foregroundColor(Color(red: 164/255, green: 170/255, blue: 162/255))
                }

                Spacer()

                Text("自动聚合 · 无需写日报")
                    .font(.system(size: 11))
                    .foregroundColor(Color(red: 137/255, green: 145/255, blue: 136/255))
            }

            // Timeline Items Stream with left vertical line
            if timelineItems.isEmpty {
                Text("今天还没有记录。在下方随手写一条吧。")
                    .font(.system(size: 13))
                    .foregroundColor(Color(red: 161/255, green: 170/255, blue: 160/255))
                    .padding(.vertical, 12)
            } else {
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color(red: 229/255, green: 235/255, blue: 226/255))
                        .frame(width: 1)
                        .padding(.leading, 7)
                        .padding(.top, 4)
                        .padding(.bottom, 12)

                    VStack(alignment: .leading, spacing: 20) {
                        ForEach(timelineItems) { item in
                            timelineRow(item)
                        }
                    }
                }
            }

            // Bottom Compose Box
            VStack(alignment: .leading, spacing: 12) {
                TextEditor(text: $newActivityText)
                    .font(.system(size: 13))
                    .frame(minHeight: 68)
                    .scrollContentBackground(.hidden)
                    .overlay(
                        Group {
                            if newActivityText.isEmpty {
                                Text("随手记下工作进展、问题或想法…")
                                    .font(.system(size: 13))
                                    .foregroundColor(Color(red: 171/255, green: 180/255, blue: 170/255))
                                    .padding(.top, 4)
                                    .padding(.leading, 4)
                            }
                        },
                        alignment: .topLeading
                    )

                HStack {
                    Text("独立 Memo · 不需要标题或标签")
                        .font(.system(size: 11))
                        .foregroundColor(Color(red: 137/255, green: 145/255, blue: 136/255))

                    Spacer()

                    Button(action: submitActivity) {
                        Text("记录一下")
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 15)
                            .padding(.vertical, 7)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color(red: 71/255, green: 110/255, blue: 88/255)))
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(red: 232/255, green: 235/255, blue: 229/255), lineWidth: 1))
            .shadow(color: Color.black.opacity(0.03), radius: 10, x: 0, y: 4)
        }
    }

    // MARK: - Timeline Item Row

    private func timelineRow(_ item: TimelineItem) -> some View {
        let isTaskEvent = item.kind == .taskEvent
        let isTaskMemo = item.kind == .taskMemo

        return HStack(alignment: .top, spacing: 16) {
            // Left Dot centered on the vertical line (x = 7.5)
            ZStack {
                Circle()
                    .fill(isTaskEvent ? Color(red: 110/255, green: 167/255, blue: 130/255) : Color(red: 155/255, green: 185/255, blue: 164/255))
                    .frame(width: 8, height: 8)
                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
                    .overlay(Circle().stroke(Color(red: 200/255, green: 217/255, blue: 201/255), lineWidth: 1))
            }
            .frame(width: 15, height: 15)
            .padding(.top, 1)

            // Right content
            VStack(alignment: .leading, spacing: 8) {
                Text("\(item.time) · \(isTaskEvent ? "任务事件" : (isTaskMemo ? "任务评论" : "独立 Memo"))")
                    .font(.system(size: 11))
                    .foregroundColor(Color(red: 160/255, green: 169/255, blue: 158/255))

                // Card
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        if isTaskEvent {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(Color(red: 71/255, green: 110/255, blue: 88/255))
                        } else {
                            Image(systemName: "bubble.left")
                                .font(.system(size: 11))
                                .foregroundColor(Color(red: 119/255, green: 131/255, blue: 117/255))
                        }

                        if let title = item.taskTitle, let tid = item.taskId {
                            Button(action: { state.openTaskInspector(taskId: tid) }) {
                                Text(title)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(Color(red: 89/255, green: 100/255, blue: 88/255))
                            }
                            .buttonStyle(.plain)
                        } else {
                            Text("随手记录")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(Color(red: 89/255, green: 100/255, blue: 88/255))
                        }

                        Spacer()
                    }

                    Text(item.text)
                        .font(.system(size: 13))
                        .foregroundColor(Color(red: 36/255, green: 40/255, blue: 36/255))
                        .lineSpacing(4)
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 11).fill(Color.white))
                .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color(red: 232/255, green: 236/255, blue: 229/255), lineWidth: 1))
                .shadow(color: Color.black.opacity(0.02), radius: 6, x: 0, y: 2)
            }
        }
    }

    // MARK: - Data Models & Helpers

    private enum TimelineKind {
        case taskEvent
        case taskMemo
        case memo
    }

    private struct TimelineItem: Identifiable {
        let id: String
        let time: String
        let at: Date
        let kind: TimelineKind
        let taskTitle: String?
        let taskId: String?
        let text: String
    }

    private func getTimelineItems() -> [TimelineItem] {
        guard let v = state.vault else { return [] }
        var rows: [TimelineItem] = []
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let tf = DateFormatter()
        tf.dateFormat = "HH:mm"

        // 1. DayPlan activities (standalone memos)
        for act in dayPlan.activities {
            let tStr = tf.string(from: act.at)
            rows.append(TimelineItem(
                id: act.id,
                time: tStr,
                at: act.at,
                kind: .memo,
                taskTitle: nil,
                taskId: nil,
                text: act.body
            ))
        }

        // 2. Task activities and completion events
        for t in v.index.listTasks() {
            // Activities
            for act in t.activities {
                if f.string(from: act.at) == state.todayDateString {
                    let isCompletion = act.body.hasPrefix("完成任务：")
                    rows.append(TimelineItem(
                        id: act.id,
                        time: tf.string(from: act.at),
                        at: act.at,
                        kind: isCompletion ? .taskEvent : .taskMemo,
                        taskTitle: t.title,
                        taskId: t.id,
                        text: act.body
                    ))
                }
            }

            // Status events (if not already recorded as activity)
            for ev in t.statusEvents {
                if f.string(from: ev.at) == state.todayDateString && ev.action == .completed {
                    let evId = "ev-\(t.id)-\(ev.at.timeIntervalSince1970)"
                    if !rows.contains(where: { $0.text.contains(t.title) && $0.kind == .taskEvent }) {
                        rows.append(TimelineItem(
                            id: evId,
                            time: tf.string(from: ev.at),
                            at: ev.at,
                            kind: .taskEvent,
                            taskTitle: t.title,
                            taskId: t.id,
                            text: "完成任务：\(t.title)"
                        ))
                    }
                }
            }
        }

        return rows.sorted { $0.at > $1.at }
    }

    private func submitActivity() {
        let trimmed = newActivityText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let v = state.vault else { return }

        do {
            _ = try v.createActivity(date: state.todayDateString, body: trimmed)
            newActivityText = ""
        } catch {
            print("Failed to append activity:", error)
        }
    }

    private func toggleTaskStatus(_ task: Task) {
        guard let v = state.vault else { return }
        let newStatus: TaskStatus = task.status == .done ? .todo : .done
        do {
            _ = try v.setTaskStatus(id: task.id, status: newStatus)
        } catch {
            print("Failed to toggle status:", error)
        }
    }

    private func removeTaskFromPlan(_ tid: String) {
        guard let v = state.vault else { return }
        var plan = v.getDayPlan(date: state.todayDateString)
        plan.taskIds.removeAll { $0 == tid }
        try? _ = v.updateDayPlan(plan)
    }

    private func previousDay() {
        shiftDate(days: -1)
    }

    private func nextDay() {
        shiftDate(days: 1)
    }

    private func jumpToToday() {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        state.todayDateString = f.string(from: Date())
    }

    private func shiftDate(days: Int) {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        guard let current = f.date(from: state.todayDateString),
              let shifted = Calendar.current.date(byAdding: .day, value: days, to: current) else {
            return
        }
        state.todayDateString = f.string(from: shifted)
    }
}

// MARK: - Task Picker Sheet

struct TaskPickerSheet: View {
    @ObservedObject var state: AppState
    @Binding var isPresented: Bool
    @State private var search: String = ""

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text("选择任务加入今日计划")
                    .font(.system(size: 14, weight: .bold))
                Spacer()
                Button("关闭") { isPresented = false }
                    .buttonStyle(.plain)
            }

            TextField("搜索未完成任务...", text: $search)
                .textFieldStyle(.roundedBorder)

            List {
                ForEach(availableTasks) { task in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(task.title)
                                .font(.system(size: 13, weight: .medium))
                            if !task.tags.isEmpty {
                                Text(task.tags.map { "#\($0)" }.joined(separator: " "))
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        Button("+ 加入") {
                            addToPlan(task.id)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(Color(red: 71/255, green: 110/255, blue: 88/255))
                    }
                    .padding(.vertical, 4)
                }
            }
            .listStyle(.inset)
            .frame(height: 260)
        }
        .padding(20)
        .frame(width: 440)
    }

    private var availableTasks: [Task] {
        guard let v = state.vault else { return [] }
        let plan = v.getDayPlan(date: state.todayDateString)
        let currentIds = Set(plan.taskIds)
        return v.index.listTasks().filter { !currentIds.contains($0.id) && $0.status != .done }
    }

    private func addToPlan(_ tid: String) {
        guard let v = state.vault else { return }
        var plan = v.getDayPlan(date: state.todayDateString)
        if !plan.taskIds.contains(tid) {
            plan.taskIds.append(tid)
            try? _ = v.updateDayPlan(plan)
        }
        isPresented = false
    }
}
