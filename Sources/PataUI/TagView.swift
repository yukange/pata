import SwiftUI
import AppKit
import PataCore

public struct TagView: View {
    @ObservedObject var state: AppState

    @State private var hoveredTag: String? = nil

    // In-place Tag Rename State
    @State private var editingTag: String? = nil
    @State private var inlineTagName: String = ""
    @FocusState private var focusedTag: String?
    @State private var tagErrorMessage: String? = nil
    @State private var showTagErrorAlert: Bool = false
    @State private var tagPendingRemoval: String? = nil
    @State private var showRemoveTagConfirm: Bool = false

    private static let splitSpace = "tagSplit"

    public init(state: AppState) {
        self.state = state
    }

    private var activeTag: String? {
        guard let tag = state.selectedTag?.trimmingCharacters(in: .whitespacesAndNewlines), !tag.isEmpty else { return nil }
        return tag
    }

    private var tagSummaries: [TagSummary] {
        state.vault?.index.listTags() ?? []
    }

    private var totalEntitiesCount: Int {
        state.vault?.index.listAllEntities().count ?? 0
    }

    private var items: [EntityRef] {
        guard let v = state.vault else { return [] }
        if let activeTag { return v.index.findByTag(activeTag) }
        return v.index.listAllEntities()
    }

    public var body: some View {
        HStack(spacing: 0) {
            // Left Column: Tag List (resizable width)
            if !state.isTagListCollapsed {
                leftColumn
                    .frame(width: state.tagListWidth)
                    .background(Color(nsColor: .windowBackgroundColor).opacity(0.4))
                    .transition(.move(edge: .leading))

                // Resizer Divider
                dividerHandle
            }

            // Right Column: Tag Items List
            rightColumn
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .coordinateSpace(.named(Self.splitSpace))

        .alert("标签操作失败", isPresented: $showTagErrorAlert) {
            Button("确定", role: .cancel) {
                tagErrorMessage = nil
            }
        } message: {
            Text(tagErrorMessage ?? "无法完成标签操作")
        }
        .confirmationDialog("移除标签", isPresented: $showRemoveTagConfirm, presenting: tagPendingRemoval) { tag in
            Button("移除「#\(tag)」", role: .destructive) {
                removeTag(tag)
            }
            Button("取消", role: .cancel) {
                tagPendingRemoval = nil
            }
        } message: { tag in
            Text("将从所有任务和笔记中移除「#\(tag)」，此操作不可撤销。")
        }
    }

    // MARK: - Left Column (Tag List Sidebar)

    private var leftColumn: some View {
        let tags = tagSummaries

        return VStack(spacing: 0) {
            // Top Action Bar
            HStack {
                HStack(spacing: 6) {
                    Text("全部标签")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)

                    Text("\(tags.count)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Collapse sidebar button
                ListSidebarToggleButton(collapsed: false, listName: "标签列表") {
                    state.toggleTagList()
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            // Scrollable Tag List
            ScrollView {
                VStack(spacing: 2) {
                    // "全部" virtual entry
                    tagRow(
                        name: "全部",
                        count: totalEntitiesCount,
                        isSelected: activeTag == nil,
                        isAll: true
                    ) {
                        state.selectedTag = nil
                    }

                    if tags.isEmpty {
                        Text("暂无标签")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .italic()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(tags) { tag in
                            if editingTag == tag.name {
                                inlineRenameRow(name: tag.name)
                            } else {
                                tagRow(
                                    name: tag.name,
                                    count: tag.totalCount,
                                    isSelected: activeTag?.caseInsensitiveCompare(tag.name) == .orderedSame,
                                    isAll: false
                                ) {
                                    state.selectedTag = tag.name
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
        }
    }

    private func tagRow(
        name: String,
        count: Int,
        isSelected: Bool,
        isAll: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let isHovered = hoveredTag == name

        return HStack(spacing: 4) {
            Button(action: action) {
                HStack(spacing: 6) {
                    if !isAll {
                        Text("#")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(isSelected ? state.effectiveAccentColor : .secondary)
                    } else {
                        Image(systemName: "number")
                            .font(.system(size: 11))
                            .foregroundColor(isSelected ? state.effectiveAccentColor : .secondary)
                    }

                    Text(name)
                        .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                        .foregroundColor(isSelected ? .primary : Color(nsColor: .labelColor).opacity(0.85))
                        .lineLimit(1)

                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isHovered && !isAll {
                Menu {
                    Button("修改名称") {
                        startInlineRename(name)
                    }
                    Divider()
                    Button("复制标签名") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(name, forType: .string)
                    }
                    Divider()
                    Button("移除标签", role: .destructive) {
                        tagPendingRemoval = name
                        showRemoveTagConfirm = true
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary)
                        .frame(width: 18, height: 18)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.primary.opacity(0.08))
                        )
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("标签操作")
            } else {
                Text("\(count)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.stoneSelectedBg : (isHovered ? Color.primary.opacity(0.04) : Color.clear))
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering {
                hoveredTag = name
            } else if hoveredTag == name {
                hoveredTag = nil
            }
        }
    }

    private func inlineRenameRow(name: String) -> some View {
        HStack(spacing: 4) {
            Text("#")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(state.effectiveAccentColor)

            TextField("标签名称", text: $inlineTagName)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .focused($focusedTag, equals: name)
                .onSubmit {
                    commitInlineRename(from: name)
                }
                .onExitCommand {
                    cancelInlineRename()
                }

            Spacer(minLength: 2)

            Button(action: {
                commitInlineRename(from: name)
            }) {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(state.effectiveAccentColor)
                    .frame(width: 18, height: 18)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(state.effectiveAccentColor.opacity(0.12))
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("保存 (Enter)")

            Button(action: {
                cancelInlineRename()
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 18, height: 18)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.primary.opacity(0.06))
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("取消 (Esc)")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(state.effectiveAccentColor, lineWidth: 1.5)
        )
    }

    // MARK: - Resizer Divider Handle

    private var dividerHandle: some View {
        ResizableDivider(
            width: $state.tagListWidth,
            allowedWidth: 160...450,
            defaultWidth: 220,
            coordinateSpaceName: Self.splitSpace,
            accentColor: state.effectiveAccentColor,
            onCommit: state.savePreferences
        )
    }

    // MARK: - Right Column (Tag Items)

    private var rightColumn: some View {
        let items = self.items
        let counts = items.reduce(into: (task: 0, note: 0)) { acc, item in
            switch item.type {
            case .task: acc.task += 1
            case .note: acc.note += 1
            default: break
            }
        }

        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header with Tag Chip & Counts
                HStack(spacing: 8) {
                    if state.isTagListCollapsed {
                        ListSidebarToggleButton(collapsed: true, listName: "标签列表") {
                            state.toggleTagList()
                        }
                    }

                    activeTagDisplay

                    Text("共 \(items.count) 项（任务 \(counts.task) · 笔记 \(counts.note)）")
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
                        Text(activeTag == nil ? "暂无任务或笔记" : "该标签下暂无内容")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, minHeight: 200)
                    .background(RoundedRectangle(cornerRadius: 12).stroke(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 1))
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(items, id: \.id) { item in
                            if item.type == .task {
                                taskCard(item)
                            } else {
                                noteCard(item)
                            }
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .id(activeTag ?? "__all__")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var activeTagDisplay: some View {
        HStack(spacing: 6) {
            Image(systemName: "number")
            Text(activeTag ?? "全部").lineLimit(1)
                .frame(maxWidth: 220, alignment: .leading)
        }
        .font(.system(size: 14, weight: .semibold))
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.stoneTagBg))
        .foregroundColor(.emeraldColor)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.emeraldColor.opacity(0.3), lineWidth: 1))
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityLabel("当前标签")
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

    // MARK: - Inline Rename Tag Helpers

    private func startInlineRename(_ tag: String) {
        editingTag = tag
        inlineTagName = tag
        DispatchQueue.main.async {
            focusedTag = tag
        }
    }

    private func commitInlineRename(from oldTag: String) {
        let submittedName = inlineTagName
        NSApp.keyWindow?.makeFirstResponder(nil)

        let cleanOld = oldTag.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        let cleanNew = submittedName.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")

        guard !cleanNew.isEmpty else {
            tagErrorMessage = "标签名称不能为空"
            showTagErrorAlert = true
            return
        }

        if cleanOld == cleanNew {
            cancelInlineRename()
            return
        }

        do {
            try state.renameTag(from: cleanOld, to: cleanNew)
            cancelInlineRename()
        } catch {
            tagErrorMessage = error.localizedDescription
            showTagErrorAlert = true
        }
    }

    private func removeTag(_ tag: String) {
        defer { tagPendingRemoval = nil }
        do {
            try state.removeTag(named: tag)
        } catch {
            tagErrorMessage = error.localizedDescription
            showTagErrorAlert = true
        }
    }

    private func cancelInlineRename() {
        editingTag = nil
        inlineTagName = ""
        focusedTag = nil
    }
}
