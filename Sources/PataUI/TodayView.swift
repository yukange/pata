import SwiftUI
import PataCore

public struct TodayView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var state: AppState
    @State private var quickCreateText: String = ""
    @FocusState private var isInputFocused: Bool
    @State private var isDropdownVisible: Bool = false
    @State private var candidateTab: CandidateTab = .uncompleted
    @State private var highlightedCandidateIndex: Int? = nil
    @State private var inputWidth: CGFloat = 0

    @State private var quickActivityText: String = ""
    @State private var isCreatingActivity: Bool = false

    public enum CandidateTab: String, CaseIterable {
        case uncompleted = "未完成"
        case completed = "已完成"
    }

    public init(state: AppState) {
        self.state = state
    }

    private var hasQuery: Bool {
        !quickCreateText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var availableTasks: [Task] {
        guard let v = state.vault else { return [] }
        let currentPlanIds = Set(dayPlan.taskIds)
        return v.index.listTasks()
            .filter { !currentPlanIds.contains($0.id) }
            .sorted { a, b in
                if a.createdAt != b.createdAt {
                    return a.createdAt > b.createdAt
                }
                return a.id > b.id
            }
    }

    private var filteredCandidates: [Task] {
        let q = quickCreateText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty {
            switch candidateTab {
            case .uncompleted:
                return availableTasks.filter { $0.status != .done }
            case .completed:
                return availableTasks.filter { $0.status == .done }
            }
        } else {
            return availableTasks.filter {
                $0.title.lowercased().contains(q) ||
                $0.tags.contains { $0.lowercased().contains(q) }
            }
        }
    }

    private var candidateListHeight: CGFloat {
        let count = filteredCandidates.count
        if count == 0 {
            return 52
        }
        let rowHeight: CGFloat = 34
        let total = CGFloat(count) * rowHeight + 8
        return min(total, 220)
    }

    private var hasAvailableTasks: Bool {
        if hasQuery {
            return !filteredCandidates.isEmpty
        }
        return !availableTasks.isEmpty
    }

    private var todayStr: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    private var isToday: Bool {
        state.todayDateString == todayStr
    }

    private var canShiftForward: Bool {
        state.todayDateString < todayStr
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

    private var isDarkMode: Bool {
        if state.themePreference == "dark" {
            return true
        } else if state.themePreference == "light" {
            return false
        }
        return colorScheme == .dark
    }

    private var popoverBackground: Color {
        isDarkMode ? Color(red: 28/255, green: 25/255, blue: 23/255) : Color.white
    }

    private var popoverFooterBackground: Color {
        isDarkMode ? Color(red: 38/255, green: 35/255, blue: 33/255) : Color(red: 247/255, green: 246/255, blue: 245/255)
    }

    private var borderColor: Color {
        isDarkMode ? Color(red: 41/255, green: 37/255, blue: 36/255) : Color(red: 231/255, green: 229/255, blue: 228/255)
    }

    public var body: some View {
        ScrollView {
            ZStack(alignment: .top) {
                if isDropdownVisible {
                    Color.black.opacity(0.0001)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            isDropdownVisible = false
                            highlightedCandidateIndex = nil
                            isInputFocused = false
                        }
                        .zIndex(1)
                }

                VStack(alignment: .leading, spacing: 20) {
                    // Top Date Bar
                    dateBar
                        .zIndex(1)

                    // Section: Plan
                    planSection
                        .zIndex(100)

                    // Thin separator
                    Rectangle()
                        .fill(borderColor)
                        .frame(height: 1)
                        .padding(.vertical, 4)
                        .zIndex(2)

                    // Section: Activity Timeline
                    activitySection
                        .zIndex(1)
                }
                .padding(.horizontal, 48)
                .padding(.top, 24)
                .padding(.bottom, 64)
                .frame(maxWidth: 860)
                .zIndex(10)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Date Bar

    private var dateBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 0) {
                DateNavStepperButton(
                    icon: "chevron.left",
                    isEnabled: true,
                    width: 28,
                    height: 24,
                    helpText: "前一天",
                    action: { shiftDay(-1) }
                )

                Rectangle()
                    .fill(borderColor)
                    .frame(width: 1, height: 14)

                DateNavStepperButton(
                    icon: "chevron.right",
                    isEnabled: canShiftForward,
                    width: 28,
                    height: 24,
                    helpText: canShiftForward ? "后一天" : "不能选择未来日期",
                    action: { shiftDay(1) }
                )
            }
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.03)))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(borderColor, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 6))

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
        if delta > 0 && !canShiftForward {
            return
        }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        if let d = f.date(from: state.todayDateString),
           let next = Calendar.current.date(byAdding: .day, value: delta, to: d) {
            let nextStr = f.string(from: next)
            if delta > 0 && nextStr > todayStr {
                state.todayDateString = todayStr
            } else {
                state.todayDateString = nextStr
            }
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
            .zIndex(1)

            // Quick Create Input Container with Dropdown
            quickCreateInputContainer
                .zIndex(100)

            Text("仅安排今天推进的任务，不改变任务的截止日期。")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .padding(.bottom, 2)
                .zIndex(1)

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

    // MARK: - Quick Create & Inline Task Picker

    private var quickCreateInputContainer: some View {
        HStack(spacing: 0) {
            TextField("添加任务或搜索...", text: $quickCreateText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .padding(.horizontal, 12)
                .focused($isInputFocused)
                .onTapGesture {
                    isDropdownVisible = true
                }
                .onSubmit {
                    handleQuickCreateSubmit()
                }
                .onKeyPress(.downArrow) {
                    if !filteredCandidates.isEmpty {
                        let current = highlightedCandidateIndex ?? -1
                        highlightedCandidateIndex = min(current + 1, filteredCandidates.count - 1)
                        isDropdownVisible = true
                        return .handled
                    }
                    return .ignored
                }
                .onKeyPress(.upArrow) {
                    if !filteredCandidates.isEmpty {
                        if let current = highlightedCandidateIndex {
                            if current > 0 {
                                highlightedCandidateIndex = current - 1
                            } else {
                                highlightedCandidateIndex = nil
                            }
                            isDropdownVisible = true
                            return .handled
                        }
                    }
                    return .ignored
                }
                .onKeyPress(.escape) {
                    isDropdownVisible = false
                    highlightedCandidateIndex = nil
                    isInputFocused = false
                    return .handled
                }
                .onKeyPress(.leftArrow) {
                    if !hasQuery {
                        candidateTab = .uncompleted
                        highlightedCandidateIndex = nil
                        isDropdownVisible = true
                        return .handled
                    }
                    return .ignored
                }
                .onKeyPress(.rightArrow) {
                    if !hasQuery {
                        candidateTab = .completed
                        highlightedCandidateIndex = nil
                        isDropdownVisible = true
                        return .handled
                    }
                    return .ignored
                }

            Button(action: handleQuickCreateSubmit) {
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
        .background(
            GeometryReader { geo in
                Color.primary.opacity(0.02)
                    .preference(key: InputWidthPreferenceKey.self, value: geo.size.width)
            }
        )
        .onPreferenceChange(InputWidthPreferenceKey.self) { width in
            inputWidth = width
        }
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(borderColor, lineWidth: 1))
        .onChange(of: isInputFocused) { _, focused in
            if focused {
                isDropdownVisible = true
            }
        }
        .overlay(alignment: .topLeading) {
            if isDropdownVisible && hasAvailableTasks {
                candidateDropdownView
                    .frame(width: inputWidth > 0 ? inputWidth : nil)
                    .offset(y: 40)
                    .zIndex(200)
            }
        }
        .zIndex(100)
    }

    private var candidateDropdownView: some View {
        VStack(spacing: 0) {
            // 1. Tab Bar (shown when there is no search query)
            if !hasQuery {
                HStack(spacing: 4) {
                    candidateTabButton(title: "未完成", tab: .uncompleted)
                    candidateTabButton(title: "已完成", tab: .completed)
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.top, 6)
                .padding(.bottom, 2)
            }

            // 2. Candidate Task List
            if filteredCandidates.isEmpty {
                VStack(spacing: 4) {
                    Text(!hasQuery ? (candidateTab == .uncompleted ? "暂无未完成任务" : "暂无已完成任务") : "未找到相关任务，按 ↵ 创建新任务")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
            } else {
                ScrollView {
                    ScrollViewReader { proxy in
                        VStack(spacing: 1) {
                            ForEach(Array(filteredCandidates.enumerated()), id: \.element.id) { index, task in
                                candidateRow(task: task, isHighlighted: highlightedCandidateIndex == index) {
                                    addExistingTaskToPlan(task)
                                }
                                .id(task.id)
                            }
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 4)
                        .onChange(of: highlightedCandidateIndex) { _, newIdx in
                            if let idx = newIdx, idx >= 0, idx < filteredCandidates.count {
                                proxy.scrollTo(filteredCandidates[idx].id, anchor: .center)
                            }
                        }
                    }
                }
                .frame(height: candidateListHeight)
            }

            Divider()

            // 3. Footer Bar with Shortcuts
            HStack {
                HStack(spacing: 4) {
                    Text("↵")
                        .font(.system(size: 10, design: .monospaced))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 3).fill(Color.stoneBadgeBg))

                    Text(hasQuery ? (highlightedCandidateIndex != nil ? "加入已有" : "创建新任务") : "加入今日")
                        .font(.system(size: 11))
                }

                Spacer()

                HStack(spacing: 8) {
                    HStack(spacing: 3) {
                        Text("↑")
                            .font(.system(size: 10, design: .monospaced))
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: 3).fill(Color.stoneBadgeBg))
                        Text("↓")
                            .font(.system(size: 10, design: .monospaced))
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: 3).fill(Color.stoneBadgeBg))
                        Text(hasQuery && highlightedCandidateIndex == nil ? "选择" : "移动")
                            .font(.system(size: 11))
                    }

                    if !hasQuery {
                        HStack(spacing: 3) {
                            Text("←")
                                .font(.system(size: 10, design: .monospaced))
                                .padding(.horizontal, 3)
                                .padding(.vertical, 1)
                                .background(RoundedRectangle(cornerRadius: 3).fill(Color.stoneBadgeBg))
                            Text("→")
                                .font(.system(size: 10, design: .monospaced))
                                .padding(.horizontal, 3)
                                .padding(.vertical, 1)
                                .background(RoundedRectangle(cornerRadius: 3).fill(Color.stoneBadgeBg))
                            Text("分类")
                                .font(.system(size: 11))
                        }
                    }

                    HStack(spacing: 3) {
                        Text("ESC")
                            .font(.system(size: 9, design: .monospaced))
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: 3).fill(Color.stoneBadgeBg))
                        Text("关闭")
                            .font(.system(size: 11))
                    }
                }
            }
            .foregroundColor(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(popoverFooterBackground)
        }
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(popoverBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderColor, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: Color.black.opacity(isDarkMode ? 0.35 : 0.14), radius: 14, x: 0, y: 8)
    }

    private func candidateTabButton(title: String, tab: CandidateTab) -> some View {
        Button(action: {
            candidateTab = tab
            highlightedCandidateIndex = nil
        }) {
            Text(title)
                .font(.system(size: 12, weight: candidateTab == tab ? .semibold : .regular))
                .foregroundColor(candidateTab == tab ? .primary : .secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(candidateTab == tab ? Color.primary.opacity(0.08) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func candidateRow(task: Task, isHighlighted: Bool, action: @escaping () -> Void) -> some View {
        CandidateTaskRowView(task: task, isHighlighted: isHighlighted, action: action)
    }

    private func handleQuickCreateSubmit() {
        if let idx = highlightedCandidateIndex, idx >= 0, idx < filteredCandidates.count {
            addExistingTaskToPlan(filteredCandidates[idx])
        } else if !hasQuery && !filteredCandidates.isEmpty {
            addExistingTaskToPlan(filteredCandidates[0])
        } else {
            submitQuickCreate()
        }
    }

    private func addExistingTaskToPlan(_ task: Task) {
        guard let v = state.vault else { return }
        do {
            try v.addTaskToPlan(date: state.todayDateString, taskId: task.id)
            quickCreateText = ""
            highlightedCandidateIndex = nil
            isDropdownVisible = false
            state.objectWillChange.send()
        } catch {
            print("Failed to add task to plan:", error)
        }
    }

    private func submitQuickCreate() {
        let clean = quickCreateText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, let v = state.vault else { return }

        // Create task and add to day plan
        do {
            let t = try v.createTask(title: clean, status: .todo, tags: [])
            try v.addTaskToPlan(date: state.todayDateString, taskId: t.id)
            quickCreateText = ""
            highlightedCandidateIndex = nil
            isDropdownVisible = false
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

    private var canShiftForward: Bool {
        state.todayDateString < todayStr
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
            HStack(spacing: 0) {
                DateNavStepperButton(
                    icon: "chevron.left",
                    isEnabled: true,
                    width: 22,
                    height: 20,
                    helpText: "前一天",
                    action: { shiftDay(-1) }
                )

                Rectangle()
                    .fill(Color(nsColor: .separatorColor))
                    .frame(width: 1, height: 12)

                DateNavStepperButton(
                    icon: "chevron.right",
                    isEnabled: canShiftForward,
                    width: 22,
                    height: 20,
                    helpText: canShiftForward ? "后一天" : "不能选择未来日期",
                    action: { shiftDay(1) }
                )
            }
            .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.03)))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color(nsColor: .separatorColor), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 5))

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
        if delta > 0 && !canShiftForward {
            return
        }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        if let d = f.date(from: state.todayDateString),
           let next = Calendar.current.date(byAdding: .day, value: delta, to: d) {
            let nextStr = f.string(from: next)
            if delta > 0 && nextStr > todayStr {
                state.todayDateString = todayStr
            } else {
                state.todayDateString = nextStr
            }
        }
    }
}

