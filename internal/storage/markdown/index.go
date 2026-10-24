package markdown

import (
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"
)

// EntityRef represents a reference to an entity returned from queries.
type EntityRef struct {
	Type      EntityType `json:"type"`
	ID        string     `json:"id"`
	Title     string     `json:"title,omitempty"`
	Path      string     `json:"path"`
	Inherited bool       `json:"inherited,omitempty"` // true if matched via parent task tag
	Time      time.Time  `json:"time"`
	Status    TaskStatus `json:"status,omitempty"`
	Snippet   string     `json:"snippet,omitempty"`
	TaskID    string     `json:"task_id,omitempty"`
}

// DanglingRef represents an explainable degraded reference to a missing entity.
type DanglingRef struct {
	SourceType EntityType `json:"source_type"`
	SourceID   string     `json:"source_id"`
	SourcePath string     `json:"source_path"`
	TargetType EntityType `json:"target_type"`
	TargetID   string     `json:"target_id"`
	Reason     string     `json:"reason"`
}

func (d DanglingRef) String() string {
	return fmt.Sprintf("[%s:%s in %s] references missing %s '%s': %s",
		d.SourceType, d.SourceID, d.SourcePath, d.TargetType, d.TargetID, d.Reason)
}

// ActivityLocation describes where an embedded activity is located.
type ActivityLocation struct {
	OwnerType EntityType `json:"owner_type"` // EntityTypeTask or EntityTypeDayPlan
	OwnerID   string     `json:"owner_id"`   // TaskID or Date
	Path      string     `json:"path"`       // absolute file path
}

// MemoryIndex maintains an in-memory rebuildable index of all vault entities.
type MemoryIndex struct {
	mu           sync.RWMutex
	vaultRoot    string
	tasks        map[string]*Task
	notes        map[string]*Note
	dayPlans     map[string]*DayPlan         // key: date YYYY-MM-DD
	files        map[string]FileResource     // key: relative slash path, e.g. "files/doc.pdf"
	fileToID     map[string]string           // absPath -> entity ID
	idToFile     map[string]string           // entity ID -> absPath
	activityLocs map[string]ActivityLocation // activityID -> location
	baselines    map[string]FileBaseline
	danglingRefs []DanglingRef
	parseErrors  []ParseError
	pendingMoves map[string]pendingMove
}

type pendingMove struct {
	path     string
	entity   Entity
	baseline FileBaseline
}

// NewMemoryIndex creates an empty MemoryIndex.
func NewMemoryIndex() *MemoryIndex {
	return &MemoryIndex{
		tasks:        make(map[string]*Task),
		notes:        make(map[string]*Note),
		dayPlans:     make(map[string]*DayPlan),
		files:        make(map[string]FileResource),
		fileToID:     make(map[string]string),
		idToFile:     make(map[string]string),
		activityLocs: make(map[string]ActivityLocation),
		baselines:    make(map[string]FileBaseline),
		pendingMoves: make(map[string]pendingMove),
	}
}

// Clear resets the index to empty state.
// 注释: Scan 清空 pendingMoves 与 Remove 事件存在竞态窗口(最长 30s 周期重扫闪失、重扫自愈，属已知可接受).
func (idx *MemoryIndex) Clear() {
	idx.mu.Lock()
	defer idx.mu.Unlock()
	idx.vaultRoot = ""
	idx.tasks = make(map[string]*Task)
	idx.notes = make(map[string]*Note)
	idx.dayPlans = make(map[string]*DayPlan)
	idx.files = make(map[string]FileResource)
	idx.fileToID = make(map[string]string)
	idx.idToFile = make(map[string]string)
	idx.activityLocs = make(map[string]ActivityLocation)
	idx.baselines = make(map[string]FileBaseline)
	idx.pendingMoves = make(map[string]pendingMove)
	idx.danglingRefs = nil
	idx.parseErrors = nil
}

// ListFiles returns clones of all file resources sorted by Name then Path.
func (idx *MemoryIndex) ListFiles() []FileResource {
	idx.mu.RLock()
	defer idx.mu.RUnlock()
	res := make([]FileResource, 0, len(idx.files))
	for _, f := range idx.files {
		res = append(res, f)
	}
	sort.Slice(res, func(i, j int) bool {
		if res[i].Name != res[j].Name {
			return res[i].Name < res[j].Name
		}
		return res[i].Path < res[j].Path
	})
	return res
}

// GetFile returns a file resource by its vault-relative path.
func (idx *MemoryIndex) GetFile(relPath string) (FileResource, bool) {
	idx.mu.RLock()
	defer idx.mu.RUnlock()
	f, ok := idx.files[filepath.ToSlash(relPath)]
	return f, ok
}

// PutFile inserts or updates a file resource in the index.
func (idx *MemoryIndex) PutFile(f FileResource) {
	idx.mu.Lock()
	defer idx.mu.Unlock()
	if idx.files == nil {
		idx.files = make(map[string]FileResource)
	}
	idx.files[filepath.ToSlash(f.Path)] = f
}

// RemoveFileResource removes a file resource by its vault-relative path.
func (idx *MemoryIndex) RemoveFileResource(relPath string) {
	idx.mu.Lock()
	defer idx.mu.Unlock()
	if idx.files != nil {
		delete(idx.files, filepath.ToSlash(relPath))
	}
}

