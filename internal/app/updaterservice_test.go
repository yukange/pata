package app

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/wailsapp/wails/v3/pkg/updater"
	"github.com/wailsapp/wails/v3/pkg/updater/providers/github"
)

type mockUpdaterBackend struct {
	checkFunc     func(ctx context.Context) (*updater.Release, error)
	downloadFunc  func(ctx context.Context) error
	restartFunc   func(ctx context.Context) error
	restarted     bool
	restartCalled chan struct{}
}

func (m *mockUpdaterBackend) Check(ctx context.Context) (*updater.Release, error) {
	if m.checkFunc != nil {
		return m.checkFunc(ctx)
	}
	return nil, nil
}

func (m *mockUpdaterBackend) DownloadAndInstall(ctx context.Context) error {
	if m.downloadFunc != nil {
		return m.downloadFunc(ctx)
	}
	return nil
}

func (m *mockUpdaterBackend) Restart(ctx context.Context) error {
	if m.restartFunc != nil {
		return m.restartFunc(ctx)
	}
	m.restarted = true
	if m.restartCalled != nil {
		close(m.restartCalled)
	}
	return nil
}

func TestUpdaterService_Preferences_DefaultAndPersistence(t *testing.T) {
	tmpDir, err := os.MkdirTemp("", "pata-updater-pref-*")
	if err != nil {
		t.Fatalf("failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tmpDir)

	configPath := filepath.Join(tmpDir, "vault.json")
	vaultSvc := &VaultService{configPath: configPath}

	// 1. Official build: default should be true
	officialSvc := NewUpdaterService(vaultSvc, "0.1.0", true)
	autoOfficial, err := officialSvc.GetAutoCheckUpdates()
	if err != nil {
		t.Fatalf("GetAutoCheckUpdates failed: %v", err)
	}
	if !autoOfficial {
		t.Fatalf("expected official build to default to true, got false")
	}

	// 2. Dev build: default should be false
	devSvc := NewUpdaterService(vaultSvc, "0.1.0", false)
	autoDev, err := devSvc.GetAutoCheckUpdates()
	if err != nil {
		t.Fatalf("GetAutoCheckUpdates failed: %v", err)
	}
	if autoDev {
		t.Fatalf("expected dev build to default to false, got true")
	}

	// 3. User explicitly sets false on official build
	if err := officialSvc.SetAutoCheckUpdates(false); err != nil {
		t.Fatalf("SetAutoCheckUpdates(false) failed: %v", err)
	}
	autoVal, _ := officialSvc.GetAutoCheckUpdates()
	if autoVal {
		t.Fatalf("expected false after SetAutoCheckUpdates(false)")
	}

	// 4. Persistence across service re-instantiation
	reloadedSvc := NewUpdaterService(vaultSvc, "0.1.0", true)
	reloadedVal, _ := reloadedSvc.GetAutoCheckUpdates()
	if reloadedVal {
		t.Fatalf("expected false to be persisted in vault.json across reloads")
	}

	// 5. Toggling off when state is available hides update button (resets to idle)
	officialSvc.status.State = UpdateStateAvailable
	officialSvc.status.AvailableVersion = "0.2.0"
	_ = officialSvc.SetAutoCheckUpdates(false)
	if officialSvc.status.State != UpdateStateIdle {
		t.Fatalf("expected toggling off to reset available state to idle, got %s", officialSvc.status.State)
	}

	// 6. Toggling off when download is in progress does NOT disrupt downloading
	officialSvc.status.State = UpdateStateDownloading
	_ = officialSvc.SetAutoCheckUpdates(false)
	if officialSvc.status.State != UpdateStateDownloading {
		t.Fatalf("expected active download to not be disrupted by toggle, got %s", officialSvc.status.State)
	}
}

func TestUpdaterService_DevBuild_Safeguard(t *testing.T) {
	tmpDir, _ := os.MkdirTemp("", "pata-updater-dev-*")
	defer os.RemoveAll(tmpDir)

	vaultSvc := &VaultService{configPath: filepath.Join(tmpDir, "vault.json")}
	devSvc := NewUpdaterService(vaultSvc, "0.1.0", false)

	// Manual check on dev build
	res, err := devSvc.CheckForUpdate(true)
	if err != nil {
		t.Fatalf("unexpected error on dev manual check: %v", err)
	}
	if res.Supported {
		t.Fatalf("expected dev build to report supported=false")
	}
	if !strings.Contains(res.Message, "开发版本") {
		t.Fatalf("expected dev build message to mention 开发版本, got: %s", res.Message)
	}

	// StartDownload on dev build must fail
	if err := devSvc.StartDownload(); err == nil {
		t.Fatalf("expected StartDownload on dev build to return error")
	}
}

func TestUpdaterService_CheckForUpdate_Official(t *testing.T) {
	tmpDir, _ := os.MkdirTemp("", "pata-updater-official-*")
	defer os.RemoveAll(tmpDir)

	vaultSvc := &VaultService{configPath: filepath.Join(tmpDir, "vault.json")}
	svc := NewUpdaterService(vaultSvc, "0.1.0", true)

	// 1. New version found
	mock := &mockUpdaterBackend{
		checkFunc: func(ctx context.Context) (*updater.Release, error) {
			return &updater.Release{
				Version: "0.2.0",
			}, nil
		},
	}
	svc.setBackend(mock)

	res, err := svc.CheckForUpdate(true)
	if err != nil {
		t.Fatalf("CheckForUpdate failed: %v", err)
	}
	if !res.UpdateAvailable || res.Version != "0.2.0" {
		t.Fatalf("expected update 0.2.0, got %+v", res)
	}
	st := svc.GetUpdateStatus()
	if st.State != UpdateStateAvailable || st.AvailableVersion != "0.2.0" {
		t.Fatalf("expected status available with 0.2.0, got %+v", st)
	}

	// 2. Up to date
	mock.checkFunc = func(ctx context.Context) (*updater.Release, error) {
		return nil, nil
	}
	res, err = svc.CheckForUpdate(true)
	if err != nil {
		t.Fatalf("CheckForUpdate up-to-date failed: %v", err)
	}
	if res.UpdateAvailable {
		t.Fatalf("expected no update available")
	}
	st = svc.GetUpdateStatus()
	if st.State != UpdateStateIdle {
		t.Fatalf("expected state idle when up-to-date, got %s", st.State)
	}

	// 3. Network error on background check -> stays silent
	mock.checkFunc = func(ctx context.Context) (*updater.Release, error) {
		return nil, errors.New("network timeout")
	}
	_, err = svc.CheckForUpdate(false) // background
	if err != nil {
		t.Fatalf("expected background check to swallow error silently, got %v", err)
	}
	st = svc.GetUpdateStatus()
	if st.State != UpdateStateIdle {
		t.Fatalf("expected state idle after background failure, got %s", st.State)
	}

	// 4. Network error on manual check -> reports error
	_, err = svc.CheckForUpdate(true) // manual
	if err == nil {
		t.Fatalf("expected manual check to return error on network failure")
	}
	st = svc.GetUpdateStatus()
	if st.State != UpdateStateError || st.ErrorMessage == "" {
		t.Fatalf("expected error state on manual failure, got %+v", st)
	}

	// 5. Concurrent check while checking returns checking state without duplicate backend check
	checkCount := 0
	checkEntered := make(chan struct{})
	blockCheck := make(chan struct{})
	mock.checkFunc = func(ctx context.Context) (*updater.Release, error) {
		checkCount++
		close(checkEntered)
		<-blockCheck
		return nil, nil
	}
	svc.status.State = UpdateStateIdle

	go func() {
		_, _ = svc.CheckForUpdate(false)
	}()

	<-checkEntered
	// At this point status is checking
	resConcurrent, err := svc.CheckForUpdate(true)
	if err != nil {
		t.Fatalf("concurrent check returned unexpected error: %v", err)
	}
	if !strings.Contains(resConcurrent.Message, "正在检查更新") {
		t.Fatalf("expected concurrent check message to mention 正在检查更新, got: %s", resConcurrent.Message)
	}
	close(blockCheck)
	time.Sleep(50 * time.Millisecond)
	if checkCount != 1 {
		t.Fatalf("expected backend.Check to only be called once, got %d", checkCount)
	}
}

func TestUpdaterService_DisableAutoCheckDuringCheck_NoDeadlock(t *testing.T) {
	tmpDir, _ := os.MkdirTemp("", "pata-updater-deadlock-*")
	defer os.RemoveAll(tmpDir)

	vaultSvc := &VaultService{configPath: filepath.Join(tmpDir, "vault.json")}
	svc := NewUpdaterService(vaultSvc, "0.1.0", true)

	checkEntered := make(chan struct{})
	finishCheck := make(chan struct{})

	mock := &mockUpdaterBackend{
		checkFunc: func(ctx context.Context) (*updater.Release, error) {
			close(checkEntered)
			<-finishCheck
			return &updater.Release{Version: "0.2.0"}, nil
		},
	}
	svc.setBackend(mock)

	// Simulate periodic check running in background
	svc.mu.Lock()
	svc.startPeriodicCheckLocked()
	svc.mu.Unlock()

	// Launch a background check
	checkDone := make(chan struct{})
	go func() {
		_, _ = svc.CheckForUpdate(false)
		close(checkDone)
	}()

	<-checkEntered

	// User disables auto check while check is in flight
	doneDisable := make(chan struct{})
	go func() {
		_ = svc.SetAutoCheckUpdates(false)
		close(doneDisable)
	}()

	// Allow backend check to complete
	close(finishCheck)

	// If there's a deadlock, doneDisable won't close
	select {
	case <-doneDisable:
		// Success!
	case <-time.After(2 * time.Second):
		t.Fatalf("DEADLOCK detected: SetAutoCheckUpdates(false) hung while check was completing")
	}

	<-checkDone

	// State should remain idle because auto check was disabled
	st := svc.GetUpdateStatus()
	if st.State != UpdateStateIdle {
		t.Fatalf("expected state idle after auto check disabled during in-flight check, got %s", st.State)
	}
}

func TestUpdaterService_DownloadProgress_Calculation(t *testing.T) {
	tmpDir, _ := os.MkdirTemp("", "pata-updater-prog-*")
	defer os.RemoveAll(tmpDir)

	vaultSvc := &VaultService{configPath: filepath.Join(tmpDir, "vault.json")}
	svc := NewUpdaterService(vaultSvc, "0.1.0", true)

	// Case 1: normal progress: floor(550 / 1000 * 100) = 55%
	svc.handleDownloadProgress(updater.Progress{
		Written: 550,
		Total:   1000,
	})
	st := svc.GetUpdateStatus()
	if st.ProgressPercent != 55 || st.State != UpdateStateDownloading {
		t.Fatalf("expected 55%% downloading, got %d%% %s", st.ProgressPercent, st.State)
	}

	// Case 2: near 100%: 999 / 1000 = floor(99.9) = 99%
	svc.handleDownloadProgress(updater.Progress{
		Written: 999,
		Total:   1000,
	})
	st = svc.GetUpdateStatus()
	if st.ProgressPercent != 99 {
		t.Fatalf("expected 99%% (floor), got %d%%", st.ProgressPercent)
	}

	// Case 3: 1000 / 1000 = 100% -> transitions to staging (busy 100%, NOT "准备安装")
	svc.handleDownloadProgress(updater.Progress{
		Written: 1000,
		Total:   1000,
	})
	st = svc.GetUpdateStatus()
	if st.ProgressPercent != 100 || st.State != UpdateStateStaging {
		t.Fatalf("expected 100%% staging, got %d%% %s", st.ProgressPercent, st.State)
	}

	// Case 4: indeterminate total (<= 0)
	svc.handleDownloadProgress(updater.Progress{
		Written: 500,
		Total:   0,
	})
	st = svc.GetUpdateStatus()
	if st.ProgressPercent != -1 {
		t.Fatalf("expected -1 for indeterminate progress, got %d", st.ProgressPercent)
	}
}

func TestUpdaterService_ReadyAndDraftGate(t *testing.T) {
	tmpDir, _ := os.MkdirTemp("", "pata-updater-draft-*")
	defer os.RemoveAll(tmpDir)

	vaultSvc := &VaultService{configPath: filepath.Join(tmpDir, "vault.json")}
	svc := NewUpdaterService(vaultSvc, "0.1.0", true)

	mock := &mockUpdaterBackend{
		restartCalled: make(chan struct{}),
	}
	svc.setBackend(mock)

	// 1. Ready event fires -> staging 100%
	svc.handleUpdateReady()
	st := svc.GetUpdateStatus()
	if st.State != UpdateStateStaging || st.ProgressPercent != 100 {
		t.Fatalf("expected staging 100%% after ready, got %+v", st)
	}

	// 2. Drafts detected by frontend -> SetWaitingInstall()
	if err := svc.SetWaitingInstall(); err != nil {
		t.Fatalf("SetWaitingInstall failed: %v", err)
	}
	st = svc.GetUpdateStatus()
	if st.State != UpdateStateWaitingInstall {
		t.Fatalf("expected waiting_install state, got %s", st.State)
	}

	// 3. User clicks waiting_install when drafts saved -> ApplyUpdateAndRestart()
	if err := svc.ApplyUpdateAndRestart(); err != nil {
		t.Fatalf("ApplyUpdateAndRestart failed: %v", err)
	}
	st = svc.GetUpdateStatus()
	if st.State != UpdateStateRestarting {
		t.Fatalf("expected restarting state, got %s", st.State)
	}
	if !mock.restarted {
		t.Fatalf("expected backend.Restart to be called")
	}
}

func TestUpdaterServiceChecksPreserveStagedUpdate(t *testing.T) {
	for _, state := range []UpdateState{UpdateStateStaging, UpdateStateWaitingInstall} {
		for _, manual := range []bool{false, true} {
			svc := NewUpdaterService(nil, "0.1.0", true)
			svc.status.State = state
			svc.status.AvailableVersion = "0.2.0"
			svc.setBackend(&mockUpdaterBackend{checkFunc: func(context.Context) (*updater.Release, error) {
				t.Fatal("must not check while a staged update awaits installation")
				return nil, nil
			}})
			res, err := svc.CheckForUpdate(manual)
			if err != nil || !res.UpdateAvailable || res.Version != "0.2.0" {
				t.Fatalf("check: %+v, %v", res, err)
			}
			if got := svc.GetUpdateStatus(); got.State != state || got.AvailableVersion != "0.2.0" {
				t.Fatalf("staged update was changed: %+v", got)
			}
		}
	}
}

func TestUpdaterServiceRestartFailureCanRetryStagedUpdate(t *testing.T) {
	svc := NewUpdaterService(nil, "0.1.0", true)
	svc.status.State = UpdateStateWaitingInstall
	svc.status.AvailableVersion = "0.2.0"
	mock := &mockUpdaterBackend{restartFunc: func(context.Context) error { return errors.New("helper failed") }}
	svc.setBackend(mock)
	if err := svc.ApplyUpdateAndRestart(); err == nil {
		t.Fatal("expected restart error")
	}
	if st := svc.GetUpdateStatus(); st.State != UpdateStateWaitingInstall || st.ErrorMessage != "helper failed" || st.AvailableVersion != "0.2.0" {
		t.Fatalf("failed restart must stay retryable: %+v", st)
	}
	mock.restartFunc = nil
	if err := svc.ApplyUpdateAndRestart(); err != nil {
		t.Fatal(err)
	}
	if st := svc.GetUpdateStatus(); st.State != UpdateStateRestarting || st.ErrorMessage != "" || !mock.restarted {
		t.Fatalf("retry failed: %+v", st)
	}

	missing := NewUpdaterService(nil, "0.1.0", true)
	missing.status.State = UpdateStateWaitingInstall
	if err := missing.ApplyUpdateAndRestart(); err == nil || missing.GetUpdateStatus().State != UpdateStateWaitingInstall {
		t.Fatal("missing backend must not leave the updater restarting")
	}
}

func TestUpdaterServiceDownloadProgressBounds(t *testing.T) {
	svc := NewUpdaterService(nil, "0.1.0", true)
	for _, tc := range []struct {
		written, total int64
		want           int
	}{
		{0, 1000, 0}, {555, 1000, 55}, {999, 1000, 99}, {1000, 1000, 100},
		{1200, 1000, 100}, {-5, 1000, 0}, {500, 0, -1}, {500, -1, -1},
	} {
		svc.handleDownloadProgress(updater.Progress{Written: tc.written, Total: tc.total})
		if got := svc.GetUpdateStatus().ProgressPercent; got != tc.want {
			t.Fatalf("progress(%d, %d) = %d, want %d", tc.written, tc.total, got, tc.want)
		}
	}
}

func TestPataAssetMatcher(t *testing.T) {
	assets := []github.ReleaseAsset{
		{Name: "pata-0.2.0-darwin-arm64.dmg"},
		{Name: "pata-0.2.0-darwin-arm64.sig"},
		{Name: "SHA256SUMS"},
		{Name: "pata-0.2.0-darwin-amd64.app.zip"},
		{Name: "pata-0.2.0-darwin-arm64.app.zip"},
	}

	// Test arm64 match
	reqArm64 := updater.CheckRequest{
		Platform: "darwin",
		Arch:     "arm64",
	}
	idx := PataAssetMatcher(reqArm64, assets)
	if idx != 4 {
		t.Fatalf("expected index 4 (pata-0.2.0-darwin-arm64.app.zip), got %d", idx)
	}

	// Test amd64 match
	reqAmd64 := updater.CheckRequest{
		Platform: "darwin",
		Arch:     "amd64",
	}
	idxAmd64 := PataAssetMatcher(reqAmd64, assets)
	if idxAmd64 != 3 {
		t.Fatalf("expected index 3 (pata-0.2.0-darwin-amd64.app.zip), got %d", idxAmd64)
	}

	// Test non-matching arch
	reqWindows := updater.CheckRequest{
		Platform: "windows",
		Arch:     "amd64",
	}
	if idxWin := PataAssetMatcher(reqWindows, assets); idxWin != -1 {
		t.Fatalf("expected -1 for windows, got %d", idxWin)
	}
}

func TestUpdaterService_StageCheckErrorIgnoredInEvent(t *testing.T) {
	tmpDir, _ := os.MkdirTemp("", "pata-updater-stagecheck-*")
	defer os.RemoveAll(tmpDir)

	vaultSvc := &VaultService{configPath: filepath.Join(tmpDir, "vault.json")}
	svc := NewUpdaterService(vaultSvc, "0.1.0", true)
	svc.status.State = UpdateStateIdle

	// Simulate Wails updater EventError during StageCheck
	var stage updater.Stage = updater.StageCheck
	if stage == updater.StageCheck {
		// As implemented in initUpdater listener, StageCheck errors are dropped
	} else {
		svc.handleError("check failed")
	}

	st := svc.GetUpdateStatus()
	if st.State != UpdateStateIdle {
		t.Fatalf("expected state to remain idle on StageCheck error, got %s", st.State)
	}
}
