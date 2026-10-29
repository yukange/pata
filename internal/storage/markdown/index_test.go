package markdown

import (
	"path/filepath"
	"strings"
	"testing"
	"time"
	"unicode/utf8"
)

func TestScanExamplesVault(t *testing.T) {
	examplesDir := filepath.Join("..", "..", "..", "docs", "02-foundation", "examples")
	idx, err := ScanVault(examplesDir)
	if err != nil {
		t.Fatalf("ScanVault failed: %v", err)
	}

	if len(idx.parseErrors) != 0 {
		t.Fatalf("expected 0 parse errors in examples, got %d: %+v", len(idx.parseErrors), idx.parseErrors)
	}

	// Verify tasks
	task1, ok := idx.GetTask("t-demo-001")
	if !ok || task1.Title != "统一资源接入方案" {
		t.Fatalf("t-demo-001 not found or wrong title: %+v", task1)
	}

	task2, ok := idx.GetTask("t-demo-002")
	if !ok || task2.Title != "Flink SQL 批处理 POC" {
		t.Fatalf("t-demo-002 not found or wrong title: %+v", task2)
	}

	// Verify activity
	act1, loc1, ok := idx.GetActivity("a-demo-001")
	if !ok || loc1.OwnerID != "t-demo-001" {
		t.Fatalf("a-demo-001 not found or wrong owner_id: %+v, %+v", act1, loc1)
	}

	// Verify day plan
	plan, ok := idx.GetDayPlan("2026-10-11")
	if !ok || len(plan.TaskIDs) != 2 {
		t.Fatalf("day plan 2026-10-11 not found or wrong task IDs: %+v", plan)
	}

	// Verify tag index and inheritance:
	// "架构设计" is on t-demo-001 and n-demo-001.
	// a-demo-001 has no own tags, but belongs to t-demo-001!
	// Therefore FindByTag("架构设计") should match Task t-demo-001, Note n-demo-001, AND Activity a-demo-001 (inherited)!
	tagRefs := idx.FindByTag("架构设计")
	if len(tagRefs) != 3 {
		t.Fatalf("expected 3 entities for tag '架构设计' (Task, Note, inherited Activity), got %d: %+v", len(tagRefs), tagRefs)
	}

	hasInheritedActivity := false
	for _, ref := range tagRefs {
		if ref.Type == EntityTypeActivity && ref.ID == "a-demo-001" && ref.Inherited {
			hasInheritedActivity = true
		}
	}
	if !hasInheritedActivity {
		t.Fatalf("expected activity a-demo-001 to inherit tag '架构设计' from parent task")
	}

	// Tag "Doris" is on a-demo-002 only
	dorisRefs := idx.FindByTag("Doris")
	if len(dorisRefs) != 1 || dorisRefs[0].ID != "a-demo-002" {
		t.Fatalf("expected a-demo-002 for tag 'Doris', got %+v", dorisRefs)
	}
}

func TestListTasksSortedByUpdatedAt(t *testing.T) {
	idx, err := ScanVault(filepath.Join("..", "..", "..", "docs", "02-foundation", "examples"))
	if err != nil {
		t.Fatalf("ScanVault failed: %v", err)
	}
	tasks := idx.ListTasks()
	if len(tasks) < 2 {
		t.Fatalf("expected at least 2 tasks, got %d", len(tasks))
	}
	for i := 1; i < len(tasks); i++ {
		if tasks[i-1].UpdatedAt.Before(tasks[i].UpdatedAt) {
			t.Fatalf("tasks not sorted by UpdatedAt desc: [%d]=%s before [%d]=%s", i-1, tasks[i-1].ID, i, tasks[i].ID)
		}
	}
}

func TestDanglingReferences(t *testing.T) {
	idx := NewMemoryIndex()

	// Task referencing non-existent note
	task := &Task{
		Type:    EntityTypeTask,
		ID:      "t-orphan-1",
		Title:   "Some task",
		NoteIDs: []string{"n-missing-123"},
	}
	idx.PutEntity("/vault/tasks/t-orphan-1.md", task, FileBaseline{})

	// DayPlan referencing non-existent task
	plan := &DayPlan{
		Type:    EntityTypeDayPlan,
		Date:    "2026-10-11",
		TaskIDs: []string{"t-missing-999"},
	}
	idx.PutEntity("/vault/plans/2026-10-11.md", plan, FileBaseline{})

	dangling := idx.ListDanglingReferences()
	if len(dangling) != 2 {
		t.Fatalf("expected 2 dangling references, got %d: %+v", len(dangling), dangling)
	}

	// Verify explainable degradation details
	t.Logf("Dangling references correctly isolated:\n")
	for _, d := range dangling {
		t.Logf("  - %s\n", d.String())
	}
}

