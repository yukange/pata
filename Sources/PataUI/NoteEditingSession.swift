import Foundation
import Combine
import PataCore

@MainActor
public final class NoteEditingSession: ObservableObject {
    @Published public private(set) var note: Note?
    @Published public private(set) var error: String?
    public private(set) var isDirty = false
    private var vault: Vault?
    private var pendingSave: DispatchWorkItem?

    public init() {}

    public func isEditing(noteId: String, in vault: Vault) -> Bool {
        self.vault === vault && note?.id == noteId
    }

    @discardableResult
    public func select(_ note: Note?, in vault: Vault?) -> Bool {
        if self.vault === vault, self.note?.id == note?.id {
            if !isDirty { self.note = note }
            return true
        }
        guard save() else { return false }
        self.vault = vault
        self.note = note
        error = nil
        return true
    }

    public func edit(_ change: (inout Note) -> Void) {
        guard var edited = note else { return }
        change(&edited)
        guard edited != note else { return }
        note = edited
        isDirty = true
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.save() }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    @discardableResult
    public func save() -> Bool {
        pendingSave?.cancel()
        pendingSave = nil
        guard isDirty, let note, let vault else { return true }
        do {
            guard vault.index.getNote(note.id) != nil else {
                throw SchemaError.validationError(field: "id", reason: "笔记已被删除，本地编辑仍保留")
            }
            self.note = try vault.updateNote(note)
            isDirty = false
            error = nil
            return true
        } catch {
            self.error = "保存失败：\(error.localizedDescription)"
            return false
        }
    }

    public func acceptSavedNote(_ note: Note, in vault: Vault) {
        guard isEditing(noteId: note.id, in: vault), !isDirty else { return }
        // A watcher echo of already-saved bytes is not an external edit. Keep the
        // editor state intact so the duplicate notification cannot interrupt IME.
        if let baseline = self.note?.baseline, baseline == note.baseline { return }
        self.note = note
    }

    public func discard() {
        pendingSave?.cancel()
        pendingSave = nil
        note = nil
        vault = nil
        isDirty = false
        error = nil
    }

    public func reload() {
        guard let vault, let id = note?.id else { return }
        do {
            try vault.rescan()
            guard let latest = vault.index.getNote(id) else {
                throw SchemaError.validationError(field: "id", reason: "磁盘上的笔记不可读取，本地编辑仍保留")
            }
            pendingSave?.cancel()
            pendingSave = nil
            note = latest
            isDirty = false
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
