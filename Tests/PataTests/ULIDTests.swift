import Testing
@testable import PataCore

@Suite("ULID Tests")
struct ULIDTests {
    @Test("ULID Generation and Monotonicity")
    func ulidGeneration() {
        let id1 = ULID.generate()
        let id2 = ULID.generate()

        #expect(id1.count == 26)
        #expect(id2.count == 26)
        #expect(id1 != id2)
        #expect(id1 < id2)

        let validChars = Set("0123456789abcdefghjkmnpqrstvwxyz")
        for ch in id1 {
            #expect(validChars.contains(ch))
        }
    }

    @Test("Entity ID Prefixes")
    func entityIDPrefixes() {
        let taskId = ULID.generateEntityID(type: .task)
        #expect(taskId.hasPrefix("t-"))
        #expect(taskId.count == 28)

        let noteId = ULID.generateEntityID(type: .note)
        #expect(noteId.hasPrefix("n-"))
        #expect(noteId.count == 28)

        let actId = ULID.generateActivityID()
        #expect(actId.hasPrefix("a-"))
        #expect(actId.count == 28)

        let planId = ULID.generateEntityID(type: .dayPlan)
        #expect(planId.count == 10)
    }

    @Test("Slug Sanitization matches Go implementation")
    func slugSanitization() {
        #expect(ULID.sanitizeSlug("统一资源接入方案") == "统一资源接入方案")
        #expect(ULID.sanitizeSlug("Flink SQL POC / Testing: v1.0?") == "Flink-SQL-POC-Testing-v1.0")
        #expect(ULID.sanitizeSlug("  Hello   World!  ") == "Hello-World!")
        #expect(ULID.sanitizeSlug("///:::***") == "untitled")
        #expect(ULID.sanitizeSlug("🚀 高性能 Rust & Go 测试") == "🚀-高性能-Rust-&-Go-测试")
        #expect(ULID.sanitizeSlug("   --- spaces   and   dashes --- ") == "spaces-and-dashes")
        #expect(ULID.sanitizeSlug("") == "untitled")
    }

    @Test("Format Entity Filenames")
    func formatEntityFilename() {
        let task = Task(id: "t-01abc", title: "设计系统")
        #expect(ULID.formatEntityFilename(task) == "设计系统_t-01abc.md")

        let draft = Note(id: "n-01xyz", draft: true, title: "")
        #expect(ULID.formatEntityFilename(draft) == "n-01xyz.md")

        let note = Note(id: "n-02def", draft: false, title: "需求讨论")
        #expect(ULID.formatEntityFilename(note) == "需求讨论_n-02def.md")
    }
}
