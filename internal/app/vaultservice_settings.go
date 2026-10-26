package app

import (
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"strings"

	"pata/internal/keychain"
)

// WindowStateConfig stores persisted window dimensions and state.
type WindowStateConfig struct {
	Width       int  `json:"width,omitempty"`
	Height      int  `json:"height,omitempty"`
	IsMaximised bool `json:"is_maximised,omitempty"`
}

// VaultConfig is the persisted single-vault choice (D18: 单 Vault) and app preferences.
type VaultConfig struct {
	AutoCheckUpdates *bool              `json:"auto_check_updates,omitempty"`
	MCPEnabled       bool               `json:"mcp_enabled,omitempty"`
	VaultPath        string             `json:"vault_path"`
	Theme            string             `json:"theme,omitempty"`
	Window           *WindowStateConfig `json:"window,omitempty"`
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

// GetAutoCheckUpdatesPreference returns the persisted preference for auto checking updates.
// If not explicitly set in config, it returns the provided defaultVal.
func (s *VaultService) GetAutoCheckUpdatesPreference(defaultVal bool) (bool, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	cfg, err := s.loadConfig()
	if err != nil || cfg.AutoCheckUpdates == nil {
		return defaultVal, nil
	}
	return *cfg.AutoCheckUpdates, nil
}

// SetAutoCheckUpdatesPreference persists the auto update check preference.
func (s *VaultService) SetAutoCheckUpdatesPreference(enabled bool) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	cfg, err := s.loadConfig()
	if err != nil {
		return fmt.Errorf("读取配置文件失败: %w", err)
	}
	if cfg.VaultPath == "" && s.vault != nil && s.vault.RootPath != "" {
		cfg.VaultPath = s.vault.RootPath
	}
	cfg.AutoCheckUpdates = &enabled
	return s.saveConfig(cfg)
}

const (
	DefaultWindowWidth  = 1120
	DefaultWindowHeight = 740
	MinWindowWidth      = 800
	MinWindowHeight     = 520
)

// OpenWindowSize returns the width and height to open the window at, based on
// saved configuration and minimum limits.
func OpenWindowSize(saved *WindowStateConfig) (int, int) {
	if saved == nil {
		return DefaultWindowWidth, DefaultWindowHeight
	}
	w, h := saved.Width, saved.Height
	if w <= 0 {
		w = DefaultWindowWidth
	}
	if h <= 0 {
		h = DefaultWindowHeight
	}
	return max(w, MinWindowWidth), max(h, MinWindowHeight)
}

func absInt(n int) int {
	if n < 0 {
		return -n
	}
	return n
}

// GetWindowStatePreference returns the persisted window dimensions and state.
func (s *VaultService) GetWindowStatePreference() (*WindowStateConfig, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	cfg, err := s.loadConfig()
	if err != nil || cfg.Window == nil {
		return nil, err
	}
	windowCopy := *cfg.Window
	return &windowCopy, nil
}

// SetWindowStatePreference sets the window state preference directly.
func (s *VaultService) SetWindowStatePreference(state WindowStateConfig) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	cfg, err := s.loadConfig()
	if err != nil {
		return fmt.Errorf("读取配置文件失败: %w", err)
	}
	if cfg.VaultPath == "" && s.vault != nil && s.vault.RootPath != "" {
		cfg.VaultPath = s.vault.RootPath
	}
	if state.Width < MinWindowWidth {
		state.Width = MinWindowWidth
	}
	if state.Height < MinWindowHeight {
		state.Height = MinWindowHeight
	}
	cfg.Window = &state
	return s.saveConfig(cfg)
}

// UpdateWindowState safely updates the persisted window state from runtime events,
// applying debounce jitter filtering and preserving unmaximised bounds.
func (s *VaultService) UpdateWindowState(w, h int, isMaximised bool) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	cfg, err := s.loadConfig()
	if err != nil {
		return err
	}
	if cfg.VaultPath == "" && s.vault != nil && s.vault.RootPath != "" {
		cfg.VaultPath = s.vault.RootPath
	}

	current := cfg.Window
	if isMaximised {
		if current == nil {
			current = &WindowStateConfig{
				Width:       DefaultWindowWidth,
				Height:      DefaultWindowHeight,
				IsMaximised: true,
			}
		} else {
			if current.IsMaximised {
				return nil
			}
			current.IsMaximised = true
		}
		cfg.Window = current
		return s.saveConfig(cfg)
	}

	if w < MinWindowWidth || h < MinWindowHeight {
		return nil
	}

	// Avoid jitter within 2 points (macOS window bounds rounding)
	if current != nil && !current.IsMaximised {
		if absInt(current.Width-w) <= 2 && absInt(current.Height-h) <= 2 {
			return nil
		}
	}

	cfg.Window = &WindowStateConfig{
		Width:       w,
		Height:      h,
		IsMaximised: false,
	}
	return s.saveConfig(cfg)
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
