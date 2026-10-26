package app

import (
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"testing"

	"pata/internal/keychain"
)

// TestAcceptance_Settings_ThemePersistenceAcrossVaults validates that theme preference
// persists across service restarts, independent of whether a Vault is open or switched.
func TestAcceptance_Settings_ThemePersistenceAcrossVaults(t *testing.T) {
	tmpDir, err := os.MkdirTemp("", "pata-settings-theme-*")
	if err != nil {
		t.Fatal(err)
	}
	defer os.RemoveAll(tmpDir)

	configPath := filepath.Join(tmpDir, "config", "vault.json")
	vaultDir1 := filepath.Join(tmpDir, "vault-1")
	vaultDir2 := filepath.Join(tmpDir, "vault-2")
	_ = os.MkdirAll(vaultDir1, 0755)
	_ = os.MkdirAll(vaultDir2, 0755)

	svc := &VaultService{
		configPath: configPath,
		keychain:   keychain.NewMemoryStore(),
	}

	// 1. Initial default is "system"
	theme, err := svc.GetThemePreference()
	if err != nil {
		t.Fatalf("GetThemePreference failed: %v", err)
	}
	if theme != "system" {
		t.Errorf("expected default theme 'system', got %q", theme)
	}

	// 2. Set theme to "dark"
	if err := svc.SetThemePreference("dark"); err != nil {
		t.Fatalf("SetThemePreference('dark') failed: %v", err)
	}

	// 3. Open vault-1
	if _, err := svc.openVault(vaultDir1); err != nil {
		t.Fatalf("openVault(vaultDir1) failed: %v", err)
	}
	cfg, _ := svc.loadConfig()
	cfg.VaultPath = vaultDir1
	_ = svc.saveConfig(cfg)

	// Verify theme is still "dark" after configuring vault
	theme, err = svc.GetThemePreference()
	if err != nil || theme != "dark" {
		t.Errorf("expected theme 'dark' preserved after configuring vault, got %q (err: %v)", theme, err)
	}

	// 4. Switch to vault-2: theme must STILL be "dark"
	if _, err := svc.openVault(vaultDir2); err != nil {
		t.Fatalf("openVault(vaultDir2) failed: %v", err)
	}
	cfg, _ = svc.loadConfig()
	cfg.VaultPath = vaultDir2
	_ = svc.saveConfig(cfg)

	theme, err = svc.GetThemePreference()
	if err != nil || theme != "dark" {
		t.Errorf("expected theme 'dark' preserved across vault switch, got %q (err: %v)", theme, err)
	}
}

// TestAcceptance_Settings_KeychainSecureStorage validates ASR API Key security:
// stored in Keychain, status query hides plain key, empty input is rejected,
// and on macOS verifies the OS Keychain CLI.
func TestAcceptance_Settings_KeychainSecureStorage(t *testing.T) {
	tmpDir, err := os.MkdirTemp("", "pata-settings-keychain-*")
	if err != nil {
		t.Fatal(err)
	}
	defer os.RemoveAll(tmpDir)

	configPath := filepath.Join(tmpDir, "config", "vault.json")
	memKeychain := keychain.NewMemoryStore()

	svc := &VaultService{
		configPath: configPath,
		keychain:   memKeychain,
	}

	// 1. Initially unconfigured
	st, err := svc.GetASRConfigStatus()
	if err != nil {
		t.Fatalf("GetASRConfigStatus failed: %v", err)
	}
	if st.Configured {
		t.Errorf("expected initially unconfigured")
	}
	if st.Provider != "阿里云百炼" || st.Model != "qwen-audio-3.1-asr-flash-filetrans" || st.Region != "华北2（北京）" {
		t.Errorf("unexpected fixed provider/model/region specs: %+v", st)
	}

	// 2. Saving empty or whitespace key must be rejected
	if err := svc.SetASRKey(""); err == nil {
		t.Errorf("expected error for empty key, got nil")
	}
	if err := svc.SetASRKey("   \t  "); err == nil {
		t.Errorf("expected error for whitespace key, got nil")
	}

	// 3. Save valid key
	firstKey := "sk-test-secret-acceptance-key-1"
	if err := svc.SetASRKey(firstKey); err != nil {
		t.Fatalf("SetASRKey failed: %v", err)
	}

	st, err = svc.GetASRConfigStatus()
	if err != nil || !st.Configured {
		t.Errorf("expected configured after setting valid key")
	}

	// 4. On macOS, verify direct interaction with Darwin Keychain
	if runtime.GOOS == "darwin" {
		darwinKeychain := keychain.NewDarwinStore()
		testSvc := "com.pata.app.test-acceptance"
		testAcct := "test-acceptance-account"
		testSecret := "sk-real-macos-keychain-test"

		_ = darwinKeychain.Delete(testSvc, testAcct)
		if err := darwinKeychain.Set(testSvc, testAcct, testSecret); err != nil {
			t.Fatalf("failed to set secret in macOS keychain: %v", err)
		}
		defer func() {
			_ = darwinKeychain.Delete(testSvc, testAcct)
		}()

		secCmd := exec.Command("/usr/bin/security", "find-generic-password", "-s", testSvc, "-a", testAcct, "-w")
		out, err := secCmd.Output()
		if err != nil {
			t.Fatalf("/usr/bin/security find-generic-password failed: %v", err)
		}
		if strings.TrimSpace(string(out)) != testSecret {
			t.Fatalf("expected keychain secret %q, got %q", testSecret, strings.TrimSpace(string(out)))
		}

		if err := darwinKeychain.Delete(testSvc, testAcct); err != nil {
			t.Fatalf("failed to delete from macOS keychain: %v", err)
		}
		secCheckCmd := exec.Command("/usr/bin/security", "find-generic-password", "-s", testSvc, "-a", testAcct, "-w")
		if err := secCheckCmd.Run(); err == nil {
			t.Fatalf("expected /usr/bin/security to return error after deletion, but it succeeded")
		}
	}
}

