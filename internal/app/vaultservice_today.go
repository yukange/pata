package app

import (
	"fmt"
	"sort"
	"strings"
	"time"

	"pata/internal/storage/markdown"
)

// TimelineItem represents an aggregated activity or task lifecycle event.
type TimelineItem struct {
	Key       string             `json:"key"`
	By        string             `json:"by,omitempty"`
	Kind      string             `json:"kind"` // "creation" | "activity" | "completion" | "reopen"
	Time      time.Time          `json:"time"`
	Activity  *markdown.Activity `json:"activity,omitempty"`
	TaskID    string             `json:"task_id,omitempty"`
	TaskTitle string             `json:"task_title,omitempty"`
}

// GetDayPlan returns the DayPlan for a date. If no plan exists, an empty DayPlan is returned without error.
func (s *VaultService) GetDayPlan(date string) (*markdown.DayPlan, error) {
	s.mu.Lock()
	v := s.vault
	s.mu.Unlock()
	if v == nil {
		return nil, fmt.Errorf("尚未打开 Vault")
	}

	trimmedDate := strings.TrimSpace(date)
	if _, err := time.Parse("2006-01-02", trimmedDate); err != nil {
		return nil, fmt.Errorf("无效的日期格式: %s (必须为 YYYY-MM-DD)", date)
	}

	if plan, ok := v.Index.GetDayPlan(trimmedDate); ok {
		if plan.TaskIDs == nil {
			plan.TaskIDs = []string{}
		}
		return plan, nil
	}

	return &markdown.DayPlan{
		Type:    markdown.EntityTypeDayPlan,
		Date:    trimmedDate,
		TaskIDs: []string{},
	}, nil
}

// SaveDayPlan creates or updates a DayPlan for a date with an ordered list of task IDs.
func (s *VaultService) SaveDayPlan(date string, taskIDs []string) (*markdown.DayPlan, error) {
	s.mu.Lock()
	v := s.vault
	s.mu.Unlock()
	if v == nil {
		return nil, fmt.Errorf("尚未打开 Vault")
	}
	v.MutationMu.Lock()
	defer v.MutationMu.Unlock()

	trimmedDate := strings.TrimSpace(date)
	if _, err := time.Parse("2006-01-02", trimmedDate); err != nil {
		return nil, fmt.Errorf("无效的日期格式: %s (必须为 YYYY-MM-DD)", date)
	}

	cleanedTaskIDs := make([]string, len(taskIDs))
	for i, tid := range taskIDs {
		id := strings.TrimSpace(tid)
		if id == "" {
			return nil, fmt.Errorf("任务 ID 不能为空")
		}
		if _, ok := v.Index.GetTask(id); !ok {
			return nil, fmt.Errorf("任务不存在: %s", id)
		}
		cleanedTaskIDs[i] = id
	}

	existing, exists := v.Index.GetDayPlan(trimmedDate)
	var baseline *markdown.FileBaseline
	var plan *markdown.DayPlan
	if exists {
		baseline = dayPlanBaseline(v, existing)
		existing.TaskIDs = cleanedTaskIDs
		plan = existing
	} else {
		plan = &markdown.DayPlan{
			Type:    markdown.EntityTypeDayPlan,
			Date:    trimmedDate,
			TaskIDs: cleanedTaskIDs,
		}
	}

	if _, err := v.SaveEntity(plan, baseline); err != nil {
		return nil, err
	}

	return plan, nil
}

// dayPlanBaseline looks up the baseline for a day plan directly from the memory index.
func dayPlanBaseline(v *markdown.Vault, plan *markdown.DayPlan) *markdown.FileBaseline {
	path := v.ResolveEntityPath(plan)
	if b, ok := v.Index.GetBaseline(path); ok {
		return &b
	}
	return nil
}

// GetDayTimeline returns activities and task lifecycle events for a YYYY-MM-DD date in local timezone.
func (s *VaultService) GetDayTimeline(date string) ([]TimelineItem, error) {
	s.mu.Lock()
	v := s.vault
	s.mu.Unlock()
	if v == nil {
		return nil, fmt.Errorf("尚未打开 Vault")
	}

	trimmedDate := strings.TrimSpace(date)
	if _, err := time.Parse("2006-01-02", trimmedDate); err != nil {
		return nil, fmt.Errorf("无效的日期格式: %s (必须为 YYYY-MM-DD)", date)
	}

	var items []TimelineItem
	tasks := v.Index.ListTasks()
	taskMap := make(map[string]*markdown.Task, len(tasks))
	for _, t := range tasks {
		taskMap[t.ID] = t
	}

	// Keys break timestamp ties in the same order as frontend/src/taskTimeline.ts.
	// 1. Task lifecycle events, independent of daily plan membership.
	for _, t := range tasks {
		if t.CreatedAt.In(time.Local).Format("2006-01-02") == trimmedDate {
			items = append(items, TimelineItem{
				Key: "0-created-" + t.ID, Kind: "creation", Time: t.CreatedAt,
				By: t.CreatedBy, TaskID: t.ID, TaskTitle: t.Title,
			})
		}
		hasCompletion := false
		for idx, ev := range t.StatusEvents {
			kind := "completion"
			if ev.Action == markdown.StatusEventActionReopened {
				kind = "reopen"
			} else if ev.Action != markdown.StatusEventActionCompleted {
				continue
			}
			if kind == "completion" && t.CompletedAt != nil && ev.At.Equal(*t.CompletedAt) {
				hasCompletion = true
			}
			if ev.At.In(time.Local).Format("2006-01-02") == trimmedDate {
				items = append(items, TimelineItem{
					Key:       fmt.Sprintf("1-status-%s-%09d", t.ID, idx),
					By:        ev.By,
					Kind:      kind,
					Time:      ev.At,
					TaskID:    t.ID,
					TaskTitle: t.Title,
				})
			}
		}
		// If task is completed and completed_at falls on this date, but not captured in status_events, include it
		if !hasCompletion && t.Status == markdown.TaskStatusDone && t.CompletedAt != nil {
			if t.CompletedAt.In(time.Local).Format("2006-01-02") == trimmedDate {
				items = append(items, TimelineItem{
					Key:       fmt.Sprintf("1-status-%s-%09d", t.ID, len(t.StatusEvents)),
					Kind:      "completion",
					Time:      *t.CompletedAt,
					TaskID:    t.ID,
					TaskTitle: t.Title,
				})
			}
		}
	}

	// 2. Task embedded activities whose local date matches
	for _, t := range tasks {
		for _, act := range t.Activities {
			localDate := act.At.In(time.Local).Format("2006-01-02")
			if localDate == trimmedDate {
				actClone := act.Clone()
				items = append(items, TimelineItem{
					Key:       "2-activity-" + act.ID,
					Kind:      "activity",
					Time:      act.At,
					Activity:  &actClone,
					TaskID:    t.ID,
					TaskTitle: t.Title,
				})
			}
		}
	}

	// 3. DayPlan independent activities whose date matches
	if plan, ok := v.Index.GetDayPlan(trimmedDate); ok {
		for _, act := range plan.Activities {
			actClone := act.Clone()
			items = append(items, TimelineItem{
				Key:      "2-activity-" + act.ID,
				Kind:     "activity",
				Time:     act.At,
				Activity: &actClone,
			})
		}
	}

	// Sort descending by Time (newest -> oldest)
	sort.Slice(items, func(i, j int) bool {
		if items[i].Time.Equal(items[j].Time) {
			return items[i].Key > items[j].Key
		}
		return items[i].Time.After(items[j].Time)
	})

	if items == nil {
		return []TimelineItem{}, nil
	}
	return items, nil
}
