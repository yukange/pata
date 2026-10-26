package app

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// TestAcceptance_NoteEditor_MarkdownSyntaxRoundTrip tests real macOS disk persistence and
// lossless round-trip reading/writing for all Markdown syntax elements.
func TestAcceptance_NoteEditor_MarkdownSyntaxRoundTrip(t *testing.T) {
	tmpDir, err := os.MkdirTemp("", "pata-note-editor-vault-*")
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

	comprehensiveMarkdownBody := `# 一级标题 Heading 1
## 二级标题 Heading 2
### 三级标题 Heading 3
#### 四级标题 Heading 4
##### 五级标题 Heading 5
###### 六级标题 Heading 6

这是**粗体文字 Bold**，这是*斜体文字 Italic*，这是~~删除线 Strikethrough~~，这是` + "`行内代码 inline_code()`" + `，这是==高亮标记 Highlight==。

> 这是一段引用内容，阐述系统设计与核心原则。
>> 这是一段嵌套引用，强调边界安全与 Local First。

- 无序列表第一项
- 无序列表第二项
  - 嵌套无序列表子项

1. 有序列表步骤一
2. 有序列表步骤二

- [ ] 待办任务清单项 A（未完成）
- [x] 已完成任务清单项 B（已勾选）

| 功能特性 | 语法标记 | 预期效果 | 对齐状态 |
| :--- | :---: | ---: | :--- |
| 标题渲染 | ` + "`# 标题`" + ` | 语义化 h1~h6 | 居左对齐 |
| 任务清单 | ` + "`- [ ]`" + ` | 交互式 Checkbox | 居中对齐 |
| 数据表格 | ` + "`\\| a \\| b \\|`" + ` | 格式化表格网格 | 居右对齐 |

` + "```go" + `
package main

import "fmt"

// Task 结构体说明
type Task struct {
    ID    string ` + "`json:\"id\"`" + `
    Title string ` + "`json:\"title\"`" + `
}

func main() {
    fmt.Println("Pata Note Editor Live Verification")
}
` + "```" + `

` + "```typescript" + `
interface NoteRef {
  id: string;
  title: string;
  tags: string[];
}
const computeExcerpt = (text: string): string => text.slice(0, 50);
` + "```" + `

---

欢迎访问 [Pata 官方链接](https://github.com/pata) 或引用内部双链 [[系统架构说明]]。

这是一个包含脚注的说明文本[^note1]。

[^note1]: 这里的脚注详细解释了 Local First 原则。

在中文排版测试中，测试中英文混排以及“全角双引号”、《书名号》、破折号——与省略号……的显示。`

	// 1. Create Note with full syntax sample
	created, err := svc.CreateNote(CreateNoteInput{
		Title: "实机测试：综合语法与排版验证",
		Tags:  []string{"测试", "Markdown", "实机验证"},
		Body:  comprehensiveMarkdownBody,
	})
	if err != nil {
		t.Fatalf("CreateNote failed: %v", err)
	}
	if created.ID == "" {
		t.Fatalf("expected non-empty note ID")
	}

	// 2. Read back from memory cache via GetNote
	fetched, err := svc.GetNote(created.ID)
	if err != nil {
		t.Fatalf("GetNote failed: %v", err)
	}
	if fetched == nil {
		t.Fatalf("GetNote returned nil")
	}
	if fetched.Title != "实机测试：综合语法与排版验证" {
		t.Fatalf("unexpected title: %q", fetched.Title)
	}
	if len(fetched.Tags) != 3 {
		t.Fatalf("expected 3 tags, got %d", len(fetched.Tags))
	}
	if fetched.Body != comprehensiveMarkdownBody {
		t.Fatalf("body mismatch in memory cache reading")
	}

	// 3. Inspect actual markdown file on disk
	notesDir := filepath.Join(tmpDir, "notes")
	files, err := os.ReadDir(notesDir)
	if err != nil {
		t.Fatalf("failed to read notes dir: %v", err)
	}
	if len(files) != 1 {
		t.Fatalf("expected 1 file in notes dir, got %d", len(files))
	}

	diskFilePath := filepath.Join(notesDir, files[0].Name())
	rawBytes, err := os.ReadFile(diskFilePath)
	if err != nil {
		t.Fatalf("failed to read raw note file from disk: %v", err)
	}
	rawContent := string(rawBytes)

	// Verify YAML frontmatter structure
	if !strings.HasPrefix(rawContent, "---\n") {
		t.Fatalf("expected YAML frontmatter start '---\\n', got %q", rawContent[:min(30, len(rawContent))])
	}
	if !strings.Contains(rawContent, "type: note\n") {
		t.Fatalf("missing 'type: note' in frontmatter")
	}
	if !strings.Contains(rawContent, "id: "+created.ID+"\n") {
		t.Fatalf("missing note ID in frontmatter")
	}
	if !strings.Contains(rawContent, "title: 实机测试：综合语法与排版验证\n") {
		t.Fatalf("missing title in frontmatter")
	}

	// Verify exact body preservation on disk
	parts := strings.SplitN(rawContent, "---\n\n", 2)
	if len(parts) != 2 {
		parts = strings.SplitN(rawContent, "---\r\n\r\n", 2)
	}
	if len(parts) != 2 {
		t.Fatalf("failed to split frontmatter and body on disk")
	}
	diskBody := strings.TrimRight(parts[1], "\r\n")
	expectedBody := strings.TrimRight(comprehensiveMarkdownBody, "\r\n")
	if diskBody != expectedBody {
		t.Fatalf("disk body does not match input exactly! Diff: disk length %d vs input length %d", len(diskBody), len(expectedBody))
	}

	// 4. Update note: change title and body, add tag
	updatedBody := comprehensiveMarkdownBody + "\n\n新增更新行：实机落盘测试成功。"
	updated, err := svc.UpdateNote(UpdateNoteInput{
		ID:    created.ID,
		Title: "实机测试：综合语法与排版验证 (已更新)",
		Tags:  []string{"测试", "Markdown", "实机验证", "已完成"},
		Body:  updatedBody,
	})
	if err != nil {
		t.Fatalf("UpdateNote failed: %v", err)
	}
	if updated.Title != "实机测试：综合语法与排版验证 (已更新)" {
		t.Fatalf("unexpected updated title: %q", updated.Title)
	}
	if len(updated.Tags) != 4 {
		t.Fatalf("expected 4 tags, got %d", len(updated.Tags))
	}

	// 5. Verify created_at is preserved and updated_at has advanced
	if updated.CreatedAt != created.CreatedAt {
		t.Fatalf("created_at was modified! original: %s, updated: %s", created.CreatedAt, updated.CreatedAt)
	}
	if !updated.UpdatedAt.After(created.UpdatedAt) && !updated.UpdatedAt.Equal(created.UpdatedAt) {
		t.Fatalf("updated_at (%v) should be >= original updated_at (%v)", updated.UpdatedAt, created.UpdatedAt)
	}

	// 6. Verify updated title and body are persisted to the disk file
	newFiles, err := os.ReadDir(notesDir)
	if err != nil {
		t.Fatalf("failed to re-read notes dir: %v", err)
	}
	if len(newFiles) != 1 {
		t.Fatalf("expected exactly 1 note file, got %d", len(newFiles))
	}
	updatedDiskBytes, err := os.ReadFile(filepath.Join(notesDir, newFiles[0].Name()))
	if err != nil {
		t.Fatalf("failed to read updated file: %v", err)
	}
	updatedDiskContent := string(updatedDiskBytes)
	if !strings.Contains(updatedDiskContent, "title: 实机测试：综合语法与排版验证 (已更新)\n") {
		t.Fatalf("updated title not found in disk frontmatter")
	}
	if !strings.Contains(updatedDiskContent, "新增更新行：实机落盘测试成功。") {
		t.Fatalf("updated body line not found on disk")
	}
}

