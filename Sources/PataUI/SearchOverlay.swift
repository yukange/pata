import SwiftUI
import AppKit
import PataCore

public struct SearchOverlay: View {
    @ObservedObject var state: AppState
    @State private var query: String = ""
    @FocusState private var isFieldFocused: Bool
    @State private var selectedIndex: Int = 0

    public init(state: AppState) {
        self.state = state
    }

    private var allResults: [EntityRef] {
        guard let v = state.vault, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        return v.index.searchAll(query)
    }

    private var tasks: [EntityRef] {
        allResults.filter { $0.type == .task }
    }

    private var notes: [EntityRef] {
        allResults.filter { $0.type == .note }
    }

    private var activities: [EntityRef] {
        allResults.filter { $0.type == .activity }
    }

    private var files: [EntityRef] {
        allResults.filter { $0.type == .file }
    }

    public var body: some View {
        ZStack {
            // Backdrop
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    state.showSearch = false
                }

            // Modal Container (560px)
            VStack(spacing: 0) {
                // Header Input Bar
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)

                    TextField("搜索任务、笔记、记录或文件...", text: $query)
                        .font(.system(size: 14))
                        .textFieldStyle(.plain)
                        .focused($isFieldFocused)

                    if !query.isEmpty {
                        Button(action: { query = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    Button("取消") {
                        state.showSearch = false
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)

                Divider()

                // Content Area
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    // Empty Query Guidance
                    VStack(spacing: 8) {
                        Spacer()
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 28))
                            .foregroundColor(.secondary.opacity(0.3))

                        Text("输入关键词跨类型快速搜索")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.primary)

                        Text("支持搜索任务、笔记、记录正文及附件文件名")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .frame(height: 220)
                } else if allResults.isEmpty {
                    // No Results Found
                    VStack(spacing: 6) {
                        Spacer()
                        Text("未找到相关内容")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.primary)
                        Text("尝试更换搜索关键词")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .frame(height: 180)
                } else {
                    // Grouped Search Results
                    ScrollView {
                        VStack(spacing: 12) {
                            // Tasks Section
                            if !tasks.isEmpty {
                                resultSection(title: "任务", count: tasks.count, icon: "checkmark.square", iconColor: Color(red: 4/255, green: 120/255, blue: 87/255)) {
                                    ForEach(tasks.prefix(5), id: \.id) { task in
                                        resultRow(task, icon: "checkmark.square", iconColor: Color(red: 4/255, green: 120/255, blue: 87/255)) {
                                            state.showSearch = false
                                            state.selectedTaskId = task.id
                                        }
                                    }
                                }
                            }

                            // Notes Section
                            if !notes.isEmpty {
                                resultSection(title: "笔记", count: notes.count, icon: "doc.text", iconColor: .blue) {
                                    ForEach(notes.prefix(5), id: \.id) { note in
                                        resultRow(note, icon: "doc.text", iconColor: .blue) {
                                            state.showSearch = false
                                            state.currentNav = .notes
                                            state.selectedNoteId = note.id
                                        }
                                    }
                                }
                            }

                            // Activities Section
                            if !activities.isEmpty {
                                resultSection(title: "记录", count: activities.count, icon: "bubble.left", iconColor: .orange) {
                                    ForEach(activities.prefix(5), id: \.id) { act in
                                        resultRow(act, icon: "bubble.left", iconColor: .orange) {
                                            state.showSearch = false
                                            if let tid = act.taskId {
                                                state.selectedTaskId = tid
                                            }
                                        }
                                    }
                                }
                            }

                            // Files Section
                            if !files.isEmpty {
                                resultSection(title: "文件资源", count: files.count, icon: "paperclip", iconColor: .blue) {
                                    ForEach(files.prefix(5), id: \.id) { file in
                                        resultRow(file, icon: "paperclip", iconColor: .blue) {
                                            state.showSearch = false
                                            if let root = state.vault?.rootPath {
                                                let fullPath = (root as NSString).appendingPathComponent(file.path)
                                                NSWorkspace.shared.selectFile(fullPath, inFileViewerRootedAtPath: root)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .frame(maxHeight: 340)
                }

                Divider()

                // Footer Bar
                HStack(spacing: 16) {
                    HStack(spacing: 4) {
                        Text("↑")
                            .font(.system(size: 10, design: .monospaced))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: 3).fill(Color.stoneBadgeBg))
                        Text("↓")
                            .font(.system(size: 10, design: .monospaced))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: 3).fill(Color.stoneBadgeBg))
                        Text("选择")
                            .font(.system(size: 11))
                    }

                    HStack(spacing: 4) {
                        Text("↵")
                            .font(.system(size: 10, design: .monospaced))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: 3).fill(Color.stoneBadgeBg))
                        Text("打开")
                            .font(.system(size: 11))
                    }

                    HStack(spacing: 4) {
                        Text("ESC")
                            .font(.system(size: 9, design: .monospaced))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: 3).fill(Color.stoneBadgeBg))
                        Text("关闭")
                            .font(.system(size: 11))
                    }

                    Spacer()
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.stoneBadgeBg.opacity(0.5))
            }
            .frame(width: 560)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(nsColor: .separatorColor).opacity(0.7), lineWidth: 1))
            .shadow(color: Color.black.opacity(0.2), radius: 24, x: 0, y: 12)
        }
        .onAppear {
            isFieldFocused = true
        }
    }

    private func resultSection<Content: View>(title: String, count: Int, icon: String, iconColor: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            // Section Header
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: icon)
                        .font(.system(size: 11))
                        .foregroundColor(iconColor)
                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(.secondary)

                Spacer()

                Text("共 \(count) 条")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .background(Color.stoneBadgeBg.opacity(0.6))

            // Section Items
            VStack(spacing: 1) {
                content()
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        }
    }

    private func resultRow(_ item: EntityRef, icon: String, iconColor: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(iconColor)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title ?? (item.snippet ?? "(空内容)"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    if let snippet = item.snippet, !snippet.isEmpty, item.title != nil {
                        Text(snippet)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Text("↵ 打开")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.8))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.clear))
        }
        .buttonStyle(.plain)
    }
}
