import Foundation
import Testing
import Yams
@testable import PataCore

final class AuditVaultFixture {
    let directory: URL
    let vault: Vault

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("pata-regression-\(UUID().uuidString)")
        vault = try Vault(rootPath: directory.appendingPathComponent("vault").path)
    }

    deinit {
        vault.stopWatcher()
        try? FileManager.default.removeItem(at: directory)
    }
}

@Suite("Audit: storage regression tests")
struct AuditCoreRegressionTests {
    @Test func rejectsInvalidDatesAndPathsBeforeWriting() throws {
        let fixture = try AuditVaultFixture()
        for date in ["../../escaped", "2026-02-30", "2026-1-01", "2026-01-01/../outside"] {
            #expect(throws: SchemaError.self) { try fixture.vault.createActivity(date: date, body: "record") }
            #expect(throws: SchemaError.self) { try fixture.vault.updateDayPlan(DayPlan(date: date)) }
        }
        #expect(!FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent("escaped.md").path))
        #expect(throws: SchemaError.self) {
            try fixture.vault.importFileData(Data([1]), filename: "../outside.bin")
        }
    }

    @Test func validatesNewRecordsAndUpdates() throws {
        let fixture = try AuditVaultFixture()
        #expect(throws: SchemaError.self) { try fixture.vault.createTask(title: " ") }
        #expect(throws: SchemaError.self) { try fixture.vault.createNote(title: "") }
        #expect(throws: SchemaError.self) { try fixture.vault.createTask(title: "valid", tags: ["#invalid"]) }
        var note = try fixture.vault.createNote(title: "valid", body: "original")
        note.title = ""
        #expect(throws: SchemaError.self) { try fixture.vault.updateNote(note) }
        let reopened = try Vault(rootPath: fixture.vault.rootPath)
        #expect(reopened.index.getNote(note.id)?.body.trimmingCharacters(in: .whitespacesAndNewlines) == "original")
        #expect(reopened.index.listParseErrors().isEmpty)
    }

    @Test func staleTaskCannotUndoStatusOrActivityEdits() throws {
        let fixture = try AuditVaultFixture()
        let vault = fixture.vault
        var stale = try vault.createTask(title: "original")
        let activity = try vault.createActivity(taskId: stale.id, body: "before")
        _ = try vault.updateActivity(id: activity.id, body: "after")
        _ = try vault.setTaskStatus(id: stale.id, status: .done, source: SourceAgent)
        stale.title = "local rename"
        #expect(throws: ConflictError.self) { try vault.updateTask(stale) }
        _ = try vault.modifyTask(id: stale.id) { $0.title = "safe rename" }
        let current = try #require(vault.index.getTask(stale.id))
        #expect(current.status == .done)
        #expect(current.statusEvents.count == 1)
        #expect(current.activities.first?.body == "after")
        #expect(current.title == "safe rename")
    }

    @Test func staleNoteConflictsEvenAfterExternalEditWasIndexed() throws {
        let fixture = try AuditVaultFixture()
        let vault = fixture.vault
        var stale = try vault.createNote(title: "original", body: "before")
        var external = stale
        external.body = "external text"
        try Frontmatter.serializeMarkdown(external).write(toFile: vault.resolveEntityPath(stale), atomically: true, encoding: .utf8)
        try vault.rescan()
        stale.title = "local rename"
        #expect(throws: ConflictError.self) { try vault.updateNote(stale) }
        #expect(vault.index.getNote(stale.id)?.body.contains("external text") == true)
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(vault.index.getNote(stale.id))) as? [String: Any]
        #expect(encoded?["baseline"] == nil)
    }

    @Test func stalePlanCannotEraseNewActivities() throws {
        let fixture = try AuditVaultFixture()
        let vault = fixture.vault
        _ = try vault.updateDayPlan(DayPlan(date: "2026-10-01"))
        var stale = vault.getDayPlan(date: "2026-10-01")
        let activity = try vault.createActivity(date: stale.date, body: "new record")
        stale.taskIds = ["t-example"]
        #expect(throws: ConflictError.self) { try vault.updateDayPlan(stale) }
        try vault.addTaskToPlan(date: stale.date, taskId: "t-example")
        #expect(vault.getDayPlan(date: stale.date).activities.first?.id == activity.id)
    }

    @Test func preservesUnknownYAMLValueTypes() throws {
        let input = """
        ---
        type: note
        id: n-yaml
        title: YAML
        nested:
          names: [one, two]
          enabled: true
        count: 42
        string_number: '42'
        empty: null
        ---

        body
        """
        var note = try #require(Frontmatter.parseMarkdown(content: input) as? Note)
        note.title = "changed"
        let multiline = "first\n---\n-->\n\n\n"
        note.extra["block"] = try Yams.dump(object: multiline)
        let output = try Frontmatter.serializeMarkdown(note)
        let yaml = try #require(Frontmatter.splitFrontmatter(output).yaml)
        let values = try #require(Yams.load(yaml: yaml) as? [String: Any])
        let nested = try #require(values["nested"] as? [String: Any])
        #expect(nested["names"] as? [String] == ["one", "two"])
        #expect(nested["enabled"] as? Bool == true)
        #expect(values["count"] as? Int == 42)
        #expect(values["string_number"] as? String == "42")
        #expect(values["empty"] is NSNull)
        #expect(values["block"] as? String == multiline)
        let metadataText = "first\n-->\n<!-- pata:activity\n<!-- /pata:activity -->\n\n\n"
        let activity = Activity(id: "a-yaml", at: Date(), body: "body", extra: [
            "nested": "{names: [one, two], enabled: true}",
            "block": try Yams.dump(object: metadataText)
        ])
        let formatted = try ActivityParser.formatActivities([activity])
        let reparsed = try #require(ActivityParser.parseActivities(formatted).first)
        let blockYAML = try #require(reparsed.extra["block"])
        #expect(try Yams.load(yaml: blockYAML) as? String == metadataText)
        let extraYAML = try #require(reparsed.extra["nested"])
        let metadata = try #require(Yams.load(yaml: extraYAML) as? [String: Any])
        #expect(metadata["enabled"] as? Bool == true)
        #expect(metadata["names"] as? [String] == ["one", "two"])
    }

    @Test func movedNoteSurvivesFirstRescan() throws {
        let fixture = try AuditVaultFixture()
        let vault = fixture.vault
        let note = try vault.createNote(title: "move", body: "body")
        let destination = URL(fileURLWithPath: vault.rootPath).appendingPathComponent("notes/moved.md")
        try FileManager.default.moveItem(atPath: vault.resolveEntityPath(note), toPath: destination.path)
        try vault.rescan()
        #expect(vault.index.getNote(note.id) != nil)
        #expect(vault.resolveEntityPath(note) == destination.path)
        #expect(vault.index.listParseErrors().isEmpty)
    }

    @Test func historicalActivityHasSelectedLocalDay() throws {
        let fixture = try AuditVaultFixture()
        let activity = try fixture.vault.createActivity(date: "2001-01-01", body: "history")
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        #expect(formatter.string(from: activity.at) == "2001-01-01")
        #expect(fixture.vault.getDayPlan(date: "2001-01-01").activities.first?.id == activity.id)
    }

    @Test func watchesInPlaceEditsNestedFilesAndExternalWritesAfterInternalWrites() async throws {
        let fixture = try AuditVaultFixture()
        let vault = fixture.vault
        let note = try vault.createNote(title: "watched", body: "before")
        vault.startWatcher()
        var external = note
        external.body = "external in-place edit"
        try Frontmatter.serializeMarkdown(external).write(toFile: vault.resolveEntityPath(note), atomically: false, encoding: .utf8)
        let nested = URL(fileURLWithPath: vault.rootPath).appendingPathComponent("notes/nested")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let imported = Note(id: "n-external", title: "external", body: "nested text")
        try Frontmatter.serializeMarkdown(imported).write(to: nested.appendingPathComponent("external.md"), atomically: true, encoding: .utf8)
        let deadline = Date().addingTimeInterval(6)
        while Date() < deadline {
            if vault.index.getNote(note.id)?.body.contains("external in-place edit") == true,
               vault.index.getNote(imported.id) != nil { break }
            try await _Concurrency.Task.sleep(for: .milliseconds(50))
        }
        #expect(vault.index.getNote(note.id)?.body.contains("external in-place edit") == true)
        #expect(vault.index.getNote(imported.id)?.body.contains("nested text") == true)
    }
}
