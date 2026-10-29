import SwiftUI
import AppKit
import PataCore
import PataAudio
import PataEditor

public struct NotesView: View {
    @ObservedObject var state: AppState
    @StateObject private var audioPlayer = AudioPlayerManager.shared

    @State private var searchQuery: String = ""
    @State private var isEditingBody: Bool = false
    @State private var editedTitle: String = ""
    @State private var editedBody: String = ""

    public init(state: AppState) {
        self.state = state
    }

    private var allNotes: [Note] {
        state.vault?.index.listNotes().sorted { $0.id < $1.id } ?? []
    }

    private var filteredNotes: [Note] {
        allNotes.filter { n in
            if searchQuery.isEmpty { return true }
            return n.title.localizedCaseInsensitiveContains(searchQuery) ||
                   n.body.localizedCaseInsensitiveContains(searchQuery) ||
                   n.tags.contains(where: { $0.localizedCaseInsensitiveContains(searchQuery) })
        }
    }

    private var currentNote: Note? {
        guard let id = state.selectedNoteId else { return nil }
        return state.vault?.index.getNote(id)
    }

    public var body: some View {
        ScrollView {
            if let note = currentNote {
                noteDetailView(note)
            } else {
                notesListView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Notes List View (Matches old_notes.png)

    private var notesListView: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Page Header: Eyebrow, Title, Subtitle, + 新建笔记 Button
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("YOUR KNOWLEDGE SPACE")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color(red: 147/255, green: 162/255, blue: 146/255))
                        .tracking(1.2)

                    Text("Notes")
                        .font(.system(size: 29, weight: .bold))
                        .foregroundColor(Color(red: 36/255, green: 40/255, blue: 36/255))

                    Text("记录值得留下的东西，打开一篇，专注写作。")
                        .font(.system(size: 12))
                        .foregroundColor(Color(red: 137/255, green: 145/255, blue: 136/255))
                }

                Spacer()

                Button(action: createNewNote) {
                    HStack(spacing: 5) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                        Text("新建笔记")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(red: 71/255, green: 110/255, blue: 88/255)))
                    .foregroundColor(.white)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 6)

            // Search Bar
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundColor(Color(red: 163/255, green: 170/255, blue: 162/255))

                TextField("搜索标题、内容、标签…", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))

                if !searchQuery.isEmpty {
                    Button(action: { searchQuery = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 43)
            .background(RoundedRectangle(cornerRadius: 11).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color(red: 231/255, green: 235/255, blue: 229/255), lineWidth: 1))

            // Section Heading: 最近编辑 + Count, Right: 单列内容浏览
            HStack(alignment: .center) {
                HStack(spacing: 8) {
                    Text("最近编辑")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(Color(red: 36/255, green: 40/255, blue: 36/255))

                    Text("\(filteredNotes.count)")
                        .font(.system(size: 11, design: .monospaced))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color(red: 240/255, green: 242/255, blue: 237/255)))
                        .foregroundColor(Color(red: 164/255, green: 170/255, blue: 162/255))
                }

                Spacer()

                Text("单列内容浏览")
                    .font(.system(size: 11))
                    .foregroundColor(Color(red: 137/255, green: 145/255, blue: 136/255))
            }
            .padding(.top, 9)

            // Stack of Note Cards
            VStack(spacing: 12) {
                ForEach(filteredNotes) { note in
                    noteCard(note)
                }
            }
        }
        .padding(.horizontal, 46)
        .padding(.top, 46)
        .padding(.bottom, 105)
        .frame(maxWidth: 785)
    }

    private func noteCard(_ note: Note) -> some View {
        Button(action: {
            state.selectedNoteId = note.id
            isEditingBody = false
        }) {
            VStack(alignment: .leading, spacing: 11) {
                Text(note.title.isEmpty ? "未命名笔记" : note.title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(Color(red: 36/255, green: 40/255, blue: 36/255))

                Text(extractExcerpt(note.body))
                    .font(.system(size: 12))
                    .foregroundColor(Color(red: 120/255, green: 129/255, blue: 121/255))
                    .lineSpacing(4)
                    .lineLimit(2)

                HStack {
                    HStack(spacing: 8) {
                        ForEach(note.tags, id: \.self) { tag in
                            Text("#\(tag)")
                                .font(.system(size: 11))
                                .foregroundColor(Color(red: 101/255, green: 132/255, blue: 105/255))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(RoundedRectangle(cornerRadius: 5).fill(Color(red: 239/255, green: 246/255, blue: 238/255)))
                        }
                    }

                    Spacer()

                    Text(formatRelativeDate(note.updatedAt))
                        .font(.system(size: 11))
                        .foregroundColor(Color(red: 173/255, green: 180/255, blue: 172/255))
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 13).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(Color(red: 232/255, green: 236/255, blue: 230/255), lineWidth: 1))
            .shadow(color: Color.black.opacity(0.03), radius: 10, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Note Detail View (Matches old_note_editor.png)

    private func noteDetailView(_ note: Note) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top Action Bar
            HStack {
                Button(action: { state.selectedNoteId = nil }) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .semibold))
                        Text("返回笔记列表")
                            .font(.system(size: 12))
                    }
                    .foregroundColor(Color(red: 115/255, green: 130/255, blue: 115/255))
                }
                .buttonStyle(.plain)

                Spacer()

                if isEditingBody {
                    Button(action: { saveNoteEdits(note) }) {
                        Text("保存修改")
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color(red: 71/255, green: 110/255, blue: 88/255)))
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button(action: {
                        editedTitle = note.title
                        editedBody = note.body
                        isEditingBody = true
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 11))
                            Text("编辑正文")
                                .font(.system(size: 12))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(red: 229/255, green: 233/255, blue: 225/255), lineWidth: 1))
                        .foregroundColor(Color(red: 89/255, green: 100/255, blue: 88/255))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 24)

            // Eyebrow
            Text("MARKDOWN NOTE")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(Color(red: 147/255, green: 162/255, blue: 146/255))
                .tracking(1.2)
                .padding(.bottom, 8)

            // Title
            if isEditingBody {
                TextField("笔记标题", text: $editedTitle)
                    .font(.system(size: 28, weight: .bold))
                    .textFieldStyle(.plain)
                    .padding(.bottom, 14)
            } else {
                Text(note.title)
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(Color(red: 36/255, green: 40/255, blue: 36/255))
                    .padding(.bottom, 14)
            }

            // Meta: Tags + Modified Date
            HStack(spacing: 10) {
                ForEach(note.tags, id: \.self) { tag in
                    Text("#\(tag)")
                        .font(.system(size: 11))
                        .foregroundColor(Color(red: 101/255, green: 132/255, blue: 105/255))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color(red: 239/255, green: 246/255, blue: 238/255)))
                }

                Text("\(formatRelativeDate(note.updatedAt)) 修改")
                    .font(.system(size: 11))
                    .foregroundColor(Color(red: 173/255, green: 180/255, blue: 172/255))
            }
            .padding(.bottom, 32)

            // Content: Rendered Markdown or TextEditor
            if isEditingBody {
                TextEditor(text: $editedBody)
                    .font(.system(size: 13))
                    .lineSpacing(4)
                    .frame(minHeight: 440)
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(red: 221/255, green: 232/255, blue: 221/255), lineWidth: 1))
            } else {
                renderedMarkdownBody(note.body)
            }
        }
        .padding(.horizontal, 46)
        .padding(.top, 46)
        .padding(.bottom, 105)
        .frame(maxWidth: 770)
    }

    // MARK: - Markdown Rendering (Matches old_note_editor.png)

    @ViewBuilder
    private func renderedMarkdownBody(_ md: String) -> some View {
        let lines = md.components(separatedBy: "\n")
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("# ") {
                    // Skip top H1 since title is rendered above
                    EmptyView()
                } else if trimmed.hasPrefix("## ") {
                    Text(trimmed.dropFirst(3))
                        .font(.system(size: 19, weight: .bold))
                        .foregroundColor(Color(red: 36/255, green: 40/255, blue: 36/255))
                        .padding(.top, 18)
                        .padding(.bottom, 4)
                } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("• ") {
                    let itemText = trimmed.hasPrefix("- ") ? trimmed.dropFirst(2) : trimmed.dropFirst(2)
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(Color(red: 68/255, green: 80/255, blue: 67/255))
                        Text(LocalizedStringKey(String(itemText)))
                            .font(.system(size: 14))
                            .foregroundColor(Color(red: 68/255, green: 80/255, blue: 67/255))
                            .lineSpacing(4)
                    }
                    .padding(.leading, 8)
                } else if trimmed.hasPrefix("> ") {
                    HStack(spacing: 12) {
                        Rectangle()
                            .fill(Color(red: 164/255, green: 194/255, blue: 168/255))
                            .frame(width: 3)
                        Text(trimmed.dropFirst(2))
                            .font(.system(size: 13))
                            .foregroundColor(Color(red: 121/255, green: 133/255, blue: 120/255))
                    }
                    .padding(.vertical, 8)
                } else if !trimmed.isEmpty {
                    Text(LocalizedStringKey(trimmed))
                        .font(.system(size: 14))
                        .foregroundColor(Color(red: 68/255, green: 80/255, blue: 67/255))
                        .lineSpacing(5)
                }
            }
        }
    }

    // MARK: - Helpers

    private func extractExcerpt(_ body: String) -> String {
        let lines = body.components(separatedBy: "\n")
        for line in lines {
            let t = line.trimmingCharacters(in: .whitespaces)
            if !t.isEmpty && !t.hasPrefix("#") && !t.hasPrefix("-") && !t.hasPrefix(">") {
                return t
            }
        }
        return ""
    }

    private func formatRelativeDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let todayStr = state.todayDateString
        let dateStr = f.string(from: d)

        let fTime = DateFormatter()
        fTime.dateFormat = "HH:mm"

        let cal = Calendar.current
        var yesterdayStr = ""
        if let todayDate = f.date(from: todayStr),
           let yDate = cal.date(byAdding: .day, value: -1, to: todayDate) {
            yesterdayStr = f.string(from: yDate)
        }

        if dateStr == todayStr {
            return "今天 \(fTime.string(from: d))"
        } else if dateStr == yesterdayStr {
            return "昨天 \(fTime.string(from: d))"
        } else {
            let month = cal.component(.month, from: d)
            let day = cal.component(.day, from: d)
            return "\(month) 月 \(day) 日"
        }
    }

    private func createNewNote() {
        guard let v = state.vault else { return }
        if let note = try? v.createNote(title: "未命名笔记", body: "# 未命名笔记\n\n开始写作…") {
            state.selectedNoteId = note.id
            editedTitle = note.title
            editedBody = note.body
            isEditingBody = true
        }
    }

    private func saveNoteEdits(_ note: Note) {
        guard let v = state.vault else { return }
        var updated = note
        updated.title = editedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未命名笔记" : editedTitle
        updated.body = editedBody
        updated.updatedAt = Date()
        try? _ = v.updateNote(updated)
        isEditingBody = false
    }
}
