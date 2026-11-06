import SwiftUI
import AppKit
import UniformTypeIdentifiers
import PataCore
import PataAudio
import PataEditor

public struct NotesView: View {
    @ObservedObject var state: AppState
    @StateObject private var asrManager = ASRManager.shared
    @ObservedObject private var editor: NoteEditingSession

    @State private var isDraftsCollapsed: Bool = false
    @State private var isNotesCollapsed: Bool = false
    @State private var isAudioNote: Bool = false
    @State private var showMissingKeyAlert: Bool = false

    // Editing state
    private var currentTitle: String {
        get { editor.note?.title ?? currentNote?.title ?? "" }
        nonmutating set { editor.edit { $0.title = newValue } }
    }
    private var currentBody: String {
        get { editor.note?.body ?? currentNote?.body ?? "" }
        nonmutating set { editor.edit { if !$0.audioTranscript { $0.body = newValue } } }
    }
    private var currentTags: [String] {
        get { editor.note?.tags ?? currentNote?.tags ?? [] }
        nonmutating set { editor.edit { $0.tags = newValue } }
    }
    @State private var newTagInput: String = ""
    @State private var showTagPopover: Bool = false
    @State private var isNamingDraft: Bool = false
    @State private var isHoveringDraftActions = false
    @FocusState private var isTitleFocused: Bool
    @State private var backlinksOpen: Bool = false
    @State private var isEditorFocused: Bool = false
    @State private var scrollToAudioMs: Int? = nil
    @State private var showReloadConfirmation = false
    @State private var hoveredNoteId: String? = nil
    @State private var notePendingDeletion: Note? = nil
    @State private var showDeleteNoteConfirm: Bool = false

    public init(state: AppState) {
        self.state = state
        self.editor = state.noteEditor
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
        if editor.note?.id == id { return editor.note }
        return state.vault?.index.getNote(id)
    }

    private var backlinks: [LinkSource] {
        guard let note = currentNote, let vault = state.vault else { return [] }
        return vault.index.backlinks(targetID: note.id)
    }

