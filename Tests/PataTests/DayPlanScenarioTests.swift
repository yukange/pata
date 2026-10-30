import Testing
import Foundation
@testable import PataCore
@testable import PataUI

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

    @Test("Given today plan date, when shifting forward from today, then forward navigation into the future is blocked")
    @MainActor
    func shiftingForwardPastTodayIsBlockedScenario() {
        let state = AppState.shared
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let todayStr = f.string(from: Date())
        state.todayDateString = todayStr

        // Given: Today's date is set
        let canShiftForward = state.todayDateString < todayStr
        #expect(!canShiftForward)

        // When: Attempting to advance day when already on today
        func shiftDay(_ delta: Int) {
            guard delta < 0 || state.todayDateString < todayStr else { return }
            if let d = f.date(from: state.todayDateString),
               let next = Calendar.current.date(byAdding: .day, value: delta, to: d) {
                let nextStr = f.string(from: next)
                if delta > 0 && nextStr > todayStr {
                    state.todayDateString = todayStr
                } else {
                    state.todayDateString = nextStr
                }
            }
        }

        // Shifting forward (+1) is blocked
        shiftDay(1)
        #expect(state.todayDateString == todayStr)

        // Shifting backward (-1) goes to yesterday
        shiftDay(-1)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let yesterdayStr = f.string(from: yesterday)
        #expect(state.todayDateString == yesterdayStr)

        // When on yesterday, canShiftForward becomes true
        #expect(state.todayDateString < todayStr)

        // Shifting forward returns to today
        shiftDay(1)
        #expect(state.todayDateString == todayStr)

        // Further shifting forward continues to be blocked
        shiftDay(5)
        #expect(state.todayDateString == todayStr)
    }

    @Test("Given existing vault tasks and a DayPlan, when candidate tasks are queried for inline dropdown, then tasks already in DayPlan are excluded and candidates are categorized and searchable")
    func inlineTaskCandidatesFilteringScenario() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let vault = try Vault(rootPath: tmpDir.path)

        // Given: 3 tasks in vault
        let task1 = try vault.createTask(title: "设计新架构方案", status: .todo, tags: ["architecture"])
        let task2 = try vault.createTask(title: "修复网络连接问题", status: .todo, tags: ["bug"])
        let task3 = try vault.createTask(title: "编写需求说明书", status: .done, tags: ["docs"])

        let dateStr = "2026-10-30"

        // And: task1 is already in DayPlan for dateStr
        try vault.addTaskToPlan(date: dateStr, taskId: task1.id)

        let plan = vault.getDayPlan(date: dateStr)
        let currentPlanIds = Set(plan.taskIds)

        // When: Filtering available tasks (excluding tasks already in plan)
        let availableTasks = vault.index.listTasks().filter { !currentPlanIds.contains($0.id) }

        // Then: task1 is excluded, task2 and task3 are available
        #expect(availableTasks.count == 2)
        #expect(!availableTasks.contains { $0.id == task1.id })
        #expect(availableTasks.contains { $0.id == task2.id })
        #expect(availableTasks.contains { $0.id == task3.id })

        // And: Uncompleted tab filter gives only task2
        let uncompletedCandidates = availableTasks.filter { $0.status == .todo }
        #expect(uncompletedCandidates.count == 1)
        #expect(uncompletedCandidates.first?.id == task2.id)

        // And: Completed tab filter gives only task3
        let completedCandidates = availableTasks.filter { $0.status == .done }
        #expect(completedCandidates.count == 1)
        #expect(completedCandidates.first?.id == task3.id)

        // And: Keyword search "网络" matches task2
        let searchResults = availableTasks.filter {
            $0.title.lowercased().contains("网络") || $0.tags.contains { $0.contains("网络") }
        }
        #expect(searchResults.count == 1)
        #expect(searchResults.first?.id == task2.id)

        // When: Selecting task2 to add to DayPlan
        try vault.addTaskToPlan(date: dateStr, taskId: task2.id)

        // Then: DayPlan now has both task1 and task2
        let updatedPlan = vault.getDayPlan(date: dateStr)
        #expect(updatedPlan.taskIds == [task1.id, task2.id])
    }

    @Test("Given multiple candidate tasks, when continuously selected into DayPlan, then all selected tasks are added in succession and candidates update continuously")
    func continuousCandidateSelectionScenario() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let vault = try Vault(rootPath: tmpDir.path)

        let t1 = try vault.createTask(title: "任务 1", status: .todo)
        let t2 = try vault.createTask(title: "任务 2", status: .todo)
        let t3 = try vault.createTask(title: "任务 3", status: .todo)

        let dateStr = "2026-10-30"

        // Step 1: Initial available tasks count is 3
        var currentPlanIds = Set(vault.getDayPlan(date: dateStr).taskIds)
        var remaining = vault.index.listTasks().filter { !currentPlanIds.contains($0.id) }
        #expect(remaining.count == 3)

        // Step 2: Select t1 continuously without closing picker
        try vault.addTaskToPlan(date: dateStr, taskId: t1.id)
        currentPlanIds = Set(vault.getDayPlan(date: dateStr).taskIds)
        remaining = vault.index.listTasks().filter { !currentPlanIds.contains($0.id) }
        #expect(remaining.count == 2)
        #expect(!remaining.contains { $0.id == t1.id })
        #expect(remaining.contains { $0.id == t2.id })
        #expect(remaining.contains { $0.id == t3.id })

        // Step 3: Select t2 continuously
        try vault.addTaskToPlan(date: dateStr, taskId: t2.id)
        currentPlanIds = Set(vault.getDayPlan(date: dateStr).taskIds)
        remaining = vault.index.listTasks().filter { !currentPlanIds.contains($0.id) }
        #expect(remaining.count == 1)
        #expect(remaining.first?.id == t3.id)

        // Step 4: Select t3 continuously
        try vault.addTaskToPlan(date: dateStr, taskId: t3.id)
        let finalPlan = vault.getDayPlan(date: dateStr)
        #expect(finalPlan.taskIds == [t1.id, t2.id, t3.id])

        currentPlanIds = Set(finalPlan.taskIds)
        remaining = vault.index.listTasks().filter { !currentPlanIds.contains($0.id) }
        #expect(remaining.isEmpty)
    }
}
