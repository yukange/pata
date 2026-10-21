package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"pata/internal/storage/markdown"
)

// TestStage13_AppBundleIntegrity validates the macOS application package on the real machine.
func TestStage13_AppBundleIntegrity(t *testing.T) {
	appPath := filepath.Join("bin", "pata.app")
	if _, err := os.Stat(appPath); os.IsNotExist(err) {
		t.Fatalf("bin/pata.app does not exist. Please run packaging first.")
	}

	// 1. Verify executable exists and codesign passes
	execPath := filepath.Join(appPath, "Contents", "MacOS", "pata")
	fi, err := os.Stat(execPath)
	if err != nil || fi.Size() == 0 {
		t.Fatalf("Contents/MacOS/pata executable missing or empty: %v", err)
	}

	cmd := exec.Command("codesign", "--verify", "--deep", "--strict", appPath)
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("codesign verification failed: %s, err: %v", string(out), err)
	}

	// 2. Verify Info.plist contains valid bundle identifier
	plistPath := filepath.Join(appPath, "Contents", "Info.plist")
	plistData, err := os.ReadFile(plistPath)
	if err != nil {
		t.Fatalf("failed to read Info.plist: %v", err)
	}
	if !strings.Contains(string(plistData), "<string>com.pata.app</string>") {
		t.Fatalf("Info.plist missing expected CFBundleIdentifier 'com.pata.app'")
	}

	// 3. Verify icons.icns exists and is non-empty
	icnsPath := filepath.Join(appPath, "Contents", "Resources", "icons.icns")
	icnsInfo, err := os.Stat(icnsPath)
	if err != nil || icnsInfo.Size() < 100000 {
		t.Fatalf("icons.icns missing or unexpectedly small: %v", err)
	}

	// 4. Verify embedded frontend assets inside production binary
	if assetsFile, err := assets.Open("frontend/dist/index.html"); err != nil {
		t.Fatalf("embedded assets missing frontend/dist/index.html: %v", err)
	} else {
		_ = assetsFile.Close()
	}
}

