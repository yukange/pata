import Testing
@testable import PataCore
import Foundation

@Suite("Activity Parser Tests")
struct ActivityParserTests {
    @Test("Activity Parsing and Formatting")
    func activityParsingAndFormatting() throws {
        let raw = """
        <!-- pata:activity
        id: a-01test
        at: 2026-10-15T10:30:00+08:00
        by: agent
        tags: [设计]
        note_refs:
          技术方案: n-002
        -->
        完成基础设计，参考 [[技术方案]]。
        <!-- /pata:activity -->
        """

        let acts = try ActivityParser.parseActivities(raw)
        #expect(acts.count == 1)

        let act = acts[0]
        #expect(act.id == "a-01test")
        #expect(act.by == SourceAgent)
        #expect(act.tags == ["设计"])
        #expect(act.noteRefs["技术方案"] == "n-002")
        #expect(act.body == "完成基础设计，参考 [[技术方案]]。")

        let formatted = try ActivityParser.formatActivities(acts)
        let reParsed = try ActivityParser.parseActivities(formatted)
        #expect(reParsed.count == 1)
        #expect(reParsed[0].id == act.id)
        #expect(reParsed[0].body == act.body)
        #expect(reParsed[0].by == act.by)
    }

    @Test("Body escaping for activity delimiter")
    func bodyEscaping() throws {
        let bodyWithMarker = "Line 1\n<!-- pata:activity\nLine 2"
        let act = Activity(
            id: "a-01escape",
            at: Date(),
            body: bodyWithMarker
        )

        let formatted = try ActivityParser.formatActivities([act])
        #expect(formatted.contains("\\<!-- pata:activity"))

        let parsed = try ActivityParser.parseActivities(formatted)
        #expect(parsed[0].body == bodyWithMarker)
    }

    @Test("Reject nested activity")
    func rejectNestedActivity() {
        let nested = """
        <!-- pata:activity
        id: a-01parent
        at: 2026-10-15T10:30:00+08:00
        -->
        <!-- pata:activity
        id: a-02child
        at: 2026-10-15T10:30:00+08:00
        -->
        Content
        <!-- /pata:activity -->
        <!-- /pata:activity -->
        """

        #expect(throws: Error.self) {
            try ActivityParser.parseActivities(nested)
        }
    }
}
