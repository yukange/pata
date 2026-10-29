import SwiftUI
import PataCore

public struct TagView: View {
    @ObservedObject var state: AppState

    public init(state: AppState) {
        self.state = state
    }

    private var activeTagName: String {
        state.selectedTag ?? "架构设计"
    }

    private var relatedTasks: [Task] {
        guard let v = state.vault else { return [] }
        return v.index.listTasks().filter { $0.tags.contains(activeTagName) }.sorted { $0.id < $1.id }
    }

    private var relatedNotes: [Note] {
        guard let v = state.vault else { return [] }
        return v.index.listNotes().filter { $0.tags.contains(activeTagName) }.sorted { $0.id < $1.id }
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 27) {
                // Page Header: Eyebrow, Title, Subtitle
                pageHeader

                // Section 1: 相关任务
                tasksSection

                // Section 2: 相关笔记
                notesSection
            }
            .padding(.horizontal, 46)
            .padding(.top, 46)
            .padding(.bottom, 105)
            .frame(maxWidth: 785)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Page Header

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TAGGED CONTENT")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(Color(red: 147/255, green: 162/255, blue: 146/255))
                .tracking(1.2)

            Text("# \(activeTagName)")
                .font(.system(size: 29, weight: .bold))
                .foregroundColor(Color(red: 36/255, green: 40/255, blue: 36/255))

            Text("聚合所有带此标签的任务、笔记与动态。")
                .font(.system(size: 12))
                .foregroundColor(Color(red: 137/255, green: 145/255, blue: 136/255))
        }
        .padding(.bottom, 6)
    }

    // MARK: - Tasks Section

    private var tasksSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Text("相关任务")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(Color(red: 36/255, green: 40/255, blue: 36/255))

                Text("\(relatedTasks.count)")
                    .font(.system(size: 11, design: .monospaced))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(red: 240/255, green: 242/255, blue: 237/255)))
                    .foregroundColor(Color(red: 164/255, green: 170/255, blue: 162/255))
            }

            if relatedTasks.isEmpty {
                Text("没有找到带此标签的任务。")
                    .font(.system(size: 13))
                    .foregroundColor(Color(red: 161/255, green: 170/255, blue: 160/255))
                    .padding(.vertical, 12)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(relatedTasks.enumerated()), id: \.element.id) { index, task in
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
    }

    private func taskRow(_ task: Task) -> some View {
        let isDone = task.status == .done

        return HStack(spacing: 14) {
            // Checkbox
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

            VStack(alignment: .leading, spacing: 3) {
                Button(action: {
                    state.currentNav = .tasks
                    state.openTaskInspector(taskId: task.id)
                }) {
                    Text(task.title)
                        .font(.system(size: 13, weight: .medium))
                        .strikethrough(isDone)
                        .foregroundColor(isDone ? Color(red: 167/255, green: 173/255, blue: 165/255) : Color(red: 36/255, green: 40/255, blue: 36/255))
                }
                .buttonStyle(.plain)

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

            if let p = task.extra["priority"], !p.isEmpty {
                priorityPill(p)
            }
        }
        .padding(.horizontal, 20)
        .frame(minHeight: 62)
    }

    // MARK: - Notes Section

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Text("相关笔记")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(Color(red: 36/255, green: 40/255, blue: 36/255))

                Text("\(relatedNotes.count)")
                    .font(.system(size: 11, design: .monospaced))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(red: 240/255, green: 242/255, blue: 237/255)))
                    .foregroundColor(Color(red: 164/255, green: 170/255, blue: 162/255))
            }

            if relatedNotes.isEmpty {
                Text("没有找到带此标签的笔记。")
                    .font(.system(size: 13))
                    .foregroundColor(Color(red: 161/255, green: 170/255, blue: 160/255))
                    .padding(.vertical, 12)
            } else {
                VStack(spacing: 12) {
                    ForEach(relatedNotes) { note in
                        Button(action: {
                            state.currentNav = .notes
                            state.selectedNoteId = note.id
                        }) {
                            VStack(alignment: .leading, spacing: 11) {
                                Text(note.title)
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundColor(Color(red: 36/255, green: 40/255, blue: 36/255))

                                Text(extractExcerpt(note.body))
                                    .font(.system(size: 12))
                                    .foregroundColor(Color(red: 120/255, green: 129/255, blue: 121/255))
                                    .lineSpacing(4)
                                    .lineLimit(2)

                                HStack {
                                    HStack(spacing: 8) {
                                        ForEach(note.tags, id: \.self) { tag in
                                            Text("#\(tag)")
                                                .font(.system(size: 11))
                                                .foregroundColor(Color(red: 101/255, green: 132/255, blue: 105/255))
                                                .padding(.horizontal, 7)
                                                .padding(.vertical, 4)
                                                .background(RoundedRectangle(cornerRadius: 5).fill(Color(red: 239/255, green: 246/255, blue: 238/255)))
                                        }
                                    }

                                    Spacer()

                                    Text(formatRelativeDate(note.updatedAt))
                                        .font(.system(size: 11))
                                        .foregroundColor(Color(red: 173/255, green: 180/255, blue: 172/255))
                                }
                            }
                            .padding(24)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 13).fill(Color.white))
                            .overlay(RoundedRectangle(cornerRadius: 13).stroke(Color(red: 232/255, green: 236/255, blue: 230/255), lineWidth: 1))
                            .shadow(color: Color.black.opacity(0.03), radius: 10, x: 0, y: 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

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

    private func extractExcerpt(_ body: String) -> String {
        let lines = body.components(separatedBy: "\n")
        for line in lines {
            let t = line.trimmingCharacters(in: .whitespaces)
            if !t.isEmpty && !t.hasPrefix("#") && !t.hasPrefix("-") && !t.hasPrefix(">") {
                return t
            }
        }
        return ""
    }

    private func formatRelativeDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let todayStr = state.todayDateString
        let dateStr = f.string(from: d)

        let fTime = DateFormatter()
        fTime.dateFormat = "HH:mm"

        let cal = Calendar.current
        var yesterdayStr = ""
        if let todayDate = f.date(from: todayStr),
           let yDate = cal.date(byAdding: .day, value: -1, to: todayDate) {
            yesterdayStr = f.string(from: yDate)
        }

        if dateStr == todayStr {
            return "今天 \(fTime.string(from: d))"
        } else if dateStr == yesterdayStr {
            return "昨天 \(fTime.string(from: d))"
        } else {
            let month = cal.component(.month, from: d)
            let day = cal.component(.day, from: d)
            return "\(month) 月 \(day) 日"
        }
    }

    private func toggleTaskStatus(_ task: Task) {
        guard let v = state.vault else { return }
        let newStatus: TaskStatus = task.status == .done ? .todo : .done
        try? v.setTaskStatus(id: task.id, status: newStatus)
    }
}
