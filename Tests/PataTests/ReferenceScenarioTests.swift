import Testing
import Foundation
@testable import PataCore

@Suite("BDD Feature: Reference Integrity & Auto-Repair")
struct ReferenceScenarioTests {

    @Test("Given a task referencing a non-existent note ID, when inspected, then a dangling reference is reported")
    func taskDanglingReferenceReportedScenario() throws {
        // Given: A vault with a task that references an uncreated note
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("pata_bdd_dang_rep_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let vault = try Vault(rootPath: tmpDir.path)
        var task = try vault.createTask(title: "架构接入任务")
        task.noteIds = ["n-missing-001"]
        try vault.updateTask(task)

        // When: Checking dangling references in the vault index
        let dangling = vault.index.listDanglingReferences()

        // Then: The missing note reference is captured
        #expect(!dangling.isEmpty)
        let found = dangling.first { $0.targetId == "n-missing-001" && $0.targetType == .note }
        #expect(found != nil)
        #expect(found?.sourceId == task.id)
    }

    @Test("Given a dangling reference to a missing note, when that note is created, then the dangling reference is automatically resolved")
    func danglingReferenceAutoRepairsOnNoteCreationScenario() throws {
        // Given: A vault with a dangling note reference on a task
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("pata_bdd_dang_rep_auto_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let vault = try Vault(rootPath: tmpDir.path)
        var task = try vault.createTask(title: "修复待办")
        task.noteIds = ["n-repair-target"]
        try vault.updateTask(task)

        #expect(vault.index.listDanglingReferences().contains { $0.targetId == "n-repair-target" })

        // When: The missing note is saved with that exact ID
        let note = Note(
            id: "n-repair-target",
            title: "补齐的笔记",
            createdAt: Date(),
            updatedAt: Date(),
            body: "正文已补充"
        )
        let noteRaw = try Frontmatter.serializeMarkdown(note)
        let notePath = vault.resolveEntityPath(note)
        try Safety.safeWrite(targetPath: notePath, data: Data(noteRaw.utf8))
        try vault.rescan()

        // Then: The dangling reference is completely resolved
        let after = vault.index.listDanglingReferences()
        #expect(after.contains { $0.targetId == "n-repair-target" } == false)
    }

    @Test("Given a task with note_refs bound to note ID, when target note is deleted and another note with the same name exists, then the bound note_ref is NOT reassigned to the new note")
    func noteRefDoesNotRebindToSameNameNoteScenario() {
        // Given: A task body referencing [[架构设计]] explicitly bound to n-original
        let body = "请参考 [[架构设计]] 的最新说明。"
        let noteRefs = ["架构设计": "n-original"]

        // And: Note n-original was deleted, but another note n-new exists with title "架构设计"
        let notes: [String: Note] = [
            "n-new": Note(
                id: "n-new",
                title: "架构设计",
                createdAt: Date(),
                updatedAt: Date()
            )
        ]

        // When: Resolving the text ref [[架构设计]]
        let resolved = Links.resolveTextRef(name: "架构设计", noteRefs: noteRefs, notes: notes)

        // Then: It must return nil (unresolved) rather than mistakenly hijacking to n-new!
        #expect(resolved == nil)
    }

    @Test("Given markdown body containing fenced code blocks with links, when extracting links, then code block links are ignored")
    func codeBlocksIgnoredInLinkExtractionScenario() {
        // Given: A note body with links in regular text and links inside fenced code blocks
        let body = """
        查看外部指南 [真实指南](../files/guide.pdf)。

        ```markdown
        [示例链接](notes/fake.md)
        [[示例引用]]
        ```

        结尾链接 [架构文档](notes/arch.md)。
        """

        // When: Extracting relative links from body
        let links = Links.noteLinkDests(body: body)

        // Then: Only the links outside fenced code blocks are returned
        #expect(links.contains("../files/guide.pdf"))
        #expect(links.contains("notes/arch.md"))
        #expect(!links.contains("notes/fake.md"))
    }

    @Test("Given a DayPlan referencing non-existent task IDs, when inspected, then dangling task references are reported")
    func dayPlanDanglingTaskReferenceScenario() throws {
        // Given: A vault with a DayPlan referencing a non-existent task
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("pata_bdd_plan_dang_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let vault = try Vault(rootPath: tmpDir.path)
        let plan = DayPlan(
            date: "2026-10-15",
            taskIds: ["t-nonexistent-01"]
        )
        try vault.updateDayPlan(plan)

        // When: Inspecting dangling references
        let dangling = vault.index.listDanglingReferences()

        // Then: The missing task reference is captured
        #expect(dangling.contains { $0.sourceType == .dayPlan && $0.targetId == "t-nonexistent-01" && $0.targetType == .task })
    }
}
