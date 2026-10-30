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
}