// GetActivity returns a clone of the activity by ID and its location.
func (idx *MemoryIndex) GetActivity(id string) (Activity, ActivityLocation, bool) {
	idx.mu.RLock()
	defer idx.mu.RUnlock()
	loc, ok := idx.activityLocs[id]
	if !ok {
		return Activity{}, ActivityLocation{}, false
	}
	switch loc.OwnerType {
	case EntityTypeTask:
		if t, exists := idx.tasks[loc.OwnerID]; exists {
			for _, act := range t.Activities {
				if act.ID == id {
					return act.Clone(), loc, true
				}
			}
		}
	case EntityTypeDayPlan:
		if p, exists := idx.dayPlans[loc.OwnerID]; exists {
			for _, act := range p.Activities {
				if act.ID == id {
					return act.Clone(), loc, true
				}
			}
		}
	}
	return Activity{}, ActivityLocation{}, false
}

// ListActivitiesByTask returns all activities of a task sorted chronologically by At.
func (idx *MemoryIndex) ListActivitiesByTask(taskID string) []Activity {
	idx.mu.RLock()
	defer idx.mu.RUnlock()
	t, ok := idx.tasks[taskID]
	if !ok {
		return []Activity{}
	}
	res := make([]Activity, len(t.Activities))
	for i, a := range t.Activities {
		res[i] = a.Clone()
		res[i].TaskID = taskID
	}
	sort.Slice(res, func(i, j int) bool {
		if res[i].At.Equal(res[j].At) {
			return res[i].ID < res[j].ID
		}
		return res[i].At.Before(res[j].At)
	})
	return res
}

// ListActivitiesByDayPlan returns all activities of a day plan sorted chronologically by At.
func (idx *MemoryIndex) ListActivitiesByDayPlan(date string) []Activity {
	idx.mu.RLock()
	defer idx.mu.RUnlock()
	p, ok := idx.dayPlans[date]
	if !ok {
		return []Activity{}
	}
	res := make([]Activity, len(p.Activities))
	for i, a := range p.Activities {
		res[i] = a.Clone()
	}
	sort.Slice(res, func(i, j int) bool {
		if res[i].At.Equal(res[j].At) {
			return res[i].ID < res[j].ID
		}
		return res[i].At.Before(res[j].At)
	})
	return res
}

// GetTask returns a clone of the task by ID.
func (idx *MemoryIndex) GetTask(id string) (*Task, bool) {
	idx.mu.RLock()
	defer idx.mu.RUnlock()
	t, ok := idx.tasks[id]
	if !ok {
		return nil, false
	}
	return t.Clone().(*Task), true
}

// ListTasks returns clones of all tasks sorted by UpdatedAt descending.
func (idx *MemoryIndex) ListTasks() []*Task {
	idx.mu.RLock()
	tasks := make([]*Task, 0, len(idx.tasks))
	for _, t := range idx.tasks {
		tasks = append(tasks, t.Clone().(*Task))
	}
	idx.mu.RUnlock()
	sort.Slice(tasks, func(i, j int) bool { return tasks[i].UpdatedAt.After(tasks[j].UpdatedAt) })
	return tasks
}

// GetNote returns a clone of the note by ID.
func (idx *MemoryIndex) GetNote(id string) (*Note, bool) {
	idx.mu.RLock()
	defer idx.mu.RUnlock()
	n, ok := idx.notes[id]
	if !ok {
		return nil, false
	}
	return n.Clone().(*Note), true
}

// ListNotes returns clones of all notes sorted by UpdatedAt descending.
func (idx *MemoryIndex) ListNotes() []*Note {
	idx.mu.RLock()
	notes := make([]*Note, 0, len(idx.notes))
	for _, n := range idx.notes {
		notes = append(notes, n.Clone().(*Note))
	}
	idx.mu.RUnlock()
	sort.Slice(notes, func(i, j int) bool {
		if notes[i].UpdatedAt.Equal(notes[j].UpdatedAt) {
			return notes[i].ID < notes[j].ID
		}
		return notes[i].UpdatedAt.After(notes[j].UpdatedAt)
	})
	return notes
}

// GetDayPlan returns a clone of the DayPlan for a date.
func (idx *MemoryIndex) GetDayPlan(date string) (*DayPlan, bool) {
	idx.mu.RLock()
	defer idx.mu.RUnlock()
	p, ok := idx.dayPlans[date]
	if !ok {
		return nil, false
	}
	return p.Clone().(*DayPlan), true
}

// ListDayPlans returns clones of all day plans.
func (idx *MemoryIndex) ListDayPlans() []*DayPlan {
	idx.mu.RLock()
	defer idx.mu.RUnlock()
	res := make([]*DayPlan, 0, len(idx.dayPlans))
	for _, p := range idx.dayPlans {
		res = append(res, p.Clone().(*DayPlan))
	}
	return res
}

// GetBaseline returns baseline info for a file path.
func (idx *MemoryIndex) GetBaseline(absPath string) (FileBaseline, bool) {
	idx.mu.RLock()
	defer idx.mu.RUnlock()
	b, ok := idx.baselines[absPath]
	return b, ok
}

// ListDanglingReferences returns all current dangling references.
func (idx *MemoryIndex) ListDanglingReferences() []DanglingRef {
	idx.mu.RLock()
	defer idx.mu.RUnlock()
	res := make([]DanglingRef, len(idx.danglingRefs))
	copy(res, idx.danglingRefs)
	return res
}

