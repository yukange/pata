import SwiftUI
import PataCore

public struct SearchOverlay: View {
    @ObservedObject var state: AppState
    @State private var query: String = ""
    @FocusState private var isFieldFocused: Bool

    public init(state: AppState) {
        self.state = state
    }

    private var results: [EntityRef] {
        guard let v = state.vault, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        return v.index.searchAll(query)
    }

    public var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    state.showSearch = false
                }

            VStack(spacing: 0) {
                // Search Input Bar
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.system(size: 16))

                    TextField("搜索任务、笔记、活动或文件名...", text: $query)
                        .font(.system(size: 16))
                        .textFieldStyle(.plain)
                        .focused($isFieldFocused)

                    if !query.isEmpty {
                        Button(action: { query = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    Button("取消") {
                        state.showSearch = false
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 13))
                }
                .padding(16)

                Divider()

                // Results list
                if results.isEmpty && !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    VStack(spacing: 8) {
                        Spacer()
                        Text("未找到相关内容")
                            .foregroundColor(.secondary)
                            .font(.system(size: 14))
                        Spacer()
                    }
                    .frame(height: 200)
                } else if !results.isEmpty {
                    List {
                        ForEach(results) { item in
                            Button(action: {
                                handleSelect(item)
                            }) {
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: iconForType(item.type))
                                        .foregroundColor(.accentColor)
                                        .frame(width: 18)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.title ?? "未命名")
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(.primary)

                                        if let snippet = item.snippet, !snippet.isEmpty {
                                            Text(snippet)
                                                .font(.system(size: 12))
                                                .foregroundColor(.secondary)
                                                .lineLimit(2)
                                        }

                                        Text(item.path)
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundColor(.secondary.opacity(0.8))
                                    }
                                }
                                .padding(.vertical, 6)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .listStyle(.inset)
                    .frame(height: 360)
                }
            }
            .frame(width: 580)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .windowBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(nsColor: .separatorColor), lineWidth: 1))
            .shadow(color: Color.black.opacity(0.2), radius: 24, x: 0, y: 12)
        }
        .onAppear {
            isFieldFocused = true
        }
    }

    private func iconForType(_ type: EntityType) -> String {
        switch type {
        case .task: return "checklist"
        case .note: return "note.text"
        case .activity: return "bubble.left"
        case .file: return "doc"
        default: return "circle"
        }
    }

    private func handleSelect(_ item: EntityRef) {
        state.showSearch = false
        switch item.type {
        case .task:
            state.navigateToTask(taskId: item.id)
        case .note:
            state.navigateToNote(noteId: item.id)
        case .activity:
            if let tid = item.taskId {
                state.navigateToTask(taskId: tid)
            } else {
                state.currentNav = .today
            }
        case .file:
            if let root = state.vault?.rootPath {
                let fullPath = URL(fileURLWithPath: root).appendingPathComponent(item.path).path
                NSWorkspace.shared.open(URL(fileURLWithPath: fullPath))
            }
        default:
            break
        }
    }
}