func TestListNotes(t *testing.T) {
	idx := NewMemoryIndex()

	// 1. Empty index returns empty slice
	empty := idx.ListNotes()
	if empty == nil || len(empty) != 0 {
		t.Fatalf("expected non-nil empty slice for empty index, got %v", empty)
	}

	t1 := time.Date(2026, 10, 11, 10, 0, 0, 0, time.UTC)
	t2 := time.Date(2026, 10, 11, 11, 0, 0, 0, time.UTC)
	t3 := time.Date(2026, 10, 11, 12, 0, 0, 0, time.UTC)

	note1 := &Note{
		Type:      EntityTypeNote,
		ID:        "n-001",
		Title:     "旧笔记",
		Tags:      []string{"tag1"},
		CreatedAt: t1,
		UpdatedAt: t1,
		Body:      "正文1",
	}
	note2 := &Note{
		Type:      EntityTypeNote,
		ID:        "n-002",
		Title:     "最新修改笔记",
		Tags:      []string{"tag2"},
		CreatedAt: t1,
		UpdatedAt: t3,
		Body:      "正文2",
	}
	note3 := &Note{
		Type:      EntityTypeNote,
		ID:        "n-003",
		Title:     "中间修改笔记",
		Tags:      []string{"tag3"},
		CreatedAt: t2,
		UpdatedAt: t2,
		Body:      "正文3",
	}

	idx.PutEntity("/vault/notes/n-001.md", note1, FileBaseline{})
	idx.PutEntity("/vault/notes/n-002.md", note2, FileBaseline{})
	idx.PutEntity("/vault/notes/n-003.md", note3, FileBaseline{})

	// 2. Sort check (UpdatedAt descending: n-002 (t3), n-003 (t2), n-001 (t1))
	notes := idx.ListNotes()
	if len(notes) != 3 {
		t.Fatalf("expected 3 notes, got %d", len(notes))
	}
	if notes[0].ID != "n-002" || notes[1].ID != "n-003" || notes[2].ID != "n-001" {
		t.Fatalf("expected order [n-002, n-003, n-001], got [%s, %s, %s]", notes[0].ID, notes[1].ID, notes[2].ID)
	}

	// 3. Clone isolation check: mutating the returned slice/elements doesn't affect index
	notes[0].Title = "被篡改的标题"
	notes[0].Tags[0] = "mutated-tag"
	notes[0].Body = "被篡改的正文"

	reloaded, ok := idx.GetNote("n-002")
	if !ok {
		t.Fatalf("GetNote n-002 failed")
	}
	if reloaded.Title != "最新修改笔记" || reloaded.Tags[0] != "tag2" || reloaded.Body != "正文2" {
		t.Fatalf("index entity was mutated through returned ListNotes clone: %+v", reloaded)
	}
}

