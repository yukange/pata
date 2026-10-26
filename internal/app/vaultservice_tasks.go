package app

import (
	"fmt"
	"strings"
	"time"

	"pata/internal/storage/markdown"
)

// CreateTaskInput defines parameters for creating a new Task.
type CreateTaskInput struct {
	Title       string              `json:"title"`
	Description string              `json:"description,omitempty"`
	Status      markdown.TaskStatus `json:"status,omitempty"`
	Due         *string             `json:"due,omitempty"`
	Tags        []string            `json:"tags,omitempty"`
	NoteIDs     []string            `json:"note_ids,omitempty"`
	Body        string              `json:"body,omitempty"`
	// NoteRefs binds [[名称]] in Description to real Note IDs.
	NoteRefs map[string]string `json:"note_refs,omitempty"`
}

// UpdateTaskInput defines parameters for updating an existing Task.
type UpdateTaskInput struct {
	ID          string              `json:"id"`
	Title       string              `json:"title"`
	Description string              `json:"description,omitempty"`
	Status      markdown.TaskStatus `json:"status"`
	Due         *string             `json:"due"`
	Tags        []string            `json:"tags,omitempty"`
	NoteIDs     []string            `json:"note_ids,omitempty"`
	Body        string              `json:"body,omitempty"`
	// NoteRefs: nil keeps existing bindings; non-nil (even empty) replaces them.
	NoteRefs map[string]string `json:"note_refs,omitempty"`
}

// ListTasks returns all tasks from the vault index, newest first.
func (s *VaultService) ListTasks() ([]*markdown.Task, error) {
	s.mu.Lock()
	v := s.vault
	s.mu.Unlock()
	if v == nil {
		return nil, fmt.Errorf("尚未打开 Vault")
	}
	return v.Index.ListTasks(), nil
}

// GetTask returns a task by its ID.
func (s *VaultService) GetTask(id string) (*markdown.Task, error) {
	s.mu.Lock()
	v := s.vault
	s.mu.Unlock()
	if v == nil {
		return nil, fmt.Errorf("尚未打开 Vault")
	}

	if strings.TrimSpace(id) == "" {
		return nil, fmt.Errorf("任务 ID 不能为空")
	}

	task, ok := v.Index.GetTask(id)
	if !ok {
		return nil, fmt.Errorf("任务不存在: %s", id)
	}
	return task, nil
}

// CreateTask creates a new Task, writes it safely as Markdown, and updates the index.
func (s *VaultService) CreateTask(input CreateTaskInput) (*markdown.Task, error) {
	return s.createTask(input, "")
}

func (s *VaultService) createTask(input CreateTaskInput, by string) (*markdown.Task, error) {
	s.mu.Lock()
	v := s.vault
	s.mu.Unlock()
	if v == nil {
		return nil, fmt.Errorf("尚未打开 Vault")
	}
	v.MutationMu.Lock()
	defer v.MutationMu.Unlock()

	title := strings.TrimSpace(input.Title)
	if title == "" {
		return nil, fmt.Errorf("任务标题不能为空")
	}

	status := input.Status
	if status == "" || status == markdown.TaskStatusDoing {
		status = markdown.TaskStatusTodo
	}
	if status != markdown.TaskStatusTodo && status != markdown.TaskStatusDone {
		return nil, fmt.Errorf("无效的任务状态: %s (必须为 todo 或 done)", status)
	}

	cleanedNoteIDs, err := validateAndCleanNoteIDs(v, input.NoteIDs)
	if err != nil {
		return nil, err
	}

	var due *string
	if input.Due != nil && strings.TrimSpace(*input.Due) != "" {
		d := strings.TrimSpace(*input.Due)
		due = &d
	}

	desc := input.Description
	if desc == "" && input.Body != "" {
		desc = input.Body
	}

	now := time.Now()
	task := &markdown.Task{
		Type:        markdown.EntityTypeTask,
		ID:          markdown.GenerateEntityID(markdown.EntityTypeTask),
		Title:       title,
		Description: desc,
		Status:      markdown.TaskStatusTodo,
		Due:         due,
		Tags:        cleanTags(input.Tags),
		NoteIDs:     cleanedNoteIDs,
		NoteRefs:    cleanNoteRefs(input.NoteRefs),
		CreatedAt:   now,
		CreatedBy:   by,
		UpdatedAt:   now,
	}

	applyTaskStatus(task, status, now, by)

	if _, err := v.SaveEntity(task, nil); err != nil {
		return nil, err
	}

	return task, nil
}

