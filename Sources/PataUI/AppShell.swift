import SwiftUI
import AppKit
import PataCore

public struct AppShell: View {
    @StateObject private var state = AppState.shared

    public init() {}

    private var preferredColorScheme: ColorScheme? {
        switch state.themePreference {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    private var topTags: [String] {
        guard let v = state.vault else { return ["架构设计", "Flink", "Doris", "POC", "复盘", "工作"] }
        let tags = v.index.listTags().map { $0.name }
        let preferred = ["架构设计", "Flink", "Doris", "POC", "复盘", "工作"]
        let ordered = preferred.filter { tags.contains($0) }
        let remaining = tags.filter { !preferred.contains($0) }
        let result = ordered + remaining
        return result.isEmpty ? preferred : result
    }

    public var body: some View {
        ZStack {
            if state.vault == nil {
                firstLaunchVaultPicker
            } else {
                HStack(spacing: 0) {
                    // Left: App Sidebar
                    if state.isSidebarVisible {
                        sidebarView
                            .frame(width: 230)
                            .background(Color(red: 245/255, green: 245/255, blue: 241/255))
                            .transition(.move(edge: .leading))

                        Rectangle()
                            .fill(Color(red: 233/255, green: 235/255, blue: 230/255))
                            .frame(width: 1)
                    }

                    // Middle: Active Workspace (with top breadcrumb bar)
                    VStack(spacing: 0) {
                        topWorkspaceBar

                        if state.showSettings {
                            SettingsView(state: state)
                        } else {
                            switch state.currentNav {
                            case .today:
                                TodayView(state: state)
                            case .tasks:
                                TasksView(state: state)
                            case .notes:
                                NotesView(state: state)
                            case .tags:
                                TagView(state: state)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(red: 250/255, green: 250/255, blue: 248/255))

                    // Right: Global Task Inspector
                    if state.isInspectorVisible, let taskId = state.selectedTaskId, !state.showSettings {
                        inspectorDivider

                        TaskInspector(state: state, taskId: taskId)
                            .frame(width: state.inspectorWidth)
                            .transition(.move(edge: .trailing))
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: state.isSidebarVisible)
            }

            // Floating Search Overlay (⌘K)
            if state.showSearch {
                SearchOverlay(state: state)
            }
        }
        .preferredColorScheme(preferredColorScheme)
        .frame(minWidth: 1000, minHeight: 650)
    }

    // MARK: - Top Workspace Breadcrumb Bar (Matches prototype 66px)

    private var topWorkspaceBar: some View {
        HStack(spacing: 12) {
            // Collapsed toggle button if sidebar hidden
            if !state.isSidebarVisible {
                Button(action: { state.toggleSidebar() }) {
                    Image(systemName: "sidebar.leading")
                        .font(.system(size: 13))
                        .foregroundColor(Color(red: 125/255, green: 136/255, blue: 123/255))
                        .padding(4)
                }
                .buttonStyle(.plain)
                .help("展开侧栏 (⌃⌘S)")
            }

            // Breadcrumb: 工作空间 / Navigation Title
            HStack(spacing: 8) {
                Text("工作空间")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(red: 69/255, green: 77/255, blue: 69/255))

                Text("/")
                    .font(.system(size: 12))
                    .foregroundColor(Color(red: 139/255, green: 147/255, blue: 137/255))

                if state.showSettings {
                    Text("偏好设置")
                        .font(.system(size: 12))
                        .foregroundColor(Color(red: 139/255, green: 147/255, blue: 137/255))
                } else if state.currentNav == .notes, let nid = state.selectedNoteId, let note = state.vault?.index.getNote(nid) {
                    Text("Notes")
                        .font(.system(size: 12))
                        .foregroundColor(Color(red: 139/255, green: 147/255, blue: 137/255))
                    Text("/")
                        .font(.system(size: 12))
                        .foregroundColor(Color(red: 139/255, green: 147/255, blue: 137/255))
                    Text(note.title)
                        .font(.system(size: 12))
                        .foregroundColor(Color(red: 139/255, green: 147/255, blue: 137/255))
                } else {
                    Text(state.currentNav.title)
                        .font(.system(size: 12))
                        .foregroundColor(Color(red: 139/255, green: 147/255, blue: 137/255))
                }
            }

            Spacer()

            // Right: Prototype badge + Search button + ⌘K + Settings
            HStack(spacing: 16) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(red: 120/255, green: 164/255, blue: 137/255))
                        .frame(width: 6, height: 6)
                    Text("仅 UI 原型")
                        .font(.system(size: 11))
                        .foregroundColor(Color(red: 139/255, green: 147/255, blue: 137/255))
                }

                Button(action: { state.showSearch = true }) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14))
                        .foregroundColor(Color(red: 125/255, green: 136/255, blue: 123/255))
                }
                .buttonStyle(.plain)

                Button(action: { state.showSearch = true }) {
                    Text("⌘ K")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundColor(Color(red: 155/255, green: 162/255, blue: 153/255))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color(red: 226/255, green: 231/255, blue: 223/255), lineWidth: 1))
                }
                .buttonStyle(.plain)

                Button(action: { state.showSettings.toggle() }) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13))
                        .foregroundColor(Color(red: 125/255, green: 136/255, blue: 123/255))
                }
                .buttonStyle(.plain)
                .help("偏好设置 (⌘,)")
            }
        }
        .padding(.horizontal, 50)
        .frame(height: 66)
        .background(Color(red: 250/255, green: 250/255, blue: 248/255).opacity(0.89))
        .overlay(
            Rectangle()
                .fill(Color(red: 238/255, green: 240/255, blue: 234/255))
                .frame(height: 1),
            alignment: .bottom
        )
    }

    // MARK: - Sidebar View (Matches old_today.png)

    private var sidebarView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Brand Logo & Titles
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(red: 71/255, green: 112/255, blue: 91/255))
                        .frame(width: 36, height: 36)
                        .shadow(color: Color(red: 71/255, green: 112/255, blue: 91/255).opacity(0.15), radius: 5, x: 0, y: 4)

                    Text("啪")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text("啪嗒")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(Color(red: 36/255, green: 40/255, blue: 36/255))

                        Text("PATA")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Color(red: 130/255, green: 137/255, blue: 128/255))
                    }

                    Text("记下一点，完成一件")
                        .font(.system(size: 10))
                        .foregroundColor(Color(red: 130/255, green: 137/255, blue: 128/255))
                }

                Spacer()
            }
            .padding(.horizontal, 17)
            .padding(.top, 29)
            .padding(.bottom, 34)

            // Primary Navigations
            VStack(spacing: 5) {
                sidebarNavButton(title: "Today", icon: "sun.max", nav: .today)
                sidebarNavButton(title: "Tasks", icon: "checklist", nav: .tasks)
                sidebarNavButton(title: "Notes", icon: "doc.text", nav: .notes)
            }
            .padding(.horizontal, 17)

            // Divider Separator
            Rectangle()
                .fill(Color(red: 230/255, green: 233/255, blue: 226/255))
                .frame(height: 1)
                .padding(.horizontal, 24)
                .padding(.top, 25)
                .padding(.bottom, 17)

            // Section: 标签 · LABELS
            VStack(alignment: .leading, spacing: 4) {
                Text("标签 · LABELS")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Color(red: 156/255, green: 163/255, blue: 153/255))
                    .tracking(1.0)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)

                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(topTags, id: \.self) { tag in
                            let isSelected = state.currentNav == .tags && state.selectedTag == tag
                            Button(action: {
                                state.showSettings = false
                                state.selectedTag = tag
                                state.currentNav = .tags
                            }) {
                                HStack {
                                    Text("# \(tag)")
                                        .font(.system(size: 12, weight: isSelected ? .bold : .regular))
                                        .foregroundColor(isSelected ? Color(red: 44/255, green: 88/255, blue: 64/255) : Color(red: 112/255, green: 123/255, blue: 111/255))
                                    Spacer()
                                }
                                .padding(.horizontal, 24)
                                .padding(.vertical, 7)
                                .background(
                                    isSelected ?
                                    RoundedRectangle(cornerRadius: 8).fill(Color(red: 228/255, green: 236/255, blue: 227/255)).padding(.horizontal, 12) :
                                    RoundedRectangle(cornerRadius: 8).fill(Color.clear).padding(.horizontal, 12)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            Spacer()

            // Footer
            VStack(alignment: .leading, spacing: 4) {
                Rectangle()
                    .fill(Color(red: 230/255, green: 233/255, blue: 226/255))
                    .frame(height: 1)
                    .padding(.bottom, 12)

                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(red: 120/255, green: 164/255, blue: 137/255))
                        .frame(width: 6, height: 6)
                    Text("本地 Markdown 工作空间")
                        .font(.system(size: 11))
                        .foregroundColor(Color(red: 154/255, green: 163/255, blue: 152/255))
                }

                Text("Less is More · 设计原型")
                    .font(.system(size: 11))
                    .foregroundColor(Color(red: 154/255, green: 163/255, blue: 152/255))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
    }

    private func sidebarNavButton(title: String, icon: String, nav: NavigationItem) -> some View {
        let isSelected = state.currentNav == nav && !state.showSettings

        return Button(action: {
            state.showSettings = false
            state.currentNav = nav
            if nav == .notes {
                state.selectedNoteId = nil
            }
        }) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(isSelected ? Color(red: 61/255, green: 113/255, blue: 82/255) : Color(red: 119/255, green: 131/255, blue: 117/255))
                    .frame(width: 18)

                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                    .foregroundColor(isSelected ? Color(red: 44/255, green: 88/255, blue: 64/255) : Color(red: 97/255, green: 106/255, blue: 96/255))

                Spacer()
            }
            .padding(.vertical, 9)
            .padding(.horizontal, 12)
            .background(
                isSelected ?
                RoundedRectangle(cornerRadius: 9).fill(Color(red: 228/255, green: 236/255, blue: 227/255)) :
                RoundedRectangle(cornerRadius: 9).fill(Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Inspector Resize Divider

    private var inspectorDivider: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(width: 1)
            .overlay(
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 7)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture()
                            .onChanged { val in
                                let newW = state.inspectorWidth - val.translation.width
                                state.inspectorWidth = min(max(newW, 280), 720)
                            }
                    )
            )
    }

    // MARK: - First Launch Vault Picker

    private var firstLaunchVaultPicker: some View {
        VStack(spacing: 20) {
            Image(systemName: "folder.badge.gearshape")
                .font(.system(size: 48))
                .foregroundColor(Color(red: 71/255, green: 112/255, blue: 91/255))

            VStack(spacing: 6) {
                Text("欢迎使用 啪嗒 / Pata")
                    .font(.system(size: 20, weight: .bold))

                Text("Pata 是纯本地优先（Local First）的任务与笔记系统。\n所有数据存储在本地纯 Markdown 文件中，请选择您的存储目录（Vault）。")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button(action: selectVaultFolder) {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                    Text("选择本地存储目录")
                }
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(red: 71/255, green: 112/255, blue: 91/255)))
                .foregroundColor(.white)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 250/255, green: 250/255, blue: 248/255))
    }

    private func selectVaultFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "选定此目录作为 Vault"

        if panel.runModal() == .OK, let url = panel.url {
            state.openVault(path: url.path)
        }
    }
}
