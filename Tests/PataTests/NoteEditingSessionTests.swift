import Foundation
import Testing
import AppKit
import SwiftUI
import PataEditor
@testable import PataCore
@testable import PataUI

@Suite("Audit: note editing and transcription", .serialized)
@MainActor
struct NoteEditingSessionTests {
    @Test(arguments: [true, false])
    func autosaveEchoPreservesMarkedTextAndCommittedChinese(draft: Bool) async throws {
        _ = NSApplication.shared
        let fixture = try AuditVaultFixture()
        let session = NoteEditingSession()
        let note = try fixture.vault.createNote(title: draft ? "" : "笔记", draft: draft)
        #expect(session.select(note, in: fixture.vault))
        let host = NSHostingView(rootView: CompositionTestEditor(session: session, noteId: note.id))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        try await _Concurrency.Task.sleep(for: .milliseconds(100))
        let textView = try #require(findTextView(in: host))
        window.makeFirstResponder(textView)
        textView.insertText("已提交", replacementRange: NSRange(location: 0, length: 0))
        try await _Concurrency.Task.sleep(for: .milliseconds(50))
        #expect(session.note?.body == "已提交")
        textView.setMarkedText(
            "zhongwen", selectedRange: NSRange(location: 8, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        #expect(textView.hasMarkedText())

        // Allow the real autosave to finish while the next word is still composing.
        try await _Concurrency.Task.sleep(for: .milliseconds(650))
        #expect(!session.isDirty)
        try fixture.vault.rescan()
        session.acceptSavedNote(try #require(fixture.vault.index.getNote(note.id)), in: fixture.vault)
        try await _Concurrency.Task.sleep(for: .milliseconds(100))
        #expect(textView.string == "已提交zhongwen")
        #expect(textView.hasMarkedText())

        textView.insertText("中文", replacementRange: textView.markedRange())
        try await _Concurrency.Task.sleep(for: .milliseconds(650))
        #expect(!textView.hasMarkedText())
        #expect(!session.isDirty)
        try fixture.vault.rescan()
        #expect(fixture.vault.index.getNote(note.id)?.body == "已提交中文")
    }

    @Test(arguments: [true, false])
    func savedFileEchoPreservesEditorText(draft: Bool) throws {
        let fixture = try AuditVaultFixture()
        let session = NoteEditingSession()
        let note = try fixture.vault.createNote(title: draft ? "" : "笔记", draft: draft)
        #expect(session.select(note, in: fixture.vault))
        session.edit { $0.body = "已提交的中文" }
        #expect(session.save())
        let saved = try #require(session.note)

        try fixture.vault.rescan()
        let reread = try #require(fixture.vault.index.getNote(note.id))
        #expect(reread.body == "已提交的中文")
        #expect(reread.baseline == saved.baseline)
        session.acceptSavedNote(reread, in: fixture.vault)
        #expect(session.note == saved)
        #expect(!session.isDirty)

        // An actual external edit must still be accepted, with a usable new baseline.
        var external = reread
        external.body = "外部修改"
        try Frontmatter.serializeMarkdown(external).write(
            toFile: fixture.vault.resolveEntityPath(note), atomically: true, encoding: .utf8
        )
        try fixture.vault.rescan()
        let changed = try #require(fixture.vault.index.getNote(note.id))
        #expect(changed.baseline != saved.baseline)
        session.acceptSavedNote(changed, in: fixture.vault)
        #expect(session.note == changed)
        session.edit { $0.body += "继续编辑" }
        #expect(session.save())
        #expect(fixture.vault.index.getNote(note.id)?.body == "外部修改继续编辑")
    }

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

    @Test func floatingEditorControlsUseArrowWithoutChangingTextCursor() async throws {
        _ = NSApplication.shared
        var isOverControls = false
        var exclusionWasQueried = false
        let host = NSHostingView(rootView: PataNoteEditor(
            noteId: "cursor-test",
            text: .constant("正文内容"),
            isCursorExcluded: { _ in
                exclusionWasQueried = true
                return isOverControls
            }
        ))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        try await _Concurrency.Task.sleep(for: .milliseconds(100))
        let textView = try #require(findTextView(in: host))
        let event = try #require(NSEvent.mouseEvent(
            with: .mouseMoved,
            location: textView.convert(NSPoint(x: 30, y: 12), to: nil),
            modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
            context: nil, eventNumber: 0, clickCount: 0, pressure: 0
        ))

        NSCursor.crosshair.set()
        textView.mouseMoved(with: event)
        let normalCursor = NSCursor.current

        isOverControls = true
        exclusionWasQueried = false
        NSCursor.iBeam.set()
        textView.mouseMoved(with: event)
        #expect(exclusionWasQueried)
        #expect(NSCursor.current == .arrow)
        // A second move must not let the editor overwrite the arrow again.
        textView.mouseMoved(with: event)
        #expect(NSCursor.current == .arrow)

        isOverControls = false
        NSCursor.crosshair.set()
        textView.mouseMoved(with: event)
        #expect(NSCursor.current == normalCursor)
    }

    private func findTextView(in view: NSView) -> NSTextView? {
        if let textView = view as? NSTextView { return textView }
        return view.subviews.lazy.compactMap { self.findTextView(in: $0) }.first
    }
}

private struct CompositionTestEditor: View {
    @ObservedObject var session: NoteEditingSession
    let noteId: String

    var body: some View {
        PataNoteEditor(
            noteId: noteId,
            text: Binding(
                get: { session.note?.body ?? "" },
                set: { value in session.edit { $0.body = value } }
            )
        )
    }
}