// ListParseErrors returns all isolated parse errors encountered.
func (idx *MemoryIndex) ListParseErrors() []ParseError {
	idx.mu.RLock()
	defer idx.mu.RUnlock()
	res := make([]ParseError, len(idx.parseErrors))
	copy(res, idx.parseErrors)
	return res
}

// FindByTag searches entities containing the tag.
// For Activities, tag matching checks `act.Tags ∪ parentTask.Tags` (for task activities).
func (idx *MemoryIndex) FindByTag(tag string) []EntityRef {
	idx.mu.RLock()
	defer idx.mu.RUnlock()

	var results []EntityRef
	targetTag := strings.TrimSpace(tag)

	// Search Tasks
	for id, t := range idx.tasks {
		if hasTag(t.Tags, targetTag) {
			tTime := t.UpdatedAt
			if tTime.IsZero() {
				tTime = t.CreatedAt
			}
			results = append(results, EntityRef{
				Type:    EntityTypeTask,
				ID:      id,
				Title:   t.Title,
				Path:    idx.idToFile[id],
				Time:    tTime,
				Status:  t.Status,
				Snippet: t.Description,
			})
		}
	}

	// Search Notes
	for id, n := range idx.notes {
		if hasTag(n.Tags, targetTag) {
			nTime := n.UpdatedAt
			if nTime.IsZero() {
				nTime = n.CreatedAt
			}
			snippet := truncateSnippet(strings.TrimSpace(n.Body), 200)
			results = append(results, EntityRef{
				Type:    EntityTypeNote,
				ID:      id,
				Title:   n.Title,
				Path:    idx.idToFile[id],
				Time:    nTime,
				Snippet: snippet,
			})
		}
	}

	// Search Activities
	for _, t := range idx.tasks {
		for _, act := range t.Activities {
			ownMatch := hasTag(act.Tags, targetTag)
			if ownMatch {
				results = append(results, EntityRef{
					Type:    EntityTypeActivity,
					ID:      act.ID,
					Title:   t.Title,
					Path:    idx.idToFile[t.ID],
					Time:    act.At,
					Snippet: act.Body,
					TaskID:  t.ID,
				})
			} else if hasTag(t.Tags, targetTag) {
				// Inherited from parent task
				results = append(results, EntityRef{
					Type:      EntityTypeActivity,
					ID:        act.ID,
					Title:     t.Title,
					Path:      idx.idToFile[t.ID],
					Inherited: true,
					Time:      act.At,
					Snippet:   act.Body,
					TaskID:    t.ID,
				})
			}
		}
	}
	for _, p := range idx.dayPlans {
		for _, act := range p.Activities {
			if hasTag(act.Tags, targetTag) {
				results = append(results, EntityRef{
					Type:    EntityTypeActivity,
					ID:      act.ID,
					Title:   p.Date,
					Path:    idx.idToFile[p.Date],
					Time:    act.At,
					Snippet: act.Body,
				})
			}
		}
	}

	return results
}

func hasTag(tags []string, target string) bool {
	for _, t := range tags {
		if strings.EqualFold(strings.TrimSpace(t), target) {
			return true
		}
	}
	return false
}

// FindAll returns all entities (Tasks, Notes, Activities) without tag filtering.
func (idx *MemoryIndex) FindAll() []EntityRef {
	idx.mu.RLock()
	defer idx.mu.RUnlock()

	var results []EntityRef

	// All Tasks
	for id, t := range idx.tasks {
		tTime := t.UpdatedAt
		if tTime.IsZero() {
			tTime = t.CreatedAt
		}
		results = append(results, EntityRef{
			Type:    EntityTypeTask,
			ID:      id,
			Title:   t.Title,
			Path:    idx.idToFile[id],
			Time:    tTime,
			Status:  t.Status,
			Snippet: t.Description,
		})
	}

	// All Notes
	for id, n := range idx.notes {
		nTime := n.UpdatedAt
		if nTime.IsZero() {
			nTime = n.CreatedAt
		}
		snippet := truncateSnippet(strings.TrimSpace(n.Body), 200)
		results = append(results, EntityRef{
			Type:    EntityTypeNote,
			ID:      id,
			Title:   n.Title,
			Path:    idx.idToFile[id],
			Time:    nTime,
			Snippet: snippet,
		})
	}

	// All Activities from Tasks
	for _, t := range idx.tasks {
		for _, act := range t.Activities {
			results = append(results, EntityRef{
				Type:    EntityTypeActivity,
				ID:      act.ID,
				Title:   t.Title,
				Path:    idx.idToFile[t.ID],
				Time:    act.At,
				Snippet: act.Body,
				TaskID:  t.ID,
			})
		}
	}

	// All Activities from DayPlans
	for _, p := range idx.dayPlans {
		for _, act := range p.Activities {
			results = append(results, EntityRef{
				Type:    EntityTypeActivity,
				ID:      act.ID,
				Title:   p.Date,
				Path:    idx.idToFile[p.Date],
				Time:    act.At,
				Snippet: act.Body,
			})
		}
	}

	return results
}

// TagOverviewItem represents a tag aggregated across tasks, notes, and activities.
type TagOverviewItem struct {
	Tag           string `json:"tag"`
	TaskCount     int    `json:"task_count"`
	NoteCount     int    `json:"note_count"`
	ActivityCount int    `json:"activity_count"`
	Total         int    `json:"total"`
}

// SearchResultItem represents a matched entity in cross-type search.
type SearchResultItem struct {
	Type    EntityType `json:"type"`
	ID      string     `json:"id"`
	Title   string     `json:"title,omitempty"`
	Snippet string     `json:"snippet,omitempty"`
	Path    string     `json:"path"`
}

