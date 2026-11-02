import SwiftUI
import AppKit
import PataCore

public struct TagView: View {
    @ObservedObject var state: AppState

    public init(state: AppState) {
        self.state = state
    }

    private var activeTag: String? {
        guard let tag = state.selectedTag?.trimmingCharacters(in: .whitespacesAndNewlines), !tag.isEmpty else { return nil }
        return tag
    }

    private var items: [EntityRef] {
        guard let v = state.vault else { return [] }
        if let activeTag { return v.index.findByTag(activeTag) }
        return v.index.listAllEntities()
    }

    private var taskCount: Int {
        items.filter { $0.type == .task }.count
    }

    private var noteCount: Int {
        items.filter { $0.type == .note }.count
    }

    private var activityCount: Int {
        items.filter { $0.type == .activity }.count
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header with Tag Chip & Counts
                HStack(spacing: 8) {
                    tagFilter

                    Text("共 \(items.count) 项（任务 \(taskCount) · 笔记 \(noteCount) · 记录 \(activityCount)）")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)

                    Spacer()
                }
                .padding(.bottom, 8)
                .overlay(Rectangle().frame(height: 1).foregroundColor(Color(nsColor: .separatorColor).opacity(0.5)), alignment: .bottom)

                // Items list
                if items.isEmpty {
                    VStack(spacing: 8) {
                        Spacer()
                        Image(systemName: "number")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary.opacity(0.3))
                        Text(activeTag == nil ? "暂无任务、笔记或记录" : "该标签下暂无内容")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, minHeight: 200)
                    .background(RoundedRectangle(cornerRadius: 12).stroke(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 1))
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(items, id: \.id) { item in
                            switch item.type {
                            case .task:
                                taskCard(item)
                            case .note:
                                noteCard(item)
                            case .activity:
                                activityCard(item)
                            default:
                                EmptyView()
                            }
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // 侧栏收起时仍可选择资料库中的真实标签。
    private var tagFilter: some View {
        Menu {
            Button("全部") { state.selectedTag = nil }
            Divider()
            ForEach(state.vault?.index.listTags() ?? [], id: \.name) { tag in
                Button("#\(tag.name)（\(tag.totalCount)）") { state.selectedTag = tag.name }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "number")
                Text(activeTag ?? "全部").lineLimit(1)
            }
            .font(.system(size: 14, weight: .semibold))
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.stoneTagBg))
            .foregroundColor(.emeraldColor)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.emeraldColor.opacity(0.3), lineWidth: 1))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel("筛选标签")
    }

    // MARK: - Task Card

    private func taskCard(_ item: EntityRef) -> some View {
        let isSelected = state.selectedTaskId == item.id && state.isInspectorVisible

        return Button(action: {
            state.openTaskInspector(taskId: item.id)
        }) {
            VStack(alignment: .leading, spacing: 8) {
                // Header Row
                HStack {
                    HStack(spacing: 6) {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.square")
                                .font(.system(size: 10))
                            Text("任务")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color.stoneTagBg))
                        .foregroundColor(Color(red: 4/255, green: 120/255, blue: 87/255))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(red: 4/255, green: 120/255, blue: 87/255).opacity(0.3), lineWidth: 1))

                        if item.status == .done {
                            Text("已完成")
                                .font(.system(size: 11, weight: .medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(RoundedRectangle(cornerRadius: 4).fill(Color.stoneBadgeBg))
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    Text(formatItemTime(item.time))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                // Content Row
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title ?? item.id)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.primary)

                        if let snippet = item.snippet, !snippet.isEmpty {
                            Text(snippet)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                    }

                    Spacer()

                    HStack(spacing: 2) {
                        Text("查看任务")
                            .font(.system(size: 11))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9))
                    }
                    .foregroundColor(.secondary)
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(isSelected ? Color.accentColor : Color(nsColor: .separatorColor).opacity(0.6), lineWidth: isSelected ? 1.5 : 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Note Card

    private func noteCard(_ item: EntityRef) -> some View {
        Button(action: {
            state.navigateToNote(noteId: item.id)
        }) {
            VStack(alignment: .leading, spacing: 8) {
                // Header Row
                HStack {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 10))
                        Text("笔记")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.blue.opacity(0.1)))
                    .foregroundColor(.blue)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.blue.opacity(0.3), lineWidth: 1))

                    Spacer()

                    Text(formatItemTime(item.time))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                // Content Row
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title ?? item.id)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.primary)

                        if let snippet = item.snippet, !snippet.isEmpty {
                            Text(snippet)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                    }

                    Spacer()

                    HStack(spacing: 2) {
                        Text("打开笔记")
                            .font(.system(size: 11))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9))
                    }
                    .foregroundColor(.secondary)
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Activity Card

    private func activityCard(_ item: EntityRef) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header Row
            HStack {
                HStack(spacing: 6) {
                    HStack(spacing: 4) {
                        Image(systemName: "bubble.left")
                            .font(.system(size: 10))
                        Text("记录")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.orange.opacity(0.1)))
                    .foregroundColor(.orange)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.orange.opacity(0.3), lineWidth: 1))

                    if item.inherited {
                        Text("经父任务")
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Color.orange.opacity(0.15)))
                            .foregroundColor(.orange)
                    }

                    if let taskId = item.taskId {
                        Text("所属任务: \(item.title ?? taskId)")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    } else {
                        Text("今日计划")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Text(formatItemTime(item.time))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            Text(item.snippet ?? "（无正文内容）")
                .font(.system(size: 14))
                .foregroundColor(.primary)
                .lineLimit(3)
                .lineSpacing(2)

            HStack {
                Spacer()
                Button(action: { state.openSearchResult(item) }) {
                    HStack(spacing: 3) {
                        Text(item.taskId == nil ? "查看当日记录" : "查看任务")
                            .font(.system(size: 11))
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 9))
                    }
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 2)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 1))
    }

    private func formatItemTime(_ date: Date) -> String {
        let cal = Calendar.current
        let formatter = DateFormatter()
        if cal.isDateInToday(date) {
            formatter.dateFormat = "HH:mm"
            return "今天 \(formatter.string(from: date))"
        } else if cal.isDate(date, equalTo: Date(), toGranularity: .year) {
            formatter.dateFormat = "MM-dd HH:mm"
            return formatter.string(from: date)
        } else {
            formatter.dateFormat = "yyyy-MM-dd HH:mm"
            return formatter.string(from: date)
        }
    }
}
