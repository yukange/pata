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
        _ = try vault.createActivity(taskId: task.id, body: "Activity")

        _ = try vault.createNote(title: "Note with tag", body: "Body", tags: ["SharedTag"])

        let tags = vault.index.listTags()
        let sharedSummary = tags.first { $0.name.lowercased() == "sharedtag" }
        #expect(sharedSummary != nil)
        #expect(sharedSummary?.taskCount == 1)
        #expect(sharedSummary?.noteCount == 1)
        #expect(sharedSummary?.totalCount == 2)
    }

    @Test("Tag page shows all untagged content but no drafts, files or DayPlan containers")
    func tagPageAllEntities() throws {
        let tempVaultDir = (NSTemporaryDirectory() as NSString).appendingPathComponent("pata_vault_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(atPath: tempVaultDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(atPath: tempVaultDir)
        }

        let vault = try Vault(rootPath: tempVaultDir)

        let tagged = try vault.createTask(title: "Tagged task", tags: ["工作"])
        _ = try vault.createActivity(taskId: tagged.id, body: "Task activity")
        let untagged = try vault.createTask(title: "Untagged task", tags: [])
        _ = try vault.createNote(title: "Draft", body: "Body", draft: true)
        let formalUntagged = try vault.createNote(title: "Formal untagged", body: "Body", tags: [])
        let formalTagged = try vault.createNote(title: "Formal tagged", body: "Body", tags: ["工作"])
        _ = try vault.createActivity(date: "2026-10-15", body: "Plan activity")

        let all = vault.index.listAllEntities()
        let ids = all.map(\.id)

        #expect(Set(ids).count == ids.count) // multi-tag content never duplicated
        #expect(all.allSatisfy { $0.type == .task || $0.type == .note })
        #expect(!all.contains { $0.title == "Draft" })
        #expect(all.contains { $0.id == untagged.id })
        #expect(all.contains { $0.id == formalUntagged.id })
        #expect(all.contains { $0.id == tagged.id })
        #expect(all.contains { $0.id == formalTagged.id })

        let taggedRefs = vault.index.findByTag("工作")
        #expect(!taggedRefs.contains { $0.id == untagged.id })
        #expect(taggedRefs.contains { $0.id == formalTagged.id })
        #expect(taggedRefs.contains { $0.id == tagged.id })
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

    @Test("Rename tag batch updates notes, tasks, activities and index")
    func renameTagBatchUpdates() throws {
        let tempVaultDir = (NSTemporaryDirectory() as NSString).appendingPathComponent("pata_vault_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(atPath: tempVaultDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(atPath: tempVaultDir)
        }

        let vault = try Vault(rootPath: tempVaultDir)

        let task = try vault.createTask(title: "测试任务", tags: ["工作", "技术"])
        _ = try vault.createActivity(taskId: task.id, body: "评论记录")
        let note = try vault.createNote(title: "设计文档", body: "正文", tags: ["工作", "架构"])
        _ = try vault.createActivity(date: "2026-11-05", body: "计划记录")

        // Rename "工作" -> "研发"
        let count = try vault.renameTag(from: "工作", to: "研发")
        #expect(count == 2) // note, task

        // 1. Verify Note in memory and on disk
        let updatedNote = try #require(vault.index.getNote(note.id))
        #expect(updatedNote.tags.contains("研发"))
        #expect(!updatedNote.tags.contains("工作"))
        #expect(updatedNote.tags.contains("架构"))

        let notePath = vault.resolveEntityPath(updatedNote)
        let noteContent = try String(contentsOfFile: notePath, encoding: .utf8)
        let parsedFromDisk = try #require(try Frontmatter.parseMarkdown(content: noteContent) as? Note)
        #expect(parsedFromDisk.tags.contains("研发"))
        #expect(!parsedFromDisk.tags.contains("工作"))

        // 2. Verify Task in memory
        let updatedTask = try #require(vault.index.getTask(task.id))
        #expect(updatedTask.tags.contains("研发"))
        #expect(!updatedTask.tags.contains("工作"))

        // 3. Verify Index findByTag
        let oldRefs = vault.index.findByTag("工作")
        #expect(oldRefs.isEmpty)

        let newRefs = vault.index.findByTag("研发")
        #expect(newRefs.contains { $0.id == note.id })
        #expect(newRefs.contains { $0.id == task.id })
    }

    @Test("Test renameTag with hashtag prefix and casing update")
    func testRenameTagWithHashAndCasing() throws {
        let tempVaultDir = (NSTemporaryDirectory() as NSString).appendingPathComponent("pata_vault_case_\(UUID().uuidString)")
        try FileManager.default.createDirectory(atPath: tempVaultDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(atPath: tempVaultDir)
        }

        let vault = try Vault(rootPath: tempVaultDir)
        let note = try vault.createNote(title: "Swift 学习", body: "内容", tags: ["swift"])

        // Rename "#swift" -> "#Swift" (preserving case change and stripping #)
        let count = try vault.renameTag(from: "#swift", to: "#Swift")
        #expect(count == 1)

        let updatedNote = try #require(vault.index.getNote(note.id))
        #expect(updatedNote.tags == ["Swift"])

        let summaries = vault.index.listTags()
        #expect(summaries.contains { $0.name == "Swift" })
    }

    @Test("Remove tag removes it from notes and tasks and updates index")
    func removeTagBatchUpdates() throws {
        let tempVaultDir = (NSTemporaryDirectory() as NSString).appendingPathComponent("pata_vault_delete_tag_\(UUID().uuidString)")
        try FileManager.default.createDirectory(atPath: tempVaultDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(atPath: tempVaultDir)
        }

        let vault = try Vault(rootPath: tempVaultDir)
        let task = try vault.createTask(title: "测试任务", tags: ["工作", "技术"])
        let note = try vault.createNote(title: "设计文档", body: "正文", tags: ["工作", "架构"])

        let count = try vault.removeTag(named: "#工作")
        #expect(count == 2)

        let updatedNote = try #require(vault.index.getNote(note.id))
        #expect(updatedNote.tags == ["架构"])

        let notePath = vault.resolveEntityPath(updatedNote)
        let noteContent = try String(contentsOfFile: notePath, encoding: .utf8)
        let parsedFromDisk = try #require(try Frontmatter.parseMarkdown(content: noteContent) as? Note)
        #expect(parsedFromDisk.tags == ["架构"])

        let updatedTask = try #require(vault.index.getTask(task.id))
        #expect(updatedTask.tags == ["技术"])

        #expect(vault.index.findByTag("工作").isEmpty)
        #expect(!vault.index.listTags().contains { $0.name == "工作" })
        #expect(try vault.removeTag(named: "工作") == 0)
    }
}