// MARK: - Date Stepper Button Component

public struct DateNavStepperButton: View {
    let icon: String
    let isEnabled: Bool
    let width: CGFloat
    let height: CGFloat
    let helpText: String
    let action: () -> Void
    @State private var isHovered = false

    public init(
        icon: String,
        isEnabled: Bool,
        width: CGFloat = 26,
        height: CGFloat = 24,
        helpText: String = "",
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.isEnabled = isEnabled
        self.width = width
        self.height = height
        self.helpText = helpText
        self.action = action
    }

    public var body: some View {
        Button(action: {
            if isEnabled { action() }
        }) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(isEnabled ? (isHovered ? .primary : .secondary) : .secondary.opacity(0.28))
                .frame(width: width, height: height)
                .background(isEnabled && isHovered ? Color.primary.opacity(0.06) : Color.black.opacity(0.0001))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .help(helpText)
        .onHover { hovering in
            if isEnabled {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Candidate Task Row View

struct CandidateTaskRowView: View {
    let task: Task
    let isHighlighted: Bool
    let action: () -> Void
    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: task.status == .done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13))
                    .foregroundColor(task.status == .done ? Color(red: 4/255, green: 120/255, blue: 87/255) : .secondary.opacity(0.6))

                Text(task.title)
                    .font(.system(size: 13))
                    .foregroundColor(task.status == .done ? .secondary : .primary)
                    .strikethrough(task.status == .done)
                    .lineLimit(1)

                Spacer()

                ForEach(task.tags.prefix(2), id: \.self) { tag in
                    Text("#\(tag)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHighlighted ? Color.primary.opacity(0.08) : (isHovered ? Color.primary.opacity(0.04) : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Input Width Preference Key

private struct InputWidthPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
