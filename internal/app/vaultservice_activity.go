package app

import (
	"fmt"
	"strings"
	"time"

	"pata/internal/storage/markdown"
)

// CreateActivityInput defines parameters for creating an Activity.
type CreateActivityInput struct {
	OwnerType markdown.EntityType `json:"owner_type,omitempty"` // "task" | "day_plan"
	TaskID    string              `json:"task_id,omitempty"`    // if owner is task
	Date      string              `json:"date,omitempty"`       // if owner is day_plan (YYYY-MM-DD)
	At        *time.Time          `json:"at,omitempty"`
	Body      string              `json:"body"`
	Tags      []string            `json:"tags,omitempty"`
	NoteRefs  map[string]string   `json:"note_refs,omitempty"`
}

// UpdateActivityInput defines parameters for updating an existing Activity by its ID.
type UpdateActivityInput struct {
	ID       string            `json:"id"`
	Body     string            `json:"body"`
	Tags     []string          `json:"tags,omitempty"`
	NoteRefs map[string]string `json:"note_refs,omitempty"`
}

// CreateActivity creates an activity embedded inside a Task or DayPlan.
func (s *VaultService) CreateActivity(input CreateActivityInput) (*markdown.Activity, error) {
	return s.createActivity(input, "")
}

func (s *VaultService) createActivity(input CreateActivityInput, by string) (*markdown.Activity, error) {
	s.mu.Lock()
	v := s.vault
	s.mu.Unlock()
	if v == nil {
		return nil, fmt.Errorf("尚未打开 Vault")
	}
	v.MutationMu.Lock()
	defer v.MutationMu.Unlock()

	body := strings.TrimSpace(input.Body)
	if body == "" {
		return nil, fmt.Errorf("Activity 正文不能为空")
	}

	taskID := strings.TrimSpace(input.TaskID)
	date := strings.TrimSpace(input.Date)

	at := time.Now().UTC()
	if input.At != nil && !input.At.IsZero() {
		at = input.At.UTC()
	} else if date != "" && taskID == "" {
		if d, err := time.ParseInLocation("2006-01-02", date, time.Local); err == nil {
			now := time.Now().In(time.Local)
			combined := time.Date(d.Year(), d.Month(), d.Day(), now.Hour(), now.Minute(), now.Second(), now.Nanosecond(), time.Local)
			at = combined.UTC()
		}
	}

	act := markdown.Activity{
		ID:       markdown.GenerateActivityID(),
		At:       at,
		By:       by,
		Tags:     cleanTags(input.Tags),
		NoteRefs: cleanNoteRefs(input.NoteRefs),
		Body:     input.Body,
	}

	// Determine owner: Task vs DayPlan
	if taskID != "" || input.OwnerType == markdown.EntityTypeTask {
		if taskID == "" {
			return nil, fmt.Errorf("任务 ID 不能为空")
		}
		task, ok := v.Index.GetTask(taskID)
		if !ok {
			return nil, fmt.Errorf("任务不存在: %s", taskID)
		}
		task.Activities = append(task.Activities, act)
		task.UpdatedAt = time.Now()
		baseline := taskBaseline(v, task)
		if _, err := v.SaveEntity(task, baseline); err != nil {
			return nil, err
		}
		return &act, nil
	}

	// DayPlan owner
	if date == "" {
		date = at.In(time.Local).Format("2006-01-02")
	}
	if _, err := time.Parse("2006-01-02", date); err != nil {
		return nil, fmt.Errorf("无效的日期格式: %s (必须为 YYYY-MM-DD)", date)
	}

	plan, exists := v.Index.GetDayPlan(date)
	var baseline *markdown.FileBaseline
	if exists {
		baseline = dayPlanBaseline(v, plan)
		plan.Activities = append(plan.Activities, act)
	} else {
		plan = &markdown.DayPlan{
			Type:       markdown.EntityTypeDayPlan,
			Date:       date,
			TaskIDs:    []string{},
			Activities: []markdown.Activity{act},
		}
	}

	if _, err := v.SaveEntity(plan, baseline); err != nil {
		return nil, err
	}

	return &act, nil
}

