package app

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"pata/internal/storage/markdown"
)

// TestAcceptance_TaskActivity_LifecycleAndInlineEditing verifies the complete lifecycle
// of Task Activities: creation, inline editing, status events, and on-disk atomic markdown consistency.
func TestAcceptance_TaskActivity_LifecycleAndInlineEditing(t *testing.T) {
	tmpDir, err := os.MkdirTemp("", "pata-task-activity-vault-*")
	if err != nil {
		t.Fatal(err)
	}
	defer os.RemoveAll(tmpDir)

	configPath := filepath.Join(tmpDir, "config", "vault.json")
	vaultDir := filepath.Join(tmpDir, "vault")
	_ = os.MkdirAll(vaultDir, 0755)

	svc := &VaultService{
		configPath: configPath,
		emitEvent:  func(name string, data any) {},
	}

	if _, err := svc.openVault(vaultDir); err != nil {
		t.Fatalf("openVault failed: %v", err)
	}
	defer func() {
		if svc.stopWatcher != nil {
			svc.stopWatcher()
		}
	}()

	// 1. Given a reference Note
	note, err := svc.CreateNote(CreateNoteInput{
		Title: "活动流交互规范",
	})
	if err != nil {
		t.Fatalf("CreateNote failed: %v", err)
	}

	// 2. When a Task referencing the note is created
	task, err := svc.CreateTask(CreateTaskInput{
		Title:       "统一任务与活动流交互",
		Description: "根据 [[活动流交互规范]] 统一布局",
		NoteRefs:    map[string]string{"活动流交互规范": note.ID},
	})
	if err != nil {
		t.Fatalf("CreateTask failed: %v", err)
	}

	// 3. And an Activity linked to the task is created
	act1, err := svc.CreateActivity(CreateActivityInput{
		TaskID:   task.ID,
		Body:     "讨论一体式 ActivityComposer 方案",
		Tags:     []string{"ui"},
		NoteRefs: map[string]string{"活动流交互规范": note.ID},
	})
	if err != nil {
		t.Fatalf("CreateActivity act1 failed: %v", err)
	}
	if act1 == nil || act1.ID == "" {
		t.Fatalf("expected valid activity ID, got nil/empty")
	}

	// 4. Then ListActivitiesByTask returns the newly created activity
	acts, err := svc.ListActivitiesByTask(task.ID)
	if err != nil {
		t.Fatalf("ListActivitiesByTask failed: %v", err)
	}
	if len(acts) != 1 || acts[0].ID != act1.ID {
		t.Fatalf("expected 1 activity with id %s, got %d", act1.ID, len(acts))
	}
	if acts[0].Body != "讨论一体式 ActivityComposer 方案" {
		t.Fatalf("unexpected body: %q", acts[0].Body)
	}

	// 5. When the Activity is edited inline
	time.Sleep(5 * time.Millisecond) // ensure distinct timestamps if any
	updatedAct, err := svc.UpdateActivity(UpdateActivityInput{
		ID:       act1.ID,
		Body:     "完成一体式 ActivityComposer 统一卡片重构，集成 [[活动流交互规范]]",
		Tags:     []string{"ui", "completed"},
		NoteRefs: map[string]string{"活动流交互规范": note.ID},
	})
	if err != nil {
		t.Fatalf("UpdateActivity failed: %v", err)
	}
	if updatedAct.Body != "完成一体式 ActivityComposer 统一卡片重构，集成 [[活动流交互规范]]" {
		t.Fatalf("unexpected updated body: %q", updatedAct.Body)
	}
	if len(updatedAct.Tags) != 2 || updatedAct.Tags[1] != "completed" {
		t.Fatalf("unexpected updated tags: %v", updatedAct.Tags)
	}

	// 6. Then subsequent listings reflect the updated body and tags
	actsAfterUpdate, err := svc.ListActivitiesByTask(task.ID)
	if err != nil {
		t.Fatalf("ListActivitiesByTask after update failed: %v", err)
	}
	if len(actsAfterUpdate) != 1 || actsAfterUpdate[0].Body != updatedAct.Body {
		t.Fatalf("ListActivitiesByTask did not reflect update: %+v", actsAfterUpdate)
	}

	// 7. And the underlying Markdown file on disk is atomically updated
	taskFile := svc.vault.ResolveEntityPath(task)
	rawContent, err := os.ReadFile(taskFile)
	if err != nil {
		t.Fatalf("failed to read raw task file: %v", err)
	}
	rawStr := string(rawContent)
	if !strings.Contains(rawStr, updatedAct.Body) {
		t.Fatalf("task file on disk does not contain updated activity body:\n%s", rawStr)
	}
	if !strings.Contains(rawStr, "- ui") || !strings.Contains(rawStr, "- completed") {
		t.Fatalf("task file on disk missing updated tags:\n%s", rawStr)
	}

	// 8. When the task is marked completed
	_, err = svc.UpdateTask(UpdateTaskInput{
		ID:     task.ID,
		Title:  task.Title,
		Status: markdown.TaskStatusDone,
	})
	if err != nil {
		t.Fatalf("UpdateTask to completed failed: %v", err)
	}

	// Then status_events record the completion action
	rawCompleted, err := os.ReadFile(taskFile)
	if err != nil {
		t.Fatalf("failed to read raw task file after completion: %v", err)
	}
	if !strings.Contains(string(rawCompleted), "action: completed") {
		t.Fatalf("expected status_event 'action: completed' in task file:\n%s", string(rawCompleted))
	}

	// 9. When the task is reopened
	_, err = svc.UpdateTask(UpdateTaskInput{
		ID:     task.ID,
		Title:  task.Title,
		Status: markdown.TaskStatusTodo,
	})
	if err != nil {
		t.Fatalf("UpdateTask to todo failed: %v", err)
	}

	// Then status_events record the reopened action
	rawReopened, err := os.ReadFile(taskFile)
	if err != nil {
		t.Fatalf("failed to read raw task file after reopen: %v", err)
	}
	if !strings.Contains(string(rawReopened), "action: reopened") {
		t.Fatalf("expected status_event 'action: reopened' in task file:\n%s", string(rawReopened))
	}

	// 10. Given a Today standalone activity
	todayStr := time.Now().Format("2006-01-02")
	todayAct, err := svc.CreateActivity(CreateActivityInput{
		Date: todayStr,
		Body: "上午完成了活动流规范代码审查",
		Tags: []string{"review"},
	})
	if err != nil {
		t.Fatalf("CreateActivity for day plan failed: %v", err)
	}
	if todayAct == nil || todayAct.ID == "" {
		t.Fatalf("expected valid today activity ID")
	}

	// When edited inline
	_, err = svc.UpdateActivity(UpdateActivityInput{
		ID:   todayAct.ID,
		Body: "上午完成了活动流规范代码审查与自动化测试补齐",
		Tags: []string{"review", "passed"},
	})
	if err != nil {
		t.Fatalf("UpdateActivity for today activity failed: %v", err)
	}

	// Then day plan on disk contains the updated text
	planFile := filepath.Join(vaultDir, "plans", todayStr+".md")
	rawPlan, err := os.ReadFile(planFile)
	if err != nil {
		t.Fatalf("failed to read day plan file: %v", err)
	}
	if !strings.Contains(string(rawPlan), "自动化测试补齐") {
		t.Fatalf("day plan file on disk does not contain updated activity body:\n%s", string(rawPlan))
	}

	// 11. Edge cases: empty ID or non-existent ID return error
	if _, err := svc.UpdateActivity(UpdateActivityInput{ID: "", Body: "test"}); err == nil {
		t.Fatalf("expected error for empty activity ID")
	}
	if _, err := svc.UpdateActivity(UpdateActivityInput{ID: "a-nonexistent", Body: "test"}); err == nil {
		t.Fatalf("expected error for non-existent activity ID")
	}
}

