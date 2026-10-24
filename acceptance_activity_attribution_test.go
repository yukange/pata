package main

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
	"time"

	"github.com/modelcontextprotocol/go-sdk/mcp"
	"pata/internal/storage/markdown"
)

// TestAcceptance_ActivityAttribution_MCPAndTaskLifecycle validates the full lifecycle
// of Agent attribution and task status transitions across MCP and GUI operations.
func TestAcceptance_ActivityAttribution_MCPAndTaskLifecycle(t *testing.T) {
	v, err := markdown.NewVault(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	events := make(chan VaultChangeEvent, 32)
	s := &VaultService{vault: v, emitEvent: func(name string, data any) {
		if name == EventVaultChanged {
			events <- data.(VaultChangeEvent)
		}
	}}
	rt := &mcpRuntime{active: true, vault: v}
	server := newPataMCPServer(s, rt)
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	st, ct := mcp.NewInMemoryTransports()
	ss, err := server.Connect(ctx, st, nil)
	if err != nil {
		t.Fatal(err)
	}
	defer ss.Close()
	cs, err := mcp.NewClient(&mcp.Implementation{Name: "test", Version: "1"}, nil).Connect(ctx, ct, nil)
	if err != nil {
		t.Fatal(err)
	}
	defer cs.Close()
	call := func(name string, args any, out any) {
		t.Helper()
		result, err := cs.CallTool(ctx, &mcp.CallToolParams{Name: name, Arguments: args})
		if err != nil || result.IsError {
			t.Fatalf("%s failed: %+v, %v", name, result, err)
		}
		var envelope struct {
			Data json.RawMessage `json:"data"`
		}
		if err := json.Unmarshal([]byte(result.Content[0].(*mcp.TextContent).Text), &envelope); err != nil {
			t.Fatal(err)
		}
		if err := json.Unmarshal(envelope.Data, out); err != nil {
			t.Fatal(err)
		}
	}

	// 1. Agent creates task directly in done state: must record Agent creation and completion
	var task markdown.Task
	call("pata_create_task", map[string]any{"title": "Agent task", "status": "done"}, &task)
	if task.CreatedBy != markdown.SourceAgent || len(task.StatusEvents) != 1 || task.StatusEvents[0].By != markdown.SourceAgent {
		t.Fatalf("initial done must retain both Agent facts: %+v", task)
	}
	today := task.CreatedAt.In(time.Local).Format("2006-01-02")
	initialTimeline, err := s.GetDayTimeline(today)
	if err != nil || len(initialTimeline) != 2 || initialTimeline[0].Kind != "completion" || initialTimeline[1].Kind != "creation" || initialTimeline[0].By != markdown.SourceAgent || initialTimeline[1].By != markdown.SourceAgent {
		t.Fatalf("initial done must display both Agent events: %+v, %v", initialTimeline, err)
	}
	if len(task.Activities) != 0 {
		t.Fatal("creation must not write an ordinary activity")
	}
	if event := <-events; event.Op != "create" || event.EntityID != task.ID {
		t.Fatalf("unexpected create notification: %+v", event)
	}

	// 2. Repeating task status via MCP: idempotent, must not rewrite or append status events
	before, _ := os.ReadFile(v.ResolveEntityPath(&task))
	call("pata_set_task_status", map[string]any{"id": task.ID, "status": "done"}, &task)
	after, _ := os.ReadFile(v.ResolveEntityPath(&task))
	if len(task.StatusEvents) != 1 || !reflect.DeepEqual(before, after) {
		t.Fatal("repeating status rewrote task or added an event")
	}
	if event := <-events; event.Op != "update" || event.Type != "task" || event.EntityID != task.ID {
		t.Fatalf("unexpected status notification: %+v", event)
	}

	// 3. GUI update: status transition records event without 'by' attribute (defaults to 'me')
	gui, err := s.UpdateTask(UpdateTaskInput{ID: task.ID, Title: "Renamed", Status: markdown.TaskStatusTodo})
	if err != nil || gui.StatusEvents[1].By != "" || gui.CompletedAt != nil {
		t.Fatalf("GUI update source: %+v, %v", gui, err)
	}
	if _, err := s.SetTaskStatus(task.ID, markdown.TaskStatusDone); err != nil {
		t.Fatal(err)
	}

	// 4. MCP reopens task: records reopened with 'by: agent'
	var reopened markdown.Task
	call("pata_set_task_status", map[string]any{"id": task.ID, "status": "todo"}, &reopened)
	task = reopened
	if task.CreatedBy != markdown.SourceAgent || task.CompletedAt != nil || len(task.StatusEvents) != 4 || task.StatusEvents[2].By != "" || task.StatusEvents[3].By != markdown.SourceAgent {
		t.Fatalf("mixed source history: %+v", task)
	}

	// 5. MCP creates Note and Activities: proper attribution preserved across edits and rescans
	var note markdown.Note
	call("pata_create_note", map[string]any{"title": "Agent note", "body": "original"}, &note)
	if note.CreatedBy != markdown.SourceAgent {
		t.Fatalf("note source missing: %+v", note)
	}
	if _, err := s.UpdateNote(UpdateNoteInput{ID: note.ID, Title: "Edited", Body: "GUI edit"}); err != nil {
		t.Fatal(err)
	}
	for _, args := range []map[string]any{
		{"task_id": task.ID, "body": "Task comment"},
		{"date": "2026-10-22", "body": "Day comment"},
	} {
		var act markdown.Activity
		call("pata_append_activity", args, &act)
		if act.By != markdown.SourceAgent {
			t.Fatalf("activity source missing: %+v", act)
		}
		if _, err := s.UpdateActivity(UpdateActivityInput{ID: act.ID, Body: "GUI edit"}); err != nil {
			t.Fatal(err)
		}
		if err := s.RescanVault(); err != nil {
			t.Fatal(err)
		}
		reloaded, err := s.GetActivity(act.ID)
		if err != nil || reloaded.By != markdown.SourceAgent || reloaded.Body != "GUI edit" {
			t.Fatalf("activity edit/rescan changed source: %+v, %v", reloaded, err)
		}
	}
	reloadedNote, err := s.GetNote(note.ID)
	if err != nil || reloadedNote.CreatedBy != markdown.SourceAgent || reloadedNote.Body != "GUI edit\n" {
		t.Fatalf("note edit/rescan changed source: %+v, %v", reloadedNote, err)
	}
	reloadedTask, err := s.GetTask(task.ID)
	if err != nil || reloadedTask.CreatedBy != markdown.SourceAgent || !reflect.DeepEqual(task.StatusEvents, reloadedTask.StatusEvents) {
		t.Fatalf("task edit/rescan changed source: %+v, %v", reloadedTask, err)
	}

	// 6. Public GUI inputs cannot forge attribution; on-disk data stays sparse
	guiTask, err := s.CreateTask(CreateTaskInput{Title: "GUI", Status: markdown.TaskStatusDone})
	if err != nil {
		t.Fatal(err)
	}
	guiNote, err := s.CreateNote(CreateNoteInput{Title: "GUI"})
	if err != nil {
		t.Fatal(err)
	}
	for _, args := range []CreateActivityInput{{TaskID: guiTask.ID, Body: "GUI"}, {Date: "2026-10-22", Body: "GUI"}} {
		act, err := s.CreateActivity(args)
		if err != nil || act.By != "" {
			t.Fatalf("GUI activity: %+v, %v", act, err)
		}
	}
	for _, entity := range []markdown.Entity{guiTask, guiNote} {
		data, err := os.ReadFile(v.ResolveEntityPath(entity))
		if err != nil || strings.Contains(string(data), "by:") {
			t.Fatalf("GUI data must omit source: %s, %v", data, err)
		}
	}

	// 7. MCP input validation and forged attribution rejection
	for _, args := range []map[string]any{
		{"id": task.ID, "status": "doing"}, {"id": task.ID, "status": "invalid"},
		{"id": "", "status": "done"}, {"id": "t-missing", "status": "done"},
		{"id": task.ID}, {"id": task.ID, "status": "done", "by": "human"},
	} {
		result, err := cs.CallTool(ctx, &mcp.CallToolParams{Name: "pata_set_task_status", Arguments: args})
		if err == nil && !result.IsError {
			t.Fatalf("invalid status request accepted: %+v", args)
		}
	}
	for _, tc := range []struct {
		name string
		args map[string]any
	}{
		{"pata_create_task", map[string]any{"title": "Forged", "created_by": "human"}},
		{"pata_create_note", map[string]any{"title": "Forged", "created_by": "human"}},
		{"pata_append_activity", map[string]any{"body": "Forged", "by": "human"}},
	} {
		result, err := cs.CallTool(ctx, &mcp.CallToolParams{Name: tc.name, Arguments: tc.args})
		if err == nil && !result.IsError {
			t.Fatalf("caller-supplied source accepted: %s", tc.name)
		}
	}

	// 8. Vault switch guards apply to status tool
	s.mu.Lock()
	s.vault = nil
	s.mu.Unlock()
	result, err := cs.CallTool(ctx, &mcp.CallToolParams{Name: "pata_set_task_status", Arguments: map[string]any{"id": task.ID, "status": "done"}})
	if err == nil && !result.IsError {
		t.Fatal("status write accepted after vault switch")
	}
}

// TestAcceptance_ActivityAttribution_DayTimelineStableOrdering verifies DayTimeline
// creation attribution, cross-midnight display, stable sorting, and legacy data fallback.
func TestAcceptance_ActivityAttribution_DayTimelineStableOrdering(t *testing.T) {
	v, err := markdown.NewVault(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	s := &VaultService{vault: v}
	at := time.Date(2026, 10, 23, 0, 10, 0, 0, time.Local)
	task := &markdown.Task{
		Type: markdown.EntityTypeTask, ID: "t-timeline", Title: "Unplanned", Status: markdown.TaskStatusDone,
		CreatedAt: at.Add(-20 * time.Minute), CreatedBy: markdown.SourceAgent, UpdatedAt: at, CompletedAt: &at,
		StatusEvents: []markdown.StatusEvent{
			{Action: markdown.StatusEventActionCompleted, At: at, By: markdown.SourceAgent},
			{Action: markdown.StatusEventActionReopened, At: at},
			{Action: markdown.StatusEventActionCompleted, At: at, By: markdown.SourceAgent},
		},
		Activities: []markdown.Activity{{ID: "a-timeline", At: at, By: markdown.SourceAgent, Body: "comment"}},
	}
	if _, err := v.SaveEntity(task, nil); err != nil {
		t.Fatal(err)
	}

	// Unplanned task creation still shows on created date across midnight
	previous, err := s.GetDayTimeline("2026-10-22")
	if err != nil || len(previous) != 1 || previous[0].Kind != "creation" || previous[0].By != markdown.SourceAgent || previous[0].TaskID != task.ID {
		t.Fatalf("unplanned creation missing across midnight: %+v, %v", previous, err)
	}

	// Identical timestamp ordering: activity, completion, reopen
	items, err := s.GetDayTimeline("2026-10-23")
	if err != nil || len(items) != 4 || items[0].Kind != "activity" || items[0].Activity.By != markdown.SourceAgent || items[1].Kind != "completion" || items[2].Kind != "reopen" || items[2].By != "" {
		t.Fatalf("same timestamp history order/source: %+v, %v", items, err)
	}
	again, err := s.GetDayTimeline("2026-10-23")
	if err != nil || !reflect.DeepEqual(items, again) {
		t.Fatal("unstable timeline")
	}

	// Old completed_at-only history defaults to me, even for an Agent-created task
	task.StatusEvents = []markdown.StatusEvent{{Action: markdown.StatusEventActionCompleted, At: at.Add(-time.Hour), By: markdown.SourceAgent}}
	task.Activities = nil
	if _, err := v.SaveEntity(task, taskBaseline(v, task)); err != nil {
		t.Fatal(err)
	}
	items, err = s.GetDayTimeline("2026-10-23")
	if err != nil || len(items) != 1 || items[0].By != "" || items[0].Kind != "completion" {
		t.Fatalf("legacy completion fallback: %+v, %v", items, err)
	}
}

// Legacy Markdown intentionally omits every attribution field.
func TestAcceptance_ActivityAttribution_LegacyVaultCompatibility(t *testing.T) {
	root := t.TempDir()
	fixtures := map[string]string{
		"tasks/legacy.md": `---
type: task
id: t-legacy
title: Legacy task
status: done
created_at: 2026-10-23T09:00:00+08:00
updated_at: 2026-10-23T10:00:00+08:00
completed_at: 2026-10-23T10:00:00+08:00
status_events:
  - action: completed
    at: 2026-10-23T10:00:00+08:00
---
<!-- pata:activity
id: a-legacy-task
at: 2026-10-23T09:30:00+08:00
-->
Legacy task comment
<!-- /pata:activity -->
`,
		"notes/legacy.md": `---
type: note
id: n-legacy
title: Legacy note
created_at: 2026-10-23T09:00:00+08:00
updated_at: 2026-10-23T09:00:00+08:00
---
Legacy note body
`,
		"plans/2026-10-23.md": `---
type: day_plan
date: 2026-10-23
task_ids: [t-legacy]
---
<!-- pata:activity
id: a-legacy-day
at: 2026-10-23T11:00:00+08:00
-->
Legacy daily record
<!-- /pata:activity -->
`,
	}
	for name, body := range fixtures {
		path := filepath.Join(root, name)
		if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, []byte(body), 0644); err != nil {
			t.Fatal(err)
		}
	}
	v, err := markdown.NewVault(root)
	if err != nil {
		t.Fatal(err)
	}
	svc := &VaultService{vault: v}

	// 1. Health inspection: zero parse errors, zero dangling references
	health, err := svc.GetVaultHealth()
	if err != nil {
		t.Fatalf("GetVaultHealth failed: %v", err)
	}
	if len(health.ParseErrors) > 0 || len(health.DanglingRefs) > 0 {
		t.Fatalf("legacy fixtures have health errors: %+v", health)
	}

	// 2. Tasks verification: all legacy tasks must have empty CreatedBy and empty StatusEvents[].By
	tasks := v.Index.ListTasks()
	if len(tasks) != 1 || len(tasks[0].StatusEvents) != 1 || len(tasks[0].Activities) != 1 {
		t.Fatalf("legacy task fixture not fully loaded: %+v", tasks)
	}
	for _, task := range tasks {
		if task.CreatedBy != "" {
			t.Errorf("legacy task %s has unexpected CreatedBy: %q", task.ID, task.CreatedBy)
		}
		for idx, ev := range task.StatusEvents {
			if ev.By != "" {
				t.Errorf("legacy task %s status event %d has unexpected By: %q", task.ID, idx, ev.By)
			}
		}
		for _, act := range task.Activities {
			if act.By != "" {
				t.Errorf("legacy task %s activity %s has unexpected By: %q", task.ID, act.ID, act.By)
			}
		}
	}

	// 3. Notes verification: all legacy notes must have empty CreatedBy
	notes := v.Index.ListNotes()
	if len(notes) != 1 {
		t.Fatalf("legacy note fixture not loaded: %+v", notes)
	}
	for _, note := range notes {
		if note.CreatedBy != "" {
			t.Errorf("legacy note %s has unexpected CreatedBy: %q", note.ID, note.CreatedBy)
		}
	}

	// 4. DayPlans verification: legacy timeline aggregation must run cleanly
	dayPlans := v.Index.ListDayPlans()
	if len(dayPlans) != 1 || len(dayPlans[0].Activities) != 1 || dayPlans[0].Activities[0].By != "" {
		t.Fatalf("legacy day fixture not fully loaded: %+v", dayPlans)
	}
	for _, plan := range dayPlans {
		timeline, err := svc.GetDayTimeline(plan.Date)
		if err != nil {
			t.Fatalf("GetDayTimeline failed for date %s: %v", plan.Date, err)
		}
		for _, item := range timeline {
			if item.By != "" || (item.Activity != nil && item.Activity.By != "") {
				t.Errorf("date %s timeline item %s has unexpected By: %q", plan.Date, item.Key, item.By)
			}
		}
	}

	if err := svc.RescanVault(); err != nil {
		t.Fatal(err)
	}
	for name, body := range fixtures {
		raw, err := os.ReadFile(filepath.Join(root, name))
		if err != nil || string(raw) != body {
			t.Fatalf("reading/rescanning legacy fixture changed %s: %v", name, err)
		}
	}
}
