package markdown

import (
	"time"

	"gopkg.in/yaml.v3"
)

// EntityType represents the type of a Pata entity.
type EntityType string

const (
	EntityTypeTask     EntityType = "task"
	EntityTypeNote     EntityType = "note"
	EntityTypeDayPlan  EntityType = "day_plan"
	EntityTypeActivity EntityType = "activity"
	EntityTypeFile     EntityType = "file"
)

// FileResource represents an ordinary binary or document file in the files/ directory.
type FileResource struct {
	Path    string    `json:"path"`     // Vault-relative path with forward slashes (e.g. "files/doc.pdf")
	Name    string    `json:"name"`     // Base filename (e.g. "doc.pdf")
	Ext     string    `json:"ext"`      // Extension including dot (e.g. ".pdf")
	Size    int64     `json:"size"`     // File size in bytes
	ModTime time.Time `json:"mod_time"` // Last modification time
}

const SourceAgent = "agent"

// Activity represents an embedded activity inside a Task or DayPlan.
type Activity struct {
	ID       string               `yaml:"id" json:"id"`
	At       time.Time            `yaml:"at" json:"at"`
	By       string               `yaml:"by,omitempty" json:"by,omitempty"`
	Tags     []string             `yaml:"tags,omitempty" json:"tags,omitempty"`
	NoteRefs map[string]string    `yaml:"note_refs,omitempty" json:"note_refs,omitempty"`
	Body     string               `yaml:"-" json:"body"`
	TaskID   string               `yaml:"-" json:"task_id,omitempty"`
	Extra    map[string]yaml.Node `yaml:",inline" json:"-"`
}

func (a *Activity) Clone() Activity {
	cp := *a
	if a.Tags != nil {
		cp.Tags = append([]string(nil), a.Tags...)
	}
	cp.NoteRefs = cloneRefs(a.NoteRefs)
	if a.Extra != nil {
		cp.Extra = make(map[string]yaml.Node, len(a.Extra))
		for k, v := range a.Extra {
			cp.Extra[k] = v
		}
	}
	return cp
}

// TaskStatus represents the current status of a task.
type TaskStatus string

const (
	TaskStatusTodo  TaskStatus = "todo"
	TaskStatusDone  TaskStatus = "done"
	TaskStatusDoing TaskStatus = "doing" // Deprecated: legacy status, treated as todo
)

// StatusEventAction represents actions recorded in task status events.
type StatusEventAction string

const (
	StatusEventActionCompleted StatusEventAction = "completed"
	StatusEventActionReopened  StatusEventAction = "reopened"
)

// StatusEvent records completion and reopen events.
type StatusEvent struct {
	Action StatusEventAction `yaml:"action" json:"action"`
	At     time.Time         `yaml:"at" json:"at"`
	By     string            `yaml:"by,omitempty" json:"by,omitempty"`
}

// Entity is the common interface implemented by all Pata Markdown entities.
type Entity interface {
	GetType() EntityType
	GetID() string
	GetBody() string
	SetBody(body string)
	GetExtra() map[string]yaml.Node
	Clone() Entity
}

// Task represents a task item.
type Task struct {
	Type         EntityType           `yaml:"type" json:"type"`
	ID           string               `yaml:"id" json:"id"`
	Title        string               `yaml:"title" json:"title"`
	Description  string               `yaml:"description,omitempty" json:"description"`
	Status       TaskStatus           `yaml:"status" json:"status"`
	CompletedAt  *time.Time           `yaml:"completed_at,omitempty" json:"completed_at,omitempty"`
	Due          *string              `yaml:"due" json:"due"` // YYYY-MM-DD or nil
	Tags         []string             `yaml:"tags,omitempty" json:"tags,omitempty"`
	NoteIDs      []string             `yaml:"note_ids,omitempty" json:"note_ids,omitempty"`
	NoteRefs     map[string]string    `yaml:"note_refs,omitempty" json:"note_refs,omitempty"` // 描述 [[名称]] -> Note ID
	CreatedAt    time.Time            `yaml:"created_at" json:"created_at"`
	CreatedBy    string               `yaml:"created_by,omitempty" json:"created_by,omitempty"`
	UpdatedAt    time.Time            `yaml:"updated_at" json:"updated_at"`
	StatusEvents []StatusEvent        `yaml:"status_events,omitempty" json:"status_events,omitempty"`
	Extra        map[string]yaml.Node `yaml:",inline" json:"-"`
	Body         string               `yaml:"-" json:"body"`
	Activities   []Activity           `yaml:"-" json:"activities,omitempty"`
}