// UpdateTask updates an existing Task, safely writes changes to Markdown, and preserves unknown frontmatter and embedded activities.
func (s *VaultService) UpdateTask(input UpdateTaskInput) (*markdown.Task, error) {
	s.mu.Lock()
	v := s.vault
	s.mu.Unlock()
	if v == nil {
		return nil, fmt.Errorf("尚未打开 Vault")
	}
	v.MutationMu.Lock()
	defer v.MutationMu.Unlock()

	if strings.TrimSpace(input.ID) == "" {
		return nil, fmt.Errorf("任务 ID 不能为空")
	}

	title := strings.TrimSpace(input.Title)
	if title == "" {
		return nil, fmt.Errorf("任务标题不能为空")
	}

	status := input.Status
	if status == markdown.TaskStatusDoing {
		status = markdown.TaskStatusTodo
	}
	if status != markdown.TaskStatusTodo && status != markdown.TaskStatusDone {
		return nil, fmt.Errorf("无效的任务状态: %s (必须为 todo 或 done)", status)
	}

	existing, ok := v.Index.GetTask(input.ID)
	if !ok {
		return nil, fmt.Errorf("任务不存在: %s", input.ID)
	}

	cleanedNoteIDs, err := validateAndCleanNoteIDs(v, input.NoteIDs)
	if err != nil {
		return nil, err
	}

	now := time.Now()
	applyTaskStatus(existing, status, now, "")

	var due *string
	if input.Due != nil && strings.TrimSpace(*input.Due) != "" {
		d := strings.TrimSpace(*input.Due)
		due = &d
	}

	existing.Title = title
	existing.Status = status
	existing.Due = due
	existing.Tags = cleanTags(input.Tags)
	existing.NoteIDs = cleanedNoteIDs
	if input.NoteRefs != nil {
		existing.NoteRefs = cleanNoteRefs(input.NoteRefs)
	}
	if input.Description != "" {
		existing.Description = input.Description
	} else if input.Body != "" {
		existing.Description = input.Body
	} else {
		existing.Description = ""
	}
	existing.UpdatedAt = now

	// SaveEntity preserves Extra (unknown frontmatter) and serializes embedded activities
	baseline := taskBaseline(v, existing)
	if _, err := v.SaveEntity(existing, baseline); err != nil {
		return nil, err
	}

	return existing, nil
}

// taskBaseline looks up the baseline for an entity directly from the memory index.
func taskBaseline(v *markdown.Vault, task *markdown.Task) *markdown.FileBaseline {
	path := v.ResolveEntityPath(task)
	if b, ok := v.Index.GetBaseline(path); ok {
		return &b
	}
	return nil
}

// SetTaskStatus toggles or updates the status of a Task with completion/reopen event semantics.
func (s *VaultService) SetTaskStatus(id string, status markdown.TaskStatus) (*markdown.Task, error) {
	return s.setTaskStatus(id, status, "")
}

func (s *VaultService) setTaskStatus(id string, status markdown.TaskStatus, by string) (*markdown.Task, error) {
	s.mu.Lock()
	v := s.vault
	s.mu.Unlock()
	if v == nil {
		return nil, fmt.Errorf("尚未打开 Vault")
	}
	v.MutationMu.Lock()
	defer v.MutationMu.Unlock()

	if strings.TrimSpace(id) == "" {
		return nil, fmt.Errorf("任务 ID 不能为空")
	}

	if status == markdown.TaskStatusDoing {
		status = markdown.TaskStatusTodo
	}

	switch status {
	case markdown.TaskStatusTodo, markdown.TaskStatusDone:
		// valid
	default:
		return nil, fmt.Errorf("无效的任务状态: %s (必须为 todo 或 done)", status)
	}

	existing, ok := v.Index.GetTask(id)
	if !ok {
		return nil, fmt.Errorf("任务不存在: %s", id)
	}

	if existing.Status == status {
		return existing, nil
	}

	now := time.Now()
	applyTaskStatus(existing, status, now, by)
	existing.UpdatedAt = now

	baseline := taskBaseline(v, existing)
	if _, err := v.SaveEntity(existing, baseline); err != nil {
		return nil, err
	}

	return existing, nil
}

func applyTaskStatus(task *markdown.Task, status markdown.TaskStatus, at time.Time, by string) {
	if task.Status != status {
		action := markdown.StatusEventActionReopened
		if status == markdown.TaskStatusDone {
			action = markdown.StatusEventActionCompleted
			task.CompletedAt = &at
		} else {
			task.CompletedAt = nil
		}
		task.StatusEvents = append(task.StatusEvents, markdown.StatusEvent{Action: action, At: at, By: by})
	} else if status == markdown.TaskStatusDone && task.CompletedAt == nil {
		task.CompletedAt = &at
	}
	task.Status = status
}

// DeleteTask deletes a task from disk and updates the index, cascading deletion to all its embedded activities
// and removing references to this task from all day plans.
func (s *VaultService) DeleteTask(id string) error {
	s.mu.Lock()
	v := s.vault
	s.mu.Unlock()
	if v == nil {
		return fmt.Errorf("尚未打开 Vault")
	}
	v.MutationMu.Lock()
	defer v.MutationMu.Unlock()

	trimmedID := strings.TrimSpace(id)
	if trimmedID == "" {
		return fmt.Errorf("任务 ID 不能为空")
	}

	if _, ok := v.Index.GetTask(trimmedID); !ok {
		return fmt.Errorf("任务不存在: %s", trimmedID)
	}

	if err := v.DeleteEntity(trimmedID); err != nil {
		return err
	}

	// Clean up task ID from all DayPlans (cascade cleanup)
	var cleanupErrors []string
	for _, dp := range v.Index.ListDayPlans() {
		newIDs := make([]string, 0, len(dp.TaskIDs))
		changed := false
		for _, tid := range dp.TaskIDs {
			if tid == trimmedID {
				changed = true
			} else {
				newIDs = append(newIDs, tid)
			}
		}
		if changed {
			dpClone := dp.Clone().(*markdown.DayPlan)
			dpClone.TaskIDs = newIDs
			baseline := dayPlanBaseline(v, dpClone)
			if _, err := v.SaveEntity(dpClone, baseline); err != nil {
				cleanupErrors = append(cleanupErrors, fmt.Sprintf("%s: %v", dp.Date, err))
			}
		}
	}

	if len(cleanupErrors) > 0 {
		return fmt.Errorf("任务已删除，但部分日计划引用清理失败: %s", strings.Join(cleanupErrors, "; "))
	}

	return nil
}
