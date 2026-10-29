import Testing
import Foundation
@testable import PataCore

@Suite("BDD Feature: Agent Attribution & Search Isolation")
struct AttributionScenarioTests {

    @Test("Given entities created by agent (created_by: agent), when serialized, then attribution is preserved; when created by user, attribution is omitted")
    func agentAttributionRoundTripScenario() throws {
        // Given: A task created by an agent
        let now = Date()
        var agentTask = Task(
            id: "t-agent-01",
            title: "Agent 自动生成的任务",
            status: .todo,
            createdAt: now,
            createdBy: "agent",
            updatedAt: now
        )
        agentTask.activities = [
            Activity(
                id: "a-01",
                at: now,
                by: "agent",
                body: "Agent 留下的操作记录"
            )
        ]

        // When: Serialized to Markdown
        let agentMD = try Frontmatter.serializeMarkdown(agentTask)

        // Then: The frontmatter contains created_by: agent and the activity contains by: agent
        #expect(agentMD.contains("created_by: agent") || agentMD.contains("created_by: \"agent\""))
        #expect(agentMD.contains("by: agent") || agentMD.contains("by: \"agent\""))

        // And: A regular user task has NO created_by field emitted
        let userTask = Task(
            id: "t-user-01",
            title: "用户手动任务",
            status: .todo,
            createdAt: now,
            updatedAt: now
        )
        let userMD = try Frontmatter.serializeMarkdown(userTask)
        #expect(!userMD.contains("created_by:"))
    }

    @Test("Given entities with agent metadata, when searching, then internal metadata does not leak into search results while visible text remains searchable")
    func agentMetadataDoesNotLeakIntoSearchScenario() throws {
        // Given: A vault with an agent-attributed task
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("pata_bdd_agent_search_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let vault = try Vault(rootPath: tmpDir.path)
        let task = Task(
            id: "t-agent-search",
            title: "性能调优排查",
            status: .done,
            createdAt: Date(),
            createdBy: "agent",
            updatedAt: Date(),
            activities: [
                Activity(id: "a-search", at: Date(), by: "agent", body: "修复已完成")
            ]
        )
        let raw = try Frontmatter.serializeMarkdown(task)
        let path = vault.resolveEntityPath(task)
        try Safety.safeWrite(targetPath: path, data: Data(raw.utf8))
        try vault.rescan()

        // When: Searching for technical metadata keywords ("agent", "by:", "pata:activity")
        let metadataResults = vault.index.searchAll("pata:activity")

        // Then: Technical delimiters must NOT match
        #expect(metadataResults.isEmpty)

        // And: Searching for visible business text ("排查", "修复") correctly matches
        let businessResults = vault.index.searchAll("修复")
        #expect(!businessResults.isEmpty)
        #expect(businessResults.contains { $0.snippet?.contains("修复已完成") == true })
    }

    @Test("Given frontmatter with unsupported created_by sources (e.g. human, app), when validated, then validation rejects invalid source")
    func unsupportedSourcesRejectedScenario() {
        // Given: A task with created_by set to unsupported string "human"
        let invalidTask = Task(
            id: "t-invalid-source",
            title: "非协议来源任务",
            status: .todo,
            createdAt: Date(),
            createdBy: "human",
            updatedAt: Date()
        )

        // When: Validating entity
        // Then: Validation error is thrown rejecting the unsupported source
        #expect(throws: SchemaError.self) {
            try SchemaValidator.validateEntity(invalidTask, path: "tasks/t1.md")
        }
    }
}