// TagOverview aggregates own tags across tasks, notes, and activities without hierarchy.
// Tag grouping is case-insensitive (aligned with FindByTag EqualFold semantics) using
// strings.ToLower(TrimSpace(tag)) as the grouping key, while preserving the raw trimmed
// string of its first appearance as the display Tag.
func (idx *MemoryIndex) TagOverview() []TagOverviewItem {
	idx.mu.RLock()
	defer idx.mu.RUnlock()

	type stats struct {
		displayTag    string
		taskCount     int
		noteCount     int
		activityCount int
	}

	tagMap := make(map[string]*stats)
	getStats := func(tag string) *stats {
		lowerKey := strings.ToLower(tag)
		s, exists := tagMap[lowerKey]
		if !exists {
			s = &stats{
				displayTag: tag,
			}
			tagMap[lowerKey] = s
		}
		return s
	}

	// Process entities in deterministic order (sorted IDs) to keep first appearance stable across runs
	taskIDs := make([]string, 0, len(idx.tasks))
	for id := range idx.tasks {
		taskIDs = append(taskIDs, id)
	}
	sort.Strings(taskIDs)
	for _, id := range taskIDs {
		t := idx.tasks[id]
		seen := make(map[string]bool)
		for _, raw := range t.Tags {
			tag := strings.TrimSpace(raw)
			if tag == "" {
				continue
			}
			lowerKey := strings.ToLower(tag)
			if seen[lowerKey] {
				continue
			}
			seen[lowerKey] = true
			getStats(tag).taskCount++
		}
	}

	noteIDs := make([]string, 0, len(idx.notes))
	for id := range idx.notes {
		noteIDs = append(noteIDs, id)
	}
	sort.Strings(noteIDs)
	for _, id := range noteIDs {
		n := idx.notes[id]
		seen := make(map[string]bool)
		for _, raw := range n.Tags {
			tag := strings.TrimSpace(raw)
			if tag == "" {
				continue
			}
			lowerKey := strings.ToLower(tag)
			if seen[lowerKey] {
				continue
			}
			seen[lowerKey] = true
			getStats(tag).noteCount++
		}
	}

	// Task activities own tags
	for _, id := range taskIDs {
		t := idx.tasks[id]
		for _, act := range t.Activities {
			seen := make(map[string]bool)
			for _, raw := range act.Tags {
				tag := strings.TrimSpace(raw)
				if tag == "" {
					continue
				}
				lowerKey := strings.ToLower(tag)
				if seen[lowerKey] {
					continue
				}
				seen[lowerKey] = true
				getStats(tag).activityCount++
			}
		}
	}

	// DayPlan activities own tags
	dayPlanDates := make([]string, 0, len(idx.dayPlans))
	for d := range idx.dayPlans {
		dayPlanDates = append(dayPlanDates, d)
	}
	sort.Strings(dayPlanDates)
	for _, d := range dayPlanDates {
		p := idx.dayPlans[d]
		for _, act := range p.Activities {
			seen := make(map[string]bool)
			for _, raw := range act.Tags {
				tag := strings.TrimSpace(raw)
				if tag == "" {
					continue
				}
				lowerKey := strings.ToLower(tag)
				if seen[lowerKey] {
					continue
				}
				seen[lowerKey] = true
				getStats(tag).activityCount++
			}
		}
	}

	results := make([]TagOverviewItem, 0, len(tagMap))
	for _, s := range tagMap {
		results = append(results, TagOverviewItem{
			Tag:           s.displayTag,
			TaskCount:     s.taskCount,
			NoteCount:     s.noteCount,
			ActivityCount: s.activityCount,
			Total:         s.taskCount + s.noteCount + s.activityCount,
		})
	}

	sort.Slice(results, func(i, j int) bool {
		return strings.ToLower(results[i].Tag) < strings.ToLower(results[j].Tag)
	})

	return results
}

