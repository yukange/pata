package markdown

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/fsnotify/fsnotify"
)

// ChangeOp represents an event operation in Vault.
type ChangeOp string

const (
	ChangeOpCreate ChangeOp = "create"
	ChangeOpUpdate ChangeOp = "update"
	ChangeOpDelete ChangeOp = "delete"
	ChangeOpError  ChangeOp = "error"
)

// VaultEvent is dispatched when an external or processed change occurs in Vault.
type VaultEvent struct {
	Op       ChangeOp   `json:"op"`
	Path     string     `json:"path"`
	EntityID string     `json:"entity_id,omitempty"`
	Type     EntityType `json:"type,omitempty"`
	Err      error      `json:"err,omitempty"`
}

// Vault manages the Markdown storage directory, safety writes, in-memory index, and filesystem watcher.
type Vault struct {
	RootPath string
	Index    *MemoryIndex
	Tracker  *WriteTracker

	// MutationMu guards complete read-modify-save operations, watcher updates, and rescans.
	MutationMu sync.Mutex

	mu      sync.Mutex
	watcher *fsnotify.Watcher
	events  chan VaultEvent
	stopCh  chan struct{}
	running bool
}

// NewVault initializes a Vault with root path and builds the initial index.
func NewVault(rootPath string) (*Vault, error) {
	absRoot, err := filepath.Abs(rootPath)
	if err != nil {
		return nil, fmt.Errorf("failed to get absolute vault root: %w", err)
	}

	if err := os.MkdirAll(absRoot, 0755); err != nil {
		return nil, fmt.Errorf("failed to create vault directory: %w", err)
	}

	for _, dir := range []string{"tasks", "notes", "plans", "files"} {
		_ = os.MkdirAll(filepath.Join(absRoot, dir), 0755)
	}

	index, err := ScanVault(absRoot)
	if err != nil {
		return nil, fmt.Errorf("initial vault scan failed: %w", err)
	}

	return &Vault{
		RootPath: absRoot,
		Index:    index,
		Tracker:  NewWriteTracker(3 * time.Second),
		events:   make(chan VaultEvent, 100),
		stopCh:   make(chan struct{}),
	}, nil
}

// Events returns the channel receiving external change events.
func (v *Vault) Events() <-chan VaultEvent {
	return v.events
}

// Scan rescans the vault from disk and replaces the memory index atomically.
func (v *Vault) Scan() error {
	v.MutationMu.Lock()
	defer v.MutationMu.Unlock()

	newIndex, err := ScanVault(v.RootPath)
	if err != nil {
		return err
	}

	v.Index.mu.Lock()
	newIndex.mu.RLock()
	v.Index.tasks = newIndex.tasks
	v.Index.notes = newIndex.notes
	v.Index.dayPlans = newIndex.dayPlans
	v.Index.files = newIndex.files
	v.Index.fileToID = newIndex.fileToID
	v.Index.idToFile = newIndex.idToFile
	v.Index.activityLocs = newIndex.activityLocs
	v.Index.baselines = newIndex.baselines
	v.Index.danglingRefs = newIndex.danglingRefs
	v.Index.parseErrors = newIndex.parseErrors
	v.Index.vaultRoot = newIndex.vaultRoot
	// 注释: Scan 清空 pendingMoves 与 Remove 事件存在竞态窗口(最长 30s 周期重扫闪失、重扫自愈，属已知可接受).
	v.Index.pendingMoves = make(map[string]pendingMove)
	newIndex.mu.RUnlock()
	v.Index.mu.Unlock()

	return nil
}

// ResolveEntityPath determines the appropriate disk path for an entity.
func (v *Vault) ResolveEntityPath(entity Entity) string {
	v.Index.mu.RLock()
	if existingPath, ok := v.Index.idToFile[entity.GetID()]; ok {
		v.Index.mu.RUnlock()
		return existingPath
	}
	v.Index.mu.RUnlock()

	filename := FormatEntityFilename(entity)
	switch entity.(type) {
	case *Task:
		return filepath.Join(v.RootPath, "tasks", filename)
	case *Note:
		return filepath.Join(v.RootPath, "notes", filename)
	case *DayPlan:
		return filepath.Join(v.RootPath, "plans", filename)
	default:
		return filepath.Join(v.RootPath, filename)
	}
}

// SaveEntity safely writes an entity to disk and updates the index.
// Callers must hold MutationMu from reading the entity and its baseline through saving.
func (v *Vault) SaveEntity(entity Entity, baseline *FileBaseline) (*FileBaseline, error) {
	if entity == nil {
		return nil, fmt.Errorf("entity cannot be nil")
	}

	// Validate entity schema before attempting to write
	if err := ValidateEntity("", entity); err != nil {
		return nil, fmt.Errorf("cannot save invalid entity: %w", err)
	}

	path := v.ResolveEntityPath(entity)

	data, err := SerializeMarkdown(entity)
	if err != nil {
		return nil, fmt.Errorf("failed to serialize entity: %w", err)
	}

	newBaseline, err := SafeWrite(path, data, baseline, v.Tracker)
	if err != nil {
		return nil, err
	}

	// Update in-memory index immediately
	v.Index.PutEntity(path, entity, *newBaseline)

	return newBaseline, nil
}

