package app

import (
	"context"
	"fmt"
	"math"
	"strings"
	"sync"
	"time"

	"github.com/wailsapp/wails/v3/pkg/application"
	"github.com/wailsapp/wails/v3/pkg/updater"
	"github.com/wailsapp/wails/v3/pkg/updater/providers/github"
)

// UpdateState represents the discrete UI states for updater.
type UpdateState string

const (
	UpdateStateIdle           UpdateState = "idle"
	UpdateStateChecking       UpdateState = "checking"
	UpdateStateAvailable      UpdateState = "available"
	UpdateStateDownloading    UpdateState = "downloading"
	UpdateStateStaging        UpdateState = "staging"
	UpdateStateWaitingInstall UpdateState = "waiting_install"
	UpdateStateRestarting     UpdateState = "restarting"
	UpdateStateError          UpdateState = "error"
)

// UpdateStatus contains the full runtime state of the in-app updater.
type UpdateStatus struct {
	State               UpdateState `json:"state"`
	Version             string      `json:"version"`
	AvailableVersion    string      `json:"available_version"`
	OfficialBuild       bool        `json:"official_build"`
	AutoCheckUpdates    bool        `json:"auto_check_updates"`
	ProgressPercent     int         `json:"progress_percent"` // 0-100, or -1 if indeterminate
	BytesWritten        int64       `json:"bytes_written"`
	TotalBytes          int64       `json:"total_bytes"`
	ErrorMessage        string      `json:"error_message,omitempty"`
	ManualCheckFeedback string      `json:"manual_check_feedback,omitempty"`
}

// UpdateCheckResult is returned from CheckForUpdate.
type UpdateCheckResult struct {
	Supported       bool   `json:"supported"`
	UpdateAvailable bool   `json:"update_available"`
	Version         string `json:"version"`
	Message         string `json:"message,omitempty"`
	Error           string `json:"error,omitempty"`
}

// UpdaterBackend abstracts Wails updater operations for testability.
type UpdaterBackend interface {
	Check(ctx context.Context) (*updater.Release, error)
	DownloadAndInstall(ctx context.Context) error
	Restart(ctx context.Context) error
}

// UpdaterService orchestrates update checks, downloading, staging, draft gating, and restarts.
type UpdaterService struct {
	mu             sync.Mutex
	vault          *VaultService
	app            *application.App
	backend        UpdaterBackend
	version        string
	officialBuild  bool
	status         UpdateStatus
	periodicCancel context.CancelFunc
	periodicDone   chan struct{}
}

// NewUpdaterService creates a new updater service instance.
func NewUpdaterService(vault *VaultService, version string, officialBuild bool) *UpdaterService {
	defaultAutoCheck := officialBuild
	if vault != nil {
		if val, err := vault.GetAutoCheckUpdatesPreference(defaultAutoCheck); err == nil {
			defaultAutoCheck = val
		}
	}

	svc := &UpdaterService{
		vault:         vault,
		version:       version,
		officialBuild: officialBuild,
		status: UpdateStatus{
			State:            UpdateStateIdle,
			Version:          version,
			OfficialBuild:    officialBuild,
			AutoCheckUpdates: defaultAutoCheck,
			ProgressPercent:  -1,
		},
	}

	return svc
}

// setBackend overrides the underlying UpdaterBackend, primarily for unit tests.
func (s *UpdaterService) setBackend(b UpdaterBackend) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.backend = b
}

// setApp sets the Wails application reference.
func (s *UpdaterService) setApp(app *application.App) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.app = app
}

// ServiceStartup implements Wails application.ServiceStartup.
func (s *UpdaterService) ServiceStartup(ctx context.Context, options application.ServiceOptions) error {
	s.mu.Lock()
	if s.app == nil {
		s.app = application.Get()
	}
	autoCheck := s.status.AutoCheckUpdates
	isOfficial := s.officialBuild
	s.mu.Unlock()

	if isOfficial && autoCheck {
		s.mu.Lock()
		s.startPeriodicCheckLocked()
		s.mu.Unlock()
	}

	return nil
}