// SearchAll performs case-insensitive substring search across tasks, notes, activities, and files.
// Empty or whitespace-only queries return an empty slice.
// Results have stable ordering grouped by type (Task -> Note -> Activity -> File).
func (idx *MemoryIndex) SearchAll(query string) []SearchResultItem {
	trimmed := strings.TrimSpace(query)
	if trimmed == "" {
		return []SearchResultItem{}
	}

	idx.mu.RLock()
	defer idx.mu.RUnlock()

	lowerQ := strings.ToLower(trimmed)

	var taskResults []SearchResultItem
	var noteResults []SearchResultItem
	var actResults []SearchResultItem

	// 1. Tasks: search visible content, excluding embedded activity metadata.
	for id, t := range idx.tasks {
		var bodyParts []string
		if !strings.Contains(t.Body, activityStartTag) {
			bodyParts = append(bodyParts, t.Body)
		}
		for _, act := range t.Activities {
			bodyParts = append(bodyParts, act.Body, strings.Join(act.Tags, " "))
		}
		body := strings.Join(bodyParts, "\n")
		if matchCaseInsensitive(t.Title, lowerQ) || matchCaseInsensitive(t.Description, lowerQ) || matchCaseInsensitive(body, lowerQ) || matchTagsCaseInsensitive(t.Tags, lowerQ) {
			snippet := extractSnippet(t.Description, lowerQ)
			if snippet == "" {
				snippet = extractSnippet(body, lowerQ)
			}
			taskResults = append(taskResults, SearchResultItem{
				Type:    EntityTypeTask,
				ID:      id,
				Title:   t.Title,
				Snippet: snippet,
				Path:    idx.idToFile[id],
			})
		}
	}
	sort.Slice(taskResults, func(i, j int) bool {
		ti, tj := idx.tasks[taskResults[i].ID], idx.tasks[taskResults[j].ID]
		if ti.UpdatedAt.Equal(tj.UpdatedAt) {
			return taskResults[i].ID < taskResults[j].ID
		}
		return ti.UpdatedAt.After(tj.UpdatedAt)
	})

	// 2. Notes: match title, body, or tags
	for id, n := range idx.notes {
		if matchCaseInsensitive(n.Title, lowerQ) || matchCaseInsensitive(n.Body, lowerQ) || matchTagsCaseInsensitive(n.Tags, lowerQ) {
			noteResults = append(noteResults, SearchResultItem{
				Type:    EntityTypeNote,
				ID:      id,
				Title:   n.Title,
				Snippet: extractSnippet(n.Body, lowerQ),
				Path:    idx.idToFile[id],
			})
		}
	}
	sort.Slice(noteResults, func(i, j int) bool {
		ni, nj := idx.notes[noteResults[i].ID], idx.notes[noteResults[j].ID]
		if ni.UpdatedAt.Equal(nj.UpdatedAt) {
			return noteResults[i].ID < noteResults[j].ID
		}
		return ni.UpdatedAt.After(nj.UpdatedAt)
	})

	// 3. Activities: match body or own tags
	type actItemWithTime struct {
		item SearchResultItem
		at   time.Time
	}
	var actItemsWithTime []actItemWithTime
	for _, t := range idx.tasks {
		for _, act := range t.Activities {
			if matchCaseInsensitive(act.Body, lowerQ) || matchTagsCaseInsensitive(act.Tags, lowerQ) {
				actItemsWithTime = append(actItemsWithTime, actItemWithTime{
					item: SearchResultItem{
						Type:    EntityTypeActivity,
						ID:      act.ID,
						Title:   t.Title,
						Snippet: extractSnippet(act.Body, lowerQ),
						Path:    idx.idToFile[t.ID],
					},
					at: act.At,
				})
			}
		}
	}
	for _, p := range idx.dayPlans {
		for _, act := range p.Activities {
			if matchCaseInsensitive(act.Body, lowerQ) || matchTagsCaseInsensitive(act.Tags, lowerQ) {
				actItemsWithTime = append(actItemsWithTime, actItemWithTime{
					item: SearchResultItem{
						Type:    EntityTypeActivity,
						ID:      act.ID,
						Title:   p.Date,
						Snippet: extractSnippet(act.Body, lowerQ),
						Path:    idx.idToFile[p.Date],
					},
					at: act.At,
				})
			}
		}
	}
	sort.Slice(actItemsWithTime, func(i, j int) bool {
		if actItemsWithTime[i].at.Equal(actItemsWithTime[j].at) {
			return actItemsWithTime[i].item.ID < actItemsWithTime[j].item.ID
		}
		return actItemsWithTime[i].at.After(actItemsWithTime[j].at)
	})
	for _, a := range actItemsWithTime {
		actResults = append(actResults, a.item)
	}

	// 4. Files: match name or path
	var fileResults []SearchResultItem
	for _, f := range idx.files {
		if matchCaseInsensitive(f.Name, lowerQ) || matchCaseInsensitive(f.Path, lowerQ) {
			absPath := ""
			if idx.vaultRoot != "" {
				absPath = filepath.Join(idx.vaultRoot, filepath.FromSlash(f.Path))
			}
			fileResults = append(fileResults, SearchResultItem{
				Type:    EntityTypeFile,
				ID:      f.Path,
				Title:   f.Name,
				Snippet: f.Path,
				Path:    absPath,
			})
		}
	}
	sort.Slice(fileResults, func(i, j int) bool {
		if fileResults[i].Title != fileResults[j].Title {
			return fileResults[i].Title < fileResults[j].Title
		}
		return fileResults[i].Path < fileResults[j].Path
	})

	total := len(taskResults) + len(noteResults) + len(actResults) + len(fileResults)
	results := make([]SearchResultItem, 0, total)
	results = append(results, taskResults...)
	results = append(results, noteResults...)
	results = append(results, actResults...)
	results = append(results, fileResults...)

	return results
}

func matchCaseInsensitive(text, lowerQ string) bool {
	return strings.Contains(strings.ToLower(text), lowerQ)
}

func matchTagsCaseInsensitive(tags []string, lowerQ string) bool {
	for _, t := range tags {
		if matchCaseInsensitive(t, lowerQ) {
			return true
		}
	}
	return false
}

func extractSnippet(body, lowerQ string) string {
	if strings.TrimSpace(body) == "" {
		return ""
	}
	normalized := strings.ReplaceAll(body, "\r\n", "\n")
	lines := strings.Split(normalized, "\n")
	for _, line := range lines {
		trimmed := strings.TrimSpace(line)
		if trimmed != "" && strings.Contains(strings.ToLower(trimmed), lowerQ) {
			return truncateSnippet(trimmed, 120)
		}
	}
	for _, line := range lines {
		trimmed := strings.TrimSpace(line)
		if trimmed != "" {
			return truncateSnippet(trimmed, 120)
		}
	}
	return ""
}