func TestExtractNoteExcerpt(t *testing.T) {
	// 1. Empty or whitespace
	if got := ExtractNoteExcerpt("标题", ""); got != "" {
		t.Fatalf("expected empty, got %q", got)
	}
	if got := ExtractNoteExcerpt("标题", "   \n\n  "); got != "" {
		t.Fatalf("expected empty, got %q", got)
	}

	// 2. Heading matching title is stripped
	body1 := "# 系统架构\n这是核心架构设计的正文，包含**重点**与`代码`。\n第二行说明\n第三行内容"
	expected1 := "这是核心架构设计的正文，包含重点与代码。\n第二行说明"
	if got := ExtractNoteExcerpt("系统架构", body1); got != expected1 {
		t.Fatalf("expected %q, got %q", expected1, got)
	}

	// 3. Heading NOT matching title is preserved as cleaned text
	body2 := "# 另一部分\n这是其他内容。"
	expected2 := "另一部分\n这是其他内容。"
	if got := ExtractNoteExcerpt("系统架构", body2); got != expected2 {
		t.Fatalf("expected %q, got %q", expected2, got)
	}

	// 4. Draft note (empty title) with complex markdown tokens and links
	draftBody := "# 第一行思考\n- [x] 完成任务项 [链接](http://example.com)\n> 第三行引用"
	expectedDraft := "第一行思考\n完成任务项 链接"
	if got := ExtractNoteExcerpt("", draftBody); got != expectedDraft {
		t.Fatalf("expected %q, got %q", expectedDraft, got)
	}

	// 5. Wikilink and inline code / bold style stripping
	wikiBody := "这是包含 [[WikiNote|别名]] 和 `code` 与 **加粗** 的正文\n第二行内容\n第三行被忽略"
	expectedWiki := "这是包含 WikiNote 和 code 与 加粗 的正文\n第二行内容"
	if got := ExtractNoteExcerpt("", wikiBody); got != expectedWiki {
		t.Fatalf("expected %q, got %q", expectedWiki, got)
	}

	// 6. Audio transcript timestamp link
	asrBody := "[00:01:05.230](#t=00:01:05.230) 说话人 1\n大家下午好，今天开会。\n第三行内容"
	expectedASR := "00:01:05.230 说话人 1\n大家下午好，今天开会。"
	if got := ExtractNoteExcerpt("会议记录", asrBody); got != expectedASR {
		t.Fatalf("expected %q, got %q", expectedASR, got)
	}

	// 7. Rune length truncation
	longLine := strings.Repeat("长", 300)
	gotLong := ExtractNoteExcerpt("", longLine)
	if runes := []rune(gotLong); len(runes) > 205 || !strings.HasSuffix(gotLong, "…") {
		t.Fatalf("expected truncated excerpt with '…', got len %d, val %q", len(runes), gotLong)
	}
}

func TestListNotes_LightweightExcerpt(t *testing.T) {
	idx := NewMemoryIndex()

	longBody := "# 庞大文档\n这是正文第一行，简要说明核心思想。\n这是正文第二行，介绍主要细节。\n" + strings.Repeat("这里是成千上万字的详细正文段落，不应当在列表接口中传输。\n", 500)
	note := &Note{
		Type:      EntityTypeNote,
		ID:        "n-huge",
		Title:     "庞大文档",
		CreatedAt: time.Now(),
		UpdatedAt: time.Now(),
		Body:      longBody,
	}

	idx.PutEntity("/vault/notes/n-huge.md", note, FileBaseline{})

	// ListNotes returns lightweight excerpt
	list := idx.ListNotes()
	if len(list) != 1 {
		t.Fatalf("expected 1 note, got %d", len(list))
	}
	expectedExcerpt := "这是正文第一行，简要说明核心思想。\n这是正文第二行，介绍主要细节。"
	if list[0].Body != expectedExcerpt {
		t.Fatalf("expected lightweight excerpt %q, got %q", expectedExcerpt, list[0].Body)
	}

	// GetNote still returns full untruncated body
	reloaded, ok := idx.GetNote("n-huge")
	if !ok {
		t.Fatalf("GetNote failed")
	}
	if reloaded.Body != longBody {
		t.Fatalf("GetNote must return complete full body, got len %d vs original len %d", len(reloaded.Body), len(longBody))
	}
}

