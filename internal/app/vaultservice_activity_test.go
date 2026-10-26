package app

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"pata/internal/storage/markdown"
)

func TestVaultService_ActivityCRUD_TaskHost(t *testing.T) {
	tempDir, err := os.MkdirTemp("", "TestVaultService_ActivityCRUD_TaskHost*")
	if err != nil {
		t.Fatal(err)
	}
	defer os.RemoveAll(tempDir)

	s := &VaultService{}
	if _, err := s.openVault(tempDir); err != nil {
		t.Fatalf("OpenVault failed: %v", err)
	}

	note, err := s.CreateNote(CreateNoteInput{Title: "引用笔记"})
	if err != nil {
		t.Fatalf("CreateNote failed: %v", err)
	}

	task, err := s.CreateTask(CreateTaskInput{
		Title: "开发任务",
		Tags:  []string{"dev"},
	})
	if err != nil {
		t.Fatalf("CreateTask failed: %v", err)
	}

	// 1. CreateActivity on Task
	act1, err := s.CreateActivity(CreateActivityInput{
		TaskID:   task.ID,
		Body:     "开始第一阶段开发 [[引用笔记]]",
		Tags:     []string{"进度"},
		NoteRefs: map[string]string{"引用笔记": note.ID},
	})
	if err != nil {
		t.Fatalf("CreateActivity failed: %v", err)
	}
	if !strings.HasPrefix(act1.ID, "a-") {
		t.Fatalf("expected ID starting with 'a-', got %s", act1.ID)
	}

	// Check task on disk contains the embedded activity block
	taskPath := s.vault.ResolveEntityPath(task)
	content, err := os.ReadFile(taskPath)
	if err != nil {
		t.Fatalf("failed to read task file: %v", err)
	}
	if !strings.Contains(string(content), "<!-- pata:activity") || !strings.Contains(string(content), act1.ID) {
		t.Fatalf("task file does not contain embedded activity: %s", string(content))
	}

	// 2. GetActivity
	gotAct, err := s.GetActivity(act1.ID)
	if err != nil || gotAct.Body != "开始第一阶段开发 [[引用笔记]]" {
		t.Fatalf("GetActivity failed: %v, got: %+v", err, gotAct)
	}

	// 3. ListActivitiesByTask
	acts, err := s.ListActivitiesByTask(task.ID)
	if err != nil || len(acts) != 1 || acts[0].ID != act1.ID {
		t.Fatalf("ListActivitiesByTask failed: %v, acts: %+v", err, acts)
	}

	// 4. UpdateActivity
	updated, err := s.UpdateActivity(UpdateActivityInput{
		ID:   act1.ID,
		Body: "修改后的进度描述",
		Tags: []string{"进度", "已完成"},
	})
	if err != nil || updated.Body != "修改后的进度描述" || len(updated.Tags) != 2 {
		t.Fatalf("UpdateActivity failed: %v, updated: %+v", err, updated)
	}

	// Verify disk reflects update
	contentAfterUpdate, _ := os.ReadFile(taskPath)
	if !strings.Contains(string(contentAfterUpdate), "修改后的进度描述") {
		t.Fatalf("task file missing updated activity body: %s", string(contentAfterUpdate))
	}

	// 5. DeleteActivity
	if err := s.DeleteActivity(act1.ID); err != nil {
		t.Fatalf("DeleteActivity failed: %v", err)
	}
	if _, err := s.GetActivity(act1.ID); err == nil {
		t.Fatalf("expected GetActivity to fail after deletion")
	}
	actsAfterDelete, err := s.ListActivitiesByTask(task.ID)
	if err != nil || len(actsAfterDelete) != 0 {
		t.Fatalf("expected 0 activities after delete, got %d", len(actsAfterDelete))
	}
	contentAfterDelete, _ := os.ReadFile(taskPath)
	if strings.Contains(string(contentAfterDelete), "<!-- pata:activity") {
		t.Fatalf("expected activity blocks to be cleared from task file, got: %s", string(contentAfterDelete))
	}
}