func truncateSnippet(s string, maxRunes int) string {
	runes := []rune(s)
	if len(runes) <= maxRunes {
		return s
	}
	return string(runes[:maxRunes]) + "..."
}

// ClearPendingMove removes any pending move candidate for an entity ID.
func (idx *MemoryIndex) ClearPendingMove(id string) {
	idx.mu.Lock()
	defer idx.mu.Unlock()
	if idx.pendingMoves != nil {
		delete(idx.pendingMoves, id)
	}
}

// RemoveFile removes an entity associated with a path from the index.
func (idx *MemoryIndex) RemoveFile(absPath string) {
	idx.RemoveFileWithPromotion(absPath)
}

// RemoveFileWithPromotion removes an entity associated with a path from the index.
// If a pendingMove exists for this entity ID at a new path, it is promoted to the index.
// Returns deletedID, and if a pendingMove was promoted, promotedID, promotedPath and promotedType.
// 注释: 锁内执行 os.Stat 进行文件存在性探查持有锁 syscalls，在单用户桌面规模可接受；后续大 vault 场景可移出锁外双检.
func (idx *MemoryIndex) RemoveFileWithPromotion(absPath string) (deletedID, promotedID, promotedPath string, promotedType EntityType) {
	idx.mu.Lock()
	defer idx.mu.Unlock()

	for actID, loc := range idx.activityLocs {
		if loc.Path == absPath {
			delete(idx.activityLocs, actID)
		}
	}

	id, ok := idx.fileToID[absPath]
	if ok {
		deletedID = id
		delete(idx.fileToID, absPath)
		// Only delete the entity if idToFile still points to this path (not already migrated)
		if idx.idToFile[id] == absPath {
			delete(idx.idToFile, id)
			delete(idx.tasks, id)
			delete(idx.notes, id)
			delete(idx.dayPlans, id)
		}
	}
	delete(idx.baselines, absPath)

	// Check if there was a pending move for this entity ID
	if ok && idx.pendingMoves != nil {
		if pm, hasPending := idx.pendingMoves[id]; hasPending {
			delete(idx.pendingMoves, id)
			if _, err := os.Stat(pm.path); err == nil {
				idx.fileToID[pm.path] = id
				idx.idToFile[id] = pm.path
				idx.baselines[pm.path] = pm.baseline

				switch e := pm.entity.(type) {
				case *Task:
					idx.tasks[id] = e.Clone().(*Task)
					for _, act := range e.Activities {
						idx.activityLocs[act.ID] = ActivityLocation{OwnerType: EntityTypeTask, OwnerID: id, Path: pm.path}
					}
				case *Note:
					idx.notes[id] = e.Clone().(*Note)
				case *DayPlan:
					idx.dayPlans[id] = e.Clone().(*DayPlan)
					for _, act := range e.Activities {
						idx.activityLocs[act.ID] = ActivityLocation{OwnerType: EntityTypeDayPlan, OwnerID: id, Path: pm.path}
					}
				}

				idx.removeDuplicateParseErrorLocked(id, pm.path)
				promotedID = id
				promotedPath = pm.path
				promotedType = pm.entity.GetType()
			}
		}
	}

	idx.recomputeDanglingRefsLocked()
	return deletedID, promotedID, promotedPath, promotedType
}

func (idx *MemoryIndex) removeDuplicateParseErrorLocked(id, path string) {
	filtered := idx.parseErrors[:0]
	for _, pe := range idx.parseErrors {
		if pe.Path == path && strings.Contains(pe.Reason, fmt.Sprintf("duplicate entity ID collision '%s'", id)) {
			continue
		}
		filtered = append(filtered, pe)
	}
	idx.parseErrors = filtered
}

