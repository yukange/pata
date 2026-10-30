import SwiftUI
import PataCore

public struct TasksView: View {
    @ObservedObject var state: AppState
    @State private var quickCreateText: String = ""
    @State private var statusFilter: String = "all" // "all", "active", "done"
    @FocusState private var isQuickCreateFocused: Bool

    public init(state: AppState) {
        self.state = state
    }

    private var allTasks: [Task] {
        state.vault?.index.listTasks().sorted { $0.id < $1.id } ?? []
    }

    private var activeTasksCount: Int {
        allTasks.filter { $0.status != .done }.count
    }

    private var doneTasksCount: Int {
        allTasks.filter { $0.status == .done }.count
    }

    private var filteredTasks: [Task] {
        allTasks.filter { task in
            if statusFilter == "active" && task.status == .done { return false }
            if statusFilter == "done" && task.status != .done { return false }
            return true
        }
    }

    private var borderColor: Color {
        switch state.themePreference {
        case "dark": return Color(red: 41/255, green: 37/255, blue: 36/255)
        default: return Color(red: 231/255, green: 229/255, blue: 228/255)
        }
    }

    private var cardBg: Color {
        switch state.themePreference {
        case "dark": return Color(red: 24/255, green: 21/255, blue: 20/255)
        default: return Color.white
        }
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 1. Quick Create Input
                HStack(spacing: 0) {
                    TextField("添加任务...", text: $quickCreateText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .padding(.horizontal, 12)
                        .focused($isQuickCreateFocused)
                        .onSubmit {
                            submitQuickCreate()
                        }
                        .onKeyPress(.escape) {
                            isQuickCreateFocused = false
                            return .handled
                        }

                    Button(action: submitQuickCreate) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.system(size: 10, weight: .bold))
                            Text("快速创建")
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

                // 2. Filter Pills
                HStack(spacing: 6) {
                    filterButton(title: "全部 (\(allTasks.count))", filterKey: "all")
                    filterButton(title: "未完成 (\(activeTasksCount))", filterKey: "active")
                    filterButton(title: "已完成 (\(doneTasksCount))", filterKey: "done")
                }
                .padding(.vertical, 2)

                // 3. Task List Cards
                if filteredTasks.isEmpty {
                    Text("当前分类下暂无任务")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .padding(.vertical, 20)
                } else {
                    VStack(spacing: 8) {
                        ForEach(filteredTasks) { task in
                            taskCard(task)
                        }
                    }
                }
            }
            .padding(.horizontal, 48)
            .padding(.top, 24)
            .padding(.bottom, 64)
            .frame(maxWidth: 860)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            isQuickCreateFocused = false
            DispatchQueue.main.async {
                isQuickCreateFocused = false
            }
        }
    }

    private func filterButton(title: String, filterKey: String) -> some View {
        let isSelected = statusFilter == filterKey

        return Button(action: { statusFilter = filterKey }) {
            Text(title)
                .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                .foregroundColor(isSelected ? .primary : .secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? Color.primary.opacity(0.08) : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }

    private func taskCard(_ task: Task) -> some View {
        let isDone = task.status == .done
        let isSelected = state.selectedTaskId == task.id && state.isInspectorVisible

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
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

                Spacer()

                // Status Badge
                Text(isDone ? "已完成" : "待办")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isDone ? Color(red: 4/255, green: 120/255, blue: 87/255) : .secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(isDone ? Color(red: 209/255, green: 250/255, blue: 229/255) : Color.primary.opacity(0.06))
                    )
            }

            // Sub row: Due date, tags, date
            HStack(spacing: 10) {
                if let due = task.due {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.system(size: 10))
                        Text("due \(due)")
                            .font(.system(size: 11))
                    }
                    .foregroundColor(.secondary)
                }

                ForEach(task.tags, id: \.self) { tag in
                    Text("#\(tag)")
                        .font(.system(size: 11))
                        .foregroundColor(Color(red: 71/255, green: 110/255, blue: 88/255))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 3).fill(Color.primary.opacity(0.04)))
                }

                Spacer()

                Text(formatDate(task.updatedAt))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? Color.primary.opacity(0.04) : cardBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color.secondary.opacity(0.4) : borderColor, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            state.openTaskInspector(taskId: task.id)
        }
    }

    private func formatDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }

    private func toggleStatus(_ task: Task) {
        let next: TaskStatus = task.status == .done ? .todo : .done
        try? state.vault?.setTaskStatus(id: task.id, status: next)
        state.objectWillChange.send()
    }

    private func submitQuickCreate() {
        let clean = quickCreateText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, let v = state.vault else { return }

        do {
            _ = try v.createTask(title: clean, status: .todo, tags: [])
            quickCreateText = ""
            state.objectWillChange.send()
        } catch {
            print("Create task failed:", error)
        }
    }
}
