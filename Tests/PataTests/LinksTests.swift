import Testing
@testable import PataCore
import Foundation

@Suite("Links Tests")
struct LinksTests {
    @Test("Note link extraction from markdown body")
    func noteLinkExtraction() {
        let body = """
        Here is a link to [My Note](../notes/my-note.md).
        And an image ![Pic](../files/pic.png) which should be ignored.
        And code block:
        ```markdown
        [Sample](fake.md)
        ```
        And inline code `[Inline](fake.md)`.
        """

        let dests = Links.noteLinkDests(body: body)
        #expect(dests == ["../notes/my-note.md"])
    }

    @Test("Resolve text ref strict rules")
    func resolveTextRef() {
        let notes = [
            "n-001": Note(id: "n-001", title: "Alpha"),
            "n-002": Note(id: "n-002", title: "Beta"),
            "n-003": Note(id: "n-003", title: "Beta") // duplicate title
        ]

        // 1. Explicit bound ref
        let refs = ["My Ref": "n-001"]
        #expect(Links.resolveTextRef(name: "My Ref", noteRefs: refs, notes: notes) == "n-001")

        // 2. Bound ref where target Note is missing: must return nil, NEVER fallback to title!
        let brokenRefs = ["Alpha": "n-missing"]
        #expect(Links.resolveTextRef(name: "Alpha", noteRefs: brokenRefs, notes: notes) == nil)

        // 3. Unbound ref with unique title
        #expect(Links.resolveTextRef(name: "Alpha", noteRefs: [:], notes: notes) == "n-001")

        // 4. Unbound ref with ambiguous title
        #expect(Links.resolveTextRef(name: "Beta", noteRefs: [:], notes: notes) == nil)
    }
}