func (t *Task) GetType() EntityType            { return EntityTypeTask }
func (t *Task) GetID() string                  { return t.ID }
func (t *Task) GetBody() string                { return t.Body }
func (t *Task) SetBody(body string)            { t.Body = body }
func (t *Task) GetExtra() map[string]yaml.Node { return t.Extra }
func (t *Task) Clone() Entity {
	cp := *t
	if t.CompletedAt != nil {
		c := *t.CompletedAt
		cp.CompletedAt = &c
	}
	if t.Due != nil {
		d := *t.Due
		cp.Due = &d
	}
	if t.Tags != nil {
		cp.Tags = append([]string(nil), t.Tags...)
	}
	if t.NoteIDs != nil {
		cp.NoteIDs = append([]string(nil), t.NoteIDs...)
	}
	cp.NoteRefs = cloneRefs(t.NoteRefs)
	if t.StatusEvents != nil {
		cp.StatusEvents = append([]StatusEvent(nil), t.StatusEvents...)
	}
	if t.Activities != nil {
		cp.Activities = make([]Activity, len(t.Activities))
		for i, a := range t.Activities {
			cp.Activities[i] = a.Clone()
		}
	}
	if t.Extra != nil {
		cp.Extra = make(map[string]yaml.Node, len(t.Extra))
		for k, v := range t.Extra {
			cp.Extra[k] = v
		}
	}
	return &cp
}

// Note represents a markdown note.
type Note struct {
	Type            EntityType           `yaml:"type" json:"type"`
	ID              string               `yaml:"id" json:"id"`
	Title           string               `yaml:"title" json:"title"`
	Tags            []string             `yaml:"tags,omitempty" json:"tags,omitempty"`
	AudioFile       string               `yaml:"audio_file,omitempty" json:"audio_file,omitempty"`
	AudioTranscript bool                 `yaml:"audio_transcript,omitempty" json:"audio_transcript,omitempty"`
	CreatedAt       time.Time            `yaml:"created_at" json:"created_at"`
	CreatedBy       string               `yaml:"created_by,omitempty" json:"created_by,omitempty"`
	UpdatedAt       time.Time            `yaml:"updated_at" json:"updated_at"`
	Extra           map[string]yaml.Node `yaml:",inline" json:"-"`
	Body            string               `yaml:"-" json:"body"`
}

func (n *Note) GetType() EntityType            { return EntityTypeNote }
func (n *Note) GetID() string                  { return n.ID }
func (n *Note) GetBody() string                { return n.Body }
func (n *Note) SetBody(body string)            { n.Body = body }
func (n *Note) GetExtra() map[string]yaml.Node { return n.Extra }
func (n *Note) Clone() Entity {
	cp := *n
	if n.Tags != nil {
		cp.Tags = append([]string(nil), n.Tags...)
	}
	if n.Extra != nil {
		cp.Extra = make(map[string]yaml.Node, len(n.Extra))
		for k, v := range n.Extra {
			cp.Extra[k] = v
		}
	}
	return &cp
}

// DayPlan represents a daily plan stored in plans/YYYY-MM-DD.md.
type DayPlan struct {
	Type       EntityType           `yaml:"type" json:"type"`
	Date       string               `yaml:"date" json:"date"` // YYYY-MM-DD
	TaskIDs    []string             `yaml:"task_ids" json:"task_ids"`
	Extra      map[string]yaml.Node `yaml:",inline" json:"-"`
	Body       string               `yaml:"-" json:"body"`
	Activities []Activity           `yaml:"-" json:"activities,omitempty"`
}

func (d *DayPlan) GetType() EntityType            { return EntityTypeDayPlan }
func (d *DayPlan) GetID() string                  { return d.Date } // DayPlan uses date as ID
func (d *DayPlan) GetBody() string                { return d.Body }
func (d *DayPlan) SetBody(body string)            { d.Body = body }
func (d *DayPlan) GetExtra() map[string]yaml.Node { return d.Extra }
func (d *DayPlan) Clone() Entity {
	cp := *d
	if d.TaskIDs != nil {
		cp.TaskIDs = append([]string(nil), d.TaskIDs...)
	}
	if d.Activities != nil {
		cp.Activities = make([]Activity, len(d.Activities))
		for i, a := range d.Activities {
			cp.Activities[i] = a.Clone()
		}
	}
	if d.Extra != nil {
		cp.Extra = make(map[string]yaml.Node, len(d.Extra))
		for k, v := range d.Extra {
			cp.Extra[k] = v
		}
	}
	return &cp
}

// FileBaseline records file identity and content baseline for optimistic concurrency.
type FileBaseline struct {
	Path    string    `json:"path"`
	Hash    string    `json:"hash"`
	ModTime time.Time `json:"mod_time"`
}