// initUpdater configures the Wails Updater singleton for official production builds.
func (s *UpdaterService) initUpdater(app *application.App) error {
	s.mu.Lock()
	s.app = app
	version := s.version
	isOfficial := s.officialBuild
	s.mu.Unlock()

	if !isOfficial {
		// Non-official / developer builds explicitly do not initialize Wails updater
		return nil
	}

	ghProvider, err := github.New(github.Config{
		Repository:    "yukange/pata",
		ChecksumAsset: "SHA256SUMS",
		AssetMatcher:  PataAssetMatcher,
	})
	if err != nil {
		return fmt.Errorf("github provider init failed: %w", err)
	}

	err = app.Updater.Init(updater.Config{
		CurrentVersion: version,
		Providers:      []updater.Provider{ghProvider},
		Window:         updater.WindowNone,
		CheckInterval:  0, // Periodic checks are managed explicitly by UpdaterService
	})
	if err != nil && err != updater.ErrAlreadyConfigured {
		return fmt.Errorf("app.Updater.Init failed: %w", err)
	}

	s.mu.Lock()
	s.backend = app.Updater
	s.mu.Unlock()

	// Register event handlers
	app.Event.On(updater.EventDownloadProgress, func(e *application.CustomEvent) {
		if e == nil {
			return
		}
		var p updater.Progress
		switch d := e.Data.(type) {
		case updater.Progress:
			p = d
		case *updater.Progress:
			if d != nil {
				p = *d
			}
		}
		s.handleDownloadProgress(p)
	})

	app.Event.On(updater.EventUpdateReady, func(e *application.CustomEvent) {
		s.handleUpdateReady()
	})

	app.Event.On(updater.EventError, func(e *application.CustomEvent) {
		msg := "更新处理失败"
		var stage updater.Stage
		if e != nil && e.Data != nil {
			if info, ok := e.Data.(updater.ErrorInfo); ok {
				msg = info.Message
				stage = info.Stage
			} else if info, ok := e.Data.(*updater.ErrorInfo); ok && info != nil {
				msg = info.Message
				stage = info.Stage
			}
		}
		// Errors in StageCheck (e.g. rate limit, network timeout) are handled by CheckForUpdate
		// directly and must not transition the global download state to UpdateStateError during background check.
		if stage == updater.StageCheck {
			return
		}
		s.handleError(msg)
	})

	return nil
}

// GetUpdateStatus returns a copy of current update status.
func (s *UpdaterService) GetUpdateStatus() UpdateStatus {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.status
}

// GetAutoCheckUpdates returns whether auto update checks are currently enabled.
func (s *UpdaterService) GetAutoCheckUpdates() (bool, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.vault == nil {
		return s.status.AutoCheckUpdates, nil
	}
	return s.vault.GetAutoCheckUpdatesPreference(s.officialBuild)
}

// SetAutoCheckUpdates toggles the auto update check preference.
func (s *UpdaterService) SetAutoCheckUpdates(enabled bool) error {
	s.mu.Lock()

	if s.vault != nil {
		if err := s.vault.SetAutoCheckUpdatesPreference(enabled); err != nil {
			s.mu.Unlock()
			return err
		}
	}

	s.status.AutoCheckUpdates = enabled

	if !enabled {
		// If an update was discovered but download hasn't started, hide it
		if s.status.State == UpdateStateAvailable {
			s.status.State = UpdateStateIdle
		}
	}

	s.emitStateLocked()
	s.mu.Unlock()

	if !enabled {
		s.stopPeriodicCheck()
	} else if s.officialBuild {
		s.mu.Lock()
		s.startPeriodicCheckLocked()
		s.mu.Unlock()
	}

	return nil
}