// PutEntity inserts or updates an entity in the index.
// 注释: 锁内执行 os.Stat 进行文件存在性探查持有锁 syscalls，在单用户桌面规模可接受；后续大 vault 场景可移出锁外双检.
func (idx *MemoryIndex) PutEntity(absPath string, entity Entity, baseline FileBaseline) {
	idx.mu.Lock()
	defer idx.mu.Unlock()

	// If old entity existed at this path, clear its ID mapping
	if oldID, exists := idx.fileToID[absPath]; exists && oldID != entity.GetID() {
		delete(idx.idToFile, oldID)
		delete(idx.tasks, oldID)
		delete(idx.notes, oldID)
		delete(idx.dayPlans, oldID)
	}

	for actID, loc := range idx.activityLocs {
		if loc.Path == absPath {
			delete(idx.activityLocs, actID)
		}
	}

	id := entity.GetID()
	if existingPath, exists := idx.idToFile[id]; exists && existingPath != absPath {
		// Check whether existingPath still exists on disk
		if _, err := os.Stat(existingPath); os.IsNotExist(err) {
			// existingPath no longer exists on disk: the entity was moved/renamed to absPath!
			delete(idx.fileToID, existingPath)
			delete(idx.baselines, existingPath)
			idx.removeDuplicateParseErrorLocked(id, absPath)
		} else {
			// existingPath still exists on disk.
			// Could be a duplicate ID collision, OR Create arrived before Remove in a move.
			if idx.pendingMoves == nil {
				idx.pendingMoves = make(map[string]pendingMove)
			}
			idx.pendingMoves[id] = pendingMove{
				path:     absPath,
				entity:   entity,
				baseline: baseline,
			}
			idx.parseErrors = append(idx.parseErrors, ParseError{
				Path:   absPath,
				Reason: fmt.Sprintf("duplicate entity ID collision '%s' (already declared in %s); update rejected", id, existingPath),
				Err:    fmt.Errorf("duplicate entity ID collision: %s", id),
			})
			return
		}
	}

	idx.fileToID[absPath] = id
	idx.idToFile[id] = absPath
	idx.baselines[absPath] = baseline
	if idx.pendingMoves != nil {
		delete(idx.pendingMoves, id)
	}

	switch e := entity.(type) {
	case *Task:
		idx.tasks[id] = e.Clone().(*Task)
		for _, act := range e.Activities {
			if existingLoc, exists := idx.activityLocs[act.ID]; exists && existingLoc.Path != absPath {
				idx.parseErrors = append(idx.parseErrors, ParseError{
					Path:   absPath,
					Reason: fmt.Sprintf("duplicate activity ID collision '%s' (already declared in %s)", act.ID, existingLoc.Path),
					Err:    fmt.Errorf("duplicate activity ID: %s", act.ID),
				})
			} else {
				idx.activityLocs[act.ID] = ActivityLocation{
					OwnerType: EntityTypeTask,
					OwnerID:   id,
					Path:      absPath,
				}
			}
		}
	case *Note:
		idx.notes[id] = e.Clone().(*Note)
	case *DayPlan:
		idx.dayPlans[id] = e.Clone().(*DayPlan)
		for _, act := range e.Activities {
			if existingLoc, exists := idx.activityLocs[act.ID]; exists && existingLoc.Path != absPath {
				idx.parseErrors = append(idx.parseErrors, ParseError{
					Path:   absPath,
					Reason: fmt.Sprintf("duplicate activity ID collision '%s' (already declared in %s)", act.ID, existingLoc.Path),
					Err:    fmt.Errorf("duplicate activity ID: %s", act.ID),
				})
			} else {
				idx.activityLocs[act.ID] = ActivityLocation{
					OwnerType: EntityTypeDayPlan,
					OwnerID:   id,
					Path:      absPath,
				}
			}
		}
	}

	idx.recomputeDanglingRefsLocked()
}

func (idx *MemoryIndex) recomputeDanglingRefsLocked() {
	var dangling []DanglingRef

	// 1. Tasks referencing non-existent notes
	for id, t := range idx.tasks {
		for _, noteID := range t.NoteIDs {
			if _, exists := idx.notes[noteID]; !exists {
				dangling = append(dangling, DanglingRef{
					SourceType: EntityTypeTask,
					SourceID:   id,
					SourcePath: idx.idToFile[id],
					TargetType: EntityTypeNote,
					TargetID:   noteID,
					Reason:     fmt.Sprintf("referenced note '%s' not found", noteID),
				})
			}
		}
	}

	// 3. DayPlans referencing non-existent tasks
	for date, p := range idx.dayPlans {
		for _, taskID := range p.TaskIDs {
			if _, exists := idx.tasks[taskID]; !exists {
				dangling = append(dangling, DanglingRef{
					SourceType: EntityTypeDayPlan,
					SourceID:   date,
					SourcePath: idx.idToFile[date],
					TargetType: EntityTypeTask,
					TargetID:   taskID,
					Reason:     fmt.Sprintf("planned task '%s' not found", taskID),
				})
			}
		}
	}

	idx.danglingRefs = dangling
}

