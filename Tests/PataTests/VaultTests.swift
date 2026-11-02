import Testing
@testable import PataCore
import Foundation

@Suite("Vault Tests")
struct VaultTests {
    @Test("Task lifecycle and cascading deletion")
    func taskLifecycleAndCascadingDelete() throws {
        let tempVaultDir = (NSTemporaryDirectory() as NSString).appendingPathComponent("pata_vault_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(atPath: tempVaultDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(atPath: tempVaultDir)
        }

        let vault = try Vault(rootPath: tempVaultDir)

        // 1. Create task
        let task = try vault.createTask(title: "测试任务", tags: ["工作"])
        #expect(vault.index.listTasks().count == 1)

        // 2. Add activity to task
        let act = try vault.createActivity(taskId: task.id, body: "进展顺利")
        let updatedTask = vault.index.getTask(task.id)
        #expect(updatedTask?.activities.count == 1)
        #expect(updatedTask?.activities.first?.id == act.id)

        // 3. Add task to today's day plan
        var plan = vault.getDayPlan(date: "2026-10-15")
        plan.taskIds.append(task.id)
        _ = try vault.updateDayPlan(plan)
        #expect(vault.index.getDayPlan(date: "2026-10-15")?.taskIds.contains(task.id) == true)

        // 4. Delete task -> Activity deleted, DayPlan reference cleaned!
        try vault.deleteTask(id: task.id)
        #expect(vault.index.getTask(task.id) == nil)
        #expect(vault.index.getActivityLocation(activityID: act.id) == nil)
        #expect(vault.index.getDayPlan(date: "2026-10-15")?.taskIds.contains(task.id) == false)
    }

    @Test("Draft in-place conversion preserves file path and ID")
    func draftInPlaceConversion() throws {
        let tempVaultDir = (NSTemporaryDirectory() as NSString).appendingPathComponent("pata_vault_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(atPath: tempVaultDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(atPath: tempVaultDir)
        }

        let vault = try Vault(rootPath: tempVaultDir)

        // 1. Create draft
        let draft = try vault.createNote(title: "", body: "草稿内容", draft: true)
        let draftPath = vault.resolveEntityPath(draft)
        #expect(draft.draft == true)
        #expect(vault.index.listNotes().count == 1)
        #expect(vault.index.listNotes().first?.draft == true)

        // 2. Convert draft to formal note in-place
        let converted = try vault.convertDraftToNote(id: draft.id, newTitle: "正式标题", tags: ["总结"])
        #expect(converted.draft == false)
        #expect(converted.id == draft.id)
        #expect(converted.title == "正式标题")
        #expect(converted.tags == ["总结"])
        #expect(converted.body == "草稿内容")

        // Path and ID unchanged
        let convertedPath = vault.resolveEntityPath(converted)
        #expect(convertedPath == draftPath)
    }

    @Test("Tag aggregation and dynamic inheritance")
    func tagAggregationAndDynamicInheritance() throws {
        let tempVaultDir = (NSTemporaryDirectory() as NSString).appendingPathComponent("pata_vault_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(atPath: tempVaultDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(atPath: tempVaultDir)
        }

        let vault = try Vault(rootPath: tempVaultDir)

        let task = try vault.createTask(title: "Task with tag", tags: ["SharedTag"])
        _ = try vault.createActivity(taskId: task.id, body: "Activity", tags: ["ActTag"])

        _ = try vault.createNote(title: "Note with tag", body: "Body", tags: ["SharedTag"])

        let tags = vault.index.listTags()
        let sharedSummary = tags.first { $0.name.lowercased() == "sharedtag" }
        #expect(sharedSummary != nil)
        #expect(sharedSummary?.taskCount == 1)
        #expect(sharedSummary?.noteCount == 1)
        #expect(sharedSummary?.activityCount == 1) // Activity inherited parent task tag!
    }

    @Test("Search all entities and content")
    func searchAll() throws {
        let tempVaultDir = (NSTemporaryDirectory() as NSString).appendingPathComponent("pata_vault_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(atPath: tempVaultDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(atPath: tempVaultDir)
        }

        let vault = try Vault(rootPath: tempVaultDir)

        _ = try vault.createTask(title: "搜索功能开发", description: "关于快速查找的说明")
        _ = try vault.createNote(title: "架构设计", body: "包含搜索索引的相关讨论")

        let results = vault.index.searchAll("搜索")
        #expect(results.count == 2)
    }
}