// DeleteEntity removes an entity file from disk and cleans up its index entry.
// It preserves associated entities. Callers must hold MutationMu.
func (v *Vault) DeleteEntity(id string) error {
	if strings.TrimSpace(id) == "" {
		return fmt.Errorf("entity ID cannot be empty")
	}

	v.Index.mu.RLock()
	filePath, exists := v.Index.idToFile[id]
	v.Index.mu.RUnlock()

	if !exists {
		return fmt.Errorf("entity %q not found in index", id)
	}

	if err := os.Remove(filePath); err != nil && !os.IsNotExist(err) {
		return fmt.Errorf("failed to delete file %s: %w", filePath, err)
	}

	v.Index.ClearPendingMove(id)
	v.Index.RemoveFile(filePath)
	return nil
}

// StartWatcher starts listening to filesystem changes using fsnotify.
func (v *Vault) StartWatcher() error {
	v.mu.Lock()
	defer v.mu.Unlock()

	if v.running {
		return nil
	}

	watcher, err := fsnotify.NewWatcher()
	if err != nil {
		return fmt.Errorf("failed to initialize fsnotify watcher: %w", err)
	}

	v.watcher = watcher
	v.stopCh = make(chan struct{})
	v.running = true

	// Add all directories recursively
	if err := v.watchSubtree(v.RootPath); err != nil {
		_ = watcher.Close()
		v.running = false
		return err
	}

	go v.watchLoop()

	return nil
}

func (v *Vault) watchSubtree(root string) error {
	return filepath.Walk(root, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		if info.IsDir() {
			base := filepath.Base(path)
			if base == ".git" {
				return filepath.SkipDir
			}
			if err := v.watcher.Add(path); err != nil {
				return err
			}
		}
		return nil
	})
}

func (v *Vault) watchLoop() {
	for {
		select {
		case <-v.stopCh:
			return

		case err, ok := <-v.watcher.Errors:
			if !ok {
				return
			}
			v.dispatch(VaultEvent{Op: ChangeOpError, Err: err})

		case event, ok := <-v.watcher.Events:
			if !ok {
				return
			}
			v.handleFSEvent(event)
		}
	}
}