    public var body: some View {
        HStack(spacing: 0) {
            // Left Column: Notes List (resizable width)
            if !state.isNotesListCollapsed {
                leftColumn
                    .frame(width: state.notesListWidth)
                    .background(Color(nsColor: .windowBackgroundColor).opacity(0.4))
                    .transition(.move(edge: .leading))

                // Resizer Divider
                dividerHandle
            }

            // Right Column: Note Editor or Empty State
            VStack(spacing: 0) {
                if let error = editor.error {
                    HStack {
                        Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled)
                        Spacer()
                        Button("重试保存") { editor.save() }
                        Button("处理未保存的修改…") { showReloadConfirmation = true }
                    }
                    .padding(12)
                }
                rightColumn
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .coordinateSpace(.named(Self.splitSpace))
        .onAppear {
            syncCurrentNoteState()
        }
        .onChange(of: state.selectedNoteId) {
            syncCurrentNoteState()
        }
        .onDisappear {
            editor.save()
            AudioPlayerManager.shared.stop()
        }
        .confirmationDialog("放弃未保存的本地修改？", isPresented: $showReloadConfirmation) {
            Button("放弃修改并重新载入", role: .destructive) { editor.reload() }
            Button("放弃修改并关闭笔记", role: .destructive) {
                editor.discard()
                state.selectedNoteId = nil
            }
            Button("取消", role: .cancel) {}
        }
        .alert("需配置语音转写 API Key", isPresented: $showMissingKeyAlert) {
            Button("前往设置") {
                state.showSettings = true
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(state.asrKeyError ?? "音频逐字稿生成依赖阿里云百炼 DashScope 语音服务。请先在「设置 - 语音转写」中配置 API Key。")
        }
        .alert(
            notePendingDeletion?.draft == true ? "确认删除草稿？" : "确认删除笔记？",
            isPresented: $showDeleteNoteConfirm,
            presenting: notePendingDeletion
        ) { note in
            Button("删除", role: .destructive) {
                deleteNote(note)
                notePendingDeletion = nil
            }
            Button("取消", role: .cancel) {
                notePendingDeletion = nil
            }
        } message: { note in
            if note.draft {
                Text("删除后无法恢复，确定要永久删除该草稿吗？")
            } else {
                let title = note.title.isEmpty ? "该笔记" : "笔记「\(note.title)」"
                Text("删除后无法恢复，确定要永久删除\(title)吗？")
            }
        }
    }

    private func selectNote(_ note: Note) {
        guard state.selectedNoteId != note.id, editor.save() else { return }
        isNamingDraft = false
        state.selectedNoteId = note.id
    }

    private func syncCurrentNoteState() {
        let selected = state.selectedNoteId.flatMap { state.vault?.index.getNote($0) }
        guard editor.select(selected, in: state.vault) else { return }
        if let note = editor.note {
            isNamingDraft = false

            if note.audioTranscript, let audioRelPath = note.audioFile, let v = state.vault {
                let fullAudioURL = URL(fileURLWithPath: (v.rootPath as NSString).appendingPathComponent(audioRelPath))
                AudioPlayerManager.shared.loadAudio(url: fullAudioURL, relativePath: audioRelPath)
            } else {
                AudioPlayerManager.shared.stop()
            }
        } else {
            AudioPlayerManager.shared.stop()
        }
    }

    // MARK: - Left Column

    private var leftColumn: some View {
        let notes = allNotes
        let currentDrafts = notes.filter { $0.draft }
        let currentFormalNotes = notes.filter { !$0.draft }

        return VStack(spacing: 0) {
            // Top Action Bar
            HStack {
                HStack(spacing: 6) {
                    Text("全部笔记")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)

                    Text("\(notes.count)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Collapse sidebar button
                NotesSidebarToggleButton(collapsed: false) {
                    state.toggleNotesList()
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 2)

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

                                    Text("\(currentDrafts.count)")
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
                                    .frame(width: 20, height: 20)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help("新建草稿")
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)

                        if !isDraftsCollapsed {
                            if currentDrafts.isEmpty {
                                Text("暂无草稿")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                    .italic()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                            } else {
                                ForEach(currentDrafts) { draft in
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

                                    Text("\(currentFormalNotes.count)")
                                        .font(.system(size: 11, design: .monospaced))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.stoneBadgeBg))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .buttonStyle(.plain)

                            Spacer()

                            Menu {
                                Button(action: handleCreateFormalNote) {
                                    Label("新建笔记", systemImage: "doc.text")
                                }
                                Button(action: handleCreateAudioNote) {
                                    Label("从音频创建逐字稿", systemImage: "waveform")
                                }
                            } label: {
                                Image(systemName: "plus")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                    .frame(width: 20, height: 20)
                                    .contentShape(Rectangle())
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                            .help("新建笔记...")
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)

                        if !isNotesCollapsed {
                            if currentFormalNotes.isEmpty {
                                Text("暂无笔记")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                    .italic()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                            } else {
                                ForEach(currentFormalNotes) { note in
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
        let isHovered = hoveredNoteId == draft.id
        let excerpt = getDraftExcerpt(draft.body)

        return Button(action: {
            selectNote(draft)
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
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.stoneSelectedBg : (isHovered ? Color.primary.opacity(0.04) : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering {
                hoveredNoteId = draft.id
            } else if hoveredNoteId == draft.id {
                hoveredNoteId = nil
            }
        }
        .contextMenu {
            Button("复制绝对路径") {
                copyNotePath(draft)
            }
            Button("在 Finder 中打开") {
                revealInFinder(draft)
            }
            Divider()
            Button("删除草稿", role: .destructive) {
                notePendingDeletion = draft
                showDeleteNoteConfirm = true
            }
        }
    }

    private func formalNoteRow(_ note: Note) -> some View {
        let isSelected = state.selectedNoteId == note.id
        let isHovered = hoveredNoteId == note.id

        return Button(action: {
            selectNote(note)
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
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.stoneSelectedBg : (isHovered ? Color.primary.opacity(0.04) : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering {
                hoveredNoteId = note.id
            } else if hoveredNoteId == note.id {
                hoveredNoteId = nil
            }
        }
        .contextMenu {
            Button("复制绝对路径") {
                copyNotePath(note)
            }
            Button("在 Finder 中打开") {
                revealInFinder(note)
            }
            Divider()
            Button("删除笔记", role: .destructive) {
                notePendingDeletion = note
                showDeleteNoteConfirm = true
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
        VStack(spacing: 0) {
            if state.isNotesListCollapsed {
                HStack {
                    NotesSidebarToggleButton(collapsed: true) {
                        state.toggleNotesList()
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
            }

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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func noteEditorView(_ note: Note) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if !note.draft || isNamingDraft {
                // Formal Note Mode or Draft Naming Header
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .center, spacing: 10) {
                        if state.isNotesListCollapsed {
                            NotesSidebarToggleButton(collapsed: true) {
                                state.toggleNotesList()
                            }
                        }

                        TextField("无标题笔记", text: Binding(get: { currentTitle }, set: { currentTitle = $0 }), onCommit: {
                            if isNamingDraft {
                                convertCurrentDraft(note)
                            } else {
                                editor.save()
                            }
                        })
                        .font(.system(size: 24, weight: .semibold))
                        .textFieldStyle(.plain)
                        .focused($isTitleFocused)

                        Spacer()

                        moreMenu(note)
                    }

                    // Metadata Row: Author & Tags
                    HStack(spacing: 12) {
                        HStack(spacing: 4) {
                            Image(systemName: note.createdBy == "agent" ? "sparkles" : "person")
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
                            Button("取消") {
                                isNamingDraft = false
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)

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
            }

            // Audio Player Toolbar for audio transcript notes
            if note.audioTranscript {
                AudioPlayerToolbarView(
                    note: note,
                    accentColor: state.effectiveAccentColor,
                    accentOnColor: state.effectiveAccentOnColor,
                    asrManager: asrManager,
                    onConfirmReplace: {
                        handleConfirmReplace(note)
                    },
                    onSeek: { ms in
                        scrollToAudioMs = ms
                    }
                )
                Divider()
            }

            // Editor / Content Body
            if note.audioTranscript && currentBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let status = asrManager.getStatus(for: note.id)
                VStack(spacing: 12) {
                    if status.state == .uploading || status.state == .transcribing || status.state == .writing {
                        ProgressView()
                            .controlSize(.regular)
                        Text(status.stageMessage.isEmpty ? "正在后台转写逐字稿..." : status.stageMessage)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                        Text("转写完成后将自动生成带时间戳与说话人的逐字稿正文")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary.opacity(0.8))
                    } else if status.state == .failed {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 28))
                            .foregroundColor(.roseBadgeText)
                        Text("转写失败")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.primary)
                        Text(status.error ?? "未能完成转写，请检查网络或 API Key")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Button("重试转写") {
                            triggerTranscription(for: note, isRetranscribe: false)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    } else {
                        Image(systemName: "waveform")
                            .font(.system(size: 28))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text("暂无逐字稿正文")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                        Button("开始转写") {
                            triggerTranscription(for: note, isRetranscribe: false)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else if note.audioTranscript {
                PataTranscriptViewer(
                    body: currentBody,
                    accentColor: state.effectiveAccentColor,
                    scrollToMs: $scrollToAudioMs,
                    onSeekAudio: { ms in
                        AudioPlayerManager.shared.seek(toMilliseconds: ms, autoPlay: true)
                    }
                )
                .id(note.id)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                PataNoteEditor(
                    noteId: note.id,
                    text: Binding(get: { currentBody }, set: { currentBody = $0 }),
                    isReadOnlyTranscript: false,
                    isFocused: $isEditorFocused,
                    vaultPath: state.vault?.rootPath,
                    noteFilePath: state.vault?.resolveEntityPath(note),
                    onPasteImage: { pasteboard in
                        handlePasteImage(pasteboard, note: note)
                    },
                    onOpenLink: { target in
                        handleOpenLink(target)
                    },
                    isCursorExcluded: { _ in
                        note.draft && !isNamingDraft && isHoveringDraftActions
                    }
                )
                .id(note.id)
                .padding(.top, note.draft && !isNamingDraft ? (state.isNotesListCollapsed ? 36 : 16) : 0)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                    handleDropFiles(providers, for: note)
                }
            }

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
        .overlay(alignment: .topTrailing) {
            if note.draft && !isNamingDraft {
                HStack(spacing: 8) {
                    Button(action: {
                        isNamingDraft = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            isTitleFocused = true
                        }
                    }) {
                        Text("转为笔记")
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.85))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color(nsColor: .separatorColor).opacity(0.8), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)

                    moreMenu(note)
                }
                .padding(.trailing, 24)
                .padding(.top, 16)
                .onHover { isHoveringDraftActions = $0 }
                .onDisappear { isHoveringDraftActions = false }
            }
        }
        .overlay(alignment: .topLeading) {
            if note.draft && !isNamingDraft && state.isNotesListCollapsed {
                NotesSidebarToggleButton(collapsed: true) {
                    state.toggleNotesList()
                }
                .padding(4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.85))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(nsColor: .separatorColor).opacity(0.8), lineWidth: 1)
                )
                .padding(.leading, 24)
                .padding(.top, 16)
            }
        }
    }

    private func moreMenu(_ note: Note) -> some View {
        let taskStatus = asrManager.getStatus(for: note.id)
        let isTranscribing = taskStatus.state == .uploading || taskStatus.state == .transcribing || taskStatus.state == .writing

        return Menu {
            if note.audioTranscript {
                Button(currentBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "开始转写 / 重试" : "重新转写") {
                    triggerTranscription(for: note, isRetranscribe: !currentBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .disabled(isTranscribing)

                if let audioRelPath = note.audioFile, let v = state.vault {
                    Button("在 Finder 中显示音频") {
                        let fullPath = (v.rootPath as NSString).appendingPathComponent(audioRelPath)
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: fullPath)])
                    }
                }

                Divider()
            }

            Button("复制绝对路径") {
                copyNotePath(note)
            }
            Button("在 Finder 中打开") {
                revealInFinder(note)
            }
            Divider()
            Button(note.draft ? "删除草稿" : "删除笔记", role: .destructive) {
                notePendingDeletion = note
                showDeleteNoteConfirm = true
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

    // MARK: - Resizer Divider Handle

    private static let splitSpace = "notesSplit"

    private var dividerHandle: some View {
        ResizableDivider(
            width: $state.notesListWidth,
            allowedWidth: 200...500,
            defaultWidth: 280,
            coordinateSpaceName: Self.splitSpace,
            accentColor: state.effectiveAccentColor,
            onCommit: state.savePreferences
        )
    }

    // MARK: - Actions

    private func handleCreateAudioNote() {
        guard let v = state.vault, editor.save() else { return }
        isNotesCollapsed = false
        if state.isNotesListCollapsed {
            state.isNotesListCollapsed = false
            state.savePreferences()
        }

        let apiKey = state.readASRKey()

        guard let key = apiKey, !key.isEmpty else {
            showMissingKeyAlert = true
            return
        }

        let panel = NSOpenPanel()
        panel.title = "选择要转写的音频文件"
        panel.allowedContentTypes = [
            UTType(filenameExtension: "mp3") ?? .audio,
            UTType(filenameExtension: "m4a") ?? .audio
        ]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        if panel.runModal() == .OK, let fileURL = panel.url {
            do {
                let relPath = try v.importFile(sourceURL: fileURL)
                let stem = fileURL.deletingPathExtension().lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
                let title = stem.isEmpty ? "音频逐字稿" : stem

                let note = try v.createNote(
                    title: title,
                    body: "",
                    tags: [],
                    draft: false,
                    audioFile: relPath,
                    audioTranscript: true
                )

                state.selectedNoteId = note.id
                isNotesCollapsed = false
                state.rescanVault()

                let fullAudioURL = URL(fileURLWithPath: (v.rootPath as NSString).appendingPathComponent(relPath))
                AudioPlayerManager.shared.loadAudio(url: fullAudioURL, relativePath: relPath)

                triggerTranscription(for: note, isRetranscribe: false)
            } catch {
                print("Failed to create audio note: \(error)")
            }
        }
    }

    private func triggerTranscription(for note: Note, isRetranscribe: Bool) {
        guard let v = state.vault, let audioRelPath = note.audioFile else { return }

        let apiKey = state.readASRKey()

        guard let key = apiKey, !key.isEmpty else {
            showMissingKeyAlert = true
            return
        }

        let fullAudioURL = URL(fileURLWithPath: (v.rootPath as NSString).appendingPathComponent(audioRelPath))

        asrManager.startTask(
            noteId: note.id,
            audioURL: fullAudioURL,
            isRetranscribe: isRetranscribe,
            apiKey: key,
            onSave: { [weak state, v] transcript in
                try state?.saveTranscript(transcript, noteId: note.id, audioFile: audioRelPath, in: v)
            }
        )
    }

    private func handleConfirmReplace(_ note: Note) {
        guard let vault = state.vault, let audioFile = note.audioFile else { return }
        asrManager.confirmReplace(noteId: note.id) { [weak state, vault] newBody in
            try state?.saveTranscript(newBody, noteId: note.id, audioFile: audioFile, in: vault)
        }
    }

    private func handleCreateDraft() {
        guard let v = state.vault, editor.save() else { return }
        isDraftsCollapsed = false
        if state.isNotesListCollapsed {
            state.isNotesListCollapsed = false
            state.savePreferences()
        }
        do {
            let note = try v.createNote(title: "", body: "", tags: [], draft: true)
            state.selectedNoteId = note.id
            state.rescanVault()
        } catch {
            print("Create draft error: \(error)")
        }
    }

    private func handleCreateFormalNote() {
        guard let v = state.vault, editor.save() else { return }
        isNotesCollapsed = false
        if state.isNotesListCollapsed {
            state.isNotesListCollapsed = false
            state.savePreferences()
        }
        do {
            let note = try v.createNote(title: "未命名笔记", body: "", tags: [], draft: false)
            state.selectedNoteId = note.id
            state.rescanVault()
        } catch {
            print("Create note error: \(error)")
        }
    }

    private func convertCurrentDraft(_ note: Note) {
        guard let v = state.vault, editor.save() else { return }
        do {
            let converted = try v.convertDraftToNote(id: note.id, newTitle: currentTitle.isEmpty ? "未命名笔记" : currentTitle, tags: currentTags)
            editor.acceptSavedNote(converted, in: v)
            isNamingDraft = false
            state.rescanVault()
        } catch {
            print("Convert draft error: \(error)")
        }
    }

    private func addTag(_ tag: String, to note: Note) {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !currentTags.contains(trimmed) else { return }
        currentTags.append(trimmed)
        newTagInput = ""
        showTagPopover = false
        editor.save()
    }

    private func removeTag(_ tag: String, from note: Note) {
        currentTags.removeAll { $0 == tag }
        editor.save()
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
        if editor.note?.id == note.id {
            editor.discard()
        } else {
            _ = editor.save()
        }
        ASRManager.shared.cancelTask(noteId: note.id)
        if state.selectedNoteId == note.id {
            AudioPlayerManager.shared.stop()
            state.selectedNoteId = nil
        }
        do {
            try v.deleteNote(id: note.id)
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
        let cleanTarget = target.removingPercentEncoding ?? target
        let fullPath: String
        if cleanTarget.hasPrefix("files/") {
            fullPath = (v.rootPath as NSString).appendingPathComponent(cleanTarget)
        } else if cleanTarget.hasPrefix("../files/") {
            let sub = String(cleanTarget.dropFirst(3))
            fullPath = (v.rootPath as NSString).appendingPathComponent(sub)
        } else if let currentNote = currentNote {
            let noteDir = (v.resolveEntityPath(currentNote) as NSString).deletingLastPathComponent
            fullPath = URL(fileURLWithPath: (noteDir as NSString).appendingPathComponent(cleanTarget)).standardized.path
        } else {
            fullPath = (v.rootPath as NSString).appendingPathComponent(cleanTarget)
        }
        if FileManager.default.fileExists(atPath: fullPath) {
            NSWorkspace.shared.open(URL(fileURLWithPath: fullPath))
        }
    }

    private func handlePasteImage(_ pasteboard: NSPasteboard, note: Note) -> String? {
        guard let v = state.vault else { return nil }
        guard PataImageHelper.canPasteImage(from: pasteboard) else { return nil }
        let notePath = v.resolveEntityPath(note)
        if let result = PataImageHelper.handlePasteImage(from: pasteboard, vaultPath: v.rootPath, noteFilePath: notePath) {
            state.objectWillChange.send()
            return result
        }
        return nil
    }

    private func handleDropFiles(_ providers: [NSItemProvider], for note: Note) -> Bool {
        guard let v = state.vault else { return false }
        let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "svg", "bmp", "tiff", "heic"]
        var handled = false

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier("public.file-url") {
                provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                    let url: URL?
                    if let fileURL = item as? URL {
                        url = fileURL
                    } else if let data = item as? Data, let fileURL = URL(dataRepresentation: data, relativeTo: nil) {
                        url = fileURL
                    } else {
                        url = nil
                    }

                    guard let fileURL = url else { return }
                    let ext = fileURL.pathExtension.lowercased()
                    guard imageExtensions.contains(ext) else { return }

                    DispatchQueue.main.async {
                        guard state.vault === v, editor.isEditing(noteId: note.id, in: v), !note.audioTranscript else { return }
                        do {
                            let relPath = try v.importFile(sourceURL: fileURL)
                            let notePath = v.resolveEntityPath(note)
                            let noteDir = (notePath as NSString).deletingLastPathComponent
                            let absImported = (v.rootPath as NSString).appendingPathComponent(relPath)
                            let markdownPath = Links.relativePath(from: noteDir, to: absImported)
                            let appendText = currentBody.isEmpty ? "![](\(markdownPath))\n" : "\n\n![](\(markdownPath))\n"
                            currentBody.append(appendText)
                            state.objectWillChange.send()
                        } catch {
                            // ignore import error
                        }
                    }
                }
                handled = true
            }
        }
        return handled
    }
}

// MARK: - Notes Sidebar Toggle Button

public struct NotesSidebarToggleButton: View {
    let collapsed: Bool
    let action: () -> Void
    @State private var isHovered = false

    public init(collapsed: Bool, action: @escaping () -> Void) {
        self.collapsed = collapsed
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: "sidebar.left")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(isHovered ? .primary : .secondary)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(isHovered ? Color.primary.opacity(0.08) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(collapsed ? "展开笔记列表" : "收起笔记列表")
    }
}

// MARK: - Audio Player Toolbar View

public struct AudioPlayerToolbarView: View {
    let note: Note
    let accentColor: Color
    let accentOnColor: Color
    @ObservedObject var asrManager: ASRManager
    @ObservedObject private var audioPlayer = AudioPlayerManager.shared
    let onConfirmReplace: () -> Void
    var onSeek: ((Int) -> Void)? = nil

    @State private var isDraggingAudioSlider: Bool = false
    @State private var dragPositionMs: Double = 0

    public init(
        note: Note,
        accentColor: Color,
        accentOnColor: Color,
        asrManager: ASRManager,
        onConfirmReplace: @escaping () -> Void,
        onSeek: ((Int) -> Void)? = nil
    ) {
        self.note = note
        self.accentColor = accentColor
        self.accentOnColor = accentOnColor
        self.asrManager = asrManager
        self.onConfirmReplace = onConfirmReplace
        self.onSeek = onSeek
    }

    private func formatDisplayTime(_ ms: Int) -> String {
        let totalSec = max(0, ms / 1000)
        let hours = totalSec / 3600
        let minutes = (totalSec % 3600) / 60
        let seconds = totalSec % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    public var body: some View {
        let taskStatus = asrManager.getStatus(for: note.id)
        let isTranscribing = taskStatus.state == .uploading || taskStatus.state == .transcribing || taskStatus.state == .writing
        let fileName = (note.audioFile as NSString?)?.lastPathComponent ?? "音频文件"

        VStack(spacing: 8) {
            // Row 1: Header (icon + filename + status tag)
            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: "waveform")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(accentColor)
                    Text(fileName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)
                }

                if isTranscribing {
                    HStack(spacing: 5) {
                        ProgressView()
                            .controlSize(.mini)
                        Text(taskStatus.stageMessage)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.1)))
                } else if taskStatus.state == .failed {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.roseBadgeText)
                        Text(taskStatus.error ?? taskStatus.stageMessage)
                            .font(.system(size: 11))
                            .foregroundColor(.roseBadgeText)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.roseBadgeBg))
                }

                Spacer()
            }

            // Warning Banner (> 2 hours)
            if let warning = taskStatus.warning, !warning.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 11))
                        .foregroundColor(.amberBadgeText)
                    Text(warning)
                        .font(.system(size: 11))
                        .foregroundColor(.amberBadgeText)
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.amberBadgeBg))
            }

            // Pending Confirmation Banner (Replace transcript?)
            if taskStatus.state == .pendingConfirmation {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(accentColor)
                    Text("重新转写已完成，是否替换现有逐字稿？")
                        .font(.system(size: 11, weight: .medium))
                    Spacer()

                    Button("保留原稿") {
                        asrManager.discardCandidate(noteId: note.id)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 4).stroke(Color(nsColor: .separatorColor), lineWidth: 1))

                    Button("替换逐字稿") {
                        onConfirmReplace()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 4).fill(accentColor))
                    .foregroundColor(accentOnColor)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 6).fill(accentColor.opacity(0.08)))
            }

            // Row 2: Audio Player Controls (Play/Pause + Slider + Time)
            HStack(spacing: 10) {
                Button(action: { audioPlayer.togglePlayPause() }) {
                    ZStack {
                        Circle()
                            .fill(accentColor)
                            .frame(width: 28, height: 28)
                        Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(accentOnColor)
                            .offset(x: audioPlayer.isPlaying ? 0 : 1)
                    }
                }
                .buttonStyle(.plain)

                // Scrubber Slider
                Slider(
                    value: Binding(
                        get: {
                            isDraggingAudioSlider ? dragPositionMs : Double(audioPlayer.currentPositionMs)
                        },
                        set: { newVal in
                            dragPositionMs = newVal
                        }
                    ),
                    in: 0...Double(max(audioPlayer.durationMs, 1000)),
                    onEditingChanged: { editing in
                        isDraggingAudioSlider = editing
                        if !editing {
                            let ms = Int(dragPositionMs)
                            audioPlayer.seek(toMilliseconds: ms)
                            onSeek?(ms)
                            PataTranscriptLocator.scrollToSentence(in: note.body, targetMs: ms)
                        }
                    }
                )

                // Time Display: 00:01:23 / 00:45:00
                HStack(spacing: 2) {
                    Text(formatDisplayTime(isDraggingAudioSlider ? Int(dragPositionMs) : audioPlayer.currentPositionMs))
                    Text("/")
                        .foregroundColor(.secondary.opacity(0.6))
                    Text(formatDisplayTime(audioPlayer.durationMs))
                }
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }
}