// TestAcceptance_TaskActivity_DayPlanStorageAndTimelineAggregation verifies:
// 1. Task activities are persisted inside the task markdown file.
// 2. DayPlan standalone activities are stored in plans/YYYY-MM-DD.md.
// 3. Today's timeline aggregates both task activities and standalone activities.
// 4. Task completion generates completion timeline items.
// 5. Deleting a task cascades to its activities and DayPlan references.
func TestAcceptance_TaskActivity_DayPlanStorageAndTimelineAggregation(t *testing.T) {
	tmpDir, err := os.MkdirTemp("", "pata-dayplan-vault-*")
	if err != nil {
		t.Fatal(err)
	}
	defer os.RemoveAll(tmpDir)

	svc := NewVaultService()
	v, err := svc.openVault(tmpDir)
	if err != nil {
		t.Fatalf("failed to open vault: %v", err)
	}
	defer func() {
		if svc.stopWatcher != nil {
			svc.stopWatcher()
		}
	}()

	today := time.Now().Format("2006-01-02")

	// 1. Create a Task
	task, err := svc.CreateTask(CreateTaskInput{
		Title:       "异步滚动性能优化",
		Description: "第一阶段：支持异步滚动",
	})
	if err != nil {
		t.Fatalf("CreateTask failed: %v", err)
	}

	// 2. Add Activity to Task
	actTime := time.Now()
	act1, err := svc.CreateActivity(CreateActivityInput{
		OwnerType: markdown.EntityTypeTask,
		TaskID:    task.ID,
		At:        &actTime,
		Body:      "完成了异步队列缓冲区设计 #queue",
		Tags:      []string{"queue"},
	})
	if err != nil {
		t.Fatalf("CreateActivity failed: %v", err)
	}
	if !strings.HasPrefix(act1.ID, "a-") {
		t.Fatalf("activity ID should have prefix 'a-', got %s", act1.ID)
	}

	// Verify task file format
	taskFile := v.ResolveEntityPath(task)
	contentBytes, err := os.ReadFile(taskFile)
	if err != nil {
		t.Fatal(err)
	}
	content := string(contentBytes)
	if !strings.Contains(content, `<!-- pata:activity`) || !strings.Contains(content, `id: `+act1.ID) || !strings.Contains(content, `<!-- /pata:activity -->`) {
		t.Fatalf("task body should contain embedded activity block, got:\n%s", content)
	}

	// 3. Add task to Today's DayPlan
	if _, err := svc.SaveDayPlan(today, []string{task.ID}); err != nil {
		t.Fatalf("SaveDayPlan failed: %v", err)
	}

	// 4. Create standalone Activity in Today's DayPlan
	_, err = svc.CreateActivity(CreateActivityInput{
		OwnerType: markdown.EntityTypeDayPlan,
		Date:      today,
		Body:      "今天团队同步晨会",
		Tags:      []string{"meeting"},
	})
	if err != nil {
		t.Fatalf("Create standalone activity failed: %v", err)
	}

	// Verify plan file location: plans/YYYY-MM-DD.md
	planFilePath := filepath.Join(tmpDir, "plans", today+".md")
	if _, err := os.Stat(planFilePath); os.IsNotExist(err) {
		t.Fatalf("DayPlan file should be at %s", planFilePath)
	}

	// 5. Test Timeline aggregation
	timeline, err := svc.GetDayTimeline(today)
	if err != nil {
		t.Fatalf("GetDayTimeline failed: %v", err)
	}
	if len(timeline) < 2 {
		t.Fatalf("expected at least 2 items in timeline (task activity + standalone activity), got %d", len(timeline))
	}

	// 6. Toggle task status to done -> should record completion event in timeline
	updatedTask, err := svc.UpdateTask(UpdateTaskInput{
		ID:     task.ID,
		Title:  task.Title,
		Status: markdown.TaskStatusDone,
	})
	if err != nil {
		t.Fatalf("UpdateTask to done failed: %v", err)
	}
	if updatedTask.Status != markdown.TaskStatusDone {
		t.Fatalf("expected task status done, got %s", updatedTask.Status)
	}

	timelineWithDone, err := svc.GetDayTimeline(today)
	if err != nil {
		t.Fatalf("GetDayTimeline after done failed: %v", err)
	}
	hasCompletion := false
	for _, item := range timelineWithDone {
		if item.Kind == "completion" && item.TaskID == task.ID {
			hasCompletion = true
			break
		}
	}
	if !hasCompletion {
		t.Fatalf("expected completion event in today's timeline")
	}

	// 7. Cascading Delete: Delete Task
	if err := svc.DeleteTask(task.ID); err != nil {
		t.Fatalf("DeleteTask failed: %v", err)
	}

	// Verify task activity is deleted
	if _, _, ok := v.Index.GetActivity(act1.ID); ok {
		t.Fatalf("activity %s should have been deleted when task was deleted", act1.ID)
	}

	// Verify task is removed from DayPlan task_ids
	plan, ok := v.Index.GetDayPlan(today)
	if !ok {
		t.Fatalf("DayPlan for %s should still exist", today)
	}
	for _, tid := range plan.TaskIDs {
		if tid == task.ID {
			t.Fatalf("deleted task ID %s still present in DayPlan task_ids", task.ID)
		}
	}
}
