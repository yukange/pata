package markdown

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestActivityParseAndFormat_RoundTrip(t *testing.T) {
	atTime, _ := time.Parse(time.RFC3339, "2026-10-15T10:30:00+08:00")
	original := []Activity{
		{
			ID:       "a-01jtest1",
			At:       atTime,
			Tags:     []string{"设计", "Pata"},
			NoteRefs: map[string]string{"技术方案": "n-002"},
			Body:     "完成基础设计，参考 [[技术方案]]。\n第二行说明。\n<!-- /pata:activity --> 包含定界符文本",
		},
		{
			ID:   "a-01jtest2",
			At:   atTime.Add(1 * time.Hour),
			Body: "简单的单行无标签活动",
		},
	}

	formatted, err := FormatActivities(original)
	if err != nil {
		t.Fatalf("FormatActivities failed: %v", err)
	}

	parsed, err := ParseActivities(formatted)
	if err != nil {
		t.Fatalf("ParseActivities failed: %v\nFormatted content:\n%s", err, formatted)
	}

	if len(parsed) != len(original) {
		t.Fatalf("expected %d activities, got %d", len(original), len(parsed))
	}

	for i := range original {
		if parsed[i].ID != original[i].ID {
			t.Errorf("[%d] ID mismatch: got %q, want %q", i, parsed[i].ID, original[i].ID)
		}
		if !parsed[i].At.Equal(original[i].At) {
			t.Errorf("[%d] At mismatch: got %v, want %v", i, parsed[i].At, original[i].At)
		}
		if len(parsed[i].Tags) != len(original[i].Tags) {
			t.Errorf("[%d] Tags mismatch: got %v, want %v", i, parsed[i].Tags, original[i].Tags)
		}
		if len(parsed[i].NoteRefs) != len(original[i].NoteRefs) {
			t.Errorf("[%d] NoteRefs mismatch: got %v, want %v", i, parsed[i].NoteRefs, original[i].NoteRefs)
		}
		if parsed[i].Body != original[i].Body {
			t.Errorf("[%d] Body mismatch:\ngot:  %q\nwant: %q", i, parsed[i].Body, original[i].Body)
		}
	}
}

