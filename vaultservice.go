package main

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/wailsapp/wails/v3/pkg/application"

	"pata/internal/asr"
	"pata/internal/keychain"
	"pata/internal/storage/markdown"
)

// VaultConfig is the persisted single-vault choice (D18: 单 Vault) and app preferences.
type VaultConfig struct {
	VaultPath string `json:"vault_path"`
	Theme     string `json:"theme,omitempty"`
}

const (
	ASRProvider        = "阿里云百炼"
	ASRModel           = "qwen-audio-3.1-asr-flash-filetrans"
	ASRRegion          = "华北2（北京）"
	ASRKeychainService = "pata.asr"
	ASRKeychainAccount = "aliyun_bailian_api_key"
)

// ASRConfigStatus reports transcription configuration status to frontend.
// Note: plain key is NEVER exposed to frontend.
type ASRConfigStatus struct {
	Configured bool   `json:"configured"`
	Provider   string `json:"provider"`
	Model      string `json:"model"`
	Region     string `json:"region"`
}

// VaultStatus reports whether a vault is configured/open for the UI.
type VaultStatus struct {
	Configured bool   `json:"configured"`
	Path       string `json:"path"`
	Open       bool   `json:"open"`
	TaskCount  int    `json:"taskCount"`
	Error      string `json:"error,omitempty"`
}

// VaultHealth reports vault health status, including parse errors and dangling references.
type VaultHealth struct {
	ParseErrors  []markdown.ParseError  `json:"parse_errors"`
	DanglingRefs []markdown.DanglingRef `json:"dangling_refs"`
}

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

// CreateNoteInput defines parameters for creating a new Note.
type CreateNoteInput struct {
	Title string   `json:"title"`
	Tags  []string `json:"tags,omitempty"`
	Body  string   `json:"body,omitempty"`
}

// UpdateNoteInput defines parameters for updating an existing Note.
// Note: tags and body follow full-replacement semantics (not partial patch).
type UpdateNoteInput struct {
	ID    string   `json:"id"`
	Title string   `json:"title"`
	Tags  []string `json:"tags,omitempty"`
	Body  string   `json:"body"`
}

// TimelineItem represents an aggregated item in the day timeline (activity or completion).
type TimelineItem struct {
	Kind      string             `json:"kind"` // "activity" | "completion" | "reopen"
	Time      time.Time          `json:"time"`
	Activity  *markdown.Activity `json:"activity,omitempty"`
	TaskID    string             `json:"task_id,omitempty"`
	TaskTitle string             `json:"task_title,omitempty"`
}

// EventVaultChanged is emitted to the Wails frontend when a vault entity is created, modified, or deleted.
const EventVaultChanged = "vault:changed"

// VaultChangeEvent describes a change dispatched to the frontend application.
type VaultChangeEvent struct {
	Op       string `json:"op"`
	Path     string `json:"path"`
	EntityID string `json:"entity_id,omitempty"`
	Type     string `json:"type,omitempty"`
}

type transcriptRecord struct {
	vault        *markdown.Vault
	baseline     *markdown.FileBaseline
	expectedBody string
}

// VaultService owns the single Vault instance; all structured file access goes through it.
type VaultService struct {
	mu                sync.Mutex
	vault             *markdown.Vault
	stopWatcher       func()
	configPath        string
	emitEvent         func(name string, data any)
	keychain          keychain.Store
	launcher          func(cmd *exec.Cmd) error
	asrManager        *asr.Manager
	transcriptRecords map[string]*transcriptRecord
}

func NewVaultService() *VaultService {
	defaultEmit := func(name string, data any) {
		if app := application.Get(); app != nil && app.Event != nil {
			app.Event.Emit(name, data)
		}
	}

	configDir, err := os.UserConfigDir()
	if err != nil {
		log.Printf("vault: cannot resolve user config dir, persistence disabled: %v", err)
		svc := &VaultService{
			emitEvent:         defaultEmit,
			keychain:          keychain.NewDefaultStore(),
			transcriptRecords: make(map[string]*transcriptRecord),
		}
		svc.asrManager = asr.NewManager(asr.NewClient("", ""), svc.dispatchEvent)
		return svc
	}
	svc := &VaultService{
		configPath:        filepath.Join(configDir, "pata", "vault.json"),
		emitEvent:         defaultEmit,
		keychain:          keychain.NewDefaultStore(),
		transcriptRecords: make(map[string]*transcriptRecord),
	}
	svc.asrManager = asr.NewManager(asr.NewClient("", ""), svc.dispatchEvent)
	return svc
}

func (s *VaultService) getASRManager() *asr.Manager {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.asrManager == nil {
		s.asrManager = asr.NewManager(asr.NewClient("", ""), s.dispatchEvent)
	}
	return s.asrManager
}

func (s *VaultService) setASRClient(c *asr.Client) {
	mgr := s.getASRManager()
	mgr.SetClient(c)
}

// ServiceStartup auto-opens the persisted vault; failure leaves the vault closed, not the app dead.
func (s *VaultService) ServiceStartup(ctx context.Context, options application.ServiceOptions) error {
	cfg, err := s.loadConfig()
	if err != nil || cfg.VaultPath == "" {
		return nil // nothing configured yet
	}
	if _, err := s.openVault(cfg.VaultPath); err != nil {
		log.Printf("vault: failed to open persisted vault %s: %v", cfg.VaultPath, err)
	}
	return nil
}

// SelectVaultDirectory shows a native directory picker, persists the choice (single vault)
// and opens it. Cancel returns the unchanged status.
func (s *VaultService) SelectVaultDirectory() (VaultStatus, error) {
	dialog := application.Get().Dialog.OpenFile()
	dialog.SetTitle("选择 Pata Vault 目录")
	dialog.CanChooseFiles(false)
	dialog.CanChooseDirectories(true)
	dialog.CanCreateDirectories(true)
	path, err := dialog.PromptForSingleSelection()
	if err != nil {
		return s.GetVaultStatus(), fmt.Errorf("打开目录选择器失败: %w", err)
	}
	if path == "" { // user cancelled
		return s.GetVaultStatus(), nil
	}
	if _, err := s.openVault(path); err != nil {
		return s.GetVaultStatus(), err
	}
	cfg, _ := s.loadConfig()
	cfg.VaultPath = path
	if err := s.saveConfig(cfg); err != nil {
		return s.GetVaultStatus(), fmt.Errorf("Vault 已打开但保存配置失败: %w", err)
	}
	return s.GetVaultStatus(), nil
}

