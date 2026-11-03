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
    @Published public var currentNav: NavigationItem = .today {
        didSet {
            if oldValue == .notes, currentNav != .notes, !noteEditor.save() { currentNav = oldValue }
        }
    }
    @Published public var isSidebarVisible: Bool = true
    @Published public var showSettings: Bool = false {
        didSet { if showSettings, !noteEditor.save() { showSettings = false } }
    }
    @Published public var showSearch: Bool = false

    // Global Task Inspector
    @Published public var selectedTaskId: String?
    @Published public var isInspectorVisible: Bool = false
    @Published public var inspectorWidth: CGFloat = 400

    // Today Context
    public static func currentDateString() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    /// 记录最近一次已知的实际今天日期，用于判断跨天前用户是否停留在“今日”
    public var lastKnownTodayDateString: String = AppState.currentDateString()

    @Published public var todayDateString: String = AppState.currentDateString()

    // Notes Context
    public let noteEditor = NoteEditingSession()
    @Published private var noteSelection: String?
    public var selectedNoteId: String? {
        get { noteSelection }
        set {
            guard newValue != noteSelection else { return }
            let selected = newValue.flatMap { vault?.index.getNote($0) }
            guard noteEditor.select(selected, in: vault) else { return }
            noteSelection = newValue
        }
    }
    @Published public var notesListWidth: CGFloat = 280
    @Published public var isNotesListCollapsed: Bool = false

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

    /// 当前生效的主题强调色（若未指定或跟随系统则返回系统强调色）
    public var effectiveAccentColor: Color {
        let clean = accentColorHex.trimmingCharacters(in: .whitespacesAndNewlines)
        if !clean.isEmpty, let c = Color(hex: clean) {
            return c
        }
        return Color(nsColor: .controlAccentColor)
    }

    /// 当前生效的主题强调色对应的高对比前景文字颜色（自动计算 AA 级对比度）
    public var effectiveAccentOnColor: Color {
        effectiveAccentColor.onAccent
    }

    /// 用户显式自定义或选定的强调色（若跟随系统则为 nil）
    public var customAccentColor: Color? {
        let clean = accentColorHex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }
        return Color(hex: clean)
    }

    private let configURL: URL = {
        if CommandLine.arguments.contains("--snapshot") {
            return URL(fileURLWithPath: "/tmp/pata_snapshot_vault.json")
        }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("pata")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("vault.json")
    }()
    private var savePreferencesWorkItem: DispatchWorkItem? = nil
    private let preferencesSaveQueue = DispatchQueue(label: "com.pata.preferences-io", qos: .utility)

    public init(loadPreferences: Bool = true, watchDayRollover: Bool = true) {
        MCPServer.shared.onStatusChange = { [weak self] status in
            DispatchQueue.main.async {
                self?.mcpStatus = status
            }
        }
        if loadPreferences {
            self.loadPreferences()
            checkASRKey()
        }
        if watchDayRollover {
            self.startDayRolloverWatcher()
        }
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
        if let nWidth = json["notes_list_width"] as? CGFloat, nWidth >= 200, nWidth <= 500 {
            self.notesListWidth = nWidth
        }
        if let nCollapsed = json["is_notes_list_collapsed"] as? Bool {
            self.isNotesListCollapsed = nCollapsed
        }

        if let vPath = json["vault_path"] as? String, !vPath.isEmpty {
            openVault(path: vPath, persist: false)
        }

        if let mcpEnabled = json["mcp_enabled"] as? Bool, mcpEnabled {
            if let v = vault {
                try? MCPServer.shared.start(vault: v)
                self.mcpStatus = MCPServer.shared.getStatus()
            } else {
                self.mcpStatus = MCPServer.shared.getStatus()
                self.mcpStatus.enabled = true
                self.mcpStatus.error = "请先选择并打开资料库"
            }
        }
    }

    public func savePreferences() {
        if CommandLine.arguments.contains("--snapshot") {
            return
        }

        var dict: [String: Any] = [
            "theme": themePreference,
            "accent_color": accentColorHex,
            "inspector_width": inspectorWidth,
            "is_sidebar_visible": isSidebarVisible,
            "notes_list_width": notesListWidth,
            "is_notes_list_collapsed": isNotesListCollapsed,
            "mcp_enabled": mcpStatus.enabled
        ]
        if let v = vault {
            dict["vault_path"] = v.rootPath
        }

        let targetURL = configURL
        savePreferencesWorkItem?.cancel()
        let item = DispatchWorkItem { [dict, targetURL] in
            if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted]) {
                try? data.write(to: targetURL)
            }
        }
        savePreferencesWorkItem = item
        preferencesSaveQueue.asyncAfter(deadline: .now() + 0.2, execute: item)
    }

    public func toggleSidebar() {
        withAnimation(.easeInOut(duration: 0.2)) {
            self.isSidebarVisible.toggle()
        }
        self.savePreferences()
    }

    public func toggleNotesList() {
        withAnimation(.easeInOut(duration: 0.2)) {
            self.isNotesListCollapsed.toggle()
        }
        self.savePreferences()
    }

    public func toggleSearch() {
        withAnimation(.easeInOut(duration: 0.15)) {
            self.showSearch.toggle()
        }
    }

    public func openVault(path: String, persist: Bool = true) {
        guard noteEditor.save() else { return }
        do {
            let v = try Vault(rootPath: path)
            v.onEvent = { [weak self, weak v] _ in
                DispatchQueue.main.async {
                    guard let self, self.vault === v else { return }
                    self.vaultHealthErrors = v?.index.listParseErrors() ?? []
                    if let v, let id = self.selectedNoteId, let note = v.index.getNote(id) {
                        self.noteEditor.acceptSavedNote(note, in: v)
                    }
                    self.objectWillChange.send()
                }
            }
            vault?.stopWatcher()
            v.startWatcher()
            self.vault = v
            noteEditor.select(nil, in: v)
            selectedNoteId = nil
            selectedTaskId = nil
            isInspectorVisible = false
            self.vaultStatus = v.rootPath
            self.vaultHealthErrors = v.index.listParseErrors()
            MCPServer.shared.setVault(v)
            mcpStatus = MCPServer.shared.getStatus()
            if persist && !CommandLine.arguments.contains("--snapshot") {
                savePreferences()
            }
        } catch {
            self.vaultStatus = "打开资料库失败: \(error.localizedDescription)"
        }
    }

    public func saveTranscript(_ body: String, noteId: String, audioFile: String, in vault: Vault) throws {
        if noteEditor.isEditing(noteId: noteId, in: vault), !noteEditor.save() {
            throw SchemaError.validationError(field: "note", reason: "请先保存当前编辑后再替换逐字稿")
        }
        let note = try vault.replaceTranscript(noteId: noteId, audioFile: audioFile, body: body)
        noteEditor.acceptSavedNote(note, in: vault)
        if self.vault === vault { objectWillChange.send() }
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
    public func navigateToToday() {
        self.showSettings = false
        self.currentNav = .today
        checkDateRollover()
        self.todayDateString = AppState.currentDateString()
        self.showSearch = false
    }

    public func navigateToNote(noteId: String) {
        self.currentNav = .notes
        self.selectedNoteId = noteId
        self.showSearch = false
    }

    public func navigateToTask(taskId: String) {
        self.showSearch = false
        openTaskInspector(taskId: taskId)
    }

    func openSearchResult(_ item: EntityRef) {
        showSearch = false
        if item.type != .file { showSettings = false }
        switch item.type {
        case .task:
            navigateToTask(taskId: item.id)
        case .note:
            navigateToNote(noteId: item.id)
        case .activity:
            guard let location = vault?.index.getActivityLocation(activityID: item.id) else { return }
            switch location.ownerType {
            case .task:
                navigateToTask(taskId: location.ownerId)
            case .dayPlan:
                currentNav = .today
                todayDateString = location.ownerId
            default:
                break
            }
        case .dayPlan:
            currentNav = .today
            todayDateString = item.id
        case .file:
            if let root = vault?.rootPath {
                let fullPath = (root as NSString).appendingPathComponent(item.path)
                NSWorkspace.shared.selectFile(fullPath, inFileViewerRootedAtPath: root)
            }
        }
    }

    public func navigateToTag(_ tag: String) {
        self.selectedTag = tag
        self.currentNav = .tags
        self.showSearch = false
    }

    // MARK: - MCP Management

    public func startMCPServer() {
        guard let v = vault else {
            mcpStatus.enabled = true
            mcpStatus.error = "请先选择并打开资料库"
            savePreferences()
            return
        }
        do {
            try MCPServer.shared.start(vault: v)
            mcpStatus = MCPServer.shared.getStatus()
            savePreferences()
        } catch {
            mcpStatus = MCPServer.shared.getStatus()
            mcpStatus.enabled = true
            mcpStatus.error = "无法启动 MCP：\(error.localizedDescription)"
            savePreferences()
        }
    }

    public func stopMCPServer() {
        MCPServer.shared.stop()
        mcpStatus = MCPServer.shared.getStatus()
        savePreferences()
    }

    public func cancelMCPAutoStart() {
        MCPServer.shared.cancelAutoStart()
        mcpStatus = MCPServer.shared.getStatus()
        savePreferences()
    }

    public func refreshMCPStatus() {
        mcpStatus = MCPServer.shared.getStatus()
    }

    // MARK: - Day Rollover & Auto-Refresh

    private var midnightTimer: Timer?
    private var periodicCheckTimer: Timer?
    private var rolloverNotificationTokens: [NSObjectProtocol] = []

    /// 检查并在跨天时自动刷新今日计划
    /// - Parameter nowDateString: 目标当前日期（默认使用实时系统日期，测试时可指定）
    /// - Returns: 若今日计划发生日期推进刷新则返回 true，否则返回 false
    @discardableResult
    public func checkDateRollover(nowDateString: String = AppState.currentDateString()) -> Bool {
        guard nowDateString != lastKnownTodayDateString else {
            return false
        }
        let previousToday = lastKnownTodayDateString
        lastKnownTodayDateString = nowDateString

        // 若用户当前处于“今日”视图（即 todayDateString 等于跨天前的当天），自动刷新推进到新的下一天
        var didAdvance = false
        if todayDateString == previousToday {
            todayDateString = nowDateString
            didAdvance = true
        } else if todayDateString > nowDateString {
            // 异常防御：若当前选择的日期由于某种原因超过了新的当天，回退到新的当天
            todayDateString = nowDateString
            didAdvance = true
        }

        objectWillChange.send()
        return didAdvance
    }

    public func startDayRolloverWatcher() {
        stopDayRolloverWatcher()

        let center = NotificationCenter.default
        let dayChangedToken = center.addObserver(
            forName: .NSCalendarDayChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            _ = MainActor.assumeIsolated {
                self?.checkDateRollover()
            }
        }
        rolloverNotificationTokens.append(dayChangedToken)

        // 2. 监听系统时钟和时区改变通知
        let clockChangeToken = center.addObserver(
            forName: Notification.Name.NSSystemClockDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            _ = MainActor.assumeIsolated {
                self?.checkDateRollover()
            }
        }
        rolloverNotificationTokens.append(clockChangeToken)

        let timeZoneChangeToken = center.addObserver(
            forName: Notification.Name.NSSystemTimeZoneDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            _ = MainActor.assumeIsolated {
                self?.checkDateRollover()
            }
        }
        rolloverNotificationTokens.append(timeZoneChangeToken)

        let activeToken = center.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            _ = MainActor.assumeIsolated {
                self?.checkDateRollover()
            }
        }
        rolloverNotificationTokens.append(activeToken)

        let wakeToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            _ = MainActor.assumeIsolated {
                self?.checkDateRollover()
            }
        }
        rolloverNotificationTokens.append(wakeToken)

        scheduleMidnightTimer()
        startPeriodicDayCheck()
    }

    public func stopDayRolloverWatcher() {
        midnightTimer?.invalidate()
        midnightTimer = nil
        periodicCheckTimer?.invalidate()
        periodicCheckTimer = nil

        for token in rolloverNotificationTokens {
            NotificationCenter.default.removeObserver(token)
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
        rolloverNotificationTokens.removeAll()
    }

    private func scheduleMidnightTimer() {
        midnightTimer?.invalidate()
        midnightTimer = nil

        let calendar = Calendar.current
        let now = Date()
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
              let nextMidnight = calendar.date(bySettingHour: 0, minute: 0, second: 1, of: tomorrow) else {
            return
        }

        let timer = Timer(fire: nextMidnight, interval: 0, repeats: false) { [weak self] _ in
            _Concurrency.Task { @MainActor [weak self] in
                guard let self else { return }
                self.checkDateRollover()
                self.scheduleMidnightTimer()
            }
        }
        timer.tolerance = 1.0
        RunLoop.main.add(timer, forMode: .common)
        self.midnightTimer = timer
    }

    private func startPeriodicDayCheck() {
        periodicCheckTimer?.invalidate()
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            _Concurrency.Task { @MainActor [weak self] in
                self?.checkDateRollover()
            }
        }
        timer.tolerance = 10.0
        RunLoop.main.add(timer, forMode: .common)
        self.periodicCheckTimer = timer
    }
}