// CheckForUpdate initiates a check against the release provider.
func (s *UpdaterService) CheckForUpdate(manual bool) (*UpdateCheckResult, error) {
	s.mu.Lock()
	if !s.officialBuild {
		s.mu.Unlock()
		res := &UpdateCheckResult{
			Supported:       false,
			UpdateAvailable: false,
			Version:         s.version,
			Message:         "当前构建为开发版本，不支持应用内更新，升级请重新构建源码。",
		}
		if manual {
			s.emitManualFeedback(res.Message)
		}
		return res, nil
	}

	if s.backend == nil {
		s.mu.Unlock()
		res := &UpdateCheckResult{
			Supported: false,
			Version:   s.version,
			Message:   "更新服务未就绪",
		}
		if manual {
			s.emitManualFeedback(res.Message)
		}
		return res, nil
	}

	// Do not interrupt active checks, downloads, staged updates, or restarts.
	if s.status.State == UpdateStateChecking || s.status.State == UpdateStateDownloading || s.status.State == UpdateStateStaging || s.status.State == UpdateStateWaitingInstall || s.status.State == UpdateStateRestarting {
		state := s.status.State
		availVer := s.status.AvailableVersion
		s.mu.Unlock()
		msg := fmt.Sprintf("当前正在处理更新 (%s)", state)
		if state == UpdateStateChecking {
			msg = "正在检查更新中…"
		}
		res := &UpdateCheckResult{
			Supported:       true,
			UpdateAvailable: availVer != "",
			Version:         availVer,
			Message:         msg,
		}
		if manual {
			s.emitManualFeedback(res.Message)
		}
		return res, nil
	}

	s.status.State = UpdateStateChecking
	s.status.ErrorMessage = ""
	s.status.ManualCheckFeedback = ""
	backend := s.backend
	current := s.status
	s.mu.Unlock()

	s.emitState(current)

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	rel, err := backend.Check(ctx)

	s.mu.Lock()
	defer s.mu.Unlock()

	if err != nil {
		if manual {
			s.status.State = UpdateStateError
			s.status.ErrorMessage = err.Error()
			s.status.ManualCheckFeedback = "检查更新失败，请稍后重试"
			res := &UpdateCheckResult{
				Supported: true,
				Error:     err.Error(),
				Message:   s.status.ManualCheckFeedback,
			}
			s.emitStateLocked()
			s.emitManualFeedbackLocked(res.Message)
			return res, err
		}
		// Silent in background check
		s.status.State = UpdateStateIdle
		s.emitStateLocked()
		return &UpdateCheckResult{
			Supported: true,
			Error:     err.Error(),
		}, nil
	}

	if rel == nil {
		s.status.State = UpdateStateIdle
		s.status.AvailableVersion = ""
		s.status.ManualCheckFeedback = "已是最新版本"
		res := &UpdateCheckResult{
			Supported:       true,
			UpdateAvailable: false,
			Version:         s.version,
			Message:         "已是最新版本",
		}
		s.emitStateLocked()
		if manual {
			s.emitManualFeedbackLocked(res.Message)
		}
		return res, nil
	}

	// Newer version found!
	if !manual && !s.status.AutoCheckUpdates {
		// Auto check was disabled while the background check was in flight: stay idle
		s.status.State = UpdateStateIdle
		s.emitStateLocked()
		return &UpdateCheckResult{
			Supported:       true,
			UpdateAvailable: false,
			Version:         s.version,
		}, nil
	}

	s.status.State = UpdateStateAvailable
	s.status.AvailableVersion = rel.Version
	s.status.ManualCheckFeedback = fmt.Sprintf("发现新版本 v%s", rel.Version)
	res := &UpdateCheckResult{
		Supported:       true,
		UpdateAvailable: true,
		Version:         rel.Version,
		Message:         s.status.ManualCheckFeedback,
	}
	s.emitStateLocked()
	if manual {
		s.emitManualFeedbackLocked(res.Message)
	}
	return res, nil
}

