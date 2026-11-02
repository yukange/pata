import Testing
import Foundation
@testable import PataCore

@Suite("BDD Feature: Multi-Entity Collisions, Plain Markdown & ID Isolation")
struct ReworkScenarioTests {

    @Test("Given two notes with identical titles, when created with different IDs, then they resolve to distinct file paths and neither overwrites the other")
    func sameTitleDifferentIDNotesNotOverwrittenScenario() throws {
        // Given: A vault ready for note creation
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("pata_bdd_same_title_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let vault = try Vault(rootPath: tmpDir.path)

        // When: Two notes with identical titles but different IDs are created
        let note1 = try vault.createNote(title: "统一架构方案", body: "第一篇同标题笔记")
        let note2 = try vault.createNote(title: "统一架构方案", body: "第二篇同标题笔记")

        // Then: They must resolve to completely distinct file paths
        let path1 = vault.resolveEntityPath(note1)
        let path2 = vault.resolveEntityPath(note2)
        #expect(path1 != path2)

        // And: Both files must exist on disk with their respective contents intact
        let diskContent1 = try String(contentsOfFile: path1, encoding: .utf8)
        let diskContent2 = try String(contentsOfFile: path2, encoding: .utf8)
        #expect(diskContent1.contains("第一篇同标题笔记"))
        #expect(diskContent2.contains("第二篇同标题笔记"))

        // And: Both notes must exist in the in-memory index
        let retrieved1 = vault.index.getNote(note1.id)
        let retrieved2 = vault.index.getNote(note2.id)
        #expect(retrieved1?.body == note1.body)
        #expect(retrieved2?.body == note2.body)
    }

    @Test("Given multiple plain markdown files without frontmatter, when scanned into the vault, then distinct derived IDs are assigned and both are fully searchable")
    func plainMarkdownCoexistScenario() throws {
        // Given: A vault containing plain markdown files without YAML frontmatter
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("pata_bdd_plain_\(UUID().uuidString)")
        let notesDir = tmpDir.appendingPathComponent("notes")
        try FileManager.default.createDirectory(at: notesDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let fileA = notesDir.appendingPathComponent("guide.md").path
        let contentA = "# 指南文档\n\n这是纯文本指南。"
        try contentA.write(toFile: fileA, atomically: true, encoding: .utf8)

        let fileB = notesDir.appendingPathComponent("intro.md").path
        let contentB = "# 介绍文档\n\n这是纯文本介绍。"
        try contentB.write(toFile: fileB, atomically: true, encoding: .utf8)

        // When: The vault is initialized and scanned
        let vault = try Vault(rootPath: tmpDir.path)

        // Then: Both plain files are indexed as notes with distinct IDs
        let notes = vault.index.listNotes()
        #expect(notes.count == 2)

        let titles = Set(notes.map { $0.title })
        #expect(titles.contains("指南文档"))
        #expect(titles.contains("介绍文档"))

        let ids = Set(notes.map { $0.id })
        #expect(ids.count == 2)

        // And: Search correctly discovers both documents
        let guideSearch = vault.index.searchAll("指南")
        #expect(!guideSearch.isEmpty)
        #expect(guideSearch.first?.title == "指南文档")

        let introSearch = vault.index.searchAll("介绍")
        #expect(!introSearch.isEmpty)
        #expect(introSearch.first?.title == "介绍文档")
    }

    @Test("Given two plain markdown notes in the index, when one file is deleted, then the remaining plain note index and mapping remain intact")
    func removeOnePlainMarkdownPreservesOtherScenario() throws {
        // Given: Two plain markdown files in the vault
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("pata_bdd_plain_del_\(UUID().uuidString)")
        let notesDir = tmpDir.appendingPathComponent("notes")
        try FileManager.default.createDirectory(at: notesDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let fileA = notesDir.appendingPathComponent("docA.md").path
        try "# 文档 A\n内容 A".write(toFile: fileA, atomically: true, encoding: .utf8)

        let fileB = notesDir.appendingPathComponent("docB.md").path
        try "# 文档 B\n内容 B".write(toFile: fileB, atomically: true, encoding: .utf8)

        let vault = try Vault(rootPath: tmpDir.path)
        let noteBId = vault.index.listNotes().first { $0.title == "文档 B" }?.id ?? ""
        #expect(!noteBId.isEmpty)

        // When: File A is deleted and removed from the index
        try FileManager.default.removeItem(atPath: fileA)
        vault.index.removeFile(absPath: fileA)

        // Then: File A is completely gone from the index
        #expect(vault.index.listNotes().contains { $0.title == "文档 A" } == false)

        // And: File B remains completely accessible and uncorrupted
        let remainingB = vault.index.getNote(noteBId)
        #expect(remainingB != nil)
        #expect(remainingB?.title == "文档 B")
    }

    @Test("Given a duplicate entity ID across different files on disk, when scanned, then collision is isolated in parseErrors and the first entity is not silently overwritten")
    func duplicateEntityIDCollisionIsolatedScenario() throws {
        // Given: A vault with two task files having the exact same entity ID
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("pata_bdd_dup_id_\(UUID().uuidString)")
        let tasksDir = tmpDir.appendingPathComponent("tasks")
        try FileManager.default.createDirectory(at: tasksDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let file1 = tasksDir.appendingPathComponent("task_one.md").path
        let content1 = """
        ---
        type: task
        id: t-dup-001
        title: 第一个任务
        status: todo
        priority: p1
        created_at: 2026-10-11T10:00:00+08:00
        updated_at: 2026-10-11T10:00:00+08:00
        ---
        内容 1
        """
        try content1.write(toFile: file1, atomically: true, encoding: .utf8)

        let file2 = tasksDir.appendingPathComponent("task_two.md").path
        let content2 = """
        ---
        type: task
        id: t-dup-001
        title: 冲突的第二个任务(同ID)
        status: doing
        priority: p2
        created_at: 2026-10-11T11:00:00+08:00
        updated_at: 2026-10-11T11:00:00+08:00
        ---
        内容 2
        """
        try content2.write(toFile: file2, atomically: true, encoding: .utf8)

        // When: The vault is scanned
        let vault = try Vault(rootPath: tmpDir.path)

        // Then: A duplicate collision error is isolated in parseErrors
        let errors = vault.index.listParseErrors()
        #expect(errors.contains { $0.contains("duplicate entity ID collision") && $0.contains("t-dup-001") })

        // And: The original entity in the index must NOT be silently overwritten
        let task = vault.index.getTask("t-dup-001")
        #expect(task != nil)
        #expect(task?.title == "第一个任务")
    }
}
