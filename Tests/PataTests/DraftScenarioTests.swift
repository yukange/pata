import Testing
import Foundation
@testable import PataCore

@Suite("BDD Feature: Notes & Drafts In-Place Lifecycle")
struct DraftScenarioTests {

    @Test("Given a draft note with empty title, when validated and serialized, then draft true is preserved and empty title is allowed")
    func draftNoteSchemaAndSerializationScenario() throws {
        // Given: A draft note with no title
        let now = Date()
        let draftNote = Note(
            id: "n-01drafttest",
            draft: true,
            title: "",
            createdAt: now,
            updatedAt: now,
            body: "草稿随笔内容"
        )

        // When: Validating entity schema
        // Then: Validation passes without error
        #expect(throws: Never.self) {
            try SchemaValidator.validateEntity(draftNote, path: "notes/n-01drafttest.md")
        }

        // When: Serialized to Markdown
        let text = try Frontmatter.serializeMarkdown(draftNote)

        // Then: Frontmatter explicitly contains draft: true
        #expect(text.contains("draft: true"))

        // And: Parsing back recovers the exact draft state
        let parsed = try Frontmatter.parseMarkdown(filePath: "notes/n-01drafttest.md", content: text)
        guard let parsedNote = parsed as? Note else {
            Issue.record("Expected Note")
            return
        }
        #expect(parsedNote.draft == true)
        #expect(parsedNote.title.isEmpty)
        #expect(parsedNote.body.trimmingCharacters(in: .whitespacesAndNewlines) == "草稿随笔内容")
    }

    @Test("Given a formal note with empty title, when validated, then validation fails with missing title reason")
    func formalNoteRequiresTitleScenario() {
        // Given: A non-draft note with an empty title
        let now = Date()
        let formalInvalid = Note(
            id: "n-01formaltest",
            draft: false,
            title: "",
            createdAt: now,
            updatedAt: now,
            body: "正式笔记正文"
        )

        // When: Validating schema
        // Then: Validation must fail with an explanation
        #expect(throws: SchemaError.self) {
            try SchemaValidator.validateEntity(formalInvalid, path: "notes/n-01formaltest.md")
        }
    }

    @Test("Given a draft note, when formatting its filename, then it uses bare ID without prefixing empty title")
    func draftFilenameFormattingScenario() {
        // Given: A draft note with an ID
        let draft = Note(
            id: "n-0123456789",
            draft: true,
            title: "",
            createdAt: Date(),
            updatedAt: Date()
        )

        // When: Formatting filename
        let filename = ULID.formatEntityFilename(draft)

        // Then: The filename is strictly bare ID with .md
        #expect(filename == "n-0123456789.md")

        // And: A formal note includes the title slug
        let formal = Note(
            id: "n-0123456789",
            draft: false,
            title: "测试笔记",
            createdAt: Date(),
            updatedAt: Date()
        )
        let formalFilename = ULID.formatEntityFilename(formal)
        #expect(formalFilename == "测试笔记_n-0123456789.md")
    }

    @Test("Given a draft note with content, when converted in-place to formal note with title, then the file is renamed, ID and body are preserved, and draft flag is removed")
    func draftInPlaceConversionScenario() throws {
        // Given: A vault with an active draft note
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("pata_bdd_draft_conv_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let vault = try Vault(rootPath: tmpDir.path)
        let draft = try vault.createNote(body: "会议即时记录内容", draft: true)
        let draftOriginalPath = vault.resolveEntityPath(draft)
        #expect(FileManager.default.fileExists(atPath: draftOriginalPath))

        // When: Naming the draft in-place into a formal note
        let formal = try vault.convertDraftToNote(id: draft.id, newTitle: "周会纪要", tags: ["会议"])

        // Then: The ID and original body are preserved
        #expect(formal.id == draft.id)
        #expect(formal.title == "周会纪要")
        #expect(formal.draft == false)
        #expect(formal.body.contains("会议即时记录内容"))
        #expect(formal.tags == ["会议"])

        // And: The file is updated in-place (preserving file path and ID)
        let formalPath = vault.resolveEntityPath(formal)
        #expect(formalPath == draftOriginalPath)
        #expect(FileManager.default.fileExists(atPath: formalPath))

        // And: Reading directly from disk and parsing back verifies persisted state
        let diskData = try Data(contentsOf: URL(fileURLWithPath: formalPath))
        let diskText = String(data: diskData, encoding: .utf8)!
        let diskParsed = try Frontmatter.parseMarkdown(filePath: formalPath, content: diskText) as? Note
        #expect(diskParsed?.title == "周会纪要")
        #expect(diskParsed?.draft == false)
        #expect(diskParsed?.tags == ["会议"])

        // And: In-memory index reflects the formal note immediately
        let indexed = vault.index.getNote(draft.id)
        #expect(indexed?.draft == false)
        #expect(indexed?.title == "周会纪要")
    }

    @Test("Given mixed formal notes and drafts, when listing notes, then they are sorted by updated timestamp descending")
    func listNotesSortingScenario() throws {
        // Given: A vault with notes updated at different times
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("pata_bdd_note_sort_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let vault = try Vault(rootPath: tmpDir.path)
        let n1 = try vault.createNote(title: "早先笔记", body: "内容 1")
        let draft = try vault.createNote(body: "最新草稿", draft: true)

        // When: Listing all notes
        let list = vault.index.listNotes()

        // Then: The most recently updated note (draft) comes first
        #expect(list.count == 2)
        #expect(list[0].id == draft.id)
        #expect(list[1].id == n1.id)
    }

    @Test("Given an existing note, when rescanning vault, then the note index is preserved continuously without index clearing")
    func rescanPreservesNoteIndexContinuouslyScenario() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("pata_bdd_note_rescan_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let vault = try Vault(rootPath: tmpDir.path)
        let note = try vault.createNote(title: "持续索引笔记", body: "正文内容", draft: false)

        // Verify initial index
        #expect(vault.index.getNote(note.id) != nil)

        // Rescan vault multiple times
        try vault.rescan()
        #expect(vault.index.getNote(note.id) != nil)
        #expect(vault.index.getNote(note.id)?.body.trimmingCharacters(in: .whitespacesAndNewlines) == "正文内容")

        // Directory write tracker verification for feedback suppression
        let notesDir = (tmpDir.path as NSString).appendingPathComponent("notes")
        var updated = note
        updated.body = "新正文内容"
        _ = try vault.updateNote(updated)

        #expect(vault.tracker.hasRecentWrites(inDirectory: notesDir, window: 2.0))
        #expect(vault.index.getNote(note.id)?.body.trimmingCharacters(in: .whitespacesAndNewlines) == "新正文内容")
    }
}
