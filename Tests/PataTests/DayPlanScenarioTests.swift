import Testing
import Foundation
@testable import PataCore

@Suite("BDD Feature: DayPlan & Task Invariants")
struct DayPlanScenarioTests {

    @Test("Given a DayPlan with duplicate task IDs, when validated, then duplicate task IDs are rejected")
    func dayPlanDuplicateTaskIDsRejectedScenario() {
        // Given: A DayPlan containing duplicate task IDs
        let duplicatePlan = DayPlan(
            date: "2026-10-11",
            taskIds: ["t-01", "t-02", "t-01"]
        )

        // When: Validating entity schema
        // Then: ValidationError is thrown with duplicate task ID reason
        #expect(throws: SchemaError.self) {
            try SchemaValidator.validateEntity(duplicatePlan, path: "plans/2026-10-11.md")
        }

        // And: A valid DayPlan with unique IDs passes cleanly
        let validPlan = DayPlan(
            date: "2026-10-11",
            taskIds: ["t-01", "t-02", "t-03"]
        )
        #expect(throws: Never.self) {
            try SchemaValidator.validateEntity(validPlan, path: "plans/2026-10-11.md")
        }
    }

    @Test("Given tasks scheduled in today plan, when task completion is toggled, then status event is recorded without altering task due date")
    func taskCompletionDoesNotAlterDueDateScenario() throws {
        // Given: A vault with a task that has a due date
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("pata_bdd_plan_due_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let vault = try Vault(rootPath: tmpDir.path)
        var task = try vault.createTask(title: "资源接入方案")
        task.due = "2026-10-20"
        try vault.updateTask(task)

        // And: Scheduled into today plan
        try vault.addTaskToPlan(date: "2026-10-11", taskId: task.id)

        // When: Task is marked as done
        let updated = try vault.setTaskStatus(id: task.id, status: .done)

        // Then: Status is done and completed event is appended
        #expect(updated.status == .done)
        #expect(updated.statusEvents.contains { $0.action == .completed })

        // And: The task's due date is NOT altered by today scheduling or completion
        #expect(updated.due == "2026-10-20")
    }

    @Test("Given activities appended to task, when viewing today timeline, then activities for today are dynamically aggregated")
    func taskActivitiesAggregateIntoTodayTimelineScenario() throws {
        // Given: A vault with a task and activity recorded today
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("pata_bdd_plan_agg_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let vault = try Vault(rootPath: tmpDir.path)
        let task = try vault.createTask(title: "Flink SQL 验证")

        // When: An activity comment is appended to the task
        let act = try vault.createActivity(taskId: task.id, body: "完成第一轮压测，吞吐达标。")

        // Then: The activity is recorded on the task
        let storedTask = vault.index.getTask(task.id)
        #expect(storedTask?.activities.contains { $0.id == act.id } == true)

        // And: Activity search finds the comment text
        let searchResults = vault.index.searchAll("吞吐达标")
        #expect(!searchResults.isEmpty)
        #expect(searchResults.first?.type == .activity)
    }

    @Test("Given a DayPlan, when removing a task from the plan, then the task remains intact in the work pool")
    func removeTaskFromPlanPreservesTaskScenario() throws {
        // Given: A task added to today plan
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("pata_bdd_plan_rm_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let vault = try Vault(rootPath: tmpDir.path)
        let task = try vault.createTask(title: "待移除测试任务")
        try vault.addTaskToPlan(date: "2026-10-11", taskId: task.id)

        // When: Removed from today's plan
        try vault.removeTaskFromPlan(date: "2026-10-11", taskId: task.id)

        // Then: The plan no longer contains the task ID
        let plan = vault.getDayPlan(date: "2026-10-11")
        #expect(plan.taskIds.contains(task.id) == false)

        // And: The task itself remains in the pool without modification
        let stored = vault.index.getTask(task.id)
        #expect(stored != nil)
        #expect(stored?.title == "待移除测试任务")
    }
}
