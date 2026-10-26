package app

import (
	"archive/zip"
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/wailsapp/wails/v3/pkg/updater"
)

// TestAcceptance_Updater_SettingsTogglePersistence verifies that the auto_check_updates preference
// is stored at application level in vault.json (not in business Markdown), defaulting to true
// for official builds, and survives restarts.
func TestAcceptance_Updater_SettingsTogglePersistence(t *testing.T) {
	tmpDir, err := os.MkdirTemp("", "pata-accept-updater-pref-*")
	if err != nil {
		t.Fatal(err)
	}
	defer os.RemoveAll(tmpDir)

	configPath := filepath.Join(tmpDir, "config", "vault.json")
	vaultSvc := &VaultService{configPath: configPath}

	// Instance 1: Official build
	updaterSvc1 := NewUpdaterService(vaultSvc, "0.1.0", true)
	enabled, err := updaterSvc1.GetAutoCheckUpdates()
	if err != nil || !enabled {
		t.Fatalf("expected official build to default to true, got %v (err: %v)", enabled, err)
	}

	// Turn off auto check
	if err := updaterSvc1.SetAutoCheckUpdates(false); err != nil {
		t.Fatalf("SetAutoCheckUpdates(false) failed: %v", err)
	}

	// Verify vault.json has auto_check_updates: false
	cfgData, err := os.ReadFile(configPath)
	if err != nil {
		t.Fatalf("failed to read config: %v", err)
	}
	if !strings.Contains(string(cfgData), `"auto_check_updates": false`) {
		t.Fatalf("config file missing auto_check_updates: false: %s", string(cfgData))
	}

	// Instance 2: Reloading service should see false
	updaterSvc2 := NewUpdaterService(vaultSvc, "0.1.0", true)
	reloaded, err := updaterSvc2.GetAutoCheckUpdates()
	if err != nil || reloaded {
		t.Fatalf("expected persisted false on reload, got %v (err: %v)", reloaded, err)
	}
}

// TestAcceptance_Updater_DevBuildIsolation verifies that non-official builds
// do not check or swap against upstream release feeds.
func TestAcceptance_Updater_DevBuildIsolation(t *testing.T) {
	tmpDir, err := os.MkdirTemp("", "pata-accept-updater-dev-*")
	if err != nil {
		t.Fatal(err)
	}
	defer os.RemoveAll(tmpDir)

	vaultSvc := &VaultService{configPath: filepath.Join(tmpDir, "vault.json")}
	devSvc := NewUpdaterService(vaultSvc, "0.1.0", false)

	// Auto check on dev build defaults to false
	autoCheck, _ := devSvc.GetAutoCheckUpdates()
	if autoCheck {
		t.Errorf("dev build should default auto_check_updates to false")
	}

	// Manual check returns informative notice
	res, err := devSvc.CheckForUpdate(true)
	if err != nil {
		t.Fatalf("CheckForUpdate on dev build returned unexpected error: %v", err)
	}
	if res.Supported {
		t.Errorf("dev build should report supported=false")
	}
	if !strings.Contains(res.Message, "开发版本") {
		t.Errorf("dev build message should indicate 开发版本, got: %s", res.Message)
	}

	// Attempting download is rejected
	if err := devSvc.StartDownload(); err == nil {
		t.Errorf("StartDownload on dev build must fail")
	}
}

