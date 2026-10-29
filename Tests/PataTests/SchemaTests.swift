import Testing
@testable import PataCore
import Foundation

@Suite("Schema Tests")
struct SchemaTests {
    @Test("Valid Task passes validation")
    func validTask() throws {
        let task = Task(
            id: "t-01m4xxx",
            title: "优化编辑器",
            description: "方案参见 [[编辑器方案]]",
            status: .todo,
            tags: ["Pata"],
            noteRefs: ["编辑器方案": "n-001"],
            createdAt: Date(),
            updatedAt: Date()
        )
        try SchemaValidator.validateEntity(task)
    }

    @Test("Invalid createdBy source rejected")
    func invalidSource() {
        let task = Task(
            id: "t-01m4xxx",
            title: "Task",
            createdBy: "unauthorized_robot"
        )
        #expect(throws: SchemaError.self) {
            try SchemaValidator.validateEntity(task)
        }
    }

    @Test("Tag with hash symbol rejected")
    func tagWithHashRejected() {
        let task = Task(
            id: "t-01m4xxx",
            title: "Task",
            tags: ["#invalid"]
        )
        #expect(throws: SchemaError.self) {
            try SchemaValidator.validateEntity(task)
        }
    }

    @Test("Note draft allows empty title, formal note requires title")
    func noteDraftAllowsEmptyTitle() throws {
        let draft = Note(
            id: "n-01xyz",
            draft: true,
            title: ""
        )
        try SchemaValidator.validateEntity(draft)

        let formalEmpty = Note(
            id: "n-01xyz",
            draft: false,
            title: ""
        )
        #expect(throws: SchemaError.self) {
            try SchemaValidator.validateEntity(formalEmpty)
        }
    }

    @Test("Audio transcript requires audio_file")
    func audioTranscriptRequiresAudioFile() {
        let note = Note(
            id: "n-01xyz",
            draft: false,
            title: "转写",
            audioFile: nil,
            audioTranscript: true
        )
        #expect(throws: SchemaError.self) {
            try SchemaValidator.validateEntity(note)
        }
    }

    @Test("DayPlan rejects duplicate task IDs")
    func dayPlanNoDuplicateTaskIds() {
        let plan = DayPlan(
            date: "2026-10-15",
            taskIds: ["t-01", "t-01"]
        )
        #expect(throws: SchemaError.self) {
            try SchemaValidator.validateEntity(plan)
        }
    }
}