func TestVaultService_ActivityCRUD_DayPlanHost(t *testing.T) {
	tempDir, err := os.MkdirTemp("", "TestVaultService_ActivityCRUD_DayPlanHost*")
	if err != nil {
		t.Fatal(err)
	}
	defer os.RemoveAll(tempDir)

	s := &VaultService{}
	if _, err := s.openVault(tempDir); err != nil {
		t.Fatalf("OpenVault failed: %v", err)
	}

	date := "2026-10-16"
	act, err := s.CreateActivity(CreateActivityInput{
		Date: date,
		Body: "今日独立记录：上午开会讨论架构方案",
		Tags: []string{"会议"},
	})
	if err != nil {
		t.Fatalf("CreateActivity on DayPlan failed: %v", err)
	}

	// Verify plan file exists at root plans/YYYY-MM-DD.md
	planPath := filepath.Join(tempDir, "plans", date+".md")
	planBytes, err := os.ReadFile(planPath)
	if err != nil {
		t.Fatalf("expected plan file at %s, failed: %v", planPath, err)
	}
	if !strings.Contains(string(planBytes), "今日独立记录") {
		t.Fatalf("plan file missing activity body: %s", string(planBytes))
	}

	// Update Activity in DayPlan
	updated, err := s.UpdateActivity(UpdateActivityInput{
		ID:   act.ID,
		Body: "今日独立记录（已更新）",
		Tags: []string{"会议", "重要"},
	})
	if err != nil || updated.Body != "今日独立记录（已更新）" {
		t.Fatalf("UpdateActivity on DayPlan failed: %v", err)
	}

	// Delete Activity from DayPlan
	if err := s.DeleteActivity(act.ID); err != nil {
		t.Fatalf("DeleteActivity on DayPlan failed: %v", err)
	}
	if _, err := s.GetActivity(act.ID); err == nil {
		t.Fatalf("expected GetActivity to fail after deletion")
	}
	contentAfterPlanDelete, _ := os.ReadFile(planPath)
	if strings.Contains(string(contentAfterPlanDelete), "<!-- pata:activity") {
		t.Fatalf("expected activity blocks to be cleared from plan file, got: %s", string(contentAfterPlanDelete))
	}
}

func TestVaultService_CreateActivity_HistoricalDate(t *testing.T) {
	tempDir, err := os.MkdirTemp("", "TestVaultService_CreateActivity_HistoricalDate*")
	if err != nil {
		t.Fatal(err)
	}
	defer os.RemoveAll(tempDir)

	s := &VaultService{}
	if _, err := s.openVault(tempDir); err != nil {
		t.Fatalf("OpenVault failed: %v", err)
	}

	date := "2025-01-01"
	act, err := s.CreateActivity(CreateActivityInput{
		Date: date,
		Body: "历史活动记录",
	})
	if err != nil {
		t.Fatalf("CreateActivity failed: %v", err)
	}

	localDate := act.At.In(time.Local).Format("2006-01-02")
	if localDate != date {
		t.Fatalf("expected activity At in local time to be %s, got %s (UTC: %v)", date, localDate, act.At)
	}
}

