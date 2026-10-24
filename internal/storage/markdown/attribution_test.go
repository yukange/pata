package markdown

import (
	"bytes"
	"encoding/json"
	"reflect"
	"strings"
	"testing"
	"time"
)

func TestAttributionRoundTripAndClone(t *testing.T) {
	for _, by := range []string{"", SourceAgent} {
		t.Run("source="+by, func(t *testing.T) {
			now := time.Date(2026, 10, 23, 9, 20, 0, 0, time.FixedZone("CST", 8*3600))
			activity := Activity{ID: "a-source", At: now, By: by, Body: "评论", NoteRefs: map[string]string{"引用": "n-source"}}
			entities := []Entity{
				&Task{Type: EntityTypeTask, ID: "t-source", Title: "任务", Status: TaskStatusTodo, CreatedAt: now, UpdatedAt: now, CreatedBy: by,
					StatusEvents: []StatusEvent{{Action: StatusEventActionCompleted, At: now, By: by}, {Action: StatusEventActionReopened, At: now}},
					Activities:   []Activity{activity}},
				&Note{Type: EntityTypeNote, ID: "n-source", Title: "笔记", CreatedAt: now, UpdatedAt: now, CreatedBy: by, Body: "正文\n"},
				&DayPlan{Type: EntityTypeDayPlan, Date: "2026-10-23", TaskIDs: []string{"t-source"}, Activities: []Activity{activity}},
			}
			for _, entity := range entities {
				raw, err := SerializeMarkdown(entity.Clone())
				if err != nil {
					t.Fatal(err)
				}
				if by == "" && (bytes.Contains(raw, []byte("created_by:")) || bytes.Contains(raw, []byte("by:"))) {
					t.Fatalf("default source must stay omitted: %s", raw)
				}
				parsed, err := ParseMarkdown("source.md", raw)
				if err != nil {
					t.Fatal(err)
				}
				reencoded, err := SerializeMarkdown(parsed.Clone())
				if err != nil || !bytes.Equal(raw, reencoded) {
					t.Fatalf("round trip changed metadata: %s, %v", reencoded, err)
				}
				parsedJSON, _ := json.Marshal(parsed)
				// Serialization also derives the host body; compare against that canonical representation.
				canonical := entity.Clone()
				_, _ = SerializeMarkdown(canonical)
				originalJSON, _ := json.Marshal(canonical)
				if !bytes.Equal(originalJSON, parsedJSON) {
					t.Fatalf("JSON lost source: %s != %s", originalJSON, parsedJSON)
				}
				if !reflect.DeepEqual(parsed, parsed.Clone()) {
					t.Fatal("clone lost metadata")
				}
			}
		})
	}
}

func TestAttributionDoesNotChangeSearch(t *testing.T) {
	v, err := NewVault(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	at := time.Date(2026, 10, 23, 9, 0, 0, 0, time.UTC)
	task := &Task{
		Type: EntityTypeTask, ID: "t-search", Title: "任务", Status: TaskStatusDone,
		CreatedAt: at, UpdatedAt: at, CompletedAt: &at,
		StatusEvents: []StatusEvent{{Action: StatusEventActionCompleted, At: at}},
		Activities:   []Activity{{ID: "a-search", At: at, Body: "修复已完成", Tags: []string{"排查"}}},
	}
	var before []SearchResultItem
	for _, by := range []string{"", SourceAgent} {
		task.CreatedBy = by
		task.StatusEvents[0].By = by
		task.Activities[0].By = by
		path := v.ResolveEntityPath(task)
		var baseline *FileBaseline
		if b, ok := v.Index.GetBaseline(path); ok {
			baseline = &b
		}
		if _, err := v.SaveEntity(task, baseline); err != nil {
			t.Fatal(err)
		}
		if err := v.Scan(); err != nil {
			t.Fatal(err)
		}
		for _, query := range []string{"agent", "by:", "pata:activity", "a-search"} {
			if results := v.Index.SearchAll(query); len(results) != 0 {
				t.Fatalf("source=%q: metadata matched %q: %+v", by, query, results)
			}
		}
		for _, query := range []string{"修复", "排查"} {
			results := v.Index.SearchAll(query)
			if len(results) != 2 || results[0].Type != EntityTypeTask || results[1].Type != EntityTypeActivity {
				t.Fatalf("source=%q: visible content %q not found: %+v", by, query, results)
			}
		}
		results := v.Index.SearchAll("修复")
		if results[0].Snippet != "修复已完成" || results[1].Snippet != "修复已完成" {
			t.Fatalf("metadata leaked into snippets: %+v", results)
		}
		if by == "" {
			before = results
		} else if !reflect.DeepEqual(before, results) {
			t.Fatalf("attribution changed search: %+v != %+v", before, results)
		}
	}

	// The same word must still match when the user writes it in visible content.
	task.Activities[0].Body = "agent 修复已完成"
	baseline, ok := v.Index.GetBaseline(v.ResolveEntityPath(task))
	if !ok {
		t.Fatal("missing baseline")
	}
	if _, err := v.SaveEntity(task, &baseline); err != nil {
		t.Fatal(err)
	}
	if results := v.Index.SearchAll("agent"); len(results) != 2 || results[0].Snippet != "agent 修复已完成" {
		t.Fatalf("visible agent text must remain searchable: %+v", results)
	}
}

func TestAttributionRejectsUnsupportedSources(t *testing.T) {
	for _, fixture := range []string{
		"type: task\nid: t-1\ntitle: Task\nstatus: todo\ncreated_by: human\n",
		"type: note\nid: n-1\ntitle: Note\ncreated_by: unknown\n",
		"type: task\nid: t-1\ntitle: Task\nstatus: todo\nstatus_events:\n  - action: completed\n    at: 2026-10-23T10:00:00Z\n    by: app\n",
	} {
		raw := "---\n" + fixture + "created_at: 2026-10-23T09:00:00Z\nupdated_at: 2026-10-23T10:00:00Z\n---\n"
		if _, err := ParseMarkdown("source.md", []byte(raw)); err == nil || !strings.Contains(err.Error(), "agent") {
			t.Fatalf("unsupported source accepted or unexplained: %v", err)
		}
	}
	if _, err := ParseActivities("<!-- pata:activity\nid: a-1\nat: 2026-10-23T10:00:00Z\nby: human\n-->\ncomment\n<!-- /pata:activity -->\n"); err == nil {
		t.Fatal("unsupported activity source accepted")
	}
	if err := ValidateEntity("plan.md", &DayPlan{Type: EntityTypeDayPlan, Date: "2026-10-23", Activities: []Activity{{ID: "a-1", At: time.Now(), By: "human"}}}); err == nil {
		t.Fatal("unsupported activity source accepted on write")
	}
}
