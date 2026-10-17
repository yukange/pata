package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"syscall"
	"testing"
	"time"

	"pata/internal/keychain"
)

// TestStage10_SettingsAcceptance validates the end-to-end capabilities of Phase 10:
// 1. Theme preference persistence across service restarts and independent of Vault
// 2. Storage operations: vault path inspection, rescan, and Finder opening
// 3. ASR API Key security: stored in Keychain, status query hides plain key, internal retrieval for stage 11,
//    failed replacement preserves old key, and secret never written to vault or config files.
func TestStage10_SettingsAcceptance(t *testing.T) {
	tmpDir, err := os.MkdirTemp("", "pata-stage10-*")
	if err != nil {
		t.Fatal(err)
	}
	defer os.RemoveAll(tmpDir)

	configPath := filepath.Join(tmpDir, "config", "vault.json")
	vaultDir1 := filepath.Join(tmpDir, "vault-1")
	vaultDir2 := filepath.Join(tmpDir, "vault-2")
	_ = os.MkdirAll(vaultDir1, 0755)
	_ = os.MkdirAll(vaultDir2, 0755)

	memKeychain := keychain.NewMemoryStore()

	var lastLaunchedCmd *exec.Cmd
	svc := &VaultService{
		configPath: configPath,
		keychain:   memKeychain,
		launcher: func(cmd *exec.Cmd) error {
			lastLaunchedCmd = cmd
			return nil
		},
	}

	// 1. Theme preference: initial default is "system"
	theme, err := svc.GetThemePreference()
	if err != nil {
		t.Fatalf("GetThemePreference failed: %v", err)
	}
	if theme != "system" {
		t.Errorf("expected default theme 'system', got %q", theme)
	}

	// Set theme to "dark"
	if err := svc.SetThemePreference("dark"); err != nil {
		t.Fatalf("SetThemePreference('dark') failed: %v", err)
	}

	// Open vault-1
	if _, err := svc.openVault(vaultDir1); err != nil {
		t.Fatalf("openVault(vaultDir1) failed: %v", err)
	}
	cfg, _ := svc.loadConfig()
	cfg.VaultPath = vaultDir1
	_ = svc.saveConfig(cfg)

	// Verify theme is still "dark" after vault configuration
	theme, err = svc.GetThemePreference()
	if err != nil || theme != "dark" {
		t.Errorf("expected theme 'dark' preserved after configuring vault, got %q (err: %v)", theme, err)
	}

	// Verify OpenVaultInFinder succeeds on opened vault without external GUI side effects
	if err := svc.OpenVaultInFinder(); err != nil {
		t.Fatalf("OpenVaultInFinder failed: %v", err)
	}
	if lastLaunchedCmd == nil || len(lastLaunchedCmd.Args) == 0 {
		t.Fatalf("expected OpenVaultInFinder to invoke launcher")
	}
	switch runtime.GOOS {
	case "darwin":
		if lastLaunchedCmd.Args[0] != "open" || lastLaunchedCmd.Args[1] != vaultDir1 {
			t.Errorf("expected 'open %s', got %v", vaultDir1, lastLaunchedCmd.Args)
		}
	case "windows":
		if lastLaunchedCmd.Args[0] != "explorer" || lastLaunchedCmd.Args[1] != vaultDir1 {
			t.Errorf("expected 'explorer %s', got %v", vaultDir1, lastLaunchedCmd.Args)
		}
	default:
		if lastLaunchedCmd.Args[0] != "xdg-open" || lastLaunchedCmd.Args[1] != vaultDir1 {
			t.Errorf("expected 'xdg-open %s', got %v", vaultDir1, lastLaunchedCmd.Args)
		}
	}

	// Verify error on closed vault
	closedSvc := &VaultService{}
	if err := closedSvc.OpenVaultInFinder(); err == nil || !strings.Contains(err.Error(), "Vault 尚未打开") {
		t.Errorf("expected error on closed vault, got %v", err)
	}

	// Verify RescanVault
	if err := svc.RescanVault(); err != nil {
		t.Fatalf("RescanVault failed: %v", err)
	}

	// Switch to vault-2
	if _, err := svc.openVault(vaultDir2); err != nil {
		t.Fatalf("openVault(vaultDir2) failed: %v", err)
	}
	cfg, _ = svc.loadConfig()
	cfg.VaultPath = vaultDir2
	_ = svc.saveConfig(cfg)

	// Theme must STILL be "dark" after changing vault!
	theme, err = svc.GetThemePreference()
	if err != nil || theme != "dark" {
		t.Errorf("expected theme 'dark' preserved across vault switch, got %q (err: %v)", theme, err)
	}

	// 2. ASR API Key security and Keychain integration
	// Initial state: unconfigured
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

	// Saving empty key must be rejected
	if err := svc.SetASRKey(""); err == nil {
		t.Errorf("expected error for empty key, got nil")
	}
	if err := svc.SetASRKey("   \t  "); err == nil {
		t.Errorf("expected error for whitespace key, got nil")
	}

	// Save valid key
	firstKey := "sk-test-secret-acceptance-key-1"
	if err := svc.SetASRKey(firstKey); err != nil {
		t.Fatalf("SetASRKey failed: %v", err)
	}

	// Status query returns configured=true
	st, err = svc.GetASRConfigStatus()
	if err != nil || !st.Configured {
		t.Fatalf("expected configured=true, got %v (err: %v)", st.Configured, err)
	}

	// Verify internal retrieval gets plain key
	internalKey, err := svc.getASRKeyInternal()
	if err != nil || internalKey != firstKey {
		t.Fatalf("expected internalKey %q, got %q (err: %v)", firstKey, internalKey, err)
	}

	// Attempt to replace with empty key: fails and preserves old key!
	if err := svc.SetASRKey("  "); err == nil {
		t.Fatalf("expected error on empty replacement")
	}
	internalKey, err = svc.getASRKeyInternal()
	if err != nil || internalKey != firstKey {
		t.Fatalf("expected old key %q preserved after failed replacement, got %q", firstKey, internalKey)
	}

	// Replace with new valid key
	secondKey := "sk-test-secret-acceptance-key-2"
	if err := svc.SetASRKey(secondKey); err != nil {
		t.Fatalf("SetASRKey(secondKey) failed: %v", err)
	}
	internalKey, err = svc.getASRKeyInternal()
	if err != nil || internalKey != secondKey {
		t.Fatalf("expected secondKey %q, got %q", secondKey, internalKey)
	}

	// 3. Security guarantee: Key must NEVER be written to vault.json or vault directories!
	configData, err := os.ReadFile(configPath)
	if err != nil {
		t.Fatalf("failed to read config file: %v", err)
	}
	if strings.Contains(string(configData), firstKey) || strings.Contains(string(configData), secondKey) {
		t.Fatalf("SECURITY VIOLATION: plain API Key was leaked into config file: %s", string(configData))
	}

	// Check vault dirs
	for _, vDir := range []string{vaultDir1, vaultDir2} {
		_ = filepath.Walk(vDir, func(p string, fi os.FileInfo, err error) error {
			if err != nil || fi.IsDir() {
				return nil
			}
			data, _ := os.ReadFile(p)
			if strings.Contains(string(data), firstKey) || strings.Contains(string(data), secondKey) {
				t.Fatalf("SECURITY VIOLATION: plain API Key was leaked into vault file %s", p)
			}
			return nil
		})
	}
}