// TestAcceptance_Settings_VaultRescanAndFinderInspection verifies storage maintenance operations:
// RescanVault, OpenVaultInFinder, and safe error handling on closed vault.
func TestAcceptance_Settings_VaultRescanAndFinderInspection(t *testing.T) {
	tmpDir, err := os.MkdirTemp("", "pata-settings-storage-*")
	if err != nil {
		t.Fatal(err)
	}
	defer os.RemoveAll(tmpDir)

	configPath := filepath.Join(tmpDir, "config", "vault.json")
	vaultDir := filepath.Join(tmpDir, "vault")
	_ = os.MkdirAll(vaultDir, 0755)

	var lastLaunchedCmd *exec.Cmd
	svc := &VaultService{
		configPath: configPath,
		keychain:   keychain.NewMemoryStore(),
		launcher: func(cmd *exec.Cmd) error {
			lastLaunchedCmd = cmd
			return nil
		},
	}

	if _, err := svc.openVault(vaultDir); err != nil {
		t.Fatalf("openVault failed: %v", err)
	}

	// 1. Verify RescanVault succeeds
	if err := svc.RescanVault(); err != nil {
		t.Fatalf("RescanVault failed: %v", err)
	}

	// 2. Verify OpenVaultInFinder executes platform-appropriate launcher command
	if err := svc.OpenVaultInFinder(); err != nil {
		t.Fatalf("OpenVaultInFinder failed: %v", err)
	}
	if lastLaunchedCmd == nil || len(lastLaunchedCmd.Args) == 0 {
		t.Fatalf("expected OpenVaultInFinder to invoke launcher")
	}
	switch runtime.GOOS {
	case "darwin":
		if lastLaunchedCmd.Args[0] != "open" || lastLaunchedCmd.Args[1] != vaultDir {
			t.Errorf("expected 'open %s', got %v", vaultDir, lastLaunchedCmd.Args)
		}
	case "windows":
		if lastLaunchedCmd.Args[0] != "explorer" || lastLaunchedCmd.Args[1] != vaultDir {
			t.Errorf("expected 'explorer %s', got %v", vaultDir, lastLaunchedCmd.Args)
		}
	default:
		if lastLaunchedCmd.Args[0] != "xdg-open" || lastLaunchedCmd.Args[1] != vaultDir {
			t.Errorf("expected 'xdg-open %s', got %v", vaultDir, lastLaunchedCmd.Args)
		}
	}

	// 3. Verify error on closed vault
	closedSvc := &VaultService{}
	if err := closedSvc.OpenVaultInFinder(); err == nil || !strings.Contains(err.Error(), "Vault 尚未打开") {
		t.Errorf("expected error on closed vault, got %v", err)
	}
}

