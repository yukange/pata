import SwiftUI
import AppKit
import PataCore
import PataAudio
import PataEditor

public struct NotesView: View {
    @ObservedObject var state: AppState
    @StateObject private var audioPlayer = AudioPlayerManager.shared

    @State private var isDraftsCollapsed: Bool = false
    @State private var isNotesCollapsed: Bool = false
    @State private var listWidth: CGFloat = 280
    @State private var isAudioNote: Bool = false

    // Editing state
    @State private var currentTitle: String = ""
    @State private var currentBody: String = ""
    @State private var currentTags: [String] = []
    @State private var newTagInput: String = ""
    @State private var showTagPopover: Bool = false
    @State private var isNamingDraft: Bool = false
    @State private var backlinksOpen: Bool = false
    @State private var isEditorFocused: Bool = false
    @State private var autoSaveWorkItem: DispatchWorkItem? = nil

    public init(state: AppState) {
        self.state = state
    }

    private var allNotes: [Note] {
        state.vault?.index.listNotes().sorted { $0.updatedAt > $1.updatedAt } ?? []
    }

    private var drafts: [Note] {
        allNotes.filter { $0.draft }
    }

    private var formalNotes: [Note] {
        allNotes.filter { !$0.draft }
    }

    private var currentNote: Note? {
        guard let id = state.selectedNoteId else { return nil }
        return state.vault?.index.getNote(id)
    }

    private var backlinks: [LinkSource] {
        guard let note = currentNote, let vault = state.vault else { return [] }
        return vault.index.backlinks(targetID: note.id)
    }

    public var body: some View {
        HStack(spacing: 0) {
            // Left Column: Notes List (280px)
            leftColumn
                .frame(width: listWidth)
                .background(Color(nsColor: .windowBackgroundColor).opacity(0.4))

            // Divider
            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.6))
                .frame(width: 1)