// TestAcceptance_Updater_EndToEndFlow simulates the end-to-end update flow:
// check -> available -> download progress (floor) -> staging -> draft gate (waiting_install) -> restart.
func TestAcceptance_Updater_EndToEndFlow(t *testing.T) {
	tmpDir, err := os.MkdirTemp("", "pata-accept-updater-flow-*")
	if err != nil {
		t.Fatal(err)
	}
	defer os.RemoveAll(tmpDir)

	vaultSvc := &VaultService{configPath: filepath.Join(tmpDir, "vault.json")}
	svc := NewUpdaterService(vaultSvc, "0.1.0", true)

	downloadDone := make(chan struct{})
	mock := &mockUpdaterBackend{
		checkFunc: func(ctx context.Context) (*updater.Release, error) {
			return &updater.Release{
				Version: "0.2.0",
				Artifact: updater.Artifact{
					Filename: "pata-darwin-arm64.app.zip",
				},
			}, nil
		},
		downloadFunc: func(ctx context.Context) error {
			// Simulate progress steps
			svc.handleDownloadProgress(updater.Progress{Written: 500, Total: 1000})
			svc.handleDownloadProgress(updater.Progress{Written: 999, Total: 1000})
			svc.handleDownloadProgress(updater.Progress{Written: 1000, Total: 1000})
			svc.handleUpdateReady()
			close(downloadDone)
			return nil
		},
	}
	mock.restartCalled = make(chan struct{})
	svc.setBackend(mock)

	// Step 1: Check for update
	res, err := svc.CheckForUpdate(true)
	if err != nil || !res.UpdateAvailable || res.Version != "0.2.0" {
		t.Fatalf("CheckForUpdate failed: %+v, err: %v", res, err)
	}
	if st := svc.GetUpdateStatus(); st.State != UpdateStateAvailable {
		t.Fatalf("expected state available, got %s", st.State)
	}

	// Step 2: User clicks download
	if err := svc.StartDownload(); err != nil {
		t.Fatalf("StartDownload failed: %v", err)
	}

	select {
	case <-downloadDone:
	case <-time.After(2 * time.Second):
		t.Fatal("download did not finish")
	}

	st := svc.GetUpdateStatus()
	if st.State != UpdateStateStaging || st.ProgressPercent != 100 {
		t.Fatalf("expected staging 100%%, got %+v", st)
	}

	// Step 3: Unsaved draft detected by frontend -> SetWaitingInstall()
	if err := svc.SetWaitingInstall(); err != nil {
		t.Fatalf("SetWaitingInstall failed: %v", err)
	}
	if st := svc.GetUpdateStatus(); st.State != UpdateStateWaitingInstall {
		t.Fatalf("expected waiting_install, got %s", st.State)
	}

	// Step 4: User saves draft and clicks "等待安装" -> ApplyUpdateAndRestart()
	if err := svc.ApplyUpdateAndRestart(); err != nil {
		t.Fatalf("ApplyUpdateAndRestart failed: %v", err)
	}
	if st := svc.GetUpdateStatus(); st.State != UpdateStateRestarting {
		t.Fatalf("expected restarting, got %s", st.State)
	}

	select {
	case <-mock.restartCalled:
	case <-time.After(2 * time.Second):
		t.Fatal("expected backend.Restart to be called")
	}
}

// TestAcceptance_Updater_ArchiveStructure validates that ditto creates a zip
// containing exactly one top-level directory entry, matching Wails updater extract constraints.
func TestAcceptance_Updater_ArchiveStructure(t *testing.T) {
	tmpDir, err := os.MkdirTemp("", "pata-accept-updater-zip-*")
	if err != nil {
		t.Fatal(err)
	}
	defer os.RemoveAll(tmpDir)

	// Create dummy app bundle
	appDir := filepath.Join(tmpDir, "pata.app")
	_ = os.MkdirAll(filepath.Join(appDir, "Contents", "MacOS"), 0755)
	_ = os.WriteFile(filepath.Join(appDir, "Contents", "MacOS", "pata"), []byte("mock binary"), 0755)

	zipPath := filepath.Join(tmpDir, "pata-darwin-arm64.app.zip")

	// Use ditto to bundle keeping parent
	cmd := exec.Command("ditto", "-c", "-k", "--keepParent", appDir, zipPath)
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("ditto failed: %s, err: %v", string(out), err)
	}

	// Read zip and verify exactly one top-level root entry
	r, err := zip.OpenReader(zipPath)
	if err != nil {
		t.Fatalf("failed to open zip: %v", err)
	}
	defer r.Close()

	topLevelRoots := make(map[string]bool)
	for _, f := range r.File {
		parts := strings.Split(strings.TrimPrefix(filepath.Clean(f.Name), "/"), string(filepath.Separator))
		if len(parts) > 0 && parts[0] != "" {
			topLevelRoots[parts[0]] = true
		}
	}

	if len(topLevelRoots) != 1 {
		t.Fatalf("expected exactly 1 top-level root in zip, got %d (%v)", len(topLevelRoots), topLevelRoots)
	}
	for root := range topLevelRoots {
		if root != "pata.app" {
			t.Errorf("expected root entry to be pata.app, got %s", root)
		}
	}
}