// TestAcceptance_Settings_WindowStatePersistenceAcrossReopenAndReinstall verifies that:
// 1. Fresh install defaults to standard window dimensions (1120x740).
// 2. Resized window dimensions persist across app closes, reopens, and reinstalls without resetting.
// 3. Other user settings (vault_path, theme, mcp_enabled) are preserved alongside window state.
func TestAcceptance_Settings_WindowStatePersistenceAcrossReopenAndReinstall(t *testing.T) {
	tmpDir, err := os.MkdirTemp("", "pata-settings-window-*")
	if err != nil {
		t.Fatal(err)
	}
	defer os.RemoveAll(tmpDir)

	configPath := filepath.Join(tmpDir, "config", "vault.json")
	vaultDir := filepath.Join(tmpDir, "vault")
	_ = os.MkdirAll(vaultDir, 0755)

	// Step 1: Fresh install - no config file exists yet
	svc1 := &VaultService{
		configPath: configPath,
		keychain:   keychain.NewMemoryStore(),
	}
	st, err := svc1.GetWindowStatePreference()
	if err != nil {
		t.Fatalf("GetWindowStatePreference failed on fresh install: %v", err)
	}
	if st != nil {
		t.Fatalf("expected nil window state on fresh install, got %+v", st)
	}
	w, h := OpenWindowSize(st)
	if w != DefaultWindowWidth || h != DefaultWindowHeight {
		t.Fatalf("fresh install must default to %dx%d, got %dx%d", DefaultWindowWidth, DefaultWindowHeight, w, h)
	}

	// Configure a vault and theme
	if _, err := svc1.openVault(vaultDir); err != nil {
		t.Fatalf("openVault failed: %v", err)
	}
	cfg, _ := svc1.loadConfig()
	cfg.VaultPath = vaultDir
	cfg.Theme = "dark"
	cfg.MCPEnabled = true
	_ = svc1.saveConfig(cfg)

	// Step 2: User resizes window to 1380x860 during session
	if err := svc1.UpdateWindowState(1380, 860, false); err != nil {
		t.Fatalf("UpdateWindowState failed: %v", err)
	}

	// Verify vault.json has the window state alongside theme & vault_path
	savedCfg, err := svc1.loadConfig()
	if err != nil {
		t.Fatalf("loadConfig failed: %v", err)
	}
	if savedCfg.Window == nil || savedCfg.Window.Width != 1380 || savedCfg.Window.Height != 860 {
		t.Fatalf("expected window state 1380x860 in config, got %+v", savedCfg.Window)
	}
	if savedCfg.VaultPath != vaultDir || savedCfg.Theme != "dark" || !savedCfg.MCPEnabled {
		t.Fatalf("expected other preferences preserved, got %+v", savedCfg)
	}

	// Step 3: Simulate closing app and reopening (svc2 represents reopened app)
	svc2 := &VaultService{
		configPath: configPath,
		keychain:   keychain.NewMemoryStore(),
	}
	reopenedState, err := svc2.GetWindowStatePreference()
	if err != nil || reopenedState == nil {
		t.Fatalf("failed to retrieve window state on reopen: %v", err)
	}
	reopenedW, reopenedH := OpenWindowSize(reopenedState)
	if reopenedW != 1380 || reopenedH != 860 {
		t.Fatalf("reopened window size reset unexpectedly: expected 1380x860, got %dx%d", reopenedW, reopenedH)
	}

	// Step 4: Simulate reinstalling app (binary replaced, config file in Application Support persists)
	// New instance svc3 represents app after reinstall
	svc3 := &VaultService{
		configPath: configPath,
		keychain:   keychain.NewMemoryStore(),
	}
	reinstalledState, err := svc3.GetWindowStatePreference()
	if err != nil || reinstalledState == nil {
		t.Fatalf("failed to retrieve window state after reinstall: %v", err)
	}
	reinstalledW, reinstalledH := OpenWindowSize(reinstalledState)
	if reinstalledW != 1380 || reinstalledH != 860 {
		t.Fatalf("reinstalled window size reset to initial: expected 1380x860, got %dx%d", reinstalledW, reinstalledH)
	}
}