func TestVaultService_DeleteTask_CascadesActivitiesAndCleansDayPlans(t *testing.T) {
	tempDir, err := os.MkdirTemp("", "TestVaultService_DeleteTask_Cascades*")
	if err != nil {
		t.Fatal(err)
	}
	defer os.RemoveAll(tempDir)

	s := &VaultService{}
	if _, err := s.openVault(tempDir); err != nil {
		t.Fatalf("OpenVault failed: %v", err)
	}

	task, err := s.CreateTask(CreateTaskInput{Title: "将被删除的任务"})
	if err != nil {
		t.Fatalf("CreateTask failed: %v", err)
	}

	act1, err := s.CreateActivity(CreateActivityInput{
		TaskID: task.ID,
		Body:   "任务活动 1",
	})
	if err != nil {
		t.Fatal(err)
	}

	act2, err := s.CreateActivity(CreateActivityInput{
		TaskID: task.ID,
		Body:   "任务活动 2",
	})
	if err != nil {
		t.Fatal(err)
	}

	date := "2026-10-16"
	if _, err := s.SaveDayPlan(date, []string{task.ID}); err != nil {
		t.Fatalf("SaveDayPlan failed: %v", err)
	}

	// Verify plan has task.ID
	plan, _ := s.GetDayPlan(date)
	if len(plan.TaskIDs) != 1 || plan.TaskIDs[0] != task.ID {
		t.Fatalf("expected task in plan, got %+v", plan.TaskIDs)
	}

	// Delete Task
	if err := s.DeleteTask(task.ID); err != nil {
		t.Fatalf("DeleteTask failed: %v", err)
	}

	// 1. Task file deleted
	if _, err := s.GetTask(task.ID); err == nil {
		t.Fatalf("task should no longer exist")
	}

	// 2. Embedded activities cascade deleted
	if _, err := s.GetActivity(act1.ID); err == nil {
		t.Fatalf("activity 1 should be deleted with task")
	}
	if _, err := s.GetActivity(act2.ID); err == nil {
		t.Fatalf("activity 2 should be deleted with task")
	}

	// 3. DayPlan reference to task cleaned up
	planAfter, _ := s.GetDayPlan(date)
	if len(planAfter.TaskIDs) != 0 {
		t.Fatalf("expected DayPlan taskIDs to be cleaned up, got %+v", planAfter.TaskIDs)
	}
}

func TestVaultService_DayTimeline_AggregatesTaskAndDayPlanActivities(t *testing.T) {
	tempDir, err := os.MkdirTemp("", "TestVaultService_DayTimeline_Aggregates*")
	if err != nil {
		t.Fatal(err)
	}
	defer os.RemoveAll(tempDir)

	s := &VaultService{}
	if _, err := s.openVault(tempDir); err != nil {
		t.Fatalf("OpenVault failed: %v", err)
	}

	today := time.Now().In(time.Local).Format("2006-01-02")

	// Task 1 with activity
	task1, err := s.CreateTask(CreateTaskInput{Title: "任务一"})
	if err != nil {
		t.Fatal(err)
	}
	tActTime := time.Now().UTC()
	taskAct, err := s.CreateActivity(CreateActivityInput{
		TaskID: task1.ID,
		At:     &tActTime,
		Body:   "任务一的最新进展",
	})
	if err != nil {
		t.Fatal(err)
	}

	// Independent activity on today
	dpActTime := time.Now().UTC()
	dpAct, err := s.CreateActivity(CreateActivityInput{
		Date: today,
		At:   &dpActTime,
		Body: "今日便签记录",
	})
	if err != nil {
		t.Fatal(err)
	}

	// Complete task1
	if _, err := s.SetTaskStatus(task1.ID, markdown.TaskStatusDone); err != nil {
		t.Fatal(err)
	}

	// Query DayTimeline
	timeline, err := s.GetDayTimeline(today)
	if err != nil {
		t.Fatalf("GetDayTimeline failed: %v", err)
	}

	if len(timeline) < 3 {
		t.Fatalf("expected at least 3 timeline items, got %d: %+v", len(timeline), timeline)
	}

	var foundTaskAct, foundDpAct, foundCompletion bool
	for _, item := range timeline {
		if item.Activity != nil && item.Activity.ID == taskAct.ID {
			foundTaskAct = true
			if item.TaskID != task1.ID || item.TaskTitle != "任务一" {
				t.Fatalf("task activity item missing task info: %+v", item)
			}
		}
		if item.Activity != nil && item.Activity.ID == dpAct.ID {
			foundDpAct = true
		}
		if item.Kind == "completion" && item.TaskID == task1.ID {
			foundCompletion = true
		}
	}

	if !foundTaskAct || !foundDpAct || !foundCompletion {
		t.Fatalf("missing items in timeline: taskAct=%v, dpAct=%v, completion=%v", foundTaskAct, foundDpAct, foundCompletion)
	}
}
