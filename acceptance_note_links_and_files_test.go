package main

import (
	"os"
	"path/filepath"
	"testing"

	"pata/internal/storage/markdown"
)

// TestAcceptance_NoteLinks_BacklinksAndDanglingSafety tests note references in Task description,
// activities, backlink aggregation, safe note deletion, and dangling reference tracking.
func TestAcceptance_NoteLinks_BacklinksAndDanglingSafety(t *testing.T) {
	tmpDir, err := os.MkdirTemp("", "pata-note-links-vault-*")
	if err != nil {
		t.Fatal(err)
	}
	defer os.RemoveAll(tmpDir)

	svc := NewVaultService()
	_, err = svc.openVault(tmpDir)
	if err != nil {
		t.Fatalf("failed to open vault: %v", err)
	}
	defer func() {
		if svc.stopWatcher != nil {
			svc.stopWatcher()
		}
	}()

	// 1. Create Note A and Note B
	noteA, err := svc.CreateNote(CreateNoteInput{
		Title: "系统架构说明",
		Body:  "# 架构说明\n核心数据结构与边界设计。",
	})
	if err != nil {
		t.Fatalf("CreateNote A failed: %v", err)
	}

	noteB, err := svc.CreateNote(CreateNoteInput{
		Title: "用户界面规范",
		Body:  "# 界面规范\nmacOS 原生窗口与 HIG 适配。",
	})
	if err != nil {
		t.Fatalf("CreateNote B failed: %v", err)
	}

	// 2. Create Task referencing Note A in Description
	task, err := svc.CreateTask(CreateTaskInput{
		Title:       "完善窗口架构",
		Description: "参考 [[系统架构说明]] 实施新窗口规范",
		NoteRefs:    map[string]string{"系统架构说明": noteA.ID},
	})
	if err != nil {
		t.Fatalf("CreateTask failed: %v", err)
	}

	// 3. Add an Activity to Task referencing Note B
	act1, err := svc.CreateActivity(CreateActivityInput{
		OwnerType: markdown.EntityTypeTask,
		TaskID:    task.ID,
		Body:      "阅读了 [[用户界面规范]] 并确认标题栏样式",
		NoteRefs:  map[string]string{"用户界面规范": noteB.ID},
	})
	if err != nil {
		t.Fatalf("CreateActivity act1 failed: %v", err)
	}
	if act1.ID == "" {
		t.Fatalf("expected non-empty activity ID")
	}

	// 4. Add another Activity to Task ALSO referencing Note A
	_, err = svc.CreateActivity(CreateActivityInput{
		OwnerType: markdown.EntityTypeTask,
		TaskID:    task.ID,
		Body:      "再次对齐 [[系统架构说明]] 的边界定义",
		NoteRefs:  map[string]string{"系统架构说明": noteA.ID},
	})
	if err != nil {
		t.Fatalf("CreateActivity act2 failed: %v", err)
	}

	// 5. Verify Backlinks (被引用):
	// Note A should have exactly 1 backlink from Task (deduplicated across Description and Activity)
	backlinksA, err := svc.GetNoteBacklinks(noteA.ID)
	if err != nil {
		t.Fatalf("GetNoteBacklinks failed: %v", err)
	}
	if len(backlinksA) != 1 {
		t.Fatalf("expected 1 backlink for Note A, got %d", len(backlinksA))
	}
	if backlinksA[0].ID != task.ID || backlinksA[0].Type != markdown.EntityTypeTask {
		t.Fatalf("unexpected backlink for Note A: %+v", backlinksA[0])
	}

	// Note B should have 1 backlink from Task
	backlinksB, err := svc.GetNoteBacklinks(noteB.ID)
	if err != nil {
		t.Fatalf("GetNoteBacklinks B failed: %v", err)
	}
	if len(backlinksB) != 1 {
		t.Fatalf("expected 1 backlink for Note B, got %d", len(backlinksB))
	}

	// 6. Test safe deletion: Delete Note A.
	// Task's note_refs still retains noteA.ID, but target Note does not exist.
	v := svc.vault
	if err := v.DeleteEntity(noteA.ID); err != nil {
		t.Fatalf("DeleteEntity Note A failed: %v", err)
	}

	// Verify Note A has 0 backlinks now
	backlinksAfterDel, err := svc.GetNoteBacklinks(noteA.ID)
	if err != nil {
		t.Fatalf("GetNoteBacklinks after del failed: %v", err)
	}
	if len(backlinksAfterDel) != 0 {
		t.Fatalf("expected 0 backlinks after deleting Note A, got %d", len(backlinksAfterDel))
	}

	// 7. Create a NEW note with the SAME title "系统架构说明"
	newNoteA, err := svc.CreateNote(CreateNoteInput{
		Title: "系统架构说明",
		Body:  "# 新架构说明",
	})
	if err != nil {
		t.Fatalf("CreateNote new Note A failed: %v", err)
	}
	if newNoteA.ID == noteA.ID {
		t.Fatalf("new note should have different ID from deleted note")
	}

	// Verify new Note A is NOT hijacked by task's old note_refs!
	newBacklinksA, err := svc.GetNoteBacklinks(newNoteA.ID)
	if err != nil {
		t.Fatalf("GetNoteBacklinks newNoteA failed: %v", err)
	}
	if len(newBacklinksA) != 0 {
		t.Fatalf("new note with same title must NOT inherit old note bindings, got %d backlinks", len(newBacklinksA))
	}
}