// TestNoteEditor_AudioTranscriptNoteProtection tests that audio transcript notes
// keep their audio metadata and transcript body intact.
func TestAcceptance_NoteEditor_AudioTranscriptNoteProtection(t *testing.T) {
	tmpDir, err := os.MkdirTemp("", "pata-audio-note-vault-*")
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

	// Create a dummy audio file outside vault
	sourceAudio := filepath.Join(tmpDir, "meeting.m4a")
	if err := os.WriteFile(sourceAudio, []byte("fake m4a content header"), 0644); err != nil {
		t.Fatal(err)
	}

	audioNote, err := svc.CreateAudioNote(sourceAudio)
	if err != nil {
		t.Fatalf("CreateAudioNote failed: %v", err)
	}
	if !audioNote.AudioTranscript {
		t.Fatalf("expected AudioTranscript == true")
	}
	if !strings.HasPrefix(audioNote.AudioFile, "files/meeting") {
		t.Fatalf("expected AudioFile in files/, got %q", audioNote.AudioFile)
	}

	// Update title and tags on audio transcript note
	updated, err := svc.UpdateNote(UpdateNoteInput{
		ID:    audioNote.ID,
		Title: "产品例会音频逐字稿 (已更名)",
		Tags:  []string{"语音", "逐字稿"},
		Body:  audioNote.Body,
	})
	if err != nil {
		t.Fatalf("UpdateNote failed: %v", err)
	}

	// Verify audio metadata preserved after update
	fetched, err := svc.GetNote(updated.ID)
	if err != nil {
		t.Fatalf("GetNote failed: %v", err)
	}
	if !fetched.AudioTranscript {
		t.Fatalf("expected AudioTranscript == true after update")
	}
	if fetched.AudioFile != audioNote.AudioFile {
		t.Fatalf("expected AudioFile preserved, got %q", fetched.AudioFile)
	}
	if fetched.Title != "产品例会音频逐字稿 (已更名)" {
		t.Fatalf("expected updated title, got %q", fetched.Title)
	}
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}