func TestTagOverview(t *testing.T) {
	idx := NewMemoryIndex()

	// 1. Empty index returns empty slice
	empty := idx.TagOverview()
	if empty == nil || len(empty) != 0 {
		t.Fatalf("expected non-nil empty slice for empty index, got %v", empty)
	}

	// 2. Add entities:
	// Task 1: tags ["架构设计", " GoCore "] (GoCore has leading/trailing spaces)
	task1 := &Task{
		Type:  EntityTypeTask,
		ID:    "t-001",
		Title: "Task 1",
		Tags:  []string{"架构设计", " GoCore "},
	}
	// Task 2: tags ["架构设计", "架构设计"] (duplicate on same entity)
	task2 := &Task{
		Type:  EntityTypeTask,
		ID:    "t-002",
		Title: "Task 2",
		Tags:  []string{"架构设计", "架构设计"},
	}
	// Note 1: tags ["架构设计", "gocore"] (lowercase gocore to test case preservation)
	note1 := &Note{
		Type:  EntityTypeNote,
		ID:    "n-001",
		Title: "Note 1",
		Tags:  []string{"架构设计", "gocore"},
	}
	// Note 2: tags ["Flink"]
	note2 := &Note{
		Type:  EntityTypeNote,
		ID:    "n-002",
		Title: "Note 2",
		Tags:  []string{"Flink"},
	}
	// Activity 1 (task comment): parent t-001 has "架构设计", but Activity 1 has NO own tags!
	// Must NOT count toward "架构设计" in TagOverview!
	task1.Activities = []Activity{
		{
			ID:   "a-001",
			At:   time.Now(),
			Tags: []string{},
			Body: "Comment on task 1",
		},
	}
	// DayPlan Activity: own tags ["Flink", "Doris"]
	plan := &DayPlan{
		Type: EntityTypeDayPlan,
		Date: "2026-10-11",
		Activities: []Activity{
			{
				ID:   "a-002",
				At:   time.Now(),
				Tags: []string{"Flink", "Doris"},
				Body: "Activity 2 body",
			},
		},
	}

	idx.PutEntity("/vault/tasks/t-001.md", task1, FileBaseline{})
	idx.PutEntity("/vault/tasks/t-002.md", task2, FileBaseline{})
	idx.PutEntity("/vault/notes/n-001.md", note1, FileBaseline{})
	idx.PutEntity("/vault/notes/n-002.md", note2, FileBaseline{})
	idx.PutEntity("/vault/plans/2026-10-11.md", plan, FileBaseline{})

	overview := idx.TagOverview()

	// Expected tags in alphabetical order:
	// "Doris": Activity: 1 -> Total 1
	// "Flink": Note: 1, Activity: 1 -> Total 2
	// "GoCore": Task: 1, Note: 1 ("gocore" merged case-insensitively, displayTag preserves first appearance "GoCore") -> Total 2
	// "架构设计": Task: 2, Note: 1, Activity: 0 (a-001 doesn't inherit in overview) -> Total 3
	if len(overview) != 4 {
		t.Fatalf("expected 4 aggregated tags (GoCore/gocore merged), got %d: %+v", len(overview), overview)
	}

	tagMap := make(map[string]TagOverviewItem)
	for _, it := range overview {
		tagMap[it.Tag] = it
	}

	// Verify "架构设计": TaskCount=2 (deduped within t-002), NoteCount=1, ActivityCount=0, Total=3
	arch, ok := tagMap["架构设计"]
	if !ok || arch.TaskCount != 2 || arch.NoteCount != 1 || arch.ActivityCount != 0 || arch.Total != 3 {
		t.Fatalf("unexpected stats for '架构设计': %+v", arch)
	}

	// Verify "Flink": TaskCount=0, NoteCount=1, ActivityCount=1, Total=2
	flink, ok := tagMap["Flink"]
	if !ok || flink.TaskCount != 0 || flink.NoteCount != 1 || flink.ActivityCount != 1 || flink.Total != 2 {
		t.Fatalf("unexpected stats for 'Flink': %+v", flink)
	}

	// Verify "Doris": TaskCount=0, NoteCount=0, ActivityCount=1, Total=1
	doris, ok := tagMap["Doris"]
	if !ok || doris.TaskCount != 0 || doris.NoteCount != 0 || doris.ActivityCount != 1 || doris.Total != 1 {
		t.Fatalf("unexpected stats for 'Doris': %+v", doris)
	}

	// Verify "GoCore": merged case-insensitively from Task 1 (" GoCore ") and Note 1 ("gocore")
	gocoreMerged, ok := tagMap["GoCore"]
	if !ok || gocoreMerged.TaskCount != 1 || gocoreMerged.NoteCount != 1 || gocoreMerged.ActivityCount != 0 || gocoreMerged.Total != 2 {
		t.Fatalf("unexpected stats for 'GoCore' (expected merged with 'gocore'): %+v", gocoreMerged)
	}

	// Verify FindByTag matches both Task 1 (" GoCore ") and Note 1 ("gocore")
	var foundTask1, foundNote1 bool
	for _, r := range idx.FindByTag("GoCore") {
		if r.ID == "t-001" {
			foundTask1 = true
		}
		if r.ID == "n-001" {
			foundNote1 = true
		}
	}
	if !foundTask1 || !foundNote1 {
		t.Fatalf("expected FindByTag('GoCore') to match both Task 1 and Note 1")
	}

	// Verify sorting is alphabetical (case-insensitive)
	for i := 1; i < len(overview); i++ {
		if strings.ToLower(overview[i-1].Tag) >= strings.ToLower(overview[i].Tag) {
			t.Fatalf("TagOverview not sorted alphabetically: [%d]=%s before [%d]=%s", i-1, overview[i-1].Tag, i, overview[i].Tag)
		}
	}
}

