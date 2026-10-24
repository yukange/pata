package markdown

import (
	"fmt"
	"path/filepath"
	"strings"
	"time"
)

// ValidationError represents a schema validation error with context.
type ValidationError struct {
	Path   string `json:"path"`
	Field  string `json:"field"`
	Reason string `json:"reason"`
}

func (e *ValidationError) Error() string {
	if e.Path != "" {
		return fmt.Sprintf("validation error at %s: field '%s' %s", e.Path, e.Field, e.Reason)
	}
	return fmt.Sprintf("validation error: field '%s' %s", e.Field, e.Reason)
}

// ValidateEntity validates an entity against strict schema invariants.
func ValidateEntity(filePath string, entity Entity) error {
	if entity == nil {
		return &ValidationError{Path: filePath, Field: "entity", Reason: "cannot be nil"}
	}

	switch e := entity.(type) {
	case *Task:
		return validateTask(filePath, e)
	case *Note:
		return validateNote(filePath, e)
	case *DayPlan:
		return validateDayPlan(filePath, e)
	default:
		return &ValidationError{
			Path:   filePath,
			Field:  "type",
			Reason: fmt.Sprintf("unsupported entity type %T", entity),
		}
	}
}

func validateTask(path string, t *Task) error {
	if err := validateSource(path, "created_by", t.CreatedBy); err != nil {
		return err
	}
	if strings.TrimSpace(t.ID) == "" {
		return &ValidationError{Path: path, Field: "id", Reason: "is required"}
	}
	if strings.TrimSpace(t.Title) == "" {
		return &ValidationError{Path: path, Field: "title", Reason: "is required"}
	}

	switch t.Status {
	case TaskStatusTodo, TaskStatusDone, TaskStatusDoing:
		// valid (TaskStatusDoing allowed for backward compatibility)
	default:
		return &ValidationError{
			Path:   path,
			Field:  "status",
			Reason: fmt.Sprintf("must be one of 'todo', 'done'; got '%s'", t.Status),
		}
	}

	if t.CompletedAt != nil && t.CompletedAt.IsZero() {
		return &ValidationError{
			Path:   path,
			Field:  "completed_at",
			Reason: "must be valid RFC3339 timestamp or null",
		}
	}

	if t.Due != nil && *t.Due != "" {
		if err := validateDateFormat(*t.Due); err != nil {
			return &ValidationError{
				Path:   path,
				Field:  "due",
				Reason: fmt.Sprintf("must be YYYY-MM-DD or null; got '%s'", *t.Due),
			}
		}
	}

	if t.CreatedAt.IsZero() {
		return &ValidationError{Path: path, Field: "created_at", Reason: "is required and must be valid RFC3339 timestamp"}
	}
	if t.UpdatedAt.IsZero() {
		return &ValidationError{Path: path, Field: "updated_at", Reason: "is required and must be valid RFC3339 timestamp"}
	}

	for i, tag := range t.Tags {
		if strings.Contains(tag, "#") {
			return &ValidationError{
				Path:   path,
				Field:  fmt.Sprintf("tags[%d]", i),
				Reason: fmt.Sprintf("must not contain '#'; got '%s'", tag),
			}
		}
	}

	for i, ev := range t.StatusEvents {
		if err := validateSource(path, fmt.Sprintf("status_events[%d].by", i), ev.By); err != nil {
			return err
		}
		switch ev.Action {
		case StatusEventActionCompleted, StatusEventActionReopened:
			// valid
		default:
			return &ValidationError{
				Path:   path,
				Field:  fmt.Sprintf("status_events[%d].action", i),
				Reason: fmt.Sprintf("must be 'completed' or 'reopened'; got '%s'", ev.Action),
			}
		}
		if ev.At.IsZero() {
			return &ValidationError{
				Path:   path,
				Field:  fmt.Sprintf("status_events[%d].at", i),
				Reason: "must be valid RFC3339 timestamp",
			}
		}
	}

	if err := validateActivities(path, t.Activities); err != nil {
		return err
	}

	return nil
}