func TestActivityMarkerRoundTrip(t *testing.T) {
	for _, marker := range []string{activityStartTag, activityEndTag} {
		for _, prefix := range []string{"", "  ", "\t", `\`, `\\`, "\\  ", "  \\  "} {
			body := prefix + marker + "  "
			for pass := 0; pass < 2; pass++ {
				formatted, err := FormatActivities([]Activity{{ID: "a-marker", At: time.Now(), Body: body}})
				if err != nil {
					t.Fatal(err)
				}
				parsed, err := ParseActivities(formatted)
				if err != nil {
					t.Fatal(err)
				}
				if len(parsed) != 1 || parsed[0].Body != body {
					t.Fatalf("pass %d: %q did not round-trip: %+v", pass, body, parsed)
				}
				body = parsed[0].Body
			}
		}
	}
}

func TestActivityParse_ErrorCases(t *testing.T) {
	tests := []struct {
		name    string
		input   string
		wantErr string
	}{
		{
			name:    "nested start tag",
			input:   "<!-- pata:activity\nid: a-1\nat: 2026-10-15T10:00:00Z\n-->\n<!-- pata:activity\nid: a-2\nat: 2026-10-15T11:00:00Z\n-->\n<!-- /pata:activity -->\n<!-- /pata:activity -->",
			wantErr: "nested activity start tag",
		},
		{
			name:    "unclosed block",
			input:   "<!-- pata:activity\nid: a-1\nat: 2026-10-15T10:00:00Z\n-->\nsome body without closing tag",
			wantErr: "unclosed activity block",
		},
		{
			name:    "missing id",
			input:   "<!-- pata:activity\nat: 2026-10-15T10:00:00Z\n-->\nbody\n<!-- /pata:activity -->",
			wantErr: "missing required 'id'",
		},
		{
			name:    "invalid id prefix",
			input:   "<!-- pata:activity\nid: t-123\nat: 2026-10-15T10:00:00Z\n-->\nbody\n<!-- /pata:activity -->",
			wantErr: "must start with 'a-'",
		},
		{
			name:    "missing timestamp at",
			input:   "<!-- pata:activity\nid: a-123\n-->\nbody\n<!-- /pata:activity -->",
			wantErr: "missing required valid timestamp 'at'",
		},
		{
			name:    "duplicate id in same file",
			input:   "<!-- pata:activity\nid: a-dup\nat: 2026-10-15T10:00:00Z\n-->\nfirst\n<!-- /pata:activity -->\n\n<!-- pata:activity\nid: a-dup\nat: 2026-10-15T11:00:00Z\n-->\nsecond\n<!-- /pata:activity -->",
			wantErr: "duplicate activity id 'a-dup'",
		},
		{
			name:    "illegal content outside blocks",
			input:   "some stray text outside\n<!-- pata:activity\nid: a-1\nat: 2026-10-15T10:00:00Z\n-->\nbody\n<!-- /pata:activity -->",
			wantErr: "unexpected content outside activity block",
		},
		{
			name:    "tag contains hash symbol",
			input:   "<!-- pata:activity\nid: a-1\nat: 2026-10-15T10:00:00Z\ntags: ['#设计']\n-->\nbody\n<!-- /pata:activity -->",
			wantErr: "must not contain '#'",
		},
		{
			name:    "invalid yaml in metadata",
			input:   "<!-- pata:activity\n[invalid: yaml:\n-->\nbody\n<!-- /pata:activity -->",
			wantErr: "invalid YAML in activity metadata",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			_, err := ParseActivities(tt.input)
			if err == nil {
				t.Fatalf("expected error containing %q, got nil", tt.wantErr)
			}
			if !strings.Contains(err.Error(), tt.wantErr) {
				t.Fatalf("error %q does not contain %q", err.Error(), tt.wantErr)
			}
		})
	}
}

func TestTaskAndDayPlan_ActivitiesIndexAndVault(t *testing.T) {
	tmpDir := t.TempDir()
	vault, err := NewVault(tmpDir)
	if err != nil {
		t.Fatalf("NewVault failed: %v", err)
	}

	now := time.Now()
	// 1. Create a Note
	note := &Note{
		Type:      EntityTypeNote,
		ID:        "n-doc-1",
		Title:     "设计文档",
		Tags:      []string{"设计"},
		CreatedAt: now,
		UpdatedAt: now,
		Body:      "# 设计文档\n这是正文内容",
	}
	if _, err := vault.SaveEntity(note, nil); err != nil {
		t.Fatalf("SaveEntity(note) failed: %v", err)
	}

	// 2. Create a Task with description and embedded activities
	task := &Task{
		Type:        EntityTypeTask,
		ID:          "t-task-1",
		Title:       "开发重构模块",
		Description: "重构任务描述，参考 [[设计文档]]",
		Status:      TaskStatusTodo,
		Tags:        []string{"重构"},
		NoteRefs:    map[string]string{"设计文档": "n-doc-1"},
		CreatedAt:   now,
		UpdatedAt:   now,
		Activities: []Activity{
			{
				ID:       "a-act-1",
				At:       now.Add(-1 * time.Hour),
				Tags:     []string{"底层"},
				NoteRefs: map[string]string{"设计文档": "n-doc-1"},
				Body:     "完成解析器编码，参见 [[设计文档]]",
			},
		},
	}
	if _, err := vault.SaveEntity(task, nil); err != nil {
		t.Fatalf("SaveEntity(task) failed: %v", err)
	}

	// 3. Create a DayPlan with embedded independent activity
	plan := &DayPlan{
		Type:    EntityTypeDayPlan,
		Date:    now.Format("2006-01-02"),
		TaskIDs: []string{task.ID},
		Activities: []Activity{
			{
				ID:   "a-act-2",
				At:   now.Add(-30 * time.Minute),
				Tags: []string{"日常"},
				Body: "今日独立记录：开会讨论了架构方案",
			},
		},
	}
	if _, err := vault.SaveEntity(plan, nil); err != nil {
		t.Fatalf("SaveEntity(plan) failed: %v", err)
	}

	// Verify ActivityLocation indexing
	act1, loc1, ok1 := vault.Index.GetActivity("a-act-1")
	if !ok1 || loc1.OwnerType != EntityTypeTask || loc1.OwnerID != task.ID {
		t.Fatalf("GetActivity(a-act-1) failed: ok=%v, loc=%+v", ok1, loc1)
	}
	if act1.Body != "完成解析器编码，参见 [[设计文档]]" {
		t.Errorf("act1 body mismatch: %q", act1.Body)
	}

	act2, loc2, ok2 := vault.Index.GetActivity("a-act-2")
	if !ok2 || loc2.OwnerType != EntityTypeDayPlan || loc2.OwnerID != plan.Date {
		t.Fatalf("GetActivity(a-act-2) failed: ok=%v, loc=%+v", ok2, loc2)
	}
	if act2.Body != "今日独立记录：开会讨论了架构方案" {
		t.Errorf("act2 body mismatch: %q", act2.Body)
	}

	// Verify ListActivitiesByTask
	taskActs := vault.Index.ListActivitiesByTask(task.ID)
	if len(taskActs) != 1 || taskActs[0].ID != "a-act-1" {
		t.Fatalf("ListActivitiesByTask failed: %+v", taskActs)
	}

	// Verify ListActivitiesByDayPlan
	planActs := vault.Index.ListActivitiesByDayPlan(plan.Date)
	if len(planActs) != 1 || planActs[0].ID != "a-act-2" {
		t.Fatalf("ListActivitiesByDayPlan failed: %+v", planActs)
	}

	// Verify Tag inheritance:
	// Task has tag "重构". Act1 has tag "底层".
	// Finding by "重构" should match Task AND Act1 (inherited).
	reconstructRefs := vault.Index.FindByTag("重构")
	hasInheritedAct := false
	for _, ref := range reconstructRefs {
		if ref.Type == EntityTypeActivity && ref.ID == "a-act-1" && ref.Inherited {
			hasInheritedAct = true
		}
	}
	if !hasInheritedAct {
		t.Errorf("expected activity a-act-1 to inherit tag '重构' from parent task, got %+v", reconstructRefs)
	}

	// Finding by "底层" matches Act1 (own match, not inherited).
	baseRefs := vault.Index.FindByTag("底层")
	if len(baseRefs) != 1 || baseRefs[0].Type != EntityTypeActivity || baseRefs[0].Inherited {
		t.Errorf("expected activity a-act-1 to match own tag '底层', got %+v", baseRefs)
	}

	// Verify TagOverview aggregates own tags
	overview := vault.Index.TagOverview()
	foundBaseTag := false
	for _, item := range overview {
		if item.Tag == "底层" {
			foundBaseTag = true
			if item.ActivityCount < 1 {
				t.Errorf("expected TagOverview for '底层' to have activity count >= 1, got %+v", item)
			}
		}
	}
	if !foundBaseTag {
		t.Errorf("expected '底层' tag in TagOverview: %+v", overview)
	}

	// Verify Backlinks: Note "n-doc-1" should be referenced by Task "t-task-1"
	backlinks := vault.Index.Backlinks("n-doc-1", vault.RootPath)
	if len(backlinks) != 1 || backlinks[0].ID != task.ID {
		t.Fatalf("expected backlinks for n-doc-1 to contain task t-task-1, got %+v", backlinks)
	}

	// Verify SearchAll matches Task description and Activity body
	searchDesc := vault.Index.SearchAll("重构任务描述")
	if len(searchDesc) == 0 || searchDesc[0].Type != EntityTypeTask {
		t.Fatalf("SearchAll failed to match Task description: %+v", searchDesc)
	}

	searchAct := vault.Index.SearchAll("解析器编码")
	foundActSearch := false
	for _, item := range searchAct {
		if item.Type == EntityTypeActivity && item.ID == "a-act-1" {
			foundActSearch = true
		}
	}
	if !foundActSearch {
		t.Fatalf("SearchAll failed to match Activity body: %+v", searchAct)
	}

	// Verify Rescan from disk preserves everything
	if err := vault.Scan(); err != nil {
		t.Fatalf("vault.Scan failed: %v", err)
	}
	if _, _, ok := vault.Index.GetActivity("a-act-1"); !ok {
		t.Fatalf("GetActivity after rescan failed")
	}
	if _, _, ok := vault.Index.GetActivity("a-act-2"); !ok {
		t.Fatalf("GetActivity after rescan failed")
	}
}

func TestActivity_DuplicateIDAcrossFilesIsolated(t *testing.T) {
	tmpDir := t.TempDir()
	tasksDir := filepath.Join(tmpDir, "tasks")
	if err := os.MkdirAll(tasksDir, 0755); err != nil {
		t.Fatal(err)
	}

	task1Content := `---
type: task
id: t-1
title: Task 1
status: todo
created_at: 2026-10-15T10:00:00Z
updated_at: 2026-10-15T10:00:00Z
---

<!-- pata:activity
id: a-dup-1
at: 2026-10-15T10:30:00Z
-->
First activity
<!-- /pata:activity -->
`
	task2Content := `---
type: task
id: t-2
title: Task 2
status: todo
created_at: 2026-10-15T10:00:00Z
updated_at: 2026-10-15T10:00:00Z
---

<!-- pata:activity
id: a-dup-1
at: 2026-10-15T10:30:00Z
-->
Duplicate activity in another task!
<!-- /pata:activity -->
`
	if err := os.WriteFile(filepath.Join(tasksDir, "t1.md"), []byte(task1Content), 0644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(tasksDir, "t2.md"), []byte(task2Content), 0644); err != nil {
		t.Fatal(err)
	}

	idx, err := ScanVault(tmpDir)
	if err != nil {
		t.Fatalf("ScanVault failed: %v", err)
	}

	if len(idx.ListParseErrors()) == 0 {
		t.Fatalf("expected duplicate activity collision parse error, got 0")
	}

	hasDupErr := false
	for _, pe := range idx.ListParseErrors() {
		if strings.Contains(pe.Reason, "duplicate activity ID collision 'a-dup-1'") {
			hasDupErr = true
		}
	}
	if !hasDupErr {
		t.Fatalf("expected duplicate activity collision error, got: %+v", idx.ListParseErrors())
	}
}

func TestDayPlan_RootPlansSupersedesLegacyPataPlans(t *testing.T) {
	tmpDir := t.TempDir()

	legacyDir := filepath.Join(tmpDir, ".pata", "plans")
	if err := os.MkdirAll(legacyDir, 0755); err != nil {
		t.Fatal(err)
	}
	rootDir := filepath.Join(tmpDir, "plans")
	if err := os.MkdirAll(rootDir, 0755); err != nil {
		t.Fatal(err)
	}

	date := "2026-10-15"
	legacyContent := `---
type: day_plan
date: 2026-10-15
task_ids: []
created_at: 2026-10-15T08:00:00Z
updated_at: 2026-10-15T08:00:00Z
---

<!-- pata:activity
id: a-legacy
at: 2026-10-15T08:30:00Z
-->
Legacy plan activity
<!-- /pata:activity -->
`
	rootContent := `---
type: day_plan
date: 2026-10-15
task_ids: []
created_at: 2026-10-15T09:00:00Z
updated_at: 2026-10-15T09:00:00Z
---

<!-- pata:activity
id: a-root
at: 2026-10-15T09:30:00Z
-->
Root plan activity
<!-- /pata:activity -->
`

	if err := os.WriteFile(filepath.Join(legacyDir, date+".md"), []byte(legacyContent), 0644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(rootDir, date+".md"), []byte(rootContent), 0644); err != nil {
		t.Fatal(err)
	}

	idx, err := ScanVault(tmpDir)
	if err != nil {
		t.Fatalf("ScanVault failed: %v", err)
	}

	// Should not report duplicate ID error for day_plan
	for _, pe := range idx.ListParseErrors() {
		if strings.Contains(pe.Reason, date) {
			t.Fatalf("unexpected parse error for date %s: %v", date, pe)
		}
	}

	dp, ok := idx.GetDayPlan(date)
	if !ok {
		t.Fatalf("expected day plan %s to exist in index", date)
	}
	if len(dp.Activities) != 1 || dp.Activities[0].ID != "a-root" {
		t.Fatalf("expected root plan activity 'a-root', got %+v", dp.Activities)
	}

	if _, _, ok := idx.GetActivity("a-root"); !ok {
		t.Fatalf("expected activity 'a-root' to be indexed")
	}
	if _, _, ok := idx.GetActivity("a-legacy"); ok {
		t.Fatalf("expected activity 'a-legacy' to NOT be indexed")
	}
}

func TestActivity_DeleteFinalActivityClearsFileBody(t *testing.T) {
	tmpDir := t.TempDir()
	vault, err := NewVault(tmpDir)
	if err != nil {
		t.Fatalf("NewVault failed: %v", err)
	}

	// 1. Task host
	task := &Task{
		Type:      EntityTypeTask,
		ID:        "t-clear-test",
		Title:     "任务活动清除测试",
		Status:    TaskStatusTodo,
		CreatedAt: time.Now(),
		UpdatedAt: time.Now(),
		Activities: []Activity{
			{
				ID:   "a-single-1",
				At:   time.Now().UTC(),
				Body: "唯一的活动",
			},
		},
	}
	rev, err := vault.SaveEntity(task, nil)
	if err != nil {
		t.Fatalf("SaveEntity task failed: %v", err)
	}

	taskPath := vault.ResolveEntityPath(task)
	contentBefore, err := os.ReadFile(taskPath)
	if err != nil || !strings.Contains(string(contentBefore), "<!-- pata:activity") {
		t.Fatalf("expected activity block in file, got: %s", string(contentBefore))
	}

	// Delete final activity
	task.Activities = []Activity{}
	_, err = vault.SaveEntity(task, rev)
	if err != nil {
		t.Fatalf("SaveEntity without activities failed: %v", err)
	}

	contentAfter, err := os.ReadFile(taskPath)
	if err != nil {
		t.Fatalf("ReadFile failed: %v", err)
	}
	if strings.Contains(string(contentAfter), "<!-- pata:activity") {
		t.Fatalf("expected activity blocks to be cleared from disk, but found: %s", string(contentAfter))
	}

	// Re-parse from disk
	reparsed, err := ParseMarkdown(taskPath, contentAfter)
	if err != nil {
		t.Fatalf("ParseMarkdown failed: %v", err)
	}
	if len(reparsed.(*Task).Activities) != 0 {
		t.Fatalf("expected 0 activities after deletion, got %d", len(reparsed.(*Task).Activities))
	}
}