func TestSearchAll(t *testing.T) {
	idx := NewMemoryIndex()

	t1 := time.Date(2026, 10, 11, 10, 0, 0, 0, time.UTC)
	t2 := time.Date(2026, 10, 11, 12, 0, 0, 0, time.UTC)

	// Task 1: matches in title ("统一资源接入")
	task1 := &Task{
		Type:      EntityTypeTask,
		ID:        "t-001",
		Title:     "统一资源接入方案",
		Body:      "第一行描述\n接入协议与规范细节",
		Tags:      []string{"架构"},
		UpdatedAt: t1,
	}
	// Task 2: matches in body ("性能指标在规范细节中定义")
	task2 := &Task{
		Type:      EntityTypeTask,
		ID:        "t-002",
		Title:     "压测分析",
		Body:      "前言\n规范细节补充",
		Tags:      []string{"测试"},
		UpdatedAt: t2,
	}
	// Note 1: matches in tag ("规范细节")
	note1 := &Note{
		Type:      EntityTypeNote,
		ID:        "n-001",
		Title:     "架构笔记",
		Body:      "笔记正文内容",
		Tags:      []string{"规范细节"},
		UpdatedAt: t1,
	}
	// Activity 1: task activity on task2. Has NO own tag, body does NOT contain "规范细节" (parent task2 matches in body, but activities do not inherit parent task matches).
	// Activity a-001 must NOT match!
	task2.Activities = []Activity{
		{
			ID:   "a-001",
			Body: "日常打卡",
			Tags: []string{},
			At:   t1,
		},
	}
	// DayPlan Activity: matches in body ("这是关于规范细节的评论")
	searchPlan := &DayPlan{
		Type: EntityTypeDayPlan,
		Date: "2026-10-11",
		Activities: []Activity{
			{
				ID:   "a-002",
				Body: "这是关于规范细节的评论\n第二行内容",
				Tags: []string{},
				At:   t2,
			},
		},
	}

	idx.PutEntity("/vault/tasks/t-001.md", task1, FileBaseline{})
	idx.PutEntity("/vault/tasks/t-002.md", task2, FileBaseline{})
	idx.PutEntity("/vault/notes/n-001.md", note1, FileBaseline{})
	idx.PutEntity("/vault/plans/2026-10-11.md", searchPlan, FileBaseline{})

	// 1. Empty and whitespace queries return empty slice
	if res := idx.SearchAll(""); len(res) != 0 {
		t.Fatalf("expected empty result for empty query, got %v", res)
	}
	if res := idx.SearchAll("   \t\n  "); len(res) != 0 {
		t.Fatalf("expected empty result for whitespace query, got %v", res)
	}

	// 2. Search for "规范细节" (case-insensitive substring)
	// Matches:
	// - Task 1 (Body: "接入协议与规范细节")
	// - Task 2 (Body: "规范细节补充")
	// - Note 1 (Tag: "规范细节")
	// - Activity a-002 (Body: "这是关于规范细节的评论")
	// Activity a-001 must NOT be matched!
	res := idx.SearchAll("规范细节")
	if len(res) != 4 {
		t.Fatalf("expected 4 results, got %d: %+v", len(res), res)
	}

	// Stable grouping: Tasks first (t-002 UpdatedAt t2, then t-001 UpdatedAt t1),
	// Notes second (n-001),
	// Activities third (a-002).
	if res[0].Type != EntityTypeTask || res[0].ID != "t-002" {
		t.Fatalf("expected res[0] to be Task t-002, got %+v", res[0])
	}
	if res[1].Type != EntityTypeTask || res[1].ID != "t-001" {
		t.Fatalf("expected res[1] to be Task t-001, got %+v", res[1])
	}
	if res[2].Type != EntityTypeNote || res[2].ID != "n-001" {
		t.Fatalf("expected res[2] to be Note n-001, got %+v", res[2])
	}
	if res[3].Type != EntityTypeActivity || res[3].ID != "a-002" {
		t.Fatalf("expected res[3] to be Activity a-002, got %+v", res[3])
	}

	// Check snippet extraction:
	// t-001 body has line containing query: "接入协议与规范细节"
	if res[1].Snippet != "接入协议与规范细节" {
		t.Fatalf("unexpected snippet for t-001: %q", res[1].Snippet)
	}
	// n-001 matched via tag, body doesn't contain query: falls back to first non-empty line "笔记正文内容"
	if res[2].Snippet != "笔记正文内容" {
		t.Fatalf("unexpected snippet for n-001: %q", res[2].Snippet)
	}
	// a-002 body matched line: "这是关于规范细节的评论"
	if res[3].Snippet != "这是关于规范细节的评论" {
		t.Fatalf("unexpected snippet for a-002: %q", res[3].Snippet)
	}

	// 3. Case-insensitivity check (e.g. search lowercase / uppercase)
	task3 := &Task{
		Type:      EntityTypeTask,
		ID:        "t-003",
		Title:     "FlinkPOC",
		Body:      "Testing flink throughput",
		Tags:      []string{"FLINK"},
		UpdatedAt: t1,
	}
	idx.PutEntity("/vault/tasks/t-003.md", task3, FileBaseline{})

	flinkRes := idx.SearchAll("flink")
	foundT3 := false
	for _, r := range flinkRes {
		if r.ID == "t-003" {
			foundT3 = true
		}
	}
	if !foundT3 {
		t.Fatalf("expected case-insensitive match for 'flink' on t-003")
	}

	// 4. Activity does NOT inherit parent task tags when query only matches parent task tags:
	taskParent := &Task{
		Type:      EntityTypeTask,
		ID:        "t-tag-parent",
		Title:     "父任务标题",
		Body:      "父任务普通正文",
		Tags:      []string{"父任务独有标签"},
		UpdatedAt: t1,
		Activities: []Activity{
			{
				ID:   "a-tag-child",
				Body: "子活动自有内容不含该词",
				Tags: []string{},
				At:   t1,
			},
		},
	}
	idx.PutEntity("/vault/tasks/t-tag-parent.md", taskParent, FileBaseline{})

	parentTagRes := idx.SearchAll("父任务独有标签")
	if len(parentTagRes) != 1 || parentTagRes[0].ID != "t-tag-parent" {
		t.Fatalf("expected only parent task to match '父任务独有标签', got %+v", parentTagRes)
	}
	for _, r := range parentTagRes {
		if r.ID == "a-tag-child" {
			t.Fatalf("SearchAll must NOT return activity when only parent task tags hit query")
		}
	}
}