// StartDownload initiates downloading and staging of the pending release.
func (s *UpdaterService) StartDownload() error {
	s.mu.Lock()
	if !s.officialBuild {
		s.mu.Unlock()
		return fmt.Errorf("当前构建为开发版本，不支持应用内更新")
	}
	if s.backend == nil {
		s.mu.Unlock()
		return fmt.Errorf("更新服务未就绪")
	}
	if s.status.State != UpdateStateAvailable && s.status.State != UpdateStateError {
		s.mu.Unlock()
		return fmt.Errorf("当前状态不可下载更新 (%s)", s.status.State)
	}

	s.status.State = UpdateStateDownloading
	s.status.ProgressPercent = 0
	s.status.BytesWritten = 0
	s.status.ErrorMessage = ""
	backend := s.backend
	current := s.status
	s.mu.Unlock()

	s.emitState(current)

	go func() {
		ctx := context.Background()
		if err := backend.DownloadAndInstall(ctx); err != nil {
			s.handleError(err.Error())
		}
	}()

	return nil
}

// SetWaitingInstall transitions updater to waiting_install when unsaved drafts are detected.
func (s *UpdaterService) SetWaitingInstall() error {
	s.mu.Lock()
	s.status.State = UpdateStateWaitingInstall
	current := s.status
	s.mu.Unlock()

	s.emitState(current)
	return nil
}

// ApplyUpdateAndRestart initiates the final restart and atomic swap into the new version.
func (s *UpdaterService) ApplyUpdateAndRestart() error {
	s.mu.Lock()
	if s.status.State != UpdateStateStaging && s.status.State != UpdateStateWaitingInstall {
		s.mu.Unlock()
		return fmt.Errorf("没有可安装的更新或尚未就绪")
	}
	backend := s.backend
	if backend == nil {
		s.mu.Unlock()
		return fmt.Errorf("更新服务未就绪")
	}
	s.status.State = UpdateStateRestarting
	s.status.ErrorMessage = ""
	current := s.status
	s.mu.Unlock()

	s.emitState(current)

	if err := backend.Restart(context.Background()); err != nil {
		s.mu.Lock()
		s.status.State = UpdateStateWaitingInstall
		s.status.ErrorMessage = err.Error()
		current = s.status
		s.mu.Unlock()
		s.emitState(current)
		return err
	}
	return nil
}

// triggerManualCheckFromMenu is called when user clicks Pata -> 检查更新… in native menu.
func (s *UpdaterService) triggerManualCheckFromMenu() {
	if s.app != nil {
		s.app.Event.Emit("menu:check-updates")
	}
	go func() {
		_, _ = s.CheckForUpdate(true)
	}()
}

// handleDownloadProgress updates byte and percent metrics from progress event.
func (s *UpdaterService) handleDownloadProgress(p updater.Progress) {
	s.mu.Lock()
	s.status.BytesWritten = p.Written
	s.status.TotalBytes = p.Total
	if p.Total > 0 {
		percent := int(math.Floor(float64(p.Written) / float64(p.Total) * 100))
		if percent > 100 {
			percent = 100
		}
		if percent < 0 {
			percent = 0
		}
		s.status.ProgressPercent = percent
	} else {
		s.status.ProgressPercent = -1 // Indeterminate
	}

	if s.status.ProgressPercent == 100 {
		s.status.State = UpdateStateStaging
	} else {
		s.status.State = UpdateStateDownloading
	}
	current := s.status
	s.mu.Unlock()

	s.emitState(current)
}

// handleUpdateReady handles successful download, verification, and staging.
func (s *UpdaterService) handleUpdateReady() {
	s.mu.Lock()
	s.status.State = UpdateStateStaging
	s.status.ProgressPercent = 100
	current := s.status
	s.mu.Unlock()

	s.emitState(current)
	if s.app != nil {
		s.app.Event.Emit("pata:updater:ready-to-apply", current)
	}
}

// handleError transitions updater to error state and records the error message.
func (s *UpdaterService) handleError(msg string) {
	s.mu.Lock()
	s.status.State = UpdateStateError
	s.status.ErrorMessage = msg
	current := s.status
	s.mu.Unlock()

	s.emitState(current)
}

