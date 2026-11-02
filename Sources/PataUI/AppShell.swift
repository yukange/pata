import SwiftUI
import AppKit
import PataCore

public struct WindowDragArea: NSViewRepresentable {
    public init() {}
    public func makeNSView(context: Context) -> WindowDragView {
        WindowDragView()
    }
    public func updateNSView(_ nsView: WindowDragView, context: Context) {}
}

public class WindowDragView: NSView {
    public override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            window?.zoom(nil)
        } else {
            window?.performDrag(with: event)
        }
    }
}

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

    private var windowBg: Color {
        switch state.themePreference {
        case "dark": return Color(red: 12/255, green: 10/255, blue: 9/255)
        default: return Color(red: 245/255, green: 245/255, blue: 244/255)
        }
    }

    private var currentThemeBg: Color {
        islandBg
    }

    private var islandBg: Color {
        switch state.themePreference {
        case "dark": return Color(red: 28/255, green: 25/255, blue: 23/255)
        default: return Color(red: 250/255, green: 250/255, blue: 248/255)
        }
    }

    private var sidebarBg: Color {
        switch state.themePreference {
        case "dark": return Color(red: 12/255, green: 10/255, blue: 9/255).opacity(0.85)
        default: return Color(red: 245/255, green: 245/255, blue: 244/255).opacity(0.85)
        }
    }

    private var borderColor: Color {
        switch state.themePreference {
        case "dark": return Color(red: 41/255, green: 37/255, blue: 36/255)
        default: return Color(red: 231/255, green: 229/255, blue: 228/255)
        }
    }

    private var allTagsWithCounts: [(tag: String, count: Int)] {
        guard let v = state.vault else { return [] }
        return v.index.listTags().map { t in
            let c = v.index.findByTag(t.name).count
            return (tag: t.name, count: c)
        }.sorted { $0.tag.localizedStandardCompare($1.tag) == .orderedAscending }
    }

    public var body: some View {
        ZStack {
            if state.vault == nil {
                firstLaunchVaultPicker
            } else {
                VStack(spacing: 0) {
                    // When sidebar is collapsed: Top Header Strip across the whole window
                    if !state.isSidebarVisible {
                        collapsedTopHeader
                    }

                    // Main Row: Sidebar (when expanded) + Island Main Content
                    HStack(alignment: .top, spacing: 0) {
                        if state.isSidebarVisible {
                            expandedSidebar
                                .frame(width: 240)
                                .frame(maxHeight: .infinity)
                                .background(sidebarBg)
                                .transition(.move(edge: .leading))
                        }

                        // Right: Island (岛屿风格主工作区)
                        islandMainContent
                            .padding(.trailing, 8)
                            .padding(.top, state.isSidebarVisible ? 8 : 0)
                            .padding(.bottom, 8)
                            .padding(.leading, state.isSidebarVisible ? 0 : 8)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .background(windowBg)
            }

            // Floating Search Overlay (⌘K / ⌘P)
            if state.showSearch {
                SearchOverlay(state: state)
            }

            // Keyboard shortcut fallback for ⌘K and ⌘P
            Group {
                Button(action: { state.toggleSearch() }) {
                    EmptyView()
                }
                .keyboardShortcut("k", modifiers: .command)

                Button(action: { state.toggleSearch() }) {
                    EmptyView()
                }
                .keyboardShortcut("p", modifiers: .command)
            }
            .opacity(0)
            .allowsHitTesting(false)
            .frame(width: 0, height: 0)
        }
        .tint(state.effectiveAccentColor)
        .accentColor(state.effectiveAccentColor)
        .preferredColorScheme(preferredColorScheme)
        .frame(minWidth: 1000, minHeight: 650)
        .ignoresSafeArea()
        .onAppear {
            LogoAnimationCoordinator.shared.playLaunch()
        }
    }

    private var islandMainContent: some View {
        HStack(spacing: 0) {
            // Main Workspace View
            VStack(spacing: 0) {
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

            // Right: Global Task Inspector (inside the island)
            if state.isInspectorVisible, let taskId = state.selectedTaskId, !state.showSettings {
                Rectangle()
                    .fill(borderColor)
                    .frame(width: 1)

                TaskInspector(state: state, taskId: taskId)
                    .frame(width: state.inspectorWidth)
                    .background(islandBg)
                    .transition(.move(edge: .trailing))
            }
        }
        .background(islandBg)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 1)
    }

    private var collapsedTopHeader: some View {
        HStack(spacing: 0) {
            // Left: Traffic lights clearance (86px) -> Logo -> "Pata" -> Expand sidebar button
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    PataLogoView()

                    Text("Pata")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .offset(y: -0.5)

                SidebarToggleButton(collapsed: true) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        state.toggleSidebar()
                    }
                }
            }
            .padding(.leading, 86)

            Spacer()

            // Center: Segmented Navigation Tabs
            HStack(spacing: 4) {
                TopNavTabButton(title: "Today", icon: "calendar", accentColor: state.effectiveAccentColor, isSelected: !state.showSettings && state.currentNav == .today) {
                    state.showSettings = false
                    state.currentNav = .today
                }
                TopNavTabButton(title: "Tasks", icon: "checkmark.square", accentColor: state.effectiveAccentColor, isSelected: !state.showSettings && state.currentNav == .tasks) {
                    state.showSettings = false
                    state.currentNav = .tasks
                }
                TopNavTabButton(title: "Notes", icon: "doc.text", accentColor: state.effectiveAccentColor, isSelected: !state.showSettings && state.currentNav == .notes) {
                    state.showSettings = false
                    state.currentNav = .notes
                }
                TopNavTabButton(title: "Tags", icon: "number", accentColor: state.effectiveAccentColor, isSelected: !state.showSettings && state.currentNav == .tags) {
                    state.showSettings = false
                    state.currentNav = .tags
                }
            }

            Spacer()

            // Right: Search & Settings
            HStack(spacing: 8) {
                SearchHeaderButton(borderColor: borderColor) {
                    state.toggleSearch()
                }

                SettingsHeaderButton(accentColor: state.effectiveAccentColor, showSettings: state.showSettings) {
                    state.showSettings.toggle()
                }
            }
            .padding(.trailing, 16)
        }
        .frame(height: 38)
        .background(WindowDragArea())
    }

    // MARK: - Expanded Sidebar (240px wide)

    private var expandedSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top Header: Traffic Lights clearance (86px) + Logo + Title + Collapse Button
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    PataLogoView()

                    Text("Pata")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .offset(y: -0.5)

                Spacer()

                SidebarToggleButton(collapsed: false) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        state.toggleSidebar()
                    }
                }
            }
            .padding(.leading, 86)
            .padding(.trailing, 12)
            .frame(height: 38)
            .background(WindowDragArea())

            // Search Bar Button in sidebar
            Button(action: { state.toggleSearch() }) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Text("搜索")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)

                    Spacer()

                    Text("⌘K/⌘P")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 3).fill(Color.primary.opacity(0.06)))
                }
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.03)))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(borderColor, lineWidth: 1))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 6)

            // Navigation Items
            VStack(spacing: 2) {
                SidebarNavRowButton(title: "Today", icon: "calendar", accentColor: state.effectiveAccentColor, isSelected: !state.showSettings && state.currentNav == .today) {
                    state.showSettings = false
                    state.currentNav = .today
                }
                SidebarNavRowButton(title: "Tasks", icon: "checkmark.square", accentColor: state.effectiveAccentColor, isSelected: !state.showSettings && state.currentNav == .tasks) {
                    state.showSettings = false
                    state.currentNav = .tasks
                }
                SidebarNavRowButton(title: "Notes", icon: "doc.text", accentColor: state.effectiveAccentColor, isSelected: !state.showSettings && state.currentNav == .notes) {
                    state.showSettings = false
                    state.currentNav = .notes
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)

            // Global Tags Section
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("全局标签")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(allTagsWithCounts.count)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.top, 16)
                .padding(.bottom, 4)

                ScrollView {
                    VStack(spacing: 1) {
                        // All virtual tag
                        SidebarTagRowButton(
                            tag: "全部",
                            count: nil,
                            isSelected: !state.showSettings && state.currentNav == .tags && state.selectedTag == nil
                        ) {
                            state.showSettings = false
                            state.currentNav = .tags
                            state.selectedTag = nil
                        }

                        ForEach(allTagsWithCounts, id: \.tag) { item in
                            SidebarTagRowButton(
                                tag: item.tag,
                                count: item.count,
                                isSelected: !state.showSettings && state.currentNav == .tags && state.selectedTag?.caseInsensitiveCompare(item.tag) == .orderedSame
                            ) {
                                state.showSettings = false
                                state.currentNav = .tags
                                state.selectedTag = item.tag
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }

            Spacer()

            // Bottom Settings Row
            Rectangle()
                .fill(borderColor)
                .frame(height: 1)

            SidebarBottomSettingsButton(accentColor: state.effectiveAccentColor, isSelected: state.showSettings) {
                state.showSettings = true
            }
        }
    }

    // MARK: - First Launch Vault Picker

    private var firstLaunchVaultPicker: some View {
        VStack(spacing: 20) {
            Image(systemName: "folder.badge.gearshape")
                .font(.system(size: 48))
                .foregroundColor(Color.accentColor)

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
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor))
                .foregroundColor(.white)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(currentThemeBg)
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

// MARK: - Header & Sidebar Sub-Components with Complete Hit-Testing & Hover Feedback

public struct SidebarToggleButton: View {
    let collapsed: Bool
    let action: () -> Void
    @State private var isHovered = false

    public init(collapsed: Bool, action: @escaping () -> Void) {
        self.collapsed = collapsed
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 5)
                    .fill(isHovered ? Color.primary.opacity(0.08) : Color.black.opacity(0.0001))
                    .frame(width: 24, height: 24)

                ZStack {
                    RoundedRectangle(cornerRadius: 2.25)
                        .stroke(Color.secondary, lineWidth: 1.25)
                        .frame(width: 14, height: 11)

                    Rectangle()
                        .fill(Color.secondary)
                        .frame(width: 1.25, height: 11)
                        .offset(x: -2)

                    if !collapsed {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.3))
                            .frame(width: 3.5, height: 9)
                            .offset(x: -4)
                    }
                }
            }
            .frame(width: 24, height: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .help(collapsed ? "展开侧栏 (⌃⌘S)" : "收起侧栏 (⌃⌘S)")
    }
}

