package app

import (
	"fmt"
	"regexp"
	"strings"
)

var accentColorPattern = regexp.MustCompile(`^#[0-9a-f]{6}$`)

// GetAccentColorPreference 返回主题强调色；空值使用应用默认配色。
func (s *VaultService) GetAccentColorPreference() (string, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	cfg, err := s.loadConfig()
	if err != nil {
		return "", fmt.Errorf("读取主题色配置失败")
	}
	color := strings.ToLower(strings.TrimSpace(cfg.AccentColor))
	if color != "" && !accentColorPattern.MatchString(color) {
		return "", fmt.Errorf("主题色配置无效，请恢复默认颜色")
	}
	return color, nil
}

// SetAccentColorPreference 仅保存应用强调色，不修改 Vault 业务数据。
func (s *VaultService) SetAccentColorPreference(color string) (err error) {
	color = strings.ToLower(strings.TrimSpace(color))
	if color != "" && !accentColorPattern.MatchString(color) {
		return fmt.Errorf("主题色必须为六位 RGB 十六进制颜色")
	}
	s.mu.Lock()
	defer func() {
		s.mu.Unlock()
		if err == nil {
			s.dispatchEvent("appearance:changed", nil)
		}
	}()
	cfg, err := s.loadConfig()
	if err != nil {
		return fmt.Errorf("读取主题色配置失败，原配置已保留")
	}
	cfg.AccentColor = color
	if err := s.saveConfig(cfg); err != nil {
		return fmt.Errorf("保存主题色失败，请重试")
	}
	return nil
}
