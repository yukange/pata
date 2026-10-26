package app

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"pata/internal/storage/markdown"
)

// TestAcceptance_TagView_MixedEntitiesChronologicalDescending verifies that ListByTag
// returns mixed entities (tasks, activities, notes) sorted chronologically descending.
func TestAcceptance_TagView_MixedEntitiesChronologicalDescending(t *testing.T) {
	tempVault := t.TempDir()
	_ = os.MkdirAll(filepath.Join(tempVault, "notes"), 0755)
	_ = os.MkdirAll(filepath.Join(tempVault, "tasks"), 0755)
	_ = os.MkdirAll(filepath.Join(tempVault, "plans"), 0755)
	_ = os.MkdirAll(filepath.Join(tempVault, "files"), 0755)

	svc := NewVaultService()
	if _, err := svc.openVault(tempVault); err != nil {
		t.Fatalf("failed to open vault: %v", err)
	}
	defer func() {
		if svc.stopWatcher != nil {
			svc.stopWatcher()
		}
	}()

	now := time.Now().UTC()
	tOld := now.Add(-3 * time.Hour)
	tMid := now.Add(-2 * time.Hour)
	tNew := now.Add(-1 * time.Hour)

	// Create Note at tOld
	noteContent := fmt.Sprintf(`---
type: note
id: n-tag-001
title: 历史架构草案
tags:
  - 核心
created_at: %s
updated_at: %s
---

这是最早的笔记正文内容
`, tOld.Format(time.RFC3339Nano), tOld.Format(time.RFC3339Nano))
	if err := os.WriteFile(filepath.Join(tempVault, "notes", "n-tag-001.md"), []byte(noteContent), 0644); err != nil {
		t.Fatalf("write note: %v", err)
	}

	// Create Task at tMid with embedded Activity at tNew
	taskContent := fmt.Sprintf(`---
type: task
id: t-tag-001
title: 核心模块重构
status: todo
tags:
  - 核心
created_at: %s
updated_at: %s
---

<!-- pata:activity
id: a-tag-001
at: %s
-->
最新的活动进展记录
<!-- /pata:activity -->
`, tMid.Format(time.RFC3339Nano), tMid.Format(time.RFC3339Nano), tNew.Format(time.RFC3339Nano))
	if err := os.WriteFile(filepath.Join(tempVault, "tasks", "t-tag-001.md"), []byte(taskContent), 0644); err != nil {
		t.Fatalf("write task: %v", err)
	}

	if err := svc.RescanVault(); err != nil {
		t.Fatalf("rescan vault failed: %v", err)
	}

	refs, err := svc.ListByTag("核心")
	if err != nil {
		t.Fatalf("ListByTag failed: %v", err)
	}

	if len(refs) != 3 {
		t.Fatalf("expected 3 refs for '核心', got %d: %+v", len(refs), refs)
	}

	// Verify descending order: tNew (activity) -> tMid (task) -> tOld (note)
	if refs[0].Type != markdown.EntityTypeActivity || refs[0].ID != "a-tag-001" {
		t.Errorf("expected 1st item to be newest activity a-tag-001, got %+v", refs[0])
	}
	if refs[0].Snippet != "最新的活动进展记录" {
		t.Errorf("expected activity snippet to be populated, got %q", refs[0].Snippet)
	}
	if refs[0].TaskID != "t-tag-001" {
		t.Errorf("expected activity TaskID to be t-tag-001, got %q", refs[0].TaskID)
	}

	if refs[1].Type != markdown.EntityTypeTask || refs[1].ID != "t-tag-001" {
		t.Errorf("expected 2nd item to be middle task t-tag-001, got %+v", refs[1])
	}
	if refs[1].Status != markdown.TaskStatusTodo {
		t.Errorf("expected task status to be todo, got %q", refs[1].Status)
	}

	if refs[2].Type != markdown.EntityTypeNote || refs[2].ID != "n-tag-001" {
		t.Errorf("expected 3rd item to be oldest note n-tag-001, got %+v", refs[2])
	}
	if !strings.Contains(refs[2].Snippet, "这是最早的笔记正文内容") {
		t.Errorf("expected note snippet to be populated, got %q", refs[2].Snippet)
	}

	if !refs[0].Time.After(refs[1].Time) || !refs[1].Time.After(refs[2].Time) {
		t.Errorf("expected strictly descending timestamps: [%v, %v, %v]", refs[0].Time, refs[1].Time, refs[2].Time)
	}
}

// TestAcceptance_VaultHealth_IntegrityInspection verifies the health and integrity inspection
// of a real vault if the test_pata directory is available.
func TestAcceptance_VaultHealth_IntegrityInspection(t *testing.T) {
	testVaultPath := "/Users/wuyukang/code/github/test_pata"
	if _, err := os.Stat(testVaultPath); os.IsNotExist(err) {
		t.Skip("skipping real vault test: test_pata directory not found")
	}

	svc := NewVaultService()
	v, err := svc.openVault(testVaultPath)
	if err != nil {
		t.Fatalf("failed to open test_pata vault: %v", err)
	}
	defer func() {
		if svc.stopWatcher != nil {
			svc.stopWatcher()
		}
	}()

	t.Logf("test_pata Tasks: %d, Notes: %d, DayPlans: %d, Files: %d",
		len(v.Index.ListTasks()),
		len(v.Index.ListNotes()),
		len(v.Index.ListDayPlans()),
		len(v.Index.ListFiles()),
	)

	health, err := svc.GetVaultHealth()
	if err != nil {
		t.Fatalf("GetVaultHealth failed: %v", err)
	}
	t.Logf("test_pata Health: %d parse errors, %d dangling references", len(health.ParseErrors), len(health.DanglingRefs))
}