struct TopNavTabButton: View {
    let title: String
    let icon: String
    let accentColor: Color
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .foregroundColor(isSelected ? accentColor.onAccent : .secondary)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? accentColor : (isHovered ? Color.primary.opacity(0.04) : Color.black.opacity(0.0001)))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

struct SearchHeaderButton: View {
    let borderColor: Color
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Text("搜索")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)

                Spacer()

                Text("⌘K/⌘P")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: 3).fill(Color.primary.opacity(0.06)))
            }
            .padding(.horizontal, 10)
            .frame(width: 176, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color.primary.opacity(0.06) : Color.primary.opacity(0.03))
            )
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(borderColor, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

struct SettingsHeaderButton: View {
    let accentColor: Color
    let showSettings: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "gearshape")
                .font(.system(size: 13))
                .foregroundColor(showSettings ? accentColor.onAccent : .secondary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(showSettings ? accentColor : (isHovered ? Color.primary.opacity(0.08) : Color.black.opacity(0.0001)))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .help("设置 (⌘,)")
    }
}

struct SidebarNavRowButton: View {
    let title: String
    let icon: String
    let accentColor: Color
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                Spacer()
            }
            .foregroundColor(isSelected ? accentColor.onAccent : .secondary)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? accentColor : (isHovered ? Color.primary.opacity(0.04) : Color.black.opacity(0.0001)))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

struct SidebarTagRowButton: View {
    let tag: String
    let count: Int?
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text("#")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Text(tag)
                    .font(.system(size: 13))
                    .foregroundColor(isSelected ? .primary : .secondary)
                Spacer()
                if let c = count {
                    Text("\(c)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.primary.opacity(0.08) : (isHovered ? Color.primary.opacity(0.04) : Color.black.opacity(0.0001)))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

struct SidebarBottomSettingsButton: View {
    let accentColor: Color
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "gearshape")
                    .font(.system(size: 13))
                Text("设置")
                    .font(.system(size: 13))
                Spacer()
            }
            .foregroundColor(isSelected ? accentColor.onAccent : .secondary)
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(isSelected ? accentColor : (isHovered ? Color.primary.opacity(0.04) : Color.black.opacity(0.0001)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