// TestAcceptance_VaultFiles_ImportSearchPreviewAndReferences verifies:
// 1. Root arbitrary markdown is ignored as Notes.
// 2. File import copies files into files/ directory.
// 3. Duplicate imports generate safe non-colliding filenames without overwriting.
// 4. Global search finds files by name and unreferenced files.
// 5. File preview path resolution validates boundaries.
// 6. Referencing files in activities works seamlessly.
func TestAcceptance_VaultFiles_ImportSearchPreviewAndReferences(t *testing.T) {
	tmpDir, err := os.MkdirTemp("", "pata-vault-files-*")
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

	// 1. Boundary test: arbitrary markdown file in vault root
	arbitraryMD := filepath.Join(tmpDir, "README.md")
	if err := os.WriteFile(arbitraryMD, []byte("# Ignored\nShould not be indexed as a note"), 0644); err != nil {
		t.Fatal(err)
	}
	if err := svc.RescanVault(); err != nil {
		t.Fatal(err)
	}
	if len(v.Index.ListNotes()) != 0 {
		t.Fatalf("arbitrary root README.md must NOT be indexed as Note, got %d notes", len(v.Index.ListNotes()))
	}

	// 2. File Import test
	extDir, err := os.MkdirTemp("", "pata-ext-files-*")
	if err != nil {
		t.Fatal(err)
	}
	defer os.RemoveAll(extDir)

	docPath := filepath.Join(extDir, "技术设计方案.pdf")
	origContent := []byte("PDF content for testing")
	if err := os.WriteFile(docPath, origContent, 0644); err != nil {
		t.Fatal(err)
	}

	imported1, err := svc.ImportFile(docPath)
	if err != nil {
		t.Fatalf("ImportFile failed: %v", err)
	}
	if imported1.Name != "技术设计方案.pdf" || imported1.Path != "files/技术设计方案.pdf" {
		t.Fatalf("unexpected imported1: %+v", imported1)
	}

	// 3. Duplicate import -> should rename without collision
	imported2, err := svc.ImportFile(docPath)
	if err != nil {
		t.Fatalf("ImportFile duplicate failed: %v", err)
	}
	if imported2.Name != "技术设计方案 1.pdf" || imported2.Path != "files/技术设计方案 1.pdf" {
		t.Fatalf("unexpected duplicate imported2: %+v", imported2)
	}

	// Verify original file is still intact
	if _, err := os.Stat(docPath); os.IsNotExist(err) {
		t.Fatalf("original external file was deleted or moved")
	}

	// 4. Global Search by filename
	searchResults, err := svc.SearchAll("技术设计方案")
	if err != nil {
		t.Fatalf("SearchAll failed: %v", err)
	}
	foundFiles := 0
	for _, res := range searchResults {
		if res.Type == "file" {
			foundFiles++
		}
	}
	if foundFiles < 2 {
		t.Fatalf("expected at least 2 files in search results, got %d", foundFiles)
	}

	// 5. Native Preview path resolution
	absPath, err := svc.resolveSafeFilePath("files/技术设计方案.pdf")
	if err != nil {
		t.Fatalf("resolveSafeFilePath failed: %v", err)
	}
	if _, err := os.Stat(absPath); os.IsNotExist(err) {
		t.Fatalf("resolved absolute path does not exist: %s", absPath)
	}

	// 6. Reference file in Activity
	task, err := svc.CreateTask(CreateTaskInput{
		Title: "审阅技术方案",
	})
	if err != nil {
		t.Fatal(err)
	}
	_, err = svc.CreateActivity(CreateActivityInput{
		OwnerType: markdown.EntityTypeTask,
		TaskID:    task.ID,
		Body:      "请查阅附件 [技术设计方案.pdf](files/技术设计方案.pdf)",
	})
	if err != nil {
		t.Fatal(err)
	}

	// Search for query in Activity body
	searchAct, err := svc.SearchAll("查阅附件")
	if err != nil {
		t.Fatalf("SearchAll for activity failed: %v", err)
	}
	hasActivity := false
	for _, it := range searchAct {
		if it.Type == "activity" {
			hasActivity = true
			break
		}
	}
	if !hasActivity {
		t.Fatalf("expected to find activity in search results: %+v", searchAct)
	}
}
