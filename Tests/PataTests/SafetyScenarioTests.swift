import Testing
import Foundation
@testable import PataCore

@Suite("BDD Feature: Safety, Concurrency Baseline & Conflict Protection")
struct SafetyScenarioTests {

    @Test("Given an external editor modified a task on disk, when saving with an outdated baseline, then ErrConflict is thrown and disk content is preserved")
    func externalEditConflictScenario() throws {
        // Given: A vault with an existing task and a captured baseline
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("pata_bdd_safety_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let vault = try Vault(rootPath: tmpDir.path)
        let task = try vault.createTask(title: "原始任务标题", description: "用户第一版内容")
        let taskPath = vault.resolveEntityPath(task)

        let (baseline, _) = try Safety.readBaseline(absPath: taskPath)

        // And: An external agent (e.g. Pi agent or external editor) writes changes directly to disk
        let externalData = """
        ---
        type: task
        id: \(task.id)
        title: 外部修改后的任务
        status: doing
        priority: p1
        created_at: 2026-10-11T10:00:00+08:00
        updated_at: 2026-10-11T10:30:00+08:00
        ---

        外部编辑者修改了这段内容。
        """
        try externalData.data(using: .utf8)!.write(to: URL(fileURLWithPath: taskPath))

        // When: User attempts to save local edits using the outdated baseline
        var userTask = task
        userTask.title = "用户想覆盖的标题"
        userTask.description = "用户想覆盖的内容"
        let userRaw = try Frontmatter.serializeMarkdown(userTask)

        // Then: SaveEntity must reject overwrite and throw ConflictError
        #expect(throws: ConflictError.self) {
            try Safety.safeWrite(targetPath: taskPath, data: Data(userRaw.utf8), baseline: baseline)
        }

        // And: Verify that the disk content was NOT overwritten
        let diskContent = try String(contentsOfFile: taskPath, encoding: .utf8)
        #expect(diskContent.contains("外部编辑者修改了这段内容"))
        #expect(!diskContent.contains("用户想覆盖的标题"))
    }

    @Test("Given an existing file on disk, when attempting to write with baseline nil, then ErrConflict is thrown")
    func baselineNilOverwriteProtectionScenario() throws {
        // Given: An existing note file already on disk
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("pata_bdd_base_nil_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let notePath = tmpDir.appendingPathComponent("test_note.md").path
        try "已有内容".data(using: .utf8)!.write(to: URL(fileURLWithPath: notePath))

        // When: An attempt is made to write colliding data with baseline nil
        let collidingData = "恶意覆盖内容".data(using: .utf8)!

        // Then: ConflictError must be thrown to prevent blind overwrites
        #expect(throws: ConflictError.self) {
            try Safety.safeWrite(targetPath: notePath, data: collidingData, baseline: nil)
        }

        // And: Original content remains unaltered
        let currentDisk = try String(contentsOfFile: notePath, encoding: .utf8)
        #expect(currentDisk == "已有内容")
    }

    @Test("Given an externally deleted file, when attempting to write with a non-nil baseline, then ErrConflict is thrown")
    func externalDeletionConflictScenario() throws {
        // Given: A file that had a baseline but was subsequently deleted from disk
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("pata_bdd_del_conf_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let filePath = tmpDir.appendingPathComponent("deleted.md").path
        try "初版内容".data(using: .utf8)!.write(to: URL(fileURLWithPath: filePath))
        let (baseline, _) = try Safety.readBaseline(absPath: filePath)
        try FileManager.default.removeItem(atPath: filePath)

        // When: Attempting to save based on the old baseline
        let newData = "更新尝试".data(using: .utf8)!

        // Then: ConflictError must be thrown indicating deletion
        #expect(throws: ConflictError.self) {
            try Safety.safeWrite(targetPath: filePath, data: newData, baseline: baseline)
        }
    }