            // Right Column: Note Editor or Empty State
            rightColumn
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .textBackgroundColor))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            syncCurrentNoteState()
        }
        .onChange(of: state.selectedNoteId) {
            flushAutoSave()
            syncCurrentNoteState()
        }
        .onChange(of: currentBody) { newBody in
            guard let note = currentNote, note.body != newBody else { return }
            scheduleAutoSave(for: note, body: newBody)
        }
        .onDisappear {
            flushAutoSave()
        }
    }

    private func syncCurrentNoteState() {
        if let note = currentNote {
            currentTitle = note.title
            currentBody = note.body
            currentTags = note.tags
            isNamingDraft = false
        }
    }

    // MARK: - Left Column

    private var leftColumn: some View {
        VStack(spacing: 0) {
            // Top Action Bar
            HStack {
                HStack(spacing: 6) {
                    Text("全部笔记")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)

                    Text("\(allNotes.count)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Split Button / Actions
                Menu {
                    Button(action: handleCreateDraft) {
                        Label("新建草稿", systemImage: "doc")
                    }
                    Button(action: handleCreateFormalNote) {
                        Label("新建笔记", systemImage: "doc.text")
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                        Text("新建草稿")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(state.effectiveAccentColor))
                    .foregroundColor(state.effectiveAccentOnColor)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            // Scrollable Groups
            ScrollView {
                VStack(spacing: 12) {
                    // Group 1: 草稿
                    VStack(spacing: 2) {
                        HStack {
                            Button {
                                isDraftsCollapsed.toggle()
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: isDraftsCollapsed ? "chevron.right" : "chevron.down")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(.secondary)

                                    Text("草稿")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(.secondary)

                                    Text("\(drafts.count)")
                                        .font(.system(size: 11, design: .monospaced))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.stoneBadgeBg))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .buttonStyle(.plain)

                            Spacer()

                            Button(action: handleCreateDraft) {
                                Image(systemName: "plus")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)

                        if !isDraftsCollapsed {
                            if drafts.isEmpty {
                                Text("暂无草稿")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                    .italic()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                            } else {
                                ForEach(drafts) { draft in
                                    draftRow(draft)
                                }
                            }
                        }
                    }

                    // Group 2: 笔记
                    VStack(spacing: 2) {
                        HStack {
                            Button {
                                isNotesCollapsed.toggle()
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: isNotesCollapsed ? "chevron.right" : "chevron.down")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(.secondary)

                                    Text("笔记")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(.secondary)

                                    Text("\(formalNotes.count)")
                                        .font(.system(size: 11, design: .monospaced))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.stoneBadgeBg))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .buttonStyle(.plain)

                            Spacer()
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)

                        if !isNotesCollapsed {
                            if formalNotes.isEmpty {
                                Text("暂无笔记")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                    .italic()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                            } else {
                                ForEach(formalNotes) { note in
                                    formalNoteRow(note)
                                }
                            }
                        }
                    }
                }
                .padding(8)
            }
        }
    }

    private func draftRow(_ draft: Note) -> some View {
        let isSelected = state.selectedNoteId == draft.id
        let excerpt = getDraftExcerpt(draft.body)

        return Button(action: {
            state.selectedNoteId = draft.id
        }) {
            VStack(alignment: .leading, spacing: 2) {
                if excerpt.isEmpty {
                    Text("(空草稿)")
                        .font(.system(size: 13))
                        .italic()
                        .foregroundColor(.secondary)
                } else {
                    Text(excerpt)
                        .font(.system(size: 13))
                        .lineLimit(2)
                        .lineSpacing(2)
                        .foregroundColor(isSelected ? .primary : .secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8).fill(isSelected ? Color.stoneSelectedBg : Color.clear))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("复制绝对路径") {
                copyNotePath(draft)
            }
            Button("在 Finder 中打开") {
                revealInFinder(draft)
            }
            Divider()
            Button("删除草稿", role: .destructive) {
                deleteNote(draft)
            }
        }
    }

    private func formalNoteRow(_ note: Note) -> some View {
        let isSelected = state.selectedNoteId == note.id

        return Button(action: {
            state.selectedNoteId = note.id
        }) {
            HStack(spacing: 6) {
                if note.audioTranscript {
                    Image(systemName: "waveform")
                        .font(.system(size: 11))
                        .foregroundColor(.accentColor)
                }

                Text(note.title.isEmpty ? "未命名笔记" : note.title)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                    .foregroundColor(isSelected ? .primary : Color(nsColor: .labelColor).opacity(0.85))
                    .lineLimit(1)

                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(isSelected ? Color.stoneSelectedBg : Color.clear))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("复制绝对路径") {
                copyNotePath(note)
            }
            Button("在 Finder 中打开") {
                revealInFinder(note)
            }
            Divider()
            Button("删除笔记", role: .destructive) {
                deleteNote(note)
            }
        }
    }

    // MARK: - Right Column

    private var rightColumn: some View {
        Group {
            if let note = currentNote {
                noteEditorView(note)
            } else {
                emptyStateView
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.text")
                .font(.system(size: 38))
                .foregroundColor(Color.secondary.opacity(0.4))
                .padding(.bottom, 4)

            Text("选择笔记开始阅读或编辑")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.primary)

            Text("或者直接创建新草稿随手记录")
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            Button(action: handleCreateDraft) {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 11))
                    Text("新建草稿")
                        .font(.system(size: 12, weight: .medium))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func noteEditorView(_ note: Note) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if note.draft && !isNamingDraft {
                // Draft Mode: Floating action bar
                HStack {
                    Spacer()

                    Button(action: { isNamingDraft = true }) {
                        Text("转为笔记")
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor), lineWidth: 1))
                    }
                    .buttonStyle(.plain)

                    moreMenu(note)
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 8)
            } else {
                // Formal Note Mode or Draft Naming Header
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .center) {
                        TextField("无标题笔记", text: $currentTitle, onCommit: {
                            saveNoteTitle(note)
                        })
                        .font(.system(size: 24, weight: .bold))
                        .textFieldStyle(.plain)

                        Spacer()

                        moreMenu(note)
                    }

                    // Metadata Row: Author & Tags
                    HStack(spacing: 12) {
                        HStack(spacing: 4) {
                            Image(systemName: note.createdBy == "agent" ? "cpu" : "person")
                                .font(.system(size: 11))
                            Text(note.createdBy == "agent" ? "智能体创建" : "由我创建")
                                .font(.system(size: 11))
                        }
                        .foregroundColor(.secondary)

                        // Tags Chips
                        HStack(spacing: 6) {
                            ForEach(currentTags, id: \.self) { tag in
                                HStack(spacing: 3) {
                                    Text("#\(tag)")
                                        .font(.system(size: 11))
                                    Button(action: { removeTag(tag, from: note) }) {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 9))
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(RoundedRectangle(cornerRadius: 4).fill(Color.stoneTagBg))
                                .foregroundColor(.primary)
                            }

                            Button(action: { showTagPopover.toggle() }) {
                                HStack(spacing: 2) {
                                    Image(systemName: "plus")
                                        .font(.system(size: 9))
                                    Text("标签")
                                        .font(.system(size: 11))
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(RoundedRectangle(cornerRadius: 4).stroke(Color(nsColor: .separatorColor), lineWidth: 1))
                                .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .popover(isPresented: $showTagPopover) {
                                VStack(spacing: 8) {
                                    TextField("添加标签...", text: $newTagInput, onCommit: {
                                        addTag(newTagInput, to: note)
                                    })
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 140)
                                }
                                .padding(8)
                            }
                        }

                        if isNamingDraft {
                            Button("确认转为笔记") {
                                convertCurrentDraft(note)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 12)

                Divider()
            }

            // Editor / Content Body
            PataNoteEditor(
                noteId: note.id,
                text: $currentBody,
                isReadOnlyTranscript: note.audioTranscript,
                isFocused: $isEditorFocused,
                onSeekAudio: { ms in
                    audioPlayer.seek(toMilliseconds: ms)
                },
                onOpenLink: { target in
                    handleOpenLink(target)
                }
            )
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Backlinks drawer
            if !backlinks.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Button {
                        backlinksOpen.toggle()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: backlinksOpen ? "chevron.down" : "chevron.right")
                                .font(.system(size: 9))
                            Text("被引用 · \(backlinks.count)")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)

                    if backlinksOpen {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(backlinks, id: \.id) { ref in
                                Button(action: {
                                    if ref.type == .task {
                                        state.selectedTaskId = ref.id
                                    } else {
                                        state.selectedNoteId = ref.id
                                    }
                                }) {
                                    Text("\(ref.type == .task ? "任务 · " : "")\(ref.title.isEmpty ? ref.id : ref.title)")
                                        .font(.system(size: 11))
                                        .foregroundColor(.accentColor)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.leading, 12)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
            }
        }
    }

    private func moreMenu(_ note: Note) -> some View {
        Menu {
            Button("复制绝对路径") {
                copyNotePath(note)
            }
            Button("在 Finder 中打开") {
                revealInFinder(note)
            }
            Divider()
            Button(note.draft ? "删除草稿" : "删除笔记", role: .destructive) {
                deleteNote(note)
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .padding(4)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: - Actions

    private func handleCreateDraft() {
        guard let v = state.vault else { return }
        do {
            let note = try v.createNote(title: "", body: "", tags: [], draft: true)
            state.selectedNoteId = note.id
            state.rescanVault()
        } catch {
            print("Create draft error: \(error)")
        }
    }

    private func handleCreateFormalNote() {
        guard let v = state.vault else { return }
        do {
            let note = try v.createNote(title: "未命名笔记", body: "", tags: [], draft: false)
            state.selectedNoteId = note.id
            state.rescanVault()
        } catch {
            print("Create note error: \(error)")
        }
    }

    private func convertCurrentDraft(_ note: Note) {
        guard let v = state.vault else { return }
        do {
            _ = try v.convertDraftToNote(id: note.id, newTitle: currentTitle.isEmpty ? "未命名笔记" : currentTitle, tags: currentTags)
            isNamingDraft = false
            state.rescanVault()
        } catch {
            print("Convert draft error: \(error)")
        }
    }

    private func saveNoteTitle(_ note: Note) {
        guard let v = state.vault else { return }
        var updated = note
        updated.title = currentTitle
        do {
            _ = try v.updateNote(updated)
            state.rescanVault()
        } catch {
            print("Update note title error: \(error)")
        }
    }

    private func scheduleAutoSave(for note: Note, body: String) {
        autoSaveWorkItem?.cancel()
        let noteId = note.id
        let item = DispatchWorkItem { [weak state] in
            guard let s = state, let v = s.vault, let n = v.index.getNote(noteId) else { return }
            if n.body != body {
                var updated = n
                updated.body = body
                do {
                    _ = try v.updateNote(updated)
                } catch {
                    print("Update note body error: \(error)")
                }
            }
        }
        autoSaveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: item)
    }

    private func flushAutoSave() {
        if let item = autoSaveWorkItem {
            item.cancel()
            autoSaveWorkItem = nil
            if let note = currentNote, note.body != currentBody, let v = state.vault {
                var updated = note
                updated.body = currentBody
                do {
                    _ = try v.updateNote(updated)
                } catch {
                    print("Flush note body error: \(error)")
                }
            }
        }
    }

    private func addTag(_ tag: String, to note: Note) {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !currentTags.contains(trimmed) else { return }
        currentTags.append(trimmed)
        newTagInput = ""
        showTagPopover = false

        guard let v = state.vault else { return }
        var updated = note
        updated.tags = currentTags
        do {
            _ = try v.updateNote(updated)
            state.rescanVault()
        } catch {
            print("Add tag error: \(error)")
        }
    }

    private func removeTag(_ tag: String, from note: Note) {
        currentTags.removeAll { $0 == tag }
        guard let v = state.vault else { return }
        var updated = note
        updated.tags = currentTags
        do {
            _ = try v.updateNote(updated)
            state.rescanVault()
        } catch {
            print("Remove tag error: \(error)")
        }
    }

    private func copyNotePath(_ note: Note) {
        if let v = state.vault {
            let path = v.resolveEntityPath(note)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(path, forType: .string)
        }
    }

    private func revealInFinder(_ note: Note) {
        if let v = state.vault {
            let path = v.resolveEntityPath(note)
            NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: v.rootPath)
        }
    }

    private func deleteNote(_ note: Note) {
        guard let v = state.vault else { return }
        do {
            try v.deleteNote(id: note.id)
            if state.selectedNoteId == note.id {
                state.selectedNoteId = nil
            }
            state.rescanVault()
        } catch {
            print("Delete note error: \(error)")
        }
    }

    private func getDraftExcerpt(_ body: String) -> String {
        let lines = body.components(separatedBy: .newlines)
        var textLines: [String] = []
        for line in lines {
            let cleaned = line
                .replacingOccurrences(of: #"^#{1,6}\s+"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"^>\s+"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"^[-*+]\s+(\[[ xX]\]\s+)?"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"^\d+\.\s+"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"\[([^\]]+)\]\([^)]+\)"#, with: "$1", options: .regularExpression)
                .replacingOccurrences(of: #"\[\[([^\]|]+)(?:\|[^\]]+)?\]\]"#, with: "$1", options: .regularExpression)
                .replacingOccurrences(of: #"[`*_~=]"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty {
                textLines.append(cleaned)
                if textLines.count >= 2 { break }
            }
        }
        return textLines.joined(separator: "\n")
    }

    private func handleOpenLink(_ target: String) {
        guard let v = state.vault else { return }
        // Check if it's a note
        for n in v.index.listNotes() {
            if target == n.id || target.hasSuffix("/\(n.id).md") || target.contains(n.id) {
                state.selectedNoteId = n.id
                return
            }
            let relPath = v.resolveEntityPath(n)
            if relPath.hasSuffix(target) || target.hasSuffix(relPath) {
                state.selectedNoteId = n.id
                return
            }
        }

        // Check if it's a file
        if target.hasPrefix("files/") {
            let full = (v.rootPath as NSString).appendingPathComponent(target)
            if FileManager.default.fileExists(atPath: full) {
                NSWorkspace.shared.open(URL(fileURLWithPath: full))
            }
        }
    }
}