func TestFindAllEntities(t *testing.T) {
	idx := NewMemoryIndex()
	now := time.Now()

	// Task with tag
	t1 := &Task{
		Type:        EntityTypeTask,
		ID:          "t-with-tag",
		Title:       "带标签任务",
		Description: "这是带标签的任务描述",
		Tags:        []string{"tag-alpha"},
		UpdatedAt:   now.Add(-10 * time.Minute),
		Activities: []Activity{
			{
				ID:   "a-task-1",
				Body: "任务内活动 1",
				Tags: []string{"tag-beta"},
				At:   now.Add(-8 * time.Minute),
			},
		},
	}
	idx.PutEntity("/vault/tasks/t-with-tag.md", t1, FileBaseline{})

	// Task without tag
	t2 := &Task{
		Type:        EntityTypeTask,
		ID:          "t-no-tag",
		Title:       "无标签任务",
		Description: "完全没有标签的任务",
		Tags:        []string{},
		UpdatedAt:   now.Add(-5 * time.Minute),
		Activities: []Activity{
			{
				ID:   "a-task-2",
				Body: "任务内活动 2（无标签）",
				Tags: []string{},
				At:   now.Add(-4 * time.Minute),
			},
		},
	}
	idx.PutEntity("/vault/tasks/t-no-tag.md", t2, FileBaseline{})

	// Note with tag
	n1 := &Note{
		Type:      EntityTypeNote,
		ID:        "n-with-tag",
		Title:     "带标签笔记",
		Body:      "笔记正文内容",
		Tags:      []string{"tag-alpha"},
		UpdatedAt: now.Add(-7 * time.Minute),
	}
	idx.PutEntity("/vault/notes/n-with-tag.md", n1, FileBaseline{})

	// Note without tag
	n2 := &Note{
		Type:      EntityTypeNote,
		ID:        "n-no-tag",
		Title:     "无标签笔记",
		Body:      "无标签笔记正文",
		Tags:      []string{},
		UpdatedAt: now.Add(-3 * time.Minute),
	}
	idx.PutEntity("/vault/notes/n-no-tag.md", n2, FileBaseline{})

	// DayPlan with activity
	dp := &DayPlan{
		Type: EntityTypeDayPlan,
		Date: "2026-10-20",
		Activities: []Activity{
			{
				ID:   "a-plan-1",
				Body: "今日独立记录",
				Tags: []string{},
				At:   now.Add(-2 * time.Minute),
			},
		},
	}
	idx.PutEntity("/vault/plans/2026-10-20.md", dp, FileBaseline{})

	all := idx.FindAll()
	// Should contain t-with-tag, t-no-tag, n-with-tag, n-no-tag, a-task-1, a-task-2, a-plan-1
	if len(all) != 7 {
		t.Fatalf("expected 7 entities in FindAll, got %d: %+v", len(all), all)
	}

	foundMap := make(map[string]EntityRef)
	for _, r := range all {
		foundMap[r.ID] = r
		if r.Inherited {
			t.Errorf("entity %s has Inherited=true, expected false in FindAll", r.ID)
		}
	}

	expectedIDs := []string{"t-with-tag", "t-no-tag", "n-with-tag", "n-no-tag", "a-task-1", "a-task-2", "a-plan-1"}
	for _, id := range expectedIDs {
		if _, ok := foundMap[id]; !ok {
			t.Errorf("expected entity %s to be returned by FindAll", id)
		}
	}

	// Verify that tasks without tags are definitely included
	if r, ok := foundMap["t-no-tag"]; !ok || r.Type != EntityTypeTask || r.Title != "无标签任务" {
		t.Errorf("untagged task not properly found: %+v", r)
	}
	// Verify that notes without tags are definitely included
	if r, ok := foundMap["n-no-tag"]; !ok || r.Type != EntityTypeNote || r.Title != "无标签笔记" {
		t.Errorf("untagged note not properly found: %+v", r)
	}
	// Verify that activities without tags are definitely included
	if r, ok := foundMap["a-task-2"]; !ok || r.Type != EntityTypeActivity || r.TaskID != "t-no-tag" {
		t.Errorf("untagged task activity not properly found: %+v", r)
	}
	if r, ok := foundMap["a-plan-1"]; !ok || r.Type != EntityTypeActivity || r.Title != "2026-10-20" {
		t.Errorf("dayplan activity not properly found: %+v", r)
	}
}

func TestFindAll_NoteSnippetUTF8Truncation(t *testing.T) {
	idx := NewMemoryIndex()
	// 300 Chinese characters (each 3 bytes in UTF-8, total 900 bytes)
	longBody := strings.Repeat("中", 300)
	n := &Note{
		Type:      EntityTypeNote,
		ID:        "n-long-chinese",
		Title:     "长中文笔记",
		Body:      longBody,
		UpdatedAt: time.Now(),
	}
	idx.PutEntity("/vault/notes/n-long-chinese.md", n, FileBaseline{})

	refs := idx.FindAll()
	var found *EntityRef
	for i := range refs {
		if refs[i].ID == "n-long-chinese" {
			found = &refs[i]
			break
		}
	}
	if found == nil {
		t.Fatalf("note not found in FindAll")
	}
	if !utf8.ValidString(found.Snippet) {
		t.Fatalf("snippet contains invalid UTF-8 bytes: %q", found.Snippet)
	}
	if runes := []rune(found.Snippet); len(runes) != 203 || !strings.HasSuffix(found.Snippet, "...") {
		t.Fatalf("expected 203 runes ending with '...', got %d: %q", len(runes), found.Snippet)
	}
}