func (s *UpdaterService) startPeriodicCheckLocked() {
	if s.periodicCancel != nil {
		return // already started
	}

	ctx, cancel := context.WithCancel(context.Background())
	s.periodicCancel = cancel
	done := make(chan struct{})
	s.periodicDone = done

	go func() {
		defer close(done)

		// Delay first background check 10 seconds after launch
		select {
		case <-ctx.Done():
			return
		case <-time.After(10 * time.Second):
			s.mu.Lock()
			autoCheck := s.status.AutoCheckUpdates
			isOfficial := s.officialBuild
			s.mu.Unlock()
			if autoCheck && isOfficial {
				_, _ = s.CheckForUpdate(false)
			}
		}

		ticker := time.NewTicker(6 * time.Hour)
		defer ticker.Stop()

		for {
			select {
			case <-ctx.Done():
				return
			case <-ticker.C:
				s.mu.Lock()
				autoCheck := s.status.AutoCheckUpdates
				isOfficial := s.officialBuild
				s.mu.Unlock()
				if autoCheck && isOfficial {
					_, _ = s.CheckForUpdate(false)
				}
			}
		}
	}()
}

func (s *UpdaterService) stopPeriodicCheck() {
	s.mu.Lock()
	cancel := s.periodicCancel
	s.periodicCancel = nil
	done := s.periodicDone
	s.periodicDone = nil
	s.mu.Unlock()

	if cancel != nil {
		cancel()
	}
	if done != nil {
		<-done
	}
}

func (s *UpdaterService) emitState(status UpdateStatus) {
	s.mu.Lock()
	app := s.app
	s.mu.Unlock()
	if app != nil {
		app.Event.Emit("pata:updater:state-changed", status)
	}
}

func (s *UpdaterService) emitStateLocked() {
	status := s.status
	app := s.app
	if app != nil {
		app.Event.Emit("pata:updater:state-changed", status)
	}
}

func (s *UpdaterService) emitManualFeedback(msg string) {
	s.mu.Lock()
	app := s.app
	s.mu.Unlock()
	if app != nil {
		app.Event.Emit("pata:updater:manual-feedback", msg)
	}
}

func (s *UpdaterService) emitManualFeedbackLocked(msg string) {
	app := s.app
	if app != nil {
		app.Event.Emit("pata:updater:manual-feedback", msg)
	}
}

// PataAssetMatcher filters release assets to find the appropriate darwin .app.zip archive.
func PataAssetMatcher(req updater.CheckRequest, assets []github.ReleaseAsset) int {
	plat := strings.ToLower(req.Platform)
	arch := strings.ToLower(req.Arch)

	for i, a := range assets {
		name := strings.ToLower(a.Name)
		// Skip dmgs, signatures, checksums, and installer binaries
		if strings.HasSuffix(name, ".dmg") ||
			strings.HasSuffix(name, ".sig") ||
			strings.HasSuffix(name, ".asc") ||
			strings.Contains(name, "-installer.") ||
			strings.Contains(name, "_installer.") ||
			isChecksumFile(name) {
			continue
		}
		// Must be a zip file
		if !strings.HasSuffix(name, ".zip") {
			continue
		}
		// Check platform match
		if plat != "" && !strings.Contains(name, plat) {
			continue
		}
		// Check architecture match
		if arch != "" && !containsArch(name, arch) {
			continue
		}
		return i
	}
	return -1
}

func isChecksumFile(name string) bool {
	n := strings.ToLower(name)
	return strings.Contains(n, "checksum") || strings.Contains(n, "sha256") || strings.HasSuffix(n, ".sha256")
}

func containsArch(name, arch string) bool {
	name = strings.ToLower(name)
	arch = strings.ToLower(arch)
	if arch == "amd64" {
		return strings.Contains(name, "amd64") || strings.Contains(name, "x86_64")
	}
	return strings.Contains(name, arch)
}
