import SwiftUI
import AppKit
import PataCore

public struct SearchOverlay: View {
    @Environment(\.colorScheme) private var colorScheme
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

    static func displayedResults(_ results: [EntityRef]) -> [EntityRef] {
        [EntityType.task, .note, .activity, .file].flatMap { type in
            results.filter { $0.type == type }.prefix(5)
        }
    }

    private var isDarkMode: Bool {
        if state.themePreference == "dark" {
            return true
        } else if state.themePreference == "light" {
            return false
        }
        return colorScheme == .dark
    }

    private var modalBackground: Color {
        isDarkMode ? Color(red: 28/255, green: 25/255, blue: 23/255) : Color.white
    }

    public var body: some View {
        let results = allResults
        let displayedResults = Self.displayedResults(results)
        let selectedID = displayedResults.indices.contains(selectedIndex) ? displayedResults[selectedIndex].id : nil
        let tasks = results.filter { $0.type == .task }
        let notes = results.filter { $0.type == .note }
        let activities = results.filter { $0.type == .activity }
        let files = results.filter { $0.type == .file }

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
                        .onKeyPress(keys: [.upArrow, .downArrow], phases: [.down, .repeat]) { press in
                            guard !displayedResults.isEmpty,
                                  press.modifiers.intersection([.command, .control, .option, .shift]).isEmpty,
                                  (NSApp.keyWindow?.firstResponder as? NSTextView)?.hasMarkedText() != true else {
                                return .ignored
                            }
                            selectedIndex = min(max(selectedIndex + (press.key == .downArrow ? 1 : -1), 0), displayedResults.count - 1)
                            return .handled
                        }
                        .onSubmit {
                            if displayedResults.indices.contains(selectedIndex) {
                                state.openSearchResult(displayedResults[selectedIndex])
                            }
                        }

                    if !query.isEmpty {
                        Button(action: { query = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    Button("取消") {
                        state.toggleSearch()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 13))
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
                } else if results.isEmpty {
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
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(spacing: 12) {
                                // Tasks Section
                                if !tasks.isEmpty {
                                    resultSection(title: "任务", count: tasks.count, icon: "checkmark.square", iconColor: Color(red: 4/255, green: 120/255, blue: 87/255)) {
                                        ForEach(displayedResults.filter { $0.type == .task }) { task in
                                            resultRow(task, icon: "checkmark.square", iconColor: Color(red: 4/255, green: 120/255, blue: 87/255), isSelected: task.id == selectedID)
                                        }
                                    }
                                }

                                // Notes Section
                                if !notes.isEmpty {
                                    resultSection(title: "笔记", count: notes.count, icon: "doc.text", iconColor: .blue) {
                                        ForEach(displayedResults.filter { $0.type == .note }) { note in
                                            resultRow(note, icon: "doc.text", iconColor: .blue, isSelected: note.id == selectedID)
                                        }
                                    }
                                }

                                // Activities Section
                                if !activities.isEmpty {
                                    resultSection(title: "记录", count: activities.count, icon: "bubble.left", iconColor: .orange) {
                                        ForEach(displayedResults.filter { $0.type == .activity }) { act in
                                            resultRow(act, icon: "bubble.left", iconColor: .orange, isSelected: act.id == selectedID)
                                        }
                                    }
                                }

                                // Files Section
                                if !files.isEmpty {
                                    resultSection(title: "文件资源", count: files.count, icon: "paperclip", iconColor: .blue) {
                                        ForEach(displayedResults.filter { $0.type == .file }) { file in
                                            resultRow(file, icon: "paperclip", iconColor: .blue, isSelected: file.id == selectedID)
                                        }
                                    }
                                }
                            }
                            .padding(.vertical, 8)
                        }
                        .frame(maxHeight: 340)
                        .onChange(of: selectedIndex) {
                            if let id = displayedResults.indices.contains(selectedIndex) ? displayedResults[selectedIndex].id : nil {
                                proxy.scrollTo(id, anchor: .center)
                            }
                        }
                    }
                }

                Divider()

                // Footer Bar
                HStack(spacing: 16) {
                    HStack(spacing: 4) {
                        Text("↑")
                            .font(.system(size: 11, design: .monospaced))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: 3).fill(Color.stoneBadgeBg))
                        Text("↓")
                            .font(.system(size: 11, design: .monospaced))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: 3).fill(Color.stoneBadgeBg))
                        Text("选择")
                            .font(.system(size: 11))
                    }

                    HStack(spacing: 4) {
                        Text("↵")
                            .font(.system(size: 11, design: .monospaced))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: 3).fill(Color.stoneBadgeBg))
                        Text("打开")
                            .font(.system(size: 11))
                    }

                    HStack(spacing: 4) {
                        Text("ESC")
                            .font(.system(size: 11, design: .monospaced))
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
            .background(RoundedRectangle(cornerRadius: 12).fill(modalBackground))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(nsColor: .separatorColor).opacity(0.7), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: Color.black.opacity(isDarkMode ? 0.35 : 0.2), radius: 24, x: 0, y: 12)
        }
        .onAppear {
            DispatchQueue.main.async {
                isFieldFocused = true
            }
        }
        .onChange(of: query) { selectedIndex = 0 }
        .onChange(of: displayedResults.map(\.id)) {
            selectedIndex = min(selectedIndex, max(0, displayedResults.count - 1))
        }
        .onExitCommand {
            state.showSearch = false
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

    private func resultRow(_ item: EntityRef, icon: String, iconColor: Color, isSelected: Bool) -> some View {
        Button(action: { state.openSearchResult(item) }) {
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
            .background(RoundedRectangle(cornerRadius: 6).fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear))
        }
        .buttonStyle(.plain)
        .id(item.id)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