func (v *Vault) handleFSEvent(event fsnotify.Event) {
	v.MutationMu.Lock()
	defer v.MutationMu.Unlock()

	path := event.Name
	base := filepath.Base(path)

	// Ignore temporary files
	if strings.HasPrefix(base, ".pata_tmp_") || strings.HasSuffix(base, ".tmp") {
		return
	}

	// If directory was created, watch it
	if event.Has(fsnotify.Create) {
		if fi, err := os.Stat(path); err == nil && fi.IsDir() {
			_ = v.watchSubtree(path)
			return
		}
	}

	rel, relErr := filepath.Rel(v.RootPath, path)
	if relErr != nil {
		return
	}
	relSlash := filepath.ToSlash(rel)

	// Handle files/ directory resources
	if strings.HasPrefix(relSlash, "files/") {
		if strings.HasPrefix(base, ".") {
			return
		}
		if event.Has(fsnotify.Remove) || event.Has(fsnotify.Rename) {
			if _, err := os.Stat(path); os.IsNotExist(err) {
				v.Index.RemoveFileResource(relSlash)
				v.dispatch(VaultEvent{
					Op:       ChangeOpDelete,
					Path:     path,
					EntityID: relSlash,
					Type:     EntityTypeFile,
				})
				return
			}
		}
		if event.Has(fsnotify.Create) || event.Has(fsnotify.Write) {
			fi, err := os.Stat(path)
			if err == nil && !fi.IsDir() {
				v.Index.PutFile(FileResource{
					Path:    relSlash,
					Name:    base,
					Ext:     filepath.Ext(base),
					Size:    fi.Size(),
					ModTime: fi.ModTime(),
				})
				op := ChangeOpUpdate
				if event.Has(fsnotify.Create) {
					op = ChangeOpCreate
				}
				v.dispatch(VaultEvent{
					Op:       op,
					Path:     path,
					EntityID: relSlash,
					Type:     EntityTypeFile,
				})
			}
			return
		}
		return
	}

	// Only process business Markdown directories
	isTaskDir := strings.HasPrefix(relSlash, "tasks/")
	isNoteDir := strings.HasPrefix(relSlash, "notes/")
	isPlanDir := strings.HasPrefix(relSlash, "plans/") || strings.HasPrefix(relSlash, ".pata/plans/")

	if !isTaskDir && !isNoteDir && !isPlanDir {
		return
	}

	// Only process markdown files
	if filepath.Ext(path) != ".md" {
		return
	}

	// Handle delete or rename-out
	if event.Has(fsnotify.Remove) || event.Has(fsnotify.Rename) {
		// If file was deleted
		if _, err := os.Stat(path); os.IsNotExist(err) {
			deletedID, promotedID, promotedPath, promotedType := v.Index.RemoveFileWithPromotion(path)
			v.dispatch(VaultEvent{
				Op:       ChangeOpDelete,
				Path:     path,
				EntityID: deletedID,
			})
			if promotedID != "" && promotedPath != "" {
				v.dispatch(VaultEvent{
					Op:       ChangeOpCreate,
					Path:     promotedPath,
					EntityID: promotedID,
					Type:     promotedType,
				})
			}
			return
		}
	}

	// Handle create or write
	if event.Has(fsnotify.Create) || event.Has(fsnotify.Write) {
		data, err := os.ReadFile(path)
		if err != nil {
			return
		}
		hash := ComputeContentHash(data)

		// Self-feedback suppression: check if write was initiated by this process
		if v.Tracker.IsInternalWrite(path, hash) {
			return
		}

		fi, err := os.Stat(path)
		if err != nil {
			return
		}

		// External modification detected: parse and update index
		entity, parseErr := ParseMarkdown(path, data)
		if parseErr != nil {
			v.Index.mu.Lock()
			found := false
			for i, pe := range v.Index.parseErrors {
				if pe.Path == path {
					v.Index.parseErrors[i] = ParseError{
						Path:   path,
						Reason: "external modification resulted in invalid markdown/frontmatter",
						Err:    parseErr,
					}
					found = true
					break
				}
			}
			if !found {
				v.Index.parseErrors = append(v.Index.parseErrors, ParseError{
					Path:   path,
					Reason: "external modification resulted in invalid markdown/frontmatter",
					Err:    parseErr,
				})
			}
			v.Index.mu.Unlock()

			v.dispatch(VaultEvent{
				Op:   ChangeOpError,
				Path: path,
				Err:  parseErr,
			})
			return
		}

		// Ensure entity matches its folder boundary (consistent with ScanVault)
		var typeMismatchErr error
		if isTaskDir && entity.GetType() != EntityTypeTask {
			typeMismatchErr = fmt.Errorf("file in tasks/ has invalid entity type '%s' (expected task)", entity.GetType())
		} else if isNoteDir && entity.GetType() != EntityTypeNote {
			typeMismatchErr = fmt.Errorf("file in notes/ has invalid entity type '%s' (expected note)", entity.GetType())
		} else if isPlanDir && entity.GetType() != EntityTypeDayPlan {
			typeMismatchErr = fmt.Errorf("file in plans/ has invalid entity type '%s' (expected day_plan)", entity.GetType())
		}

		if typeMismatchErr != nil {
			v.Index.RemoveFile(path)
			v.Index.mu.Lock()
			found := false
			for i, pe := range v.Index.parseErrors {
				if pe.Path == path {
					v.Index.parseErrors[i] = ParseError{
						Path:   path,
						Reason: typeMismatchErr.Error(),
						Err:    typeMismatchErr,
					}
					found = true
					break
				}
			}
			if !found {
				v.Index.parseErrors = append(v.Index.parseErrors, ParseError{
					Path:   path,
					Reason: typeMismatchErr.Error(),
					Err:    typeMismatchErr,
				})
			}
			v.Index.mu.Unlock()

			v.dispatch(VaultEvent{
				Op:   ChangeOpError,
				Path: path,
				Err:  typeMismatchErr,
			})
			return
		}

		baseline := FileBaseline{
			Path:    path,
			Hash:    hash,
			ModTime: fi.ModTime(),
		}

		v.Index.PutEntity(path, entity, baseline)

		v.Index.mu.RLock()
		acceptedPath := v.Index.idToFile[entity.GetID()]
		v.Index.mu.RUnlock()

		if acceptedPath == path {
			op := ChangeOpUpdate
			if event.Has(fsnotify.Create) {
				op = ChangeOpCreate
			}

			v.dispatch(VaultEvent{
				Op:       op,
				Path:     path,
				EntityID: entity.GetID(),
				Type:     entity.GetType(),
			})
		}
	}
}

// Note (L4): Non-blocking dispatch may drop events if channel buffer (100) overflows;
// parseErrors appends without deduplication. Background periodic rescan (StartPeriodicRescan)
// serves as the safety net for missed events.
func (v *Vault) dispatch(ev VaultEvent) {
	select {
	case v.events <- ev:
	default:
		// Do not block if channel buffer is full
	}
}

// StopWatcher terminates the fsnotify event loop.
func (v *Vault) StopWatcher() error {
	v.mu.Lock()
	defer v.mu.Unlock()

	if !v.running {
		return nil
	}

	close(v.stopCh)
	err := v.watcher.Close()
	v.running = false
	return err
}

// StartPeriodicRescan starts a background ticker that periodically calls Scan() as a fallback.
// Returns a stop function.
func (v *Vault) StartPeriodicRescan(interval time.Duration) func() {
	if interval <= 0 {
		interval = 30 * time.Second
	}
	ticker := time.NewTicker(interval)
	stop := make(chan struct{})

	go func() {
		for {
			select {
			case <-stop:
				ticker.Stop()
				return
			case <-ticker.C:
				_ = v.Scan()
			}
		}
	}()

	return func() {
		close(stop)
	}
}
