import Testing
import Foundation
@testable import PataCore

@Suite("BDD Feature: Concurrent Vault Mutations")
struct ConcurrencyScenarioTests {

    @Test("Given concurrent activity appends to a task, when executed in parallel, then all activities are safely recorded without data loss")
    func concurrentTaskActivityAppendsScenario() throws {
        // Given: A vault with an active task
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("pata_bdd_conc_task_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let vault = try Vault(rootPath: tmpDir.path)
        let task = try vault.createTask(title: "并发活动写入目标任务")

        let iterations = 16

        // When: Appending activities concurrently across multiple threads
        DispatchQueue.concurrentPerform(iterations: iterations) { i in
            do {
                _ = try vault.createActivity(taskId: task.id, body: "并发活动条目 #\(i)")
            } catch {
                Issue.record("Concurrent append failed for iteration \(i): \(error)")
            }
        }

        // Then: All activities are successfully stored on the task
        guard let updatedTask = vault.index.getTask(task.id) else {
            Issue.record("Task not found after concurrent mutations")
            return
        }

        #expect(updatedTask.activities.count == iterations)

        // And: All distinct bodies are preserved without clobbering
        let bodies = Set(updatedTask.activities.map { $0.body })
        #expect(bodies.count == iterations)

        // And: Reopening the vault from disk recovers all items
        let reopened = try Vault(rootPath: tmpDir.path)
        let diskTask = reopened.index.getTask(task.id)
        #expect(diskTask?.activities.count == iterations)
    }

    @Test("Given concurrent activity appends to a day plan, when executed in parallel, then all activities are safely recorded")
    func concurrentDayPlanActivityAppendsScenario() throws {
        // Given: A vault with a today plan
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("pata_bdd_conc_plan_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let vault = try Vault(rootPath: tmpDir.path)
        let planDate = "2026-10-26"
        let iterations = 12

        // When: Appending standalone memos concurrently to the DayPlan
        DispatchQueue.concurrentPerform(iterations: iterations) { i in
            do {
                _ = try vault.createActivity(date: planDate, body: "独立 Memo 记录 #\(i)")
            } catch {
                Issue.record("Concurrent memo append failed: \(error)")
            }
        }

        // Then: The DayPlan contains all appended activities
        let plan = vault.getDayPlan(date: planDate)
        #expect(plan.activities.count == iterations)

        let bodies = Set(plan.activities.map { $0.body })
        #expect(bodies.count == iterations)
    }

    @Test("Given concurrent task title updates and activity additions, when executed simultaneously, then task state and activities are both preserved")
    func concurrentUpdatesAndActivitiesScenario() throws {
        // Given: A vault and a task
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("pata_bdd_conc_mixed_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let vault = try Vault(rootPath: tmpDir.path)
        var task = try vault.createTask(title: "初版任务")

        let count = 10

        // When: Updating task metadata and appending activities in parallel
        DispatchQueue.concurrentPerform(iterations: count) { i in
            do {
                if i % 2 == 0 {
                    _ = try vault.createActivity(taskId: task.id, body: "并行评论 \(i)")
                } else {
                    if var current = vault.index.getTask(task.id) {
                        current.description = "最新说明版本 \(i)"
                        _ = try vault.updateTask(current)
                    }
                }
            } catch {
                Issue.record("Mutation error in iteration \(i): \(error)")
            }
        }

        // Then: The task remains readable with activities intact
        let finalTask = vault.index.getTask(task.id)
        #expect(finalTask != nil)
        #expect(finalTask!.activities.count == count / 2)
    }
}
