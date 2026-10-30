import Testing
@testable import PataCore
import Foundation

@Suite("Frontmatter Tests")
struct FrontmatterTests {
    @Test("Task roundtrip serialization and deserialization")
    func taskRoundtrip() throws {
        let task = Task(
            id: "t-01abc",
            title: "Task Title",
            description: "Some description with [[Ref]]",
            status: .todo,
            tags: ["Work", "Design"],
            noteRefs: ["Ref": "n-001"],
            statusEvents: [
                StatusEvent(action: .completed, at: Date(), by: SourceAgent)
            ],
            extra: ["unknown_custom_field": "custom_value"]
        )

        let md = try Frontmatter.serializeMarkdown(task)
        let parsed = try Frontmatter.parseMarkdown(content: md)

        #expect(parsed.type == .task)
        guard let pTask = parsed as? Task else {
            Issue.record("Parsed entity should be Task")
            return
        }

        #expect(pTask.id == task.id)
        #expect(pTask.title == task.title)
        #expect(pTask.description == task.description)
        #expect(pTask.tags == task.tags)
        #expect(pTask.noteRefs == task.noteRefs)
        #expect(pTask.statusEvents.count == 1)
        #expect(pTask.statusEvents[0].action == .completed)
        #expect(pTask.statusEvents[0].by == SourceAgent)
        #expect(pTask.extra["unknown_custom_field"] == "custom_value")
    }

    @Test("Draft Note Parsing")
    func draftNoteParsing() throws {
        let raw = """
        ---
        type: note
        id: n-01draft
        draft: true
        created_at: 2026-10-26T18:30:00+08:00
        updated_at: 2026-10-26T18:45:00+08:00
        ---

        直接开始编写正文。
        """

        let entity = try Frontmatter.parseMarkdown(content: raw)
        #expect(entity.type == .note)
        guard let note = entity as? Note else {
            Issue.record("Expected Note")
            return
        }

        #expect(note.draft == true)
        #expect(note.title == "")
        #expect(note.body.contains("直接开始编写正文。"))
    }

    @Test("Plain Markdown Parsing")
    func plainMarkdownParsing() throws {
        let plain = """
        # 我的随想

        这是一篇没有 Frontmatter 的外部笔记。
        """

        let entity = try Frontmatter.parseMarkdown(filePath: "/vault/notes/thoughts.md", content: plain)
        #expect(entity.type == .note)
        guard let note = entity as? Note else {
            Issue.record("Expected Note")
            return
        }

        #expect(note.id.hasPrefix("plain-"))
        #expect(note.title == "我的随想")
    }
}