// UpdateActivity updates an existing Activity's body, tags, and note refs in its host Task or DayPlan.
func (s *VaultService) UpdateActivity(input UpdateActivityInput) (*markdown.Activity, error) {
	s.mu.Lock()
	v := s.vault
	s.mu.Unlock()
	if v == nil {
		return nil, fmt.Errorf("尚未打开 Vault")
	}
	v.MutationMu.Lock()
	defer v.MutationMu.Unlock()

	id := strings.TrimSpace(input.ID)
	if id == "" {
		return nil, fmt.Errorf("Activity ID 不能为空")
	}

	body := strings.TrimSpace(input.Body)
	if body == "" {
		return nil, fmt.Errorf("Activity 正文不能为空")
	}

	_, loc, ok := v.Index.GetActivity(id)
	if !ok {
		return nil, fmt.Errorf("Activity 不存在: %s", id)
	}

	cleanedTags := cleanTags(input.Tags)

	switch loc.OwnerType {
	case markdown.EntityTypeTask:
		task, ok := v.Index.GetTask(loc.OwnerID)
		if !ok {
			return nil, fmt.Errorf("任务不存在: %s", loc.OwnerID)
		}
		var updated *markdown.Activity
		for i := range task.Activities {
			if task.Activities[i].ID == id {
				task.Activities[i].Body = input.Body
				task.Activities[i].Tags = cleanedTags
				if input.NoteRefs != nil {
					task.Activities[i].NoteRefs = cleanNoteRefs(input.NoteRefs)
				}
				updated = &task.Activities[i]
				break
			}
		}
		if updated == nil {
			return nil, fmt.Errorf("Activity 不存在: %s", id)
		}
		task.UpdatedAt = time.Now()
		baseline := taskBaseline(v, task)
		if _, err := v.SaveEntity(task, baseline); err != nil {
			return nil, err
		}
		return updated, nil

	case markdown.EntityTypeDayPlan:
		plan, ok := v.Index.GetDayPlan(loc.OwnerID)
		if !ok {
			return nil, fmt.Errorf("日计划不存在: %s", loc.OwnerID)
		}
		var updated *markdown.Activity
		for i := range plan.Activities {
			if plan.Activities[i].ID == id {
				plan.Activities[i].Body = input.Body
				plan.Activities[i].Tags = cleanedTags
				if input.NoteRefs != nil {
					plan.Activities[i].NoteRefs = cleanNoteRefs(input.NoteRefs)
				}
				updated = &plan.Activities[i]
				break
			}
		}
		if updated == nil {
			return nil, fmt.Errorf("Activity 不存在: %s", id)
		}
		baseline := dayPlanBaseline(v, plan)
		if _, err := v.SaveEntity(plan, baseline); err != nil {
			return nil, err
		}
		return updated, nil

	default:
		return nil, fmt.Errorf("未知的宿主类型: %s", loc.OwnerType)
	}
}

// DeleteActivity deletes an Activity from its host Task or DayPlan.
func (s *VaultService) DeleteActivity(id string) error {
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
		return fmt.Errorf("Activity ID 不能为空")
	}

	_, loc, ok := v.Index.GetActivity(trimmedID)
	if !ok {
		return fmt.Errorf("Activity 不存在: %s", trimmedID)
	}

	switch loc.OwnerType {
	case markdown.EntityTypeTask:
		task, ok := v.Index.GetTask(loc.OwnerID)
		if !ok {
			return fmt.Errorf("任务不存在: %s", loc.OwnerID)
		}
		filtered := make([]markdown.Activity, 0, len(task.Activities))
		for _, a := range task.Activities {
			if a.ID != trimmedID {
				filtered = append(filtered, a)
			}
		}
		task.Activities = filtered
		task.UpdatedAt = time.Now()
		baseline := taskBaseline(v, task)
		_, err := v.SaveEntity(task, baseline)
		return err

	case markdown.EntityTypeDayPlan:
		plan, ok := v.Index.GetDayPlan(loc.OwnerID)
		if !ok {
			return fmt.Errorf("日计划不存在: %s", loc.OwnerID)
		}
		filtered := make([]markdown.Activity, 0, len(plan.Activities))
		for _, a := range plan.Activities {
			if a.ID != trimmedID {
				filtered = append(filtered, a)
			}
		}
		plan.Activities = filtered
		baseline := dayPlanBaseline(v, plan)
		_, err := v.SaveEntity(plan, baseline)
		return err

	default:
		return fmt.Errorf("未知的宿主类型: %s", loc.OwnerType)
	}
}

// GetActivity returns an activity by its ID.
func (s *VaultService) GetActivity(id string) (*markdown.Activity, error) {
	s.mu.Lock()
	v := s.vault
	s.mu.Unlock()
	if v == nil {
		return nil, fmt.Errorf("尚未打开 Vault")
	}

	trimmedID := strings.TrimSpace(id)
	if trimmedID == "" {
		return nil, fmt.Errorf("Activity ID 不能为空")
	}

	act, loc, ok := v.Index.GetActivity(trimmedID)
	if !ok {
		return nil, fmt.Errorf("Activity 不存在: %s", trimmedID)
	}
	cp := act.Clone()
	if loc.OwnerType == markdown.EntityTypeTask {
		cp.TaskID = loc.OwnerID
	}
	return &cp, nil
}

// ListActivitiesByTask returns all activities of a task sorted chronologically by At.
func (s *VaultService) ListActivitiesByTask(taskID string) ([]markdown.Activity, error) {
	s.mu.Lock()
	v := s.vault
	s.mu.Unlock()
	if v == nil {
		return nil, fmt.Errorf("尚未打开 Vault")
	}
	return v.Index.ListActivitiesByTask(taskID), nil
}
