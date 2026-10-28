package app

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"pata/internal/keychain"
)

func openAppearanceIntegrationVault(t *testing.T) *VaultService {
	t.Helper()
	s := &VaultService{keychain: keychain.NewMemoryStore(), configPath: filepath.Join(t.TempDir(), "vault.json")}
	if _, err := s.openVault(t.TempDir()); err != nil {
		t.Fatal(err)
	}
	if err := s.saveConfig(VaultConfig{VaultPath: s.vault.RootPath}); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		if s.stopWatcher != nil {
			s.stopWatcher()
		}
	})
	return s
}

func TestAppearanceIntegrationPersistenceAndIsolation(t *testing.T) {
	s := openAppearanceIntegrationVault(t)
	root := s.vault.RootPath
	note, err := s.CreateNote(CreateNoteInput{Title: "颜色测试笔记", Body: "正文不随外观设置变化"})
	if err != nil {
		t.Fatal(err)
	}
	path := s.vault.ResolveEntityPath(note)
	before, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if color, err := s.GetAccentColorPreference(); err != nil || color != "" {
		t.Fatal("旧配置应使用默认强调色")
	}
	if err := s.SetThemePreference("light"); err != nil {
		t.Fatal(err)
	}
	if err := s.SetAccentColorPreference("  #7C3AED "); err != nil {
		t.Fatal(err)
	}
	reopened := &VaultService{configPath: s.configPath}
	if color, err := reopened.GetAccentColorPreference(); err != nil || color != "#7c3aed" {
		t.Fatal("重新创建服务后未恢复颜色")
	}
	cfg, err := s.loadConfig()
	if err != nil || cfg.Theme != "light" || cfg.VaultPath != root {
		t.Fatal("保存颜色影响了明暗模式或 Vault 配置")
	}
	if _, err := s.openVault(t.TempDir()); err != nil {
		t.Fatal(err)
	}
	if err := s.SetThemePreference("dark"); err != nil {
		t.Fatal(err)
	}
	if color, err := s.GetAccentColorPreference(); err != nil || color != "#7c3aed" {
		t.Fatal("更换 Vault 或切换明暗模式后丢失颜色")
	}
	if err := s.SetAccentColorPreference(""); err != nil {
		t.Fatal(err)
	}
	if color, err := reopened.GetAccentColorPreference(); err != nil || color != "" {
		t.Fatal("恢复默认后不应残留自定义颜色")
	}
	data, err := os.ReadFile(s.configPath)
	if err != nil || strings.Contains(string(data), "accent_color") {
		t.Fatal("默认颜色应清除自定义偏好")
	}
	after, err := os.ReadFile(path)
	if err != nil || string(before) != string(after) {
		t.Fatal("外观设置修改了原笔记文件")
	}
}

func TestAppearanceIntegrationValidationAndFailure(t *testing.T) {
	s := openAppearanceIntegrationVault(t)
	if err := s.SetAccentColorPreference("#000000"); err != nil {
		t.Fatal(err)
	}
	before, err := os.ReadFile(s.configPath)
	if err != nil {
		t.Fatal(err)
	}
	for _, invalid := range []string{"#fff", "#12345678", "rgb(1,2,3)", "#gg0000", "red; color: black", "none"} {
		if err := s.SetAccentColorPreference(invalid); err == nil {
			t.Fatalf("接受了无效颜色 %q", invalid)
		}
	}
	after, err := os.ReadFile(s.configPath)
	if err != nil || string(before) != string(after) {
		t.Fatal("无效颜色不应改变配置")
	}
	if err := s.SetAccentColorPreference("#ffffff"); err != nil {
		t.Fatal("应接受 RGB 边界颜色")
	}
	if err := os.WriteFile(s.configPath, []byte("{损坏配置"), 0600); err != nil {
		t.Fatal(err)
	}
	if _, err := s.GetAccentColorPreference(); err == nil {
		t.Fatal("读取失败不应冒充默认配置")
	}
	if err := s.SetAccentColorPreference("#123456"); err == nil {
		t.Fatal("不应覆盖损坏的配置")
	}
	after, err = os.ReadFile(s.configPath)
	if err != nil || string(after) != "{损坏配置" {
		t.Fatal("原损坏配置未保留")
	}
	s.configPath = filepath.Join(t.TempDir(), "config-directory")
	if err := os.Mkdir(s.configPath, 0700); err != nil {
		t.Fatal(err)
	}
	if err := s.SetAccentColorPreference("#123456"); err == nil {
		t.Fatal("配置不可写时应报告错误")
	}
}
