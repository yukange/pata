import Foundation
import Testing
@testable import PataCore
@testable import PataUI

@Suite("Audit: note editing and transcription", .serialized)
@MainActor
struct NoteEditingSessionTests {
    @Test func navigationFlushesTheOriginalNoteOnly() throws {
        let fixture = try AuditVaultFixture()
        let state = AppState(loadPreferences: false)
        state.openVault(path: fixture.vault.rootPath, persist: false)
        let vault = try #require(state.vault)
        let a = try vault.createNote(title: "A", body: "original A")
        let b = try vault.createNote(title: "B", body: "original B")
        state.currentNav = .notes
        state.selectedNoteId = a.id
        state.noteEditor.edit { $0.body = "unsaved A" }
        state.navigateToNote(noteId: b.id)
        #expect(state.selectedNoteId == b.id)
        #expect(vault.index.getNote(a.id)?.body == "unsaved A")
        #expect(vault.index.getNote(b.id)?.body == "original B")
        #expect(state.noteEditor.note?.body == "original B")
    }

    @Test func conflictsPreserveDraftAndBlockEveryLeavePath() throws {
        let fixture = try AuditVaultFixture()
        let other = try AuditVaultFixture()
        let state = AppState(loadPreferences: false)
        state.openVault(path: fixture.vault.rootPath, persist: false)
        let vault = try #require(state.vault)
        let a = try vault.createNote(title: "A", body: "original A")
        let b = try vault.createNote(title: "B", body: "original B")
        state.currentNav = .notes
        state.selectedNoteId = a.id
        state.noteEditor.edit { $0.body = "local draft" }
        var external = a
        external.body = "external edit"
        try Frontmatter.serializeMarkdown(external).write(toFile: vault.resolveEntityPath(a), atomically: true, encoding: .utf8)
        try vault.rescan()
        state.navigateToNote(noteId: b.id)
        #expect(state.selectedNoteId == a.id)
        #expect(state.noteEditor.note?.body == "local draft")
        #expect(state.noteEditor.error != nil)
        state.currentNav = .tasks
        #expect(state.currentNav == .notes)
        state.showSettings = true
        #expect(!state.showSettings)
        state.openVault(path: other.vault.rootPath, persist: false)
        #expect(state.vault === vault)
        #expect(!state.noteEditor.save()) // The same gate is used by applicationShouldTerminate.
        #expect(state.noteEditor.isDirty)
        #expect(vault.index.getNote(a.id)?.body.contains("external edit") == true)
        #expect(vault.index.getNote(b.id)?.body.trimmingCharacters(in: .whitespacesAndNewlines) == "original B")
        state.noteEditor.reload()
        #expect(!state.noteEditor.isDirty)
        #expect(state.noteEditor.note?.body.contains("external edit") == true)
        state.navigateToNote(noteId: b.id)
        #expect(state.selectedNoteId == b.id)
        state.noteEditor.edit { $0.body = "draft before external deletion" }
        try vault.deleteNote(id: b.id)
        state.navigateToNote(noteId: a.id)
        #expect(state.selectedNoteId == b.id)
        #expect(state.noteEditor.isDirty)
        state.noteEditor.discard()
        state.selectedNoteId = nil
        state.navigateToNote(noteId: a.id)
        #expect(state.selectedNoteId == a.id)
        #expect(!state.noteEditor.isDirty)
        #expect(vault.index.getNote(b.id) == nil)
    }

    @Test func pendingSaveCannotWriteIntoNewSelection() async throws {
        let fixture = try AuditVaultFixture()
        let session = NoteEditingSession()
        let a = try fixture.vault.createNote(title: "A", body: "A")
        let b = try fixture.vault.createNote(title: "B", body: "B")
        #expect(session.select(a, in: fixture.vault))
        session.edit { $0.body = "saved A" }
        #expect(session.select(b, in: fixture.vault))
        try await _Concurrency.Task.sleep(for: .milliseconds(650))
        #expect(fixture.vault.index.getNote(a.id)?.body == "saved A")
        #expect(fixture.vault.index.getNote(b.id)?.body == "B")
    }

    @Test func transcriptionKeepsItsOriginalVaultAndDoesNotReplaceOtherEditor() throws {
        let fixture = try AuditVaultFixture()
        let other = try AuditVaultFixture()
        let state = AppState(loadPreferences: false)
        state.openVault(path: fixture.vault.rootPath, persist: false)
        let vault = try #require(state.vault)
        let audio = try vault.createNote(title: "recording", body: "old transcript", audioFile: "files/audio.mp3", audioTranscript: true)
        var renamed = audio
        renamed.title = "renamed while transcribing"
        _ = try vault.updateNote(renamed)
        let b = try vault.createNote(title: "B", body: "B")
        state.selectedNoteId = b.id
        try state.saveTranscript("new transcript", noteId: audio.id, audioFile: "files/audio.mp3", in: vault)
        #expect(state.noteEditor.note?.body == "B")
        #expect(vault.index.getNote(b.id)?.body == "B")
        #expect(vault.index.getNote(audio.id)?.title == renamed.title)
        state.openVault(path: other.vault.rootPath, persist: false)
        try state.saveTranscript("another transcript", noteId: audio.id, audioFile: "files/audio.mp3", in: vault)
        #expect(state.vault?.index.getNote(audio.id) == nil)
        #expect(vault.index.getNote(audio.id)?.body == "another transcript")
        try vault.deleteNote(id: audio.id)
        #expect(throws: SchemaError.self) {
            try state.saveTranscript("late result", noteId: audio.id, audioFile: "files/audio.mp3", in: vault)
        }
        #expect(vault.index.getNote(audio.id) == nil)
    }

    @Test func activityViewHonorsBoundIDsAfterRenameAndDeletion() throws {
        let fixture = try AuditVaultFixture()
        let state = AppState(loadPreferences: false)
        state.openVault(path: fixture.vault.rootPath, persist: false)
        let vault = try #require(state.vault)
        let original = try vault.createNote(title: "same")
        let replacement = try vault.createNote(title: "same")
        let view = ActivityTextView(text: "[[same]]", state: state, noteRefs: ["same": original.id])
        #expect(view.noteDestination(named: "same") == original.id)
        var renamed = original
        renamed.title = "renamed"
        _ = try vault.updateNote(renamed)
        #expect(view.noteDestination(named: "same") == original.id)
        try vault.deleteNote(id: original.id)
        #expect(vault.index.getNote(replacement.id) != nil)
        #expect(view.noteDestination(named: "same") == nil)
    }
}