// TestStage13_ActivityLifecycleAndInlineEditing verifies the end-to-end Activity lifecycle,
// including creation, inline editing, status events, and on-disk atomic markdown consistency.
func TestStage13_ActivityLifecycleAndInlineEditing(t *testing.T) {
	tmpDir, err := os.MkdirTemp("", "pata-stage13-vault-*")
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

	// 1. Create a Note for reference
	note, err := svc.CreateNote(CreateNoteInput{
		Title: "阶段13设计规范",
	})
	if err != nil {
		t.Fatalf("CreateNote failed: %v", err)
	}

	// 2. Create a Task
	task, err := svc.CreateTask(CreateTaskInput{
		Title:       "统一三栏 Inspector 与 Activity",
		Description: "根据 [[阶段13设计规范]] 统一布局",
		NoteRefs:    map[string]string{"阶段13设计规范": note.ID},
	})
	if err != nil {
		t.Fatalf("CreateTask failed: %v", err)
	}

	// 3. Create an Activity linked to the task
	act1, err := svc.CreateActivity(CreateActivityInput{
		TaskID:   task.ID,
		Body:     "讨论一体式 ActivityComposer 方案",
		Tags:     []string{"ui"},
		NoteRefs: map[string]string{"阶段13设计规范": note.ID},
	})
	if err != nil {
		t.Fatalf("CreateActivity act1 failed: %v", err)
	}
	if act1 == nil || act1.ID == "" {
		t.Fatalf("expected valid activity ID, got nil/empty")
	}

	// 4. Verify ListActivitiesByTask
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

	// 5. Inline Edit Activity (013-005): update body, tags, and note refs
	time.Sleep(5 * time.Millisecond) // ensure distinct timestamps if any
	updatedAct, err := svc.UpdateActivity(UpdateActivityInput{
		ID:       act1.ID,
		Body:     "完成一体式 ActivityComposer 统一卡片重构，集成 [[阶段13设计规范]]",
		Tags:     []string{"ui", "completed"},
		NoteRefs: map[string]string{"阶段13设计规范": note.ID},
	})
	if err != nil {
		t.Fatalf("UpdateActivity failed: %v", err)
	}
	if updatedAct.Body != "完成一体式 ActivityComposer 统一卡片重构，集成 [[阶段13设计规范]]" {
		t.Fatalf("unexpected updated body: %q", updatedAct.Body)
	}
	if len(updatedAct.Tags) != 2 || updatedAct.Tags[1] != "completed" {
		t.Fatalf("unexpected updated tags: %v", updatedAct.Tags)
	}

	// 6. Verify ListActivitiesByTask reflects the update
	actsAfterUpdate, err := svc.ListActivitiesByTask(task.ID)
	if err != nil {
		t.Fatalf("ListActivitiesByTask after update failed: %v", err)
	}
	if len(actsAfterUpdate) != 1 || actsAfterUpdate[0].Body != updatedAct.Body {
		t.Fatalf("ListActivitiesByTask did not reflect update: %+v", actsAfterUpdate)
	}

	// 7. Verify atomic on-disk task markdown file
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

	// 8. Task status event handling: Complete task
	_, err = svc.UpdateTask(UpdateTaskInput{
		ID:     task.ID,
		Title:  task.Title,
		Status: markdown.TaskStatusDone,
	})
	if err != nil {
		t.Fatalf("UpdateTask to completed failed: %v", err)
	}

	// Verify on-disk status_events
	rawCompleted, err := os.ReadFile(taskFile)
	if err != nil {
		t.Fatalf("failed to read raw task file after completion: %v", err)
	}
	if !strings.Contains(string(rawCompleted), "action: completed") {
		t.Fatalf("expected status_event 'action: completed' in task file:\n%s", string(rawCompleted))
	}

	// 9. Reopen task
	_, err = svc.UpdateTask(UpdateTaskInput{
		ID:     task.ID,
		Title:  task.Title,
		Status: markdown.TaskStatusTodo,
	})
	if err != nil {
		t.Fatalf("UpdateTask to todo failed: %v", err)
	}

	rawReopened, err := os.ReadFile(taskFile)
	if err != nil {
		t.Fatalf("failed to read raw task file after reopen: %v", err)
	}
	if !strings.Contains(string(rawReopened), "action: reopened") {
		t.Fatalf("expected status_event 'action: reopened' in task file:\n%s", string(rawReopened))
	}

	// 10. Today standalone activity creation and inline editing
	todayStr := time.Now().Format("2006-01-02")
	todayAct, err := svc.CreateActivity(CreateActivityInput{
		Date: todayStr,
		Body: "上午完成了阶段 13 代码审查",
		Tags: []string{"review"},
	})
	if err != nil {
		t.Fatalf("CreateActivity for day plan failed: %v", err)
	}
	if todayAct == nil || todayAct.ID == "" {
		t.Fatalf("expected valid today activity ID")
	}

	// Update today activity inline
	_, err = svc.UpdateActivity(UpdateActivityInput{
		ID:   todayAct.ID,
		Body: "上午完成了阶段 13 代码审查与自动化测试补齐",
		Tags: []string{"review", "passed"},
	})
	if err != nil {
		t.Fatalf("UpdateActivity for today activity failed: %v", err)
	}

	// Verify day plan on disk
	planFile := filepath.Join(vaultDir, "plans", todayStr+".md")
	rawPlan, err := os.ReadFile(planFile)
	if err != nil {
		t.Fatalf("failed to read day plan file: %v", err)
	}
	if !strings.Contains(string(rawPlan), "自动化测试补齐") {
		t.Fatalf("day plan file on disk does not contain updated activity body:\n%s", string(rawPlan))
	}

	// 11. Error cases: empty ID or non-existent ID
	if _, err := svc.UpdateActivity(UpdateActivityInput{ID: "", Body: "test"}); err == nil {
		t.Fatalf("expected error for empty activity ID")
	}
	if _, err := svc.UpdateActivity(UpdateActivityInput{ID: "a-nonexistent", Body: "test"}); err == nil {
		t.Fatalf("expected error for non-existent activity ID")
	}
}