// ScanVault walks a vault directory and rebuilds the memory index from scratch.
// Invalid YAML files are tracked in parseErrors without modifying or deleting them.
func ScanVault(vaultRoot string) (*MemoryIndex, error) {
	absRoot, err := filepath.Abs(vaultRoot)
	if err != nil {
		return nil, fmt.Errorf("failed to get absolute vault root: %w", err)
	}

	idx := NewMemoryIndex()
	idx.vaultRoot = absRoot
	var parseErrs []ParseError

	err = filepath.Walk(absRoot, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		if path == absRoot {
			return nil
		}
		rel, relErr := filepath.Rel(absRoot, path)
		if relErr != nil {
			return nil
		}
		relSlash := filepath.ToSlash(rel)
		base := filepath.Base(path)

		if info.IsDir() {
			// Skip .git or temporary directories
			if base == ".git" {
				return filepath.SkipDir
			}
			// Only allow business root directories
			if !strings.Contains(relSlash, "/") {
				if base != "tasks" && base != "notes" && base != "plans" && base != "files" && base != ".pata" {
					return filepath.SkipDir
				}
			} else if strings.HasPrefix(relSlash, ".pata/") && relSlash != ".pata/plans" {
				return filepath.SkipDir
			}
			return nil
		}

		// Ignore temporary swap/atomic files or hidden files
		if strings.HasPrefix(base, ".pata_tmp_") || strings.HasSuffix(base, ".tmp") || base == ".DS_Store" {
			return nil
		}

		// Files directory: index as FileResource without frontmatter
		if strings.HasPrefix(relSlash, "files/") {
			if strings.HasPrefix(base, ".") {
				return nil
			}
			idx.files[relSlash] = FileResource{
				Path:    relSlash,
				Name:    base,
				Ext:     filepath.Ext(base),
				Size:    info.Size(),
				ModTime: info.ModTime(),
			}
			return nil
		}

		// Business entity directories must contain .md files
		isTaskDir := strings.HasPrefix(relSlash, "tasks/")
		isNoteDir := strings.HasPrefix(relSlash, "notes/")
		isPlanDir := strings.HasPrefix(relSlash, "plans/") || strings.HasPrefix(relSlash, ".pata/plans/")

		if !isTaskDir && !isNoteDir && !isPlanDir {
			// Files in root (e.g. README.md) or other folders are not indexed
			return nil
		}

		if filepath.Ext(path) != ".md" {
			return nil
		}

		data, readErr := os.ReadFile(path)
		if readErr != nil {
			parseErrs = append(parseErrs, ParseError{
				Path:   path,
				Reason: "failed to read file",
				Err:    readErr,
			})
			return nil
		}

		entity, parseErr := ParseMarkdown(path, data)
		if parseErr != nil {
			parseErrs = append(parseErrs, ParseError{
				Path:   path,
				Reason: "failed to parse markdown entity",
				Err:    parseErr,
			})
			return nil
		}

		// Ensure entity matches its folder boundary
		if isTaskDir && entity.GetType() != EntityTypeTask {
			parseErrs = append(parseErrs, ParseError{
				Path:   path,
				Reason: fmt.Sprintf("file in tasks/ has invalid entity type '%s'", entity.GetType()),
				Err:    fmt.Errorf("expected type task, got %s", entity.GetType()),
			})
			return nil
		} else if isNoteDir && entity.GetType() != EntityTypeNote {
			parseErrs = append(parseErrs, ParseError{
				Path:   path,
				Reason: fmt.Sprintf("file in notes/ has invalid entity type '%s'", entity.GetType()),
				Err:    fmt.Errorf("expected type note, got %s", entity.GetType()),
			})
			return nil
		} else if isPlanDir && entity.GetType() != EntityTypeDayPlan {
			parseErrs = append(parseErrs, ParseError{
				Path:   path,
				Reason: fmt.Sprintf("file in plans/ has invalid entity type '%s'", entity.GetType()),
				Err:    fmt.Errorf("expected type day_plan, got %s", entity.GetType()),
			})
			return nil
		}

		baseline := FileBaseline{
			Path:    path,
			Hash:    ComputeContentHash(data),
			ModTime: info.ModTime(),
		}

		id := entity.GetID()
		if existingPath, exists := idx.idToFile[id]; exists && existingPath != path {
			// Special handling for DayPlan: root plans/YYYY-MM-DD.md supersedes legacy .pata/plans/YYYY-MM-DD.md
			isDayPlan := entity.GetType() == EntityTypeDayPlan
			isLegacyCurrent := strings.Contains(path, filepath.Join(".pata", "plans"))
			isLegacyExisting := strings.Contains(existingPath, filepath.Join(".pata", "plans"))

			if isDayPlan && isLegacyCurrent && !isLegacyExisting {
				// Current file is legacy and we already scanned the root one: ignore legacy silently
				return nil
			} else if isDayPlan && !isLegacyCurrent && isLegacyExisting {
				// Current file is root and existing one was legacy: root wins! Clean up legacy entry first
				delete(idx.fileToID, existingPath)
				delete(idx.baselines, existingPath)
				if oldPlan, ok := idx.dayPlans[id]; ok {
					for _, act := range oldPlan.Activities {
						delete(idx.activityLocs, act.ID)
					}
				}
				delete(idx.dayPlans, id)
			} else {
				// M2: Duplicate ID detected across different files.
				// Do not overwrite existing entity; isolate error in parseErrors to align with Invariant 6.
				parseErrs = append(parseErrs, ParseError{
					Path:   path,
					Reason: fmt.Sprintf("duplicate entity ID collision '%s' (already declared in %s); file ignored to prevent silent overwrite", id, existingPath),
					Err:    fmt.Errorf("duplicate entity ID collision: %s", id),
				})
				return nil
			}
		}

		idx.fileToID[path] = id
		idx.idToFile[id] = path
		idx.baselines[path] = baseline

		switch e := entity.(type) {
		case *Task:
			idx.tasks[id] = e
			for _, act := range e.Activities {
				if existingLoc, exists := idx.activityLocs[act.ID]; exists && existingLoc.Path != path {
					parseErrs = append(parseErrs, ParseError{
						Path:   path,
						Reason: fmt.Sprintf("duplicate activity ID collision '%s' (already declared in %s); activity ignored", act.ID, existingLoc.Path),
						Err:    fmt.Errorf("duplicate activity ID collision: %s", act.ID),
					})
				} else {
					idx.activityLocs[act.ID] = ActivityLocation{OwnerType: EntityTypeTask, OwnerID: id, Path: path}
				}
			}
		case *Note:
			idx.notes[id] = e
		case *DayPlan:
			idx.dayPlans[id] = e
			for _, act := range e.Activities {
				if existingLoc, exists := idx.activityLocs[act.ID]; exists && existingLoc.Path != path {
					parseErrs = append(parseErrs, ParseError{
						Path:   path,
						Reason: fmt.Sprintf("duplicate activity ID collision '%s' (already declared in %s); activity ignored", act.ID, existingLoc.Path),
						Err:    fmt.Errorf("duplicate activity ID collision: %s", act.ID),
					})
				} else {
					idx.activityLocs[act.ID] = ActivityLocation{OwnerType: EntityTypeDayPlan, OwnerID: id, Path: path}
				}
			}
		}

		return nil
	})

	if err != nil {
		return nil, fmt.Errorf("failed to scan vault: %w", err)
	}

	idx.mu.Lock()
	idx.parseErrors = parseErrs
	idx.recomputeDanglingRefsLocked()
	idx.mu.Unlock()

	return idx, nil
}
