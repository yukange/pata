import SwiftUI
import PataCore

public struct TasksView: View {
    @ObservedObject var state: AppState
    @State private var searchQuery: String = ""
    @State private var statusFilter: String = "all" // "all", "todo", "doing", "done"
    @State private var showNewTaskModal: Bool = false
    @State private var newTaskTitle: String = ""

    public init(state: AppState) {
        self.state = state
    }

    private var allTasks: [Task] {
        state.vault?.index.listTasks().sorted { $0.id < $1.id } ?? []
    }

    private var filteredTasks: [Task] {
        allTasks.filter { task in
            if statusFilter == "todo" && task.status == .done { return false }
            if statusFilter == "done" && task.status != .done { return false }
            if !searchQuery.isEmpty {
                return task.title.localizedCaseInsensitiveContains(searchQuery) ||
                       task.tags.contains(where: { $0.localizedCaseInsensitiveContains(searchQuery) })
            }
            return true
        }
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Page Header: Eyebrow, Title, Subtitle, + 新建任务 Button
                pageHeader

                // Search Bar
                searchBar

                // Status Filter Chips
                filterChips

                // Section Heading: 任务列表 + Count, Right: 点击任务查看进展与 Memo
                HStack(alignment: .center) {
                    HStack(spacing: 8) {
                        Text("任务列表")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(Color(red: 36/255, green: 40/255, blue: 36/255))

                        Text("\(filteredTasks.count)")
                            .font(.system(size: 11, design: .monospaced))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color(red: 240/255, green: 242/255, blue: 237/255)))
                            .foregroundColor(Color(red: 164/255, green: 170/255, blue: 162/255))
                    }

                    Spacer()