    @Test("Given an external tool writes malformed YAML, when the vault scans the folder, then the error is isolated in parseErrors without corrupting or deleting the file")
    func invalidYAMLIsolationScenario() throws {
        // Given: A vault containing a valid note and a corrupted markdown file
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("pata_bdd_yaml_iso_\(UUID().uuidString)")
        let notesDir = tmpDir.appendingPathComponent("notes")
        try FileManager.default.createDirectory(at: notesDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let validNotePath = notesDir.appendingPathComponent("valid_n-01.md").path
        let validYAML = """
        ---
        type: note
        id: n-valid-01
        title: 正常笔记
        created_at: 2026-10-11T10:00:00+08:00
        updated_at: 2026-10-11T10:00:00+08:00
        ---
        正常内容
        """
        try validYAML.write(toFile: validNotePath, atomically: true, encoding: .utf8)

        let brokenNotePath = notesDir.appendingPathComponent("broken.md").path
        let brokenYAML = """
        ---
        type: note
        id: [bad yaml syntax:::
          - unclosed
        title: Broken
        ---
        正文内容未损坏
        """
        try brokenYAML.write(toFile: brokenNotePath, atomically: true, encoding: .utf8)

        // When: The vault scans all files
        let vault = try Vault(rootPath: tmpDir.path)

        // Then: The valid note is indexed successfully
        #expect(vault.index.getNote("n-valid-01") != nil)
        #expect(vault.index.getNote("n-valid-01")?.title == "正常笔记")

        // And: The malformed file is recorded in parseErrors
        let errors = vault.index.listParseErrors()
        #expect(!errors.isEmpty)
        #expect(errors.contains { $0.contains("broken.md") })

        // And: The physical file on disk is preserved intact without being deleted or truncated
        let brokenDiskContent = try String(contentsOfFile: brokenNotePath, encoding: .utf8)
        #expect(brokenDiskContent.contains("正文内容未损坏"))
    }

    @Test("Given a markdown file with unknown YAML frontmatter fields, when parsed and serialized, then custom unknown fields are preserved intact")
    func unknownYAMLFieldsPreservationScenario() throws {
        // Given: A task markdown file with custom third-party agent metadata
        let input = """
        ---
        custom_agent_id: pi-007
        id: t-roundtrip-01
        nested_attributes:
          ai_confidence: 0.98
          source: ide_plugin
        priority: p1
        status: doing
        title: 未知字段测试
        type: task
        ---

        正文内容保持不变。
        """

        // When: Parsed into domain Entity
        let entity = try Frontmatter.parseMarkdown(filePath: "tasks/task.md", content: input)
        guard var task = entity as? Task else {
            Issue.record("Expected Task entity")
            return
        }

        // And: A known field is modified
        task.title = "更新后的已知标题"

        // And: Serialized back to markdown
        let output = try Frontmatter.serializeMarkdown(task)

        // Then: The unknown metadata fields must be preserved on roundtrip parse
        let reparsed = try Frontmatter.parseMarkdown(filePath: "tasks/task.md", content: output) as? Task
        #expect(reparsed != nil)
        #expect(reparsed?.title == "更新后的已知标题")
        #expect(reparsed?.description == "正文内容保持不变。")
        #expect(reparsed?.extra["custom_agent_id"] == "pi-007")
        #expect(reparsed?.extra["nested_attributes"]?.contains("ai_confidence") == true)
        #expect(reparsed?.extra["nested_attributes"]?.contains("ide_plugin") == true)
    }

    @Test("Given an internal write through Vault, when the write tracker is queried, then the write is recognized as internal to suppress fsnotify feedback loops")
    func internalWriteSuppressionScenario() throws {
        // Given: A WriteTracker instance
        let tracker = WriteTracker(retention: 2.0)
        let filePath = "/test/vault/tasks/task_1.md"
        let data = "测试数据".data(using: .utf8)!
        let hash = Safety.computeContentHash(data)

        // When: The internal write is recorded
        tracker.markInternalWrite(absPath: filePath, hash: hash)

        // Then: Querying immediately identifies it as an internal write
        #expect(tracker.isInternalWrite(absPath: filePath, hash: hash) == true)

        // And: Subsequent query on the same path is no longer internal (one-shot consumption)
        #expect(tracker.isInternalWrite(absPath: filePath, hash: hash) == false)
    }
}
