package app

import (
	"context"
	"fmt"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"sync"
	"time"

	"github.com/wailsapp/wails/v3/pkg/application"

	"pata/internal/asr"
	"pata/internal/keychain"
	"pata/internal/storage/markdown"
)

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

// EventVaultChanged is emitted to the Wails frontend when a vault entity is created, modified, or deleted.
const EventVaultChanged = "vault:changed"

// VaultChangeEvent describes a change dispatched to the frontend application.
type VaultChangeEvent struct {
	Op       string `json:"op"`
	Path     string `json:"path"`
	EntityID string `json:"entity_id,omitempty"`
	Type     string `json:"type,omitempty"`
}

// VaultService owns the single Vault instance; all structured file access goes through it.
type VaultService struct {
	externalMu        sync.RWMutex
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
	s.mu.Lock()
	cfg, _ := s.loadConfig()
	cfg.VaultPath = path
	saveErr := s.saveConfig(cfg)
	s.mu.Unlock()
	if err := saveErr; err != nil {
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
	s.externalMu.Lock()
	defer s.externalMu.Unlock()
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