// GetVaultStatus is cheap and callable before any vault is opened.
func (s *VaultService) GetVaultStatus() VaultStatus {
	s.mu.Lock()
	defer s.mu.Unlock()
	st := VaultStatus{}
	if cfg, err := s.loadConfig(); err == nil && cfg.VaultPath != "" {
		st.Configured = true
		st.Path = cfg.VaultPath
	}
	if s.vault != nil {
		st.Open = true
		st.TaskCount = len(s.vault.Index.ListTasks())
	}
	return st
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

// RescanVault rebuilds the index from disk (manual refresh; watcher handles external changes).
func (s *VaultService) RescanVault() error {
	s.mu.Lock()
	v := s.vault
	s.mu.Unlock()
	if v == nil {
		return fmt.Errorf("尚未打开 Vault")
	}
	return v.Scan()
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
	s.mu.Lock()
	v := s.vault
	s.mu.Unlock()
	if v == nil {
		return nil, fmt.Errorf("尚未打开 Vault")
	}

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
		Status:      status,
		Due:         due,
		Tags:        input.Tags,
		NoteIDs:     cleanedNoteIDs,
		NoteRefs:    cleanNoteRefs(input.NoteRefs),
		CreatedAt:   now,
		UpdatedAt:   now,
	}

	if status == markdown.TaskStatusDone {
		task.CompletedAt = &now
		task.StatusEvents = []markdown.StatusEvent{
			{
				Action: markdown.StatusEventActionCompleted,
				At:     now,
			},
		}
	}

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
	// Status event semantics: record completion or reopen, maintain completed_at
	if existing.Status != markdown.TaskStatusDone && status == markdown.TaskStatusDone {
		existing.CompletedAt = &now
		existing.StatusEvents = append(existing.StatusEvents, markdown.StatusEvent{
			Action: markdown.StatusEventActionCompleted,
			At:     now,
		})
	} else if existing.Status == markdown.TaskStatusDone && status == markdown.TaskStatusTodo {
		existing.CompletedAt = nil
		existing.StatusEvents = append(existing.StatusEvents, markdown.StatusEvent{
			Action: markdown.StatusEventActionReopened,
			At:     now,
		})
	} else if status == markdown.TaskStatusDone && existing.CompletedAt == nil {
		existing.CompletedAt = &now
	}

	var due *string
	if input.Due != nil && strings.TrimSpace(*input.Due) != "" {
		d := strings.TrimSpace(*input.Due)
		due = &d
	}

	existing.Title = title
	existing.Status = status
	existing.Due = due
	existing.Tags = input.Tags
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

// cleanNoteRefs drops blank entries. Bindings to missing notes are kept on purpose:
// a deleted target must stay dangling instead of being re-guessed by title.
func cleanNoteRefs(in map[string]string) map[string]string {
	var out map[string]string
	for k, v := range in {
		k, v = strings.TrimSpace(k), strings.TrimSpace(v)
		if k == "" || v == "" {
			continue
		}
		if out == nil {
			out = map[string]string{}
		}
		out[k] = v
	}
	return out
}

// ListNoteRefs returns all notes (ID, title, vault-relative path) for [[ candidates and link resolution.
func (s *VaultService) ListNoteRefs() ([]markdown.NoteRef, error) {
	s.mu.Lock()
	v := s.vault
	s.mu.Unlock()
	if v == nil {
		return nil, fmt.Errorf("尚未打开 Vault")
	}
	return v.Index.ListNoteRefs(v.RootPath), nil
}

// GetNoteBacklinks returns the notes/tasks referencing noteID, deduped by source identity.
func (s *VaultService) GetNoteBacklinks(noteID string) ([]markdown.LinkSource, error) {
	s.mu.Lock()
	v := s.vault
	s.mu.Unlock()
	if v == nil {
		return nil, fmt.Errorf("尚未打开 Vault")
	}
	return v.Index.Backlinks(strings.TrimSpace(noteID), v.RootPath), nil
}

// validateAndCleanNoteIDs validates that all non-empty note IDs exist in the index.
func validateAndCleanNoteIDs(v *markdown.Vault, noteIDs []string) ([]string, error) {
	if len(noteIDs) == 0 {
		return []string{}, nil
	}
	cleaned := make([]string, len(noteIDs))
	for i, nid := range noteIDs {
		id := strings.TrimSpace(nid)
		if id == "" {
			return nil, fmt.Errorf("笔记 ID 不能为空")
		}
		if _, ok := v.Index.GetNote(id); !ok {
			return nil, fmt.Errorf("笔记不存在: %s", id)
		}
		cleaned[i] = id
	}
	return cleaned, nil
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
	s.mu.Lock()
	v := s.vault
	s.mu.Unlock()
	if v == nil {
		return nil, fmt.Errorf("尚未打开 Vault")
	}

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
	if status == markdown.TaskStatusDone {
		existing.CompletedAt = &now
		existing.StatusEvents = append(existing.StatusEvents, markdown.StatusEvent{
			Action: markdown.StatusEventActionCompleted,
			At:     now,
		})
	} else if existing.Status == markdown.TaskStatusDone {
		existing.CompletedAt = nil
		existing.StatusEvents = append(existing.StatusEvents, markdown.StatusEvent{
			Action: markdown.StatusEventActionReopened,
			At:     now,
		})
	}

	existing.Status = status
	existing.UpdatedAt = now

	baseline := taskBaseline(v, existing)
	if _, err := v.SaveEntity(existing, baseline); err != nil {
		return nil, err
	}

	return existing, nil
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

// CreateActivity creates an activity embedded inside a Task or DayPlan.
func (s *VaultService) CreateActivity(input CreateActivityInput) (*markdown.Activity, error) {
	s.mu.Lock()
	v := s.vault
	s.mu.Unlock()
	if v == nil {
		return nil, fmt.Errorf("尚未打开 Vault")
	}

	body := strings.TrimSpace(input.Body)
	if body == "" {
		return nil, fmt.Errorf("Activity 正文不能为空")
	}

	var tags []string
	for _, tag := range input.Tags {
		cleaned := strings.TrimSpace(strings.TrimPrefix(tag, "#"))
		if cleaned != "" {
			tags = append(tags, cleaned)
		}
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
		Tags:     tags,
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

	var tags []string
	for _, tag := range input.Tags {
		cleaned := strings.TrimSpace(strings.TrimPrefix(tag, "#"))
		if cleaned != "" {
			tags = append(tags, cleaned)
		}
	}

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
				task.Activities[i].Tags = tags
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
				plan.Activities[i].Tags = tags
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

// ListNotes returns all notes from the vault index, newest updated first.
func (s *VaultService) ListNotes() ([]*markdown.Note, error) {
	s.mu.Lock()
	v := s.vault
	s.mu.Unlock()
	if v == nil {
		return nil, fmt.Errorf("尚未打开 Vault")
	}
	return v.Index.ListNotes(), nil
}

// GetNote returns a note by its ID.
func (s *VaultService) GetNote(id string) (*markdown.Note, error) {
	s.mu.Lock()
	v := s.vault
	s.mu.Unlock()
	if v == nil {
		return nil, fmt.Errorf("尚未打开 Vault")
	}

	trimmedID := strings.TrimSpace(id)
	if trimmedID == "" {
		return nil, fmt.Errorf("笔记 ID 不能为空")
	}

	note, ok := v.Index.GetNote(trimmedID)
	if !ok {
		return nil, fmt.Errorf("笔记不存在: %s", trimmedID)
	}
	return note, nil
}

// CreateNote creates a new Note, writes it safely as Markdown, and updates the index.
func (s *VaultService) CreateNote(input CreateNoteInput) (*markdown.Note, error) {
	s.mu.Lock()
	v := s.vault
	s.mu.Unlock()
	if v == nil {
		return nil, fmt.Errorf("尚未打开 Vault")
	}

	title := strings.TrimSpace(input.Title)
	if title == "" {
		return nil, fmt.Errorf("笔记标题不能为空")
	}

	var tags []string
	for _, tag := range input.Tags {
		cleaned := strings.TrimSpace(strings.TrimPrefix(tag, "#"))
		if cleaned != "" {
			tags = append(tags, cleaned)
		}
	}

	now := time.Now()
	note := &markdown.Note{
		Type:      markdown.EntityTypeNote,
		ID:        markdown.GenerateEntityID(markdown.EntityTypeNote),
		Title:     title,
		Tags:      tags,
		CreatedAt: now,
		UpdatedAt: now,
		Body:      input.Body,
	}

	if _, err := v.SaveEntity(note, nil); err != nil {
		return nil, err
	}

	return note, nil
}

// UpdateNote updates an existing Note, safely writes changes to Markdown, and preserves unknown frontmatter.
func (s *VaultService) UpdateNote(input UpdateNoteInput) (*markdown.Note, error) {
	s.mu.Lock()
	v := s.vault
	s.mu.Unlock()
	if v == nil {
		return nil, fmt.Errorf("尚未打开 Vault")
	}

	trimmedID := strings.TrimSpace(input.ID)
	if trimmedID == "" {
		return nil, fmt.Errorf("笔记 ID 不能为空")
	}

	title := strings.TrimSpace(input.Title)
	if title == "" {
		return nil, fmt.Errorf("笔记标题不能为空")
	}

	existing, ok := v.Index.GetNote(trimmedID)
	if !ok {
		return nil, fmt.Errorf("笔记不存在: %s", trimmedID)
	}

	var tags []string
	for _, tag := range input.Tags {
		cleaned := strings.TrimSpace(strings.TrimPrefix(tag, "#"))
		if cleaned != "" {
			tags = append(tags, cleaned)
		}
	}

	now := time.Now()
	existing.Title = title
	existing.Tags = tags
	if !(existing.AudioTranscript && strings.TrimSpace(existing.AudioFile) != "") {
		existing.Body = input.Body
	}
	existing.UpdatedAt = now

	baseline := noteBaseline(v, existing)
	newBaseline, err := v.SaveEntity(existing, baseline)
	if err != nil {
		return nil, err
	}

	s.mu.Lock()
	if s.transcriptRecords != nil {
		if rec, ok := s.transcriptRecords[trimmedID]; ok && rec != nil {
			rec.baseline = newBaseline
		}
	}
	s.mu.Unlock()

	return existing, nil
}

// noteBaseline looks up the baseline for a note directly from the memory index.
func noteBaseline(v *markdown.Vault, note *markdown.Note) *markdown.FileBaseline {
	path := v.ResolveEntityPath(note)
	if b, ok := v.Index.GetBaseline(path); ok {
		return &b
	}
	return nil
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

// GetDayTimeline returns daily timeline items (activities and task completion events) for a given date YYYY-MM-DD in local timezone.
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

	// 1. Task status events (completed / reopened) whose local date matches
	for _, t := range tasks {
		hasCompletionForDate := false
		for _, ev := range t.StatusEvents {
			kind := "completion"
			if ev.Action == markdown.StatusEventActionReopened {
				kind = "reopen"
			} else if ev.Action != markdown.StatusEventActionCompleted {
				continue
			}
			if ev.At.In(time.Local).Format("2006-01-02") == trimmedDate {
				if kind == "completion" {
					hasCompletionForDate = true
				}
				items = append(items, TimelineItem{
					Kind:      kind,
					Time:      ev.At,
					TaskID:    t.ID,
					TaskTitle: t.Title,
				})
			}
		}
		// If task is completed and completed_at falls on this date, but not captured in status_events, include it
		if !hasCompletionForDate && t.Status == markdown.TaskStatusDone && t.CompletedAt != nil {
			if t.CompletedAt.In(time.Local).Format("2006-01-02") == trimmedDate {
				items = append(items, TimelineItem{
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
				Kind:     "activity",
				Time:     act.At,
				Activity: &actClone,
			})
		}
	}

	// Sort descending by Time (newest -> oldest)
	sort.Slice(items, func(i, j int) bool {
		if items[i].Time.Equal(items[j].Time) {
			if items[i].Kind != items[j].Kind {
				return items[i].Kind < items[j].Kind
			}
			idI := ""
			if items[i].Activity != nil {
				idI = items[i].Activity.ID
			} else {
				idI = items[i].TaskID
			}

			idJ := ""
			if items[j].Activity != nil {
				idJ = items[j].Activity.ID
			} else {
				idJ = items[j].TaskID
			}
			return idI > idJ
		}
		return items[i].Time.After(items[j].Time)
	})

	if items == nil {
		return []TimelineItem{}, nil
	}
	return items, nil
}

// GetTagOverview returns aggregated counts of all unique tags across tasks, notes, and activities.
func (s *VaultService) GetTagOverview() ([]markdown.TagOverviewItem, error) {
	s.mu.Lock()
	v := s.vault
	s.mu.Unlock()
	if v == nil {
		return nil, fmt.Errorf("尚未打开 Vault")
	}

	return v.Index.TagOverview(), nil
}

// ListByTag returns all entities matching the specified tag.
// For Activities, tag matching checks act.Tags ∪ parentTask.Tags (for task activities).
func (s *VaultService) ListByTag(tag string) ([]markdown.EntityRef, error) {
	s.mu.Lock()
	v := s.vault
	s.mu.Unlock()
	if v == nil {
		return nil, fmt.Errorf("尚未打开 Vault")
	}

	trimmed := strings.TrimSpace(tag)
	if trimmed == "" {
		return []markdown.EntityRef{}, nil
	}

	refs := v.Index.FindByTag(trimmed)
	result := make([]markdown.EntityRef, len(refs))
	copy(result, refs)

	sort.SliceStable(result, func(i, j int) bool {
		if !result[i].Time.Equal(result[j].Time) {
			return result[i].Time.After(result[j].Time)
		}
		if result[i].Type != result[j].Type {
			return result[i].Type < result[j].Type
		}
		return result[i].ID < result[j].ID
	})

	return result, nil
}

// SearchAll performs case-insensitive substring search across tasks, notes, activities, and files.
// Empty or whitespace-only queries return an empty list without error.
func (s *VaultService) SearchAll(query string) ([]markdown.SearchResultItem, error) {
	s.mu.Lock()
	v := s.vault
	s.mu.Unlock()
	if v == nil {
		return nil, fmt.Errorf("尚未打开 Vault")
	}

	return v.Index.SearchAll(query), nil
}

func generateUniqueFilename(dir, filename string) string {
	ext := filepath.Ext(filename)
	stem := strings.TrimSuffix(filename, ext)
	if stem == "" {
		stem = "file"
	}
	candidate := filename
	counter := 1
	for {
		targetPath := filepath.Join(dir, candidate)
		if _, err := os.Stat(targetPath); os.IsNotExist(err) {
			return candidate
		}
		candidate = fmt.Sprintf("%s %d%s", stem, counter, ext)
		counter++
	}
}

// ListFiles returns all files in the files/ directory of the vault.
func (s *VaultService) ListFiles() ([]markdown.FileResource, error) {
	s.mu.Lock()
	v := s.vault
	s.mu.Unlock()
	if v == nil {
		return nil, fmt.Errorf("尚未打开 Vault")
	}
	return v.Index.ListFiles(), nil
}

// ImportFile safely copies an external file into the vault's files/ directory without overwriting.
func (s *VaultService) ImportFile(sourcePath string) (*markdown.FileResource, error) {
	s.mu.Lock()
	v := s.vault
	s.mu.Unlock()
	if v == nil {
		return nil, fmt.Errorf("尚未打开 Vault")
	}

	cleanSrc := filepath.Clean(strings.TrimSpace(sourcePath))
	fi, err := os.Stat(cleanSrc)
	if err != nil {
		return nil, fmt.Errorf("读取源文件失败: %w", err)
	}
	if fi.IsDir() {
		return nil, fmt.Errorf("源路径是一个目录，仅支持导入文件")
	}

	filesDir := filepath.Join(v.RootPath, "files")
	if err := os.MkdirAll(filesDir, 0755); err != nil {
		return nil, fmt.Errorf("创建 files 目录失败: %w", err)
	}

	baseName := filepath.Base(cleanSrc)
	var (
		uniqueName string
		targetPath string
		baseline   *markdown.FileBaseline
	)

	const maxRetries = 100
	for attempt := 0; attempt < maxRetries; attempt++ {
		uniqueName = generateUniqueFilename(filesDir, baseName)
		targetPath = filepath.Join(filesDir, uniqueName)

		b, err := markdown.SafeCopyFile(cleanSrc, targetPath, v.Tracker)
		if err != nil {
			if errors.Is(err, os.ErrExist) {
				// Target appeared concurrently during streamed copy; retry with a new unique filename
				continue
			}
			return nil, fmt.Errorf("保存文件至 files/ 失败: %w", err)
		}
		baseline = b
		break
	}
	if baseline == nil {
		return nil, fmt.Errorf("保存文件至 files/ 失败: 无法生成唯一文件名")
	}

	relPath := "files/" + uniqueName
	res := markdown.FileResource{
		Path:    relPath,
		Name:    uniqueName,
		Ext:     filepath.Ext(uniqueName),
		Size:    fi.Size(),
		ModTime: baseline.ModTime,
	}

	v.Index.PutFile(res)
	s.dispatchEvent(EventVaultChanged, VaultChangeEvent{
		Op:       "create",
		Path:     targetPath,
		EntityID: relPath,
		Type:     string(markdown.EntityTypeFile),
	})

	return &res, nil
}

// ImportFileData saves base64-encoded binary data into the vault's files/ directory.
func (s *VaultService) ImportFileData(name string, base64Data string) (*markdown.FileResource, error) {
	s.mu.Lock()
	v := s.vault
	s.mu.Unlock()
	if v == nil {
		return nil, fmt.Errorf("尚未打开 Vault")
	}

	cleanName := filepath.Base(strings.TrimSpace(name))
	if cleanName == "" || cleanName == "." {
		cleanName = "attachment"
	}

	rawB64 := base64Data
	if commaIdx := strings.Index(rawB64, ","); commaIdx != -1 {
		rawB64 = rawB64[commaIdx+1:]
	}

	data, err := base64.StdEncoding.DecodeString(rawB64)
	if err != nil {
		return nil, fmt.Errorf("base64 解码失败: %w", err)
	}

	filesDir := filepath.Join(v.RootPath, "files")
	if err := os.MkdirAll(filesDir, 0755); err != nil {
		return nil, fmt.Errorf("创建 files 目录失败: %w", err)
	}

	var (
		uniqueName string
		targetPath string
		baseline   *markdown.FileBaseline
	)

	const maxRetries = 100
	for attempt := 0; attempt < maxRetries; attempt++ {
		uniqueName = generateUniqueFilename(filesDir, cleanName)
		targetPath = filepath.Join(filesDir, uniqueName)

		b, err := markdown.SafeWriteExclusive(targetPath, data, v.Tracker)
		if err != nil {
			if errors.Is(err, os.ErrExist) {
				// Target appeared concurrently during write; retry with a new unique filename
				continue
			}
			return nil, fmt.Errorf("写入文件失败: %w", err)
		}
		baseline = b
		break
	}
	if baseline == nil {
		return nil, fmt.Errorf("写入文件失败: 无法生成唯一文件名")
	}

	relPath := "files/" + uniqueName
	res := markdown.FileResource{
		Path:    relPath,
		Name:    uniqueName,
		Ext:     filepath.Ext(uniqueName),
		Size:    int64(len(data)),
		ModTime: baseline.ModTime,
	}

	v.Index.PutFile(res)
	s.dispatchEvent(EventVaultChanged, VaultChangeEvent{
		Op:       "create",
		Path:     targetPath,
		EntityID: relPath,
		Type:     string(markdown.EntityTypeFile),
	})

	return &res, nil
}

func (s *VaultService) resolveSafeFilePath(filePath string) (string, error) {
	s.mu.Lock()
	v := s.vault
	s.mu.Unlock()
	if v == nil {
		return "", fmt.Errorf("尚未打开 Vault")
	}

	absPath, _, err := markdown.SafeResolveVaultPath(v.RootPath, filePath)
	if err != nil {
		return "", fmt.Errorf("非法文件路径: %w", err)
	}

	if _, err := os.Stat(absPath); err != nil {
		return "", fmt.Errorf("文件不存在或已移动: %s", filePath)
	}

	return absPath, nil
}

func startAndReap(cmd *exec.Cmd) error {
	if err := cmd.Start(); err != nil {
		return err
	}
	go func() {
		_ = cmd.Wait()
	}()
	return nil
}

func (s *VaultService) runCommand(cmd *exec.Cmd) error {
	if s.launcher != nil {
		return s.launcher(cmd)
	}
	return startAndReap(cmd)
}

// PreviewFile invokes the macOS Quick Look preview or system preview for a file in the vault.
func (s *VaultService) PreviewFile(filePath string) error {
	absPath, err := s.resolveSafeFilePath(filePath)
	if err != nil {
		return err
	}

	if runtime.GOOS == "darwin" {
		cmd := exec.Command("qlmanage", "-p", absPath)
		if err := s.runCommand(cmd); err == nil {
			return nil
		}
	}

	return s.OpenFile(filePath)
}

// OpenFile opens a file in the vault with the system default application.
func (s *VaultService) OpenFile(filePath string) error {
	absPath, err := s.resolveSafeFilePath(filePath)
	if err != nil {
		return err
	}

	var cmd *exec.Cmd
	switch runtime.GOOS {
	case "darwin":
		cmd = exec.Command("open", absPath)
	case "windows":
		cmd = exec.Command("cmd", "/c", "start", "", absPath)
	default:
		cmd = exec.Command("xdg-open", absPath)
	}

	return s.runCommand(cmd)
}

// RevealInFinder reveals a file inside Finder (or Explorer on Windows).
func (s *VaultService) RevealInFinder(filePath string) error {
	absPath, err := s.resolveSafeFilePath(filePath)
	if err != nil {
		return err
	}

	var cmd *exec.Cmd
	switch runtime.GOOS {
	case "darwin":
		cmd = exec.Command("open", "-R", absPath)
	case "windows":
		cmd = exec.Command("explorer", "/select,", absPath)
	default:
		cmd = exec.Command("xdg-open", filepath.Dir(absPath))
	}

	return s.runCommand(cmd)
}

// GetVaultHealth returns the current health status of the vault, including parse errors and dangling references.
func (s *VaultService) GetVaultHealth() (*VaultHealth, error) {
	s.mu.Lock()
	v := s.vault
	s.mu.Unlock()
	if v == nil {
		return nil, fmt.Errorf("尚未打开 Vault")
	}

	parseErrs := v.Index.ListParseErrors()
	if parseErrs == nil {
		parseErrs = []markdown.ParseError{}
	}
	dangling := v.Index.ListDanglingReferences()
	if dangling == nil {
		dangling = []markdown.DanglingRef{}
	}

	return &VaultHealth{
		ParseErrors:  parseErrs,
		DanglingRefs: dangling,
	}, nil
}

func (s *VaultService) dispatchEvent(name string, data any) {
	s.mu.Lock()
	emit := s.emitEvent
	s.mu.Unlock()
	if emit != nil {
		emit(name, data)
	}
}

func (s *VaultService) openVault(path string) (*markdown.Vault, error) {
	v, err := markdown.NewVault(path)
	if err != nil {
		return nil, fmt.Errorf("打开 Vault 失败: %w", err)
	}
	if err := v.StartWatcher(); err != nil {
		log.Printf("vault: watcher failed to start, relying on rescan: %v", err)
	}
	stopRescan := v.StartPeriodicRescan(30 * time.Second)

	stopForwarder := make(chan struct{})
	go s.forwardVaultEvents(v.Events(), stopForwarder)

	s.mu.Lock()
	oldVault := s.vault
	oldStop := s.stopWatcher
	s.vault = v
	if oldVault != nil && filepath.Clean(oldVault.RootPath) != filepath.Clean(v.RootPath) {
		// Vault changed: scope ASR state by clearing prior vault's transcript records and cancelling active tasks
		s.transcriptRecords = make(map[string]*transcriptRecord)
		if s.asrManager != nil {
			s.asrManager.Reset()
		}
	}
	var stopOnce sync.Once
	s.stopWatcher = func() {
		stopOnce.Do(func() {
			close(stopForwarder)
			stopRescan()
			_ = v.StopWatcher()
		})
	}
	s.mu.Unlock()

	if oldStop != nil {
		oldStop()
	}
	return v, nil
}

func (s *VaultService) forwardVaultEvents(events <-chan markdown.VaultEvent, stop <-chan struct{}) {
	for {
		select {
		case <-stop:
			return
		case ev, ok := <-events:
			if !ok {
				return
			}
			payload := VaultChangeEvent{
				Op:       string(ev.Op),
				Path:     ev.Path,
				EntityID: ev.EntityID,
				Type:     string(ev.Type),
			}
			s.dispatchEvent(EventVaultChanged, payload)
		}
	}
}

func (s *VaultService) loadConfig() (VaultConfig, error) {
	var cfg VaultConfig
	if s.configPath == "" {
		return cfg, fmt.Errorf("persistence disabled")
	}
	data, err := os.ReadFile(s.configPath)
	if os.IsNotExist(err) {
		return cfg, nil
	}
	if err != nil {
		return cfg, err
	}
	err = json.Unmarshal(data, &cfg)
	return cfg, err
}

func (s *VaultService) saveConfig(cfg VaultConfig) error {
	if s.configPath == "" {
		return fmt.Errorf("persistence disabled")
	}
	if err := os.MkdirAll(filepath.Dir(s.configPath), 0755); err != nil {
		return err
	}
	data, err := json.MarshalIndent(cfg, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(s.configPath, data, 0644)
}

// setKeychainStore overrides the keychain store, primarily for testing.
func (s *VaultService) setKeychainStore(k keychain.Store) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.keychain = k
}

// GetThemePreference returns the persisted theme preference ("system", "light", or "dark").
func (s *VaultService) GetThemePreference() (string, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	cfg, err := s.loadConfig()
	if err != nil || cfg.Theme == "" {
		return "system", nil
	}
	return cfg.Theme, nil
}

// SetThemePreference persists the theme preference ("system", "light", or "dark").
func (s *VaultService) SetThemePreference(theme string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	theme = strings.TrimSpace(strings.ToLower(theme))
	if theme != "system" && theme != "light" && theme != "dark" {
		return fmt.Errorf("无效的主题选项: %s，仅支持 system, light, dark", theme)
	}
	cfg, err := s.loadConfig()
	if err != nil {
		return fmt.Errorf("读取配置文件失败: %w", err)
	}
	if cfg.VaultPath == "" && s.vault != nil && s.vault.RootPath != "" {
		cfg.VaultPath = s.vault.RootPath
	}
	cfg.Theme = theme
	return s.saveConfig(cfg)
}

// OpenVaultInFinder opens the current vault root directory in Finder (or native file explorer).
func (s *VaultService) OpenVaultInFinder() error {
	s.mu.Lock()
	v := s.vault
	s.mu.Unlock()
	if v == nil {
		return fmt.Errorf("Vault 尚未打开")
	}
	path := v.RootPath
	if path == "" {
		return fmt.Errorf("Vault 路径为空")
	}
	fi, err := os.Stat(path)
	if err != nil || !fi.IsDir() {
		return fmt.Errorf("Vault 目录不存在或无法访问: %s", path)
	}

	var cmd *exec.Cmd
	switch runtime.GOOS {
	case "darwin":
		cmd = exec.Command("open", path)
	case "windows":
		cmd = exec.Command("explorer", path)
	default:
		cmd = exec.Command("xdg-open", path)
	}

	return s.runCommand(cmd)
}

// GetASRConfigStatus returns the current transcription configuration status.
// React/Wails frontend only receives the configured status; plain key is never returned.
func (s *VaultService) GetASRConfigStatus() (ASRConfigStatus, error) {
	status := ASRConfigStatus{
		Configured: false,
		Provider:   ASRProvider,
		Model:      ASRModel,
		Region:     ASRRegion,
	}

	s.mu.Lock()
	k := s.keychain
	s.mu.Unlock()

	if k == nil {
		return status, nil
	}

	secret, err := k.Get(ASRKeychainService, ASRKeychainAccount)
	if err != nil {
		if errors.Is(err, keychain.ErrNotFound) {
			return status, nil
		}
		return status, fmt.Errorf("查询 Keychain 状态失败: %w", err)
	}

	if strings.TrimSpace(secret) != "" {
		status.Configured = true
	}
	return status, nil
}

// SetASRKey saves or updates the Qwen-Audio ASR API Key into macOS Keychain.
// Notice: Key is never logged and never returned to the frontend.
func (s *VaultService) SetASRKey(key string) error {
	trimmed := strings.TrimSpace(key)
	if trimmed == "" {
		return fmt.Errorf("API Key 不能为空")
	}

	s.mu.Lock()
	k := s.keychain
	s.mu.Unlock()

	if k == nil {
		return fmt.Errorf("Keychain 存储不可用")
	}

	if err := k.Set(ASRKeychainService, ASRKeychainAccount, trimmed); err != nil {
		return fmt.Errorf("保存 API Key 到 Keychain 失败: %w", err)
	}

	log.Println("ASR API Key 成功更新至系统 Keychain")
	return nil
}

// getASRKeyInternal retrieves the plain API Key from Keychain for internal backend ASR calls (Stage 11).
// It is deliberately unexported so Wails will never expose it to frontend IPC bindings.
func (s *VaultService) getASRKeyInternal() (string, error) {
	s.mu.Lock()
	k := s.keychain
	s.mu.Unlock()

	if k == nil {
		return "", fmt.Errorf("Keychain 存储未就绪")
	}
	secret, err := k.Get(ASRKeychainService, ASRKeychainAccount)
	if err != nil {
		if errors.Is(err, keychain.ErrNotFound) {
			return "", fmt.Errorf("未配置语音转写 API Key，请在设置中配置")
		}
		return "", fmt.Errorf("读取 Keychain 失败: %w", err)
	}
	trimmed := strings.TrimSpace(secret)
	if trimmed == "" {
		return "", fmt.Errorf("语音转写 API Key 为空，请在设置中重新配置")
	}
	return trimmed, nil
}

// SelectAudioFile opens a native dialog for selecting an MP3 audio file.
func (s *VaultService) SelectAudioFile() (string, error) {
	app := application.Get()
	if app == nil || app.Dialog == nil {
		return "", fmt.Errorf("桌面对话框不可用")
	}
	dialog := app.Dialog.OpenFile()
	dialog.SetTitle("选择要转写的 MP3 音频文件")
	dialog.CanChooseFiles(true)
	dialog.CanChooseDirectories(false)
	dialog.AddFilter("MP3 音频 (*.mp3)", "*.mp3")
	path, err := dialog.PromptForSingleSelection()
	if err != nil {
		return "", fmt.Errorf("打开文件选择器失败: %w", err)
	}
	return path, nil
}

// CreateAudioNote imports an MP3 audio file into files/, creates an audio transcript Note immediately,
// and starts the asynchronous transcription pipeline in the background.
func (s *VaultService) CreateAudioNote(sourcePath string) (*markdown.Note, error) {
	cleanSrc := filepath.Clean(strings.TrimSpace(sourcePath))
	ext := strings.ToLower(filepath.Ext(cleanSrc))
	if ext != ".mp3" {
		return nil, fmt.Errorf("第一版仅支持导入 MP3 格式音频文件")
	}

	// Try retrieving API key (if unconfigured, task will report failure, but Note and MP3 are preserved)
	apiKey, _ := s.getASRKeyInternal()

	// 1. Import file to files/ (copies without overwriting)
	res, err := s.ImportFile(cleanSrc)
	if err != nil {
		return nil, fmt.Errorf("导入音频文件失败: %w", err)
	}

	s.mu.Lock()
	v := s.vault
	s.mu.Unlock()
	if v == nil {
		return nil, fmt.Errorf("尚未打开 Vault")
	}

	// Derive default note title from base name without .mp3
	title := strings.TrimSuffix(res.Name, filepath.Ext(res.Name))
	if strings.TrimSpace(title) == "" {
		title = "音频逐字稿"
	}

	now := time.Now()
	note := &markdown.Note{
		Type:            markdown.EntityTypeNote,
		ID:              markdown.GenerateEntityID(markdown.EntityTypeNote),
		Title:           title,
		Tags:            []string{},
		AudioFile:       res.Path,
		AudioTranscript: true,
		CreatedAt:       now,
		UpdatedAt:       now,
		Body:            "",
	}

	initBaseline, err := v.SaveEntity(note, nil)
	if err != nil {
		return nil, fmt.Errorf("创建逐字稿笔记失败: %w", err)
	}

	noteID := note.ID
	rec := &transcriptRecord{
		vault:        v,
		baseline:     initBaseline,
		expectedBody: "",
	}
	s.mu.Lock()
	if s.transcriptRecords == nil {
		s.transcriptRecords = make(map[string]*transcriptRecord)
	}
	s.transcriptRecords[noteID] = rec
	s.mu.Unlock()

	// 2. Start asynchronous transcription in background
	originVault := v
	audioAbsPath := filepath.Join(v.RootPath, filepath.FromSlash(res.Path))
	mgr := s.getASRManager()
	cleanup := func(state asr.ASRTaskState) {
		if state == asr.StateFailed || state == asr.StateCompleted {
			s.mu.Lock()
			if s.transcriptRecords != nil && s.transcriptRecords[noteID] == rec {
				delete(s.transcriptRecords, noteID)
			}
			s.mu.Unlock()
		}
	}
	if !mgr.StartTask(noteID, audioAbsPath, false, apiKey, func(transcriptBody string) error {
		return s.saveTranscriptBody(originVault, noteID, transcriptBody)
	}, cleanup) {
		s.mu.Lock()
		if s.transcriptRecords != nil && s.transcriptRecords[noteID] == rec {
			delete(s.transcriptRecords, noteID)
		}
		s.mu.Unlock()
	}

	return note, nil
}

// CreateAudioNoteData imports base64 MP3 audio data into files/, creates an audio transcript Note immediately,
// and starts the asynchronous transcription pipeline in the background.
func (s *VaultService) CreateAudioNoteData(name string, base64Data string) (*markdown.Note, error) {
	cleanName := filepath.Base(strings.TrimSpace(name))
	ext := strings.ToLower(filepath.Ext(cleanName))
	if ext != ".mp3" {
		return nil, fmt.Errorf("第一版仅支持导入 MP3 格式音频文件")
	}

	apiKey, _ := s.getASRKeyInternal()

	res, err := s.ImportFileData(cleanName, base64Data)
	if err != nil {
		return nil, fmt.Errorf("导入音频数据失败: %w", err)
	}

	s.mu.Lock()
	v := s.vault
	s.mu.Unlock()
	if v == nil {
		return nil, fmt.Errorf("尚未打开 Vault")
	}

	title := strings.TrimSuffix(res.Name, filepath.Ext(res.Name))
	if strings.TrimSpace(title) == "" {
		title = "音频逐字稿"
	}

	now := time.Now()
	note := &markdown.Note{
		Type:            markdown.EntityTypeNote,
		ID:              markdown.GenerateEntityID(markdown.EntityTypeNote),
		Title:           title,
		Tags:            []string{},
		AudioFile:       res.Path,
		AudioTranscript: true,
		CreatedAt:       now,
		UpdatedAt:       now,
		Body:            "",
	}

	initBaseline, err := v.SaveEntity(note, nil)
	if err != nil {
		return nil, fmt.Errorf("创建逐字稿笔记失败: %w", err)
	}

	noteID := note.ID
	rec := &transcriptRecord{
		vault:        v,
		baseline:     initBaseline,
		expectedBody: "",
	}
	s.mu.Lock()
	if s.transcriptRecords == nil {
		s.transcriptRecords = make(map[string]*transcriptRecord)
	}
	s.transcriptRecords[noteID] = rec
	s.mu.Unlock()

	originVault := v
	audioAbsPath := filepath.Join(v.RootPath, filepath.FromSlash(res.Path))
	mgr := s.getASRManager()
	cleanup := func(state asr.ASRTaskState) {
		if state == asr.StateFailed || state == asr.StateCompleted {
			s.mu.Lock()
			if s.transcriptRecords != nil && s.transcriptRecords[noteID] == rec {
				delete(s.transcriptRecords, noteID)
			}
			s.mu.Unlock()
		}
	}
	if !mgr.StartTask(noteID, audioAbsPath, false, apiKey, func(transcriptBody string) error {
		return s.saveTranscriptBody(originVault, noteID, transcriptBody)
	}, cleanup) {
		s.mu.Lock()
		if s.transcriptRecords != nil && s.transcriptRecords[noteID] == rec {
			delete(s.transcriptRecords, noteID)
		}
		s.mu.Unlock()
	}

	return note, nil
}

func (s *VaultService) saveTranscriptBody(v *markdown.Vault, noteID string, transcriptBody string) error {
	s.mu.Lock()
	activeVault := s.vault
	s.mu.Unlock()
	if activeVault == nil || v == nil {
		return fmt.Errorf("Vault 为空")
	}
	if filepath.Clean(v.RootPath) != filepath.Clean(activeVault.RootPath) {
		return fmt.Errorf("逐字稿任务所属 Vault 与当前激活 Vault 不一致，已取消写入")
	}
	if strings.TrimSpace(transcriptBody) == "" {
		return fmt.Errorf("逐字稿内容为空，未识别到有效内容")
	}

	existing, ok := activeVault.Index.GetNote(noteID)
	if !ok {
		return fmt.Errorf("目标笔记不存在: %s", noteID)
	}

	s.mu.Lock()
	var rec *transcriptRecord
	if s.transcriptRecords != nil {
		rec = s.transcriptRecords[noteID]
	}
	s.mu.Unlock()

	// Reject if note's body was modified externally
	if rec != nil {
		if strings.TrimSpace(existing.Body) != strings.TrimSpace(rec.expectedBody) {
			return fmt.Errorf("笔记正文在生成逐字稿期间已被外部修改，已取消写入以保护外部编辑")
		}
	}

	// Reject if external editor changed the file (trusted in-app UpdateNote updates rec.baseline)
	currentBaseline := noteBaseline(v, existing)
	if rec != nil && rec.baseline != nil && currentBaseline != nil {
		if rec.baseline.Hash != currentBaseline.Hash {
			return fmt.Errorf("笔记在生成逐字稿期间已被外部修改，已取消写入以保护外部编辑")
		}
	}

	existing.Body = transcriptBody
	existing.UpdatedAt = time.Now()

	saveBaseline := currentBaseline
	if rec != nil && rec.baseline != nil {
		saveBaseline = rec.baseline
	}
	if _, err := v.SaveEntity(existing, saveBaseline); err != nil {
		return err
	}

	s.mu.Lock()
	if s.transcriptRecords != nil {
		delete(s.transcriptRecords, noteID)
	}
	s.mu.Unlock()

	return nil
}

// StartAudioTranscription triggers or retries transcription on an existing Note.
func (s *VaultService) StartAudioTranscription(noteID string) error {
	s.mu.Lock()
	v := s.vault
	s.mu.Unlock()
	if v == nil {
		return fmt.Errorf("尚未打开 Vault")
	}

	trimmedID := strings.TrimSpace(noteID)
	if trimmedID == "" {
		return fmt.Errorf("笔记 ID 不能为空")
	}

	mgr := s.getASRManager()
	currStatus := mgr.GetStatus(trimmedID)
	if currStatus.State == asr.StatePendingConfirmation {
		return fmt.Errorf("当前逐字稿已有待确认的新结果，请先确认替换或放弃")
	}
	if currStatus.State == asr.StateUploading || currStatus.State == asr.StateTranscribing || currStatus.State == asr.StateWriting {
		return fmt.Errorf("当前笔记已有正在进行的转写任务")
	}

	note, ok := v.Index.GetNote(trimmedID)
	if !ok {
		mgr.SetTaskFailed(trimmedID, "笔记不存在", fmt.Sprintf("笔记不存在: %s", trimmedID))
		return fmt.Errorf("笔记不存在: %s", trimmedID)
	}

	if !note.AudioTranscript || note.AudioFile == "" {
		mgr.SetTaskFailed(trimmedID, "类型错误", "该笔记不是音频逐字稿笔记")
		return fmt.Errorf("该笔记不是音频逐字稿笔记")
	}

	apiKey, err := s.getASRKeyInternal()
	if err != nil {
		mgr.SetTaskFailed(trimmedID, "未配置 API Key", err.Error())
		return err
	}

	audioAbsPath, err := s.resolveSafeFilePath(note.AudioFile)
	if err != nil {
		mgr.SetTaskFailed(trimmedID, "音频文件失效", "关联音频文件不存在或失效: "+err.Error())
		return fmt.Errorf("关联音频文件不存在或失效: %w", err)
	}

	isRetranscribe := strings.TrimSpace(note.Body) != ""
	var initBaseline *markdown.FileBaseline
	b := noteBaseline(v, note)
	if b != nil {
		cp := *b
		initBaseline = &cp
	}
	rec := &transcriptRecord{
		vault:        v,
		baseline:     initBaseline,
		expectedBody: note.Body,
	}
	s.mu.Lock()
	if s.transcriptRecords == nil {
		s.transcriptRecords = make(map[string]*transcriptRecord)
	}
	s.transcriptRecords[trimmedID] = rec
	s.mu.Unlock()

	originVault := v
	cleanup := func(state asr.ASRTaskState) {
		if state == asr.StateFailed || state == asr.StateCompleted {
			s.mu.Lock()
			if s.transcriptRecords != nil && s.transcriptRecords[trimmedID] == rec {
				delete(s.transcriptRecords, trimmedID)
			}
			s.mu.Unlock()
		}
	}
	if !mgr.StartTask(trimmedID, audioAbsPath, isRetranscribe, apiKey, func(transcriptBody string) error {
		return s.saveTranscriptBody(originVault, trimmedID, transcriptBody)
	}, cleanup) {
		s.mu.Lock()
		if s.transcriptRecords != nil && s.transcriptRecords[trimmedID] == rec {
			delete(s.transcriptRecords, trimmedID)
		}
		s.mu.Unlock()
		return fmt.Errorf("当前逐字稿已有正在进行的转写任务或等待确认")
	}

	return nil
}

// GetASRTaskStatus returns the current in-memory transcription status for a note.
func (s *VaultService) GetASRTaskStatus(noteID string) (asr.ASRTaskStatus, error) {
	trimmedID := strings.TrimSpace(noteID)
	if trimmedID == "" {
		return asr.ASRTaskStatus{}, fmt.Errorf("笔记 ID 不能为空")
	}
	mgr := s.getASRManager()
	return mgr.GetStatus(trimmedID), nil
}

// ConfirmReplaceTranscript applies the candidate re-transcription result to the Note body.
func (s *VaultService) ConfirmReplaceTranscript(noteID string) (*markdown.Note, error) {
	trimmedID := strings.TrimSpace(noteID)
	if trimmedID == "" {
		return nil, fmt.Errorf("笔记 ID 不能为空")
	}

	s.mu.Lock()
	var rec *transcriptRecord
	if s.transcriptRecords != nil {
		rec = s.transcriptRecords[trimmedID]
	}
	activeVault := s.vault
	s.mu.Unlock()

	if activeVault == nil {
		return nil, fmt.Errorf("尚未打开 Vault")
	}

	if rec != nil && rec.vault != nil && filepath.Clean(rec.vault.RootPath) != filepath.Clean(activeVault.RootPath) {
		return nil, fmt.Errorf("逐字稿任务所属 Vault 与当前激活 Vault 不一致，已取消替换")
	}

	targetVault := activeVault
	var candidateBaseline *markdown.FileBaseline
	if rec != nil {
		candidateBaseline = rec.baseline
	}

	mgr := s.getASRManager()
	var updatedNote *markdown.Note
	err := mgr.ConfirmReplace(trimmedID, func(transcriptBody string) error {
		existing, ok := targetVault.Index.GetNote(trimmedID)
		if !ok {
			return fmt.Errorf("笔记不存在: %s", trimmedID)
		}

		// Reject replacement if note's body was modified externally
		if rec != nil {
			if strings.TrimSpace(existing.Body) != strings.TrimSpace(rec.expectedBody) {
				return fmt.Errorf("笔记在生成逐字稿候选期间正文已被外部修改，已取消替换以保护外部编辑")
			}
		}

		// Reject replacement if note was modified externally since candidate was generated
		currentBaseline := noteBaseline(targetVault, existing)
		if candidateBaseline != nil && currentBaseline != nil {
			if candidateBaseline.Hash != currentBaseline.Hash {
				return fmt.Errorf("笔记在生成逐字稿候选期间已被外部修改，已取消替换以保护外部编辑")
			}
		}

		existing.Body = transcriptBody
		existing.UpdatedAt = time.Now()
		// Save with candidateBaseline so disk-level concurrency check catches external edits
		if _, err := targetVault.SaveEntity(existing, candidateBaseline); err != nil {
			return err
		}
		updatedNote = existing
		return nil
	})
	if err != nil {
		return nil, err
	}

	s.mu.Lock()
	if s.transcriptRecords != nil && s.transcriptRecords[trimmedID] == rec {
		delete(s.transcriptRecords, trimmedID)
	}
	s.mu.Unlock()

	return updatedNote, nil
}

// DiscardCandidateTranscript discards candidate re-transcription results.
func (s *VaultService) DiscardCandidateTranscript(noteID string) error {
	trimmedID := strings.TrimSpace(noteID)
	if trimmedID == "" {
		return fmt.Errorf("笔记 ID 不能为空")
	}
	s.mu.Lock()
	if s.transcriptRecords != nil {
		delete(s.transcriptRecords, trimmedID)
	}
	s.mu.Unlock()

	mgr := s.getASRManager()
	mgr.DiscardCandidate(trimmedID)
	return nil
}

// GetAudioURL returns the internal asset URL to stream/play a vault audio file.
func (s *VaultService) GetAudioURL(filePath string) (string, error) {
	_, err := s.resolveSafeFilePath(filePath)
	if err != nil {
		return "", err
	}
	cleanRel := filepath.ToSlash(filepath.Clean(strings.TrimSpace(filePath)))
	cleanRel = strings.TrimPrefix(cleanRel, "/")
	segments := strings.Split(cleanRel, "/")
	for i, seg := range segments {
		segments[i] = url.PathEscape(seg)
	}
	return "/vault-audio/" + strings.Join(segments, "/"), nil
}

// GetAudioData returns the base64 data URI of a vault audio file (fallback/testing).
func (s *VaultService) GetAudioData(filePath string) (string, error) {
	absPath, err := s.resolveSafeFilePath(filePath)
	if err != nil {
		return "", err
	}
	data, err := os.ReadFile(absPath)
	if err != nil {
		return "", fmt.Errorf("读取音频文件失败: %w", err)
	}
	encoded := base64.StdEncoding.EncodeToString(data)
	return "data:audio/mpeg;base64," + encoded, nil
}
