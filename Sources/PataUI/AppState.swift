import SwiftUI
import AppKit
import PataCore
import PataKeychain
import PataAudio
import PataMCP

public enum NavigationItem: String, CaseIterable, Identifiable {
    case today = "Today"
    case tasks = "Tasks"
    case notes = "Notes"
    case tags = "Tags"

    public var id: String { rawValue }
    public var title: String { rawValue }
    public var icon: String {
        switch self {
        case .today: return "calendar"
        case .tasks: return "checkmark.square"
        case .notes: return "doc.text"
        case .tags: return "number"
        }
    }
}

@MainActor
public final class AppState: ObservableObject {
    public static let shared = AppState()

    // Navigation & Layout
    @Published public var currentNav: NavigationItem = .today
    @Published public var isSidebarVisible: Bool = true
    @Published public var showSettings: Bool = false
    @Published public var showSearch: Bool = false

    // Global Task Inspector
    @Published public var selectedTaskId: String?
    @Published public var isInspectorVisible: Bool = false
    @Published public var inspectorWidth: CGFloat = 400

    // Today Context
    @Published public var todayDateString: String = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }()

    // Notes Context
    @Published public var selectedNoteId: String?

    // Tag View Context
    @Published public var selectedTag: String?

    // Vault
    @Published public private(set) var vault: Vault?
    @Published public var vaultStatus: String = "未选择资料库"
    @Published public var vaultHealthErrors: [String] = []

    // MCP
    @Published public var mcpStatus: MCPStatus = MCPStatus()

    // Audio & Keychain
    @Published public var isASRConfigured: Bool = false

    // App Preferences
    @Published public var themePreference: String = "system" // "system", "light", "dark"
    @Published public var accentColorHex: String = ""

    private let configURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("pata")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("vault.json")
    }()

    public init() {
        loadPreferences()
        checkASRKey()
    }

    public func loadPreferences() {
        guard let data = try? Data(contentsOf: configURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        if let theme = json["theme"] as? String {
            self.themePreference = theme
        }
        if let accent = json["accent_color"] as? String {
            self.accentColorHex = accent
        }
        if let width = json["inspector_width"] as? CGFloat, width >= 280, width <= 720 {
            self.inspectorWidth = width
        }
        if let sidebar = json["is_sidebar_visible"] as? Bool {
            self.isSidebarVisible = sidebar
        }

        if let vPath = json["vault_path"] as? String, !vPath.isEmpty {
            openVault(path: vPath)
        }

        if let mcpEnabled = json["mcp_enabled"] as? Bool, mcpEnabled, let v = vault {
            try? MCPServer.shared.start(vault: v)
            self.mcpStatus = MCPServer.shared.getStatus()
        }
    }

    public func savePreferences() {
        var dict: [String: Any] = [
            "theme": themePreference,
            "accent_color": accentColorHex,
            "inspector_width": inspectorWidth,
            "is_sidebar_visible": isSidebarVisible,
            "mcp_enabled": mcpStatus.enabled
        ]
        if let v = vault {
            dict["vault_path"] = v.rootPath
        }

        if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted]) {
            try? data.write(to: configURL)
        }
    }

    public func toggleSidebar() {
        withAnimation(.easeInOut(duration: 0.2)) {
            self.isSidebarVisible.toggle()
        }
        self.savePreferences()
    }

    public func openVault(path: String) {
        do {
            let v = try Vault(rootPath: path)
            v.onEvent = { [weak self] _ in
                DispatchQueue.main.async {
                    self?.objectWillChange.send()
                }
            }
            v.startWatcher()
            self.vault = v
            self.vaultStatus = v.rootPath
            self.vaultHealthErrors = v.index.listParseErrors()
            MCPServer.shared.setVault(v)
            savePreferences()
        } catch {
            self.vaultStatus = "打开资料库失败: \(error.localizedDescription)"
        }
    }

    public func rescanVault() {
        guard let v = vault else { return }
        try? v.rescan()
        self.vaultHealthErrors = v.index.listParseErrors()
        objectWillChange.send()
    }

    public func checkASRKey() {
        if CommandLine.arguments.contains("--snapshot") {
            self.isASRConfigured = true
            return
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let key = try? DefaultKeychainStore.shared.get(
                service: ASRConstants.keychainService,
                account: ASRConstants.keychainAccount
            )
            DispatchQueue.main.async {
                self?.isASRConfigured = (key != nil && !(key?.isEmpty ?? true))
            }
        }
    }

    public func setASRKey(_ key: String) throws {
        try DefaultKeychainStore.shared.set(
            service: ASRConstants.keychainService,
            account: ASRConstants.keychainAccount,
            secret: key
        )
        checkASRKey()
    }

    // Inspector Control
    public func openTaskInspector(taskId: String) {
        self.selectedTaskId = taskId
        self.isInspectorVisible = true
    }

    public func closeTaskInspector() {
        self.isInspectorVisible = false
    }

    // Navigation Helper
    public func navigateToNote(noteId: String) {
        self.currentNav = .notes
        self.selectedNoteId = noteId
        self.showSearch = false
    }

    public func navigateToTask(taskId: String) {
        self.showSearch = false
        openTaskInspector(taskId: taskId)
    }

    public func navigateToTag(_ tag: String) {
        self.selectedTag = tag
        self.currentNav = .tags
        self.showSearch = false
    }
}
