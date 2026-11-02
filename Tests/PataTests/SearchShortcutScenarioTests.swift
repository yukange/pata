import Testing
import Foundation
@testable import PataCore
@testable import PataUI

@Suite("BDD Feature: Search Shortcuts & Overlay")
@MainActor
struct SearchShortcutScenarioTests {

    @Test("Given AppState, when toggleSearch is called, then showSearch toggles correctly")
    func toggleSearchStateScenario() {
        let state = AppState.shared
        state.showSearch = false

        // When: toggling search on
        state.toggleSearch()

        // Then: search overlay state is true (opened by ⌘K / ⌘P)
        #expect(state.showSearch == true)

        // When: toggling search off
        state.toggleSearch()

        // Then: search overlay state is false
        #expect(state.showSearch == false)
    }

    @Test("Given a vault with tasks, when searching, then matching entities are retrieved")
    func searchIndexAndResultsScenario() throws {
        let tempVaultURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempVaultURL, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempVaultURL)
        }

        let tasksDir = tempVaultURL.appendingPathComponent("tasks")
        try FileManager.default.createDirectory(at: tasksDir, withIntermediateDirectories: true)

        let taskContent = """
        ---
        id: "t-search-001"
        type: "task"
        title: "快捷键测试任务"
        status: "todo"
        created_at: "2026-10-30T10:00:00Z"
        updated_at: "2026-10-30T10:00:00Z"
        tags: ["search"]
        ---

        任务描述正文
        """
        try taskContent.write(to: tasksDir.appendingPathComponent("t-search-001.md"), atomically: true, encoding: .utf8)

        let vault = try Vault(rootPath: tempVaultURL.path)
        let results = vault.index.searchAll("快捷键")

        #expect(!results.isEmpty)
        #expect(results.first?.id == "t-search-001")
    }

    @Test("Search opens a hidden task inspector for tasks and task activities")
    func opensTaskInspectorFromSearch() throws {
        let fixture = try AuditVaultFixture()
        let state = AppState(loadPreferences: false)
        state.openVault(path: fixture.vault.rootPath, persist: false)
        let vault = try #require(state.vault)
        let task = try vault.createTask(title: "search-route")
        _ = try vault.createActivity(taskId: task.id, body: "search-route")
        let results = vault.index.searchAll("search-route")
        #expect(results.count == 2)
        for result in results {
            state.showSettings = true
            state.showSearch = true
            state.isInspectorVisible = false
            state.selectedTaskId = nil
            state.openSearchResult(result)
            #expect(state.selectedTaskId == task.id)
            #expect(state.isInspectorVisible)
            #expect(!state.showSearch)
            #expect(!state.showSettings)
        }
    }

    @Test("Search opens the owning DayPlan for a standalone activity")
    func opensStandaloneActivityDay() throws {
        let fixture = try AuditVaultFixture()
        let state = AppState(loadPreferences: false)
        state.openVault(path: fixture.vault.rootPath, persist: false)
        let vault = try #require(state.vault)
        _ = try vault.createActivity(date: "2025-01-03", body: "historical-search-record")
        var result = try #require(vault.index.searchAll("historical-search-record").first)
        result.time = Date() // Older records may carry a timestamp from a different day.
        state.currentNav = .tasks
        state.showSettings = true
        state.showSearch = true
        state.openSearchResult(result)
        #expect(state.currentNav == .today)
        #expect(state.todayDateString == "2025-01-03")
        #expect(!state.showSearch)
        #expect(!state.showSettings)
    }

    @Test("Keyboard results follow visible group order and omit hidden rows")
    func keyboardResultsMatchVisibleRows() {
        let results = [EntityType.file, .activity, .note, .task].flatMap { type in
            (0..<7).map { index in
                EntityRef(type: type, id: "\(type.rawValue)-\(index)", path: "", time: Date())
            }
        }
        let displayed = SearchOverlay.displayedResults(results)
        #expect(displayed.map(\.id) == [
            "task-0", "task-1", "task-2", "task-3", "task-4",
            "note-0", "note-1", "note-2", "note-3", "note-4",
            "activity-0", "activity-1", "activity-2", "activity-3", "activity-4",
            "file-0", "file-1", "file-2", "file-3", "file-4"
        ])
        #expect(SearchOverlay.displayedResults([]).isEmpty)
    }
}