                    Text("点击任务查看进展与 Memo")
                        .font(.system(size: 11))
                        .foregroundColor(Color(red: 137/255, green: 145/255, blue: 136/255))
                }

                // Unified Task Panel
                if filteredTasks.isEmpty {
                    emptyStateView
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(filteredTasks.enumerated()), id: \.element.id) { index, task in
                            if index > 0 {
                                Rectangle()
                                    .fill(Color(red: 240/255, green: 241/255, blue: 237/255))
                                    .frame(height: 1)
                            }
                            taskRow(task)
                        }
                    }
                    .background(RoundedRectangle(cornerRadius: 13).fill(Color.white))
                    .overlay(RoundedRectangle(cornerRadius: 13).stroke(Color(red: 232/255, green: 235/255, blue: 229/255), lineWidth: 1))
                    .shadow(color: Color.black.opacity(0.03), radius: 10, x: 0, y: 4)
                }
            }
            .padding(.horizontal, 46)
            .padding(.top, 46)
            .padding(.bottom, 105)
            .frame(maxWidth: 840)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showNewTaskModal) {
            newTaskSheet
        }
    }

    // MARK: - Page Header

    private var pageHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("THE WORK POOL")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color(red: 147/255, green: 162/255, blue: 146/255))
                    .tracking(1.2)

                Text("Tasks")
                    .font(.system(size: 29, weight: .bold))
                    .foregroundColor(Color(red: 36/255, green: 40/255, blue: 36/255))

                Text("所有工作都在这里，跨天持续推进。")
                    .font(.system(size: 12))
                    .foregroundColor(Color(red: 137/255, green: 145/255, blue: 136/255))
            }

            Spacer()

            Button(action: { showNewTaskModal = true }) {
                HStack(spacing: 5) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                    Text("新建任务")
                        .font(.system(size: 12, weight: .medium))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(red: 71/255, green: 110/255, blue: 88/255)))
                .foregroundColor(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(.bottom, 6)
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundColor(Color(red: 163/255, green: 170/255, blue: 162/255))

            TextField("查找任务…", text: $searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 13))

            if !searchQuery.isEmpty {
                Button(action: { searchQuery = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 43)
        .background(RoundedRectangle(cornerRadius: 11).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color(red: 231/255, green: 235/255, blue: 229/255), lineWidth: 1))
    }

    // MARK: - Filter Chips

    private var filterChips: some View {
        HStack(spacing: 8) {
            chipButton(title: "全部", key: "all")
            chipButton(title: "待办", key: "todo")
            chipButton(title: "进行中", key: "doing")
            chipButton(title: "已完成", key: "done")
        }
        .padding(.top, 2)
        .padding(.bottom, 6)
    }

    private func chipButton(title: String, key: String) -> some View {
        let isSelected = statusFilter == key
        return Button(action: { statusFilter = key }) {
            Text(title)
                .font(.system(size: 11, weight: isSelected ? .bold : .regular))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(isSelected ? Color(red: 234/255, green: 242/255, blue: 233/255) : Color.white)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(isSelected ? Color(red: 228/255, green: 238/255, blue: 226/255) : Color(red: 231/255, green: 235/255, blue: 229/255), lineWidth: 1)
                )
                .foregroundColor(isSelected ? Color(red: 69/255, green: 110/255, blue: 82/255) : Color(red: 133/255, green: 144/255, blue: 130/255))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Task Row

    private func taskRow(_ task: Task) -> some View {
        let isDone = task.status == .done

        return HStack(spacing: 14) {
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
            .help(isDone ? "点击恢复为待办" : "点击标记为完成")

            // Title & Sub-row
            Button(action: { state.openTaskInspector(taskId: task.id) }) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(task.title)
                        .font(.system(size: 13, weight: .medium))
                        .strikethrough(isDone)
                        .foregroundColor(isDone ? Color(red: 167/255, green: 173/255, blue: 165/255) : Color(red: 36/255, green: 40/255, blue: 36/255))
                        .lineLimit(1)

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
            }
            .buttonStyle(.plain)

            Spacer()

            // Priority Pill
            if let p = task.extra["priority"], !p.isEmpty {
                priorityPill(p)
            }
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

    // MARK: - Empty State

    private var emptyStateView: some View {
        HStack {
            Spacer()
            Text("没有找到符合条件的任务。")
                .font(.system(size: 13))
                .foregroundColor(Color(red: 161/255, green: 170/255, blue: 160/255))
            Spacer()
        }
        .padding(.vertical, 45)
        .background(RoundedRectangle(cornerRadius: 13).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(Color(red: 232/255, green: 235/255, blue: 229/255), lineWidth: 1))
    }

    // MARK: - New Task Sheet

    private var newTaskSheet: some View {
        VStack(spacing: 16) {
            HStack {
                Text("新建任务")
                    .font(.system(size: 14, weight: .bold))
                Spacer()
                Button("关闭") { showNewTaskModal = false }
                    .buttonStyle(.plain)
            }

            TextField("输入任务标题，例如：调研 Doris 存算分离 #调研", text: $newTaskTitle)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("创建") {
                    createNewTask()
                }
                .buttonStyle(.borderedProminent)
                .disabled(newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    private func createNewTask() {
        let raw = newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, let v = state.vault else { return }

        let parts = raw.components(separatedBy: " ")
        var titleWords: [String] = []
        var tags: [String] = []
        var inTrailingTags = true

        for part in parts.reversed() {
            if inTrailingTags && part.hasPrefix("#") && part.count > 1 {
                tags.append(String(part.dropFirst()))
            } else {
                inTrailingTags = false
                titleWords.insert(part, at: 0)
            }
        }

        let title = titleWords.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        let finalTitle = title.isEmpty ? raw : title

        do {
            let task = try v.createTask(title: finalTitle, tags: tags.reversed())
            newTaskTitle = ""
            showNewTaskModal = false
            state.openTaskInspector(taskId: task.id)
        } catch {
            print("Failed to create task:", error)
        }
    }

    private func toggleTaskStatus(_ task: Task) {
        guard let v = state.vault else { return }
        let newStatus: TaskStatus = task.status == .done ? .todo : .done
        do {
            try v.setTaskStatus(id: task.id, status: newStatus)
        } catch {
            print("Failed to toggle status:", error)
        }
    }
}