func validateNote(path string, n *Note) error {
	if err := validateSource(path, "created_by", n.CreatedBy); err != nil {
		return err
	}
	if strings.TrimSpace(n.ID) == "" {
		return &ValidationError{Path: path, Field: "id", Reason: "is required"}
	}
	if strings.TrimSpace(n.Title) == "" {
		return &ValidationError{Path: path, Field: "title", Reason: "is required"}
	}
	if n.CreatedAt.IsZero() {
		return &ValidationError{Path: path, Field: "created_at", Reason: "is required and must be valid RFC3339 timestamp"}
	}
	if n.UpdatedAt.IsZero() {
		return &ValidationError{Path: path, Field: "updated_at", Reason: "is required and must be valid RFC3339 timestamp"}
	}
	for i, tag := range n.Tags {
		if strings.Contains(tag, "#") {
			return &ValidationError{
				Path:   path,
				Field:  fmt.Sprintf("tags[%d]", i),
				Reason: fmt.Sprintf("must not contain '#'; got '%s'", tag),
			}
		}
	}
	if n.AudioTranscript && strings.TrimSpace(n.AudioFile) == "" {
		return &ValidationError{
			Path:   path,
			Field:  "audio_file",
			Reason: "audio_file must be specified when audio_transcript is true",
		}
	}
	if n.AudioFile != "" {
		cleaned := filepath.Clean(filepath.ToSlash(n.AudioFile))
		if strings.HasPrefix(cleaned, "../") || cleaned == ".." || filepath.IsAbs(cleaned) {
			return &ValidationError{
				Path:   path,
				Field:  "audio_file",
				Reason: fmt.Sprintf("must be a valid vault-relative path; got '%s'", n.AudioFile),
			}
		}
	}
	return nil
}

func validateDayPlan(path string, p *DayPlan) error {
	if err := validateDateFormat(p.Date); err != nil {
		return &ValidationError{
			Path:   path,
			Field:  "date",
			Reason: fmt.Sprintf("must be YYYY-MM-DD; got '%s'", p.Date),
		}
	}

	// Invariant: no duplicate task IDs in the same DayPlan
	seen := make(map[string]bool, len(p.TaskIDs))
	for i, taskID := range p.TaskIDs {
		if strings.TrimSpace(taskID) == "" {
			return &ValidationError{
				Path:   path,
				Field:  fmt.Sprintf("task_ids[%d]", i),
				Reason: "task id cannot be empty",
			}
		}
		if seen[taskID] {
			return &ValidationError{
				Path:   path,
				Field:  "task_ids",
				Reason: fmt.Sprintf("duplicate task id '%s' violated DayPlan invariant", taskID),
			}
		}
		seen[taskID] = true
	}

	if err := validateActivities(path, p.Activities); err != nil {
		return err
	}

	return nil
}

func validateActivities(path string, activities []Activity) error {
	seen := make(map[string]bool, len(activities))
	for i, act := range activities {
		if err := validateSource(path, fmt.Sprintf("activities[%d].by", i), act.By); err != nil {
			return err
		}
		id := strings.TrimSpace(act.ID)
		if id == "" {
			return &ValidationError{Path: path, Field: fmt.Sprintf("activities[%d].id", i), Reason: "is required"}
		}
		if !strings.HasPrefix(id, "a-") || len(id) <= 2 {
			return &ValidationError{Path: path, Field: fmt.Sprintf("activities[%d].id", i), Reason: fmt.Sprintf("must start with 'a-'; got '%s'", id)}
		}
		if act.At.IsZero() {
			return &ValidationError{Path: path, Field: fmt.Sprintf("activities[%d].at", i), Reason: "is required and must be valid RFC3339 timestamp"}
		}
		if seen[id] {
			return &ValidationError{Path: path, Field: fmt.Sprintf("activities[%d].id", i), Reason: fmt.Sprintf("duplicate activity ID '%s' in same entity", id)}
		}
		seen[id] = true
		for j, tag := range act.Tags {
			if strings.Contains(tag, "#") {
				return &ValidationError{Path: path, Field: fmt.Sprintf("activities[%d].tags[%d]", i, j), Reason: fmt.Sprintf("must not contain '#'; got '%s'", tag)}
			}
		}
	}
	return nil
}

func validateSource(path, field, source string) error {
	if source != "" && source != SourceAgent {
		return &ValidationError{Path: path, Field: field, Reason: "must be 'agent' or omitted"}
	}
	return nil
}

func validateDateFormat(d string) error {
	_, err := time.Parse("2006-01-02", d)
	return err
}
