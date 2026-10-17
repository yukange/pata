package main

import (
	"os"
	"path/filepath"
	"testing"

	"pata/internal/keychain"
)

func TestThemePreference(t *testing.T) {
	tmpDir := t.TempDir()
	configPath := filepath.Join(tmpDir, "pata", "vault.json")

	svc := &VaultService{
		configPath: configPath,
		keychain:   keychain.NewMemoryStore(),
	}

	// 1. Default should be "system"
	theme, err := svc.GetThemePreference()
	if err != nil {
		t.Fatalf("GetThemePreference failed: %v", err)
	}
	if theme != "system" {
		t.Fatalf("expected default theme to be 'system', got %q", theme)
	}

	// 2. Invalid theme should return error
	if err := svc.SetThemePreference("blue"); err == nil {
		t.Fatalf("expected error for invalid theme 'blue', got nil")
	}

	// 3. Set valid theme "dark"
	if err := svc.SetThemePreference("dark"); err != nil {
		t.Fatalf("SetThemePreference('dark') failed: %v", err)
	}
	theme, err = svc.GetThemePreference()
	if err != nil {
		t.Fatalf("GetThemePreference failed: %v", err)
	}
	if theme != "dark" {
		t.Fatalf("expected 'dark', got %q", theme)
	}

	// 4. Persistence across service instances
	svc2 := &VaultService{
		configPath: configPath,
		keychain:   keychain.NewMemoryStore(),
	}
	theme, err = svc2.GetThemePreference()
	if err != nil {
		t.Fatalf("GetThemePreference on second instance failed: %v", err)
	}
	if theme != "dark" {
		t.Fatalf("expected persisted theme 'dark', got %q", theme)
	}

	// 5. Set "light" with trimming
	if err := svc.SetThemePreference("  LIGHT  "); err != nil {
		t.Fatalf("SetThemePreference('  LIGHT  ') failed: %v", err)
	}
	theme, err = svc.GetThemePreference()
	if err != nil {
		t.Fatalf("GetThemePreference failed: %v", err)
	}
	if theme != "light" {
		t.Fatalf("expected 'light', got %q", theme)
	}

	// 6. Test that corrupted config returns error rather than overwriting config
	_ = os.WriteFile(configPath, []byte("invalid-json{"), 0644)
	if err := svc.SetThemePreference("dark"); err == nil {
		t.Fatalf("expected error when setting theme on corrupted config, got nil")
	}
	content, _ := os.ReadFile(configPath)
	if string(content) != "invalid-json{" {
		t.Fatalf("corrupted config was overwritten: %s", string(content))
	}
}

func TestOpenVaultInFinderErrors(t *testing.T) {
	svc := &VaultService{
		keychain: keychain.NewMemoryStore(),
	}

	// Vault not opened
	err := svc.OpenVaultInFinder()
	if err == nil {
		t.Fatalf("expected error when vault is not opened, got nil")
	}
}

func TestASRConfigAndKeychain(t *testing.T) {
	memStore := keychain.NewMemoryStore()
	svc := &VaultService{
		keychain: memStore,
	}

	// 1. Initial status: unconfigured
	st, err := svc.GetASRConfigStatus()
	if err != nil {
		t.Fatalf("GetASRConfigStatus failed: %v", err)
	}
	if st.Configured {
		t.Fatalf("expected configured to be false initially")
	}
	if st.Provider != ASRProvider || st.Model != ASRModel || st.Region != ASRRegion {
		t.Fatalf("unexpected provider/model/region info: %+v", st)
	}

	// 2. getASRKeyInternal should fail when unconfigured
	_, err = svc.getASRKeyInternal()
	if err == nil {
		t.Fatalf("expected error when ASR key is unconfigured, got nil")
	}

	// 3. Set empty key should fail
	if err := svc.SetASRKey("   "); err == nil {
		t.Fatalf("expected error when setting whitespace key, got nil")
	}

	// 4. Set valid key
	firstKey := "sk-test-valid-aliyun-key-12345"
	if err := svc.SetASRKey(firstKey); err != nil {
		t.Fatalf("SetASRKey failed: %v", err)
	}

	// 5. Config status should now be true
	st, err = svc.GetASRConfigStatus()
	if err != nil {
		t.Fatalf("GetASRConfigStatus failed: %v", err)
	}
	if !st.Configured {
		t.Fatalf("expected configured to be true after setting key")
	}

	// 6. Internal retrieval should return the exact key
	retrieved, err := svc.getASRKeyInternal()
	if err != nil {
		t.Fatalf("getASRKeyInternal failed: %v", err)
	}
	if retrieved != firstKey {
		t.Fatalf("got %q, want %q", retrieved, firstKey)
	}

	// 7. Attempt replacement with empty key fails and preserves old key
	if err := svc.SetASRKey("   "); err == nil {
		t.Fatalf("expected error on empty key replacement")
	}
	retrieved, err = svc.getASRKeyInternal()
	if err != nil || retrieved != firstKey {
		t.Fatalf("expected old key %q preserved after failed replacement, got %q (err: %v)", firstKey, retrieved, err)
	}

	// 8. Successful replacement
	secondKey := "sk-test-replacement-key-67890"
	if err := svc.SetASRKey(secondKey); err != nil {
		t.Fatalf("SetASRKey failed: %v", err)
	}
	retrieved, err = svc.getASRKeyInternal()
	if err != nil || retrieved != secondKey {
		t.Fatalf("expected new key %q, got %q", secondKey, retrieved)
	}
}

func TestChangingVaultPreservesTheme(t *testing.T) {
	tmpDir := t.TempDir()
	configPath := filepath.Join(tmpDir, "pata", "vault.json")

	svc := &VaultService{
		configPath: configPath,
		keychain:   keychain.NewMemoryStore(),
	}

	// Set theme to dark
	if err := svc.SetThemePreference("dark"); err != nil {
		t.Fatalf("SetThemePreference failed: %v", err)
	}

	// Create dummy vault dir
	vaultDir := filepath.Join(tmpDir, "my-vault")
	if err := os.MkdirAll(vaultDir, 0755); err != nil {
		t.Fatalf("MkdirAll failed: %v", err)
	}

	// Simulate config save as done in SelectVaultDirectory
	cfg, err := svc.loadConfig()
	if err != nil {
		t.Fatalf("loadConfig failed: %v", err)
	}
	cfg.VaultPath = vaultDir
	if err := svc.saveConfig(cfg); err != nil {
		t.Fatalf("saveConfig failed: %v", err)
	}

	// Theme must still be dark!
	theme, err := svc.GetThemePreference()
	if err != nil {
		t.Fatalf("GetThemePreference failed: %v", err)
	}
	if theme != "dark" {
		t.Fatalf("expected theme 'dark' preserved across vault update, got %q", theme)
	}
}
