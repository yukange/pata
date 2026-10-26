package app

import (
	"testing"
	"time"

	"pata/internal/storage/markdown"
)

func TestTodayActivityNoteLinksPersistAndEdit(t *testing.T) {
	v, err := markdown.NewVault(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	s := &VaultService{vault: v}
	a, err := s.CreateNote(CreateNoteInput{Title: "同名笔记"})
	if err != nil {
		t.Fatal(err)
	}
	b, err := s.CreateNote(CreateNoteInput{Title: "同名笔记"})
	if err != nil {
		t.Fatal(err)
	}
	today := time.Now().In(time.Local).Format("2006-01-02")
	act, err := s.CreateActivity(CreateActivityInput{
		Date: today,
		Body: "今日记录 **纯文本**\n[[同名笔记]]", Tags: []string{"工作"},
		NoteRefs: map[string]string{"同名笔记": b.ID},
	})
	if err != nil {
		t.Fatal(err)
	}
	check := func(body string, refs map[string]string) {
		t.Helper()
		// 重建 Vault，而不只验证当前内存中的对象。
		reopened, err := markdown.NewVault(v.RootPath)
		if err != nil {
			t.Fatal(err)
		}
		timeline, err := (&VaultService{vault: reopened}).GetDayTimeline(today)
		if err != nil || len(timeline) != 1 || timeline[0].Activity == nil {
			t.Fatalf("timeline: %+v, %v", timeline, err)
		}
		got := timeline[0].Activity
		if got.Body != body || len(got.Tags) != 1 || got.Tags[0] != "工作" {
			t.Fatalf("activity content changed: %+v", got)
		}
		if len(got.NoteRefs) != len(refs) {
			t.Fatalf("bindings: %+v, want %+v", got.NoteRefs, refs)
		}
		for name, id := range refs {
			if got.NoteRefs[name] != id {
				t.Fatalf("wrong target: %+v", got.NoteRefs)
			}
		}
	}
	check(act.Body, map[string]string{"同名笔记": b.ID})

	// 行内编辑选择另一个同名目标，应保存新绑定，而非沿用旧目标。
	if _, err := s.UpdateActivity(UpdateActivityInput{
		ID: act.ID, Body: "改为 [[同名笔记]]", Tags: act.Tags,
		NoteRefs: map[string]string{"同名笔记": a.ID},
	}); err != nil {
		t.Fatal(err)
	}
	check("改为 [[同名笔记]]", map[string]string{"同名笔记": a.ID})

	// 删除引用，空 map 明确清除绑定。
	if _, err := s.UpdateActivity(UpdateActivityInput{
		ID: act.ID, Body: "只保留文字", Tags: act.Tags, NoteRefs: map[string]string{},
	}); err != nil {
		t.Fatal(err)
	}
	check("只保留文字", map[string]string{})
}

func TestTaskActivityBacklinkDoesNotRebindDeletedNote(t *testing.T) {
	v, err := markdown.NewVault(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	s := &VaultService{vault: v}
	old, err := s.CreateNote(CreateNoteInput{Title: "同名笔记"})
	if err != nil {
		t.Fatal(err)
	}
	task, err := s.CreateTask(CreateTaskInput{Title: "任务"})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := s.CreateActivity(CreateActivityInput{
		TaskID: task.ID, Body: "[[同名笔记]]",
		NoteRefs: map[string]string{"同名笔记": old.ID},
	}); err != nil {
		t.Fatal(err)
	}
	if got, err := s.GetNoteBacklinks(old.ID); err != nil || len(got) != 1 {
		t.Fatalf("original backlink: %+v, %v", got, err)
	}
	if err := s.DeleteNote(old.ID); err != nil {
		t.Fatal(err)
	}
	replacement, err := s.CreateNote(CreateNoteInput{Title: "同名笔记"})
	if err != nil {
		t.Fatal(err)
	}
	if err := s.RescanVault(); err != nil {
		t.Fatal(err)
	}
	if got, err := s.GetNoteBacklinks(replacement.ID); err != nil || len(got) != 0 {
		t.Fatalf("replacement inherited deleted note's backlinks: %+v, %v", got, err)
	}
}