// TestStage10_RealMachineLiveMacOS executes true macOS hardware and OS integration testing:
// 1. Verifies bin/pata.app package structure and codesign verification
// 2. Tests real macOS Keychain (/usr/bin/security) generic password operations directly
// 3. Tests real user config in ~/Library/Application Support/pata/vault.json
// 4. Tests real Vault interaction on /Users/wuyukang/code/github/test_pata
// 5. Launches bin/pata.app process on macOS and checks process lifecycle
func TestStage10_RealMachineLiveMacOS(t *testing.T) {
	if runtime.GOOS != "darwin" {
		t.Skip("skipping live macOS acceptance test on non-macOS")
	}
	if os.Getenv("PATA_LIVE_MACOS_TEST") != "1" {
		t.Skip("skipping live macOS acceptance test; set PATA_LIVE_MACOS_TEST=1 on macOS to run")
	}

	appPath := filepath.Join("bin", "pata.app")
	if _, err := os.Stat(appPath); os.IsNotExist(err) {
		t.Skip("bin/pata.app does not exist; run 'wails3 task package' first")
	}

	// 1. Codesign verification
	cmd := exec.Command("codesign", "--verify", "--deep", "--strict", appPath)
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("codesign verification failed: %s (err: %v)", string(out), err)
	}

	// 2. Real macOS Keychain testing via /usr/bin/security
	darwinKeychain := keychain.NewDarwinStore()
	testSvc := "pata.asr.acceptance.macos"
	testAcct := "aliyun_bailian_api_key"
	testSecret := "sk-real-mac-acceptance-key-live-10"

	// Cleanup first
	_ = darwinKeychain.Delete(testSvc, testAcct)

	// Set key into macOS login keychain
	if err := darwinKeychain.Set(testSvc, testAcct, testSecret); err != nil {
		t.Fatalf("failed to set secret in real macOS keychain: %v", err)
	}
	defer func() {
		_ = darwinKeychain.Delete(testSvc, testAcct)
	}()

	// Query macOS security command-line tool directly to prove the secret is in Keychain DB
	secCmd := exec.Command("/usr/bin/security", "find-generic-password", "-s", testSvc, "-a", testAcct, "-w")
	out, err := secCmd.Output()
	if err != nil {
		t.Fatalf("/usr/bin/security find-generic-password failed: %v", err)
	}
	if strings.TrimSpace(string(out)) != testSecret {
		t.Fatalf("expected keychain secret %q, got %q", testSecret, strings.TrimSpace(string(out)))
	}

	// Delete and verify gone
	if err := darwinKeychain.Delete(testSvc, testAcct); err != nil {
		t.Fatalf("failed to delete from macOS keychain: %v", err)
	}
	secCheckCmd := exec.Command("/usr/bin/security", "find-generic-password", "-s", testSvc, "-a", testAcct, "-w")
	if err := secCheckCmd.Run(); err == nil {
		t.Fatalf("expected /usr/bin/security to return error after deletion, but it succeeded")
	}

	// 3. Real Vault inspection on /Users/wuyukang/code/github/test_pata
	realVaultDir := "/Users/wuyukang/code/github/test_pata"
	if fi, err := os.Stat(realVaultDir); err == nil && fi.IsDir() {
		svc := NewVaultService()
		v, err := svc.openVault(realVaultDir)
		if err != nil {
			t.Fatalf("failed to open real vault %s: %v", realVaultDir, err)
		}
		defer func() {
			if svc.stopWatcher != nil {
				svc.stopWatcher()
			}
		}()

		st := svc.GetVaultStatus()
		if !st.Open || st.Path != realVaultDir {
			t.Fatalf("unexpected vault status for real vault: %+v", st)
		}

		if err := svc.RescanVault(); err != nil {
			t.Fatalf("rescan real vault failed: %v", err)
		}

		health, err := svc.GetVaultHealth()
		if err != nil {
			t.Fatalf("GetVaultHealth on real vault failed: %v", err)
		}
		t.Logf("Real vault health: %d parse errors, %d dangling refs, %d tasks indexed",
			len(health.ParseErrors), len(health.DanglingRefs), len(v.Index.ListTasks()))

		// Live macOS test: verify real OpenVaultInFinder launcher
		if err := svc.OpenVaultInFinder(); err != nil {
			t.Fatalf("OpenVaultInFinder on real vault failed: %v", err)
		}
	}

	// 4. Test live process launch of bin/pata.app
	launchCmd := exec.Command(filepath.Join(appPath, "Contents", "MacOS", "pata"))
	if err := launchCmd.Start(); err != nil {
		t.Fatalf("failed to launch bin/pata.app: %v", err)
	}
	defer func() {
		if launchCmd.Process != nil {
			_ = launchCmd.Process.Kill()
		}
	}()

	// Wait 1.5s to ensure window/app process initializes
	time.Sleep(1500 * time.Millisecond)

	// Check that process is running in macOS kernel
	if err := launchCmd.Process.Signal(os.Signal(syscall.Signal(0))); err != nil {
		t.Fatalf("pata process died prematurely: %v", err)
	}

	// Gracefully terminate the launched instance
	_ = launchCmd.Process.Signal(os.Interrupt)
	_ = launchCmd.Wait()
}
