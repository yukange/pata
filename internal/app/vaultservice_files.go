package app

import (
	"encoding/base64"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"

	"pata/internal/storage/markdown"
)

func generateUniqueFilename(dir, filename string) string {
	ext := filepath.Ext(filename)
	stem := strings.TrimSuffix(filename, ext)
	if stem == "" {
		stem = "file"
	}
	candidate := filename
	counter := 1
	for {
		targetPath := filepath.Join(dir, candidate)
		if _, err := os.Stat(targetPath); os.IsNotExist(err) {
			return candidate
		}
		candidate = fmt.Sprintf("%s %d%s", stem, counter, ext)
		counter++
	}
}

// ListFiles returns all files in the files/ directory of the vault.
func (s *VaultService) ListFiles() ([]markdown.FileResource, error) {
	s.mu.Lock()
	v := s.vault
	s.mu.Unlock()
	if v == nil {
		return nil, fmt.Errorf("尚未打开 Vault")
	}
	return v.Index.ListFiles(), nil
}

// ImportFile safely copies an external file into the vault's files/ directory without overwriting.
func (s *VaultService) ImportFile(sourcePath string) (*markdown.FileResource, error) {
	s.mu.Lock()
	v := s.vault
	s.mu.Unlock()
	if v == nil {
		return nil, fmt.Errorf("尚未打开 Vault")
	}

	cleanSrc := filepath.Clean(strings.TrimSpace(sourcePath))
	fi, err := os.Stat(cleanSrc)
	if err != nil {
		return nil, fmt.Errorf("读取源文件失败: %w", err)
	}
	if fi.IsDir() {
		return nil, fmt.Errorf("源路径是一个目录，仅支持导入文件")
	}

	filesDir := filepath.Join(v.RootPath, "files")
	if err := os.MkdirAll(filesDir, 0755); err != nil {
		return nil, fmt.Errorf("创建 files 目录失败: %w", err)
	}

	baseName := filepath.Base(cleanSrc)
	var (
		uniqueName string
		targetPath string
		baseline   *markdown.FileBaseline
	)

	const maxRetries = 100
	for attempt := 0; attempt < maxRetries; attempt++ {
		uniqueName = generateUniqueFilename(filesDir, baseName)
		targetPath = filepath.Join(filesDir, uniqueName)

		b, err := markdown.SafeCopyFile(cleanSrc, targetPath, v.Tracker)
		if err != nil {
			if errors.Is(err, os.ErrExist) {
				// Target appeared concurrently during streamed copy; retry with a new unique filename
				continue
			}
			return nil, fmt.Errorf("保存文件至 files/ 失败: %w", err)
		}
		baseline = b
		break
	}
	if baseline == nil {
		return nil, fmt.Errorf("保存文件至 files/ 失败: 无法生成唯一文件名")
	}

	relPath := "files/" + uniqueName
	res := markdown.FileResource{
		Path:    relPath,
		Name:    uniqueName,
		Ext:     filepath.Ext(uniqueName),
		Size:    fi.Size(),
		ModTime: baseline.ModTime,
	}

	v.Index.PutFile(res)
	s.dispatchEvent(EventVaultChanged, VaultChangeEvent{
		Op:       "create",
		Path:     targetPath,
		EntityID: relPath,
		Type:     string(markdown.EntityTypeFile),
	})

	return &res, nil
}

// ImportFileData saves base64-encoded binary data into the vault's files/ directory.
func (s *VaultService) ImportFileData(name string, base64Data string) (*markdown.FileResource, error) {
	s.mu.Lock()
	v := s.vault
	s.mu.Unlock()
	if v == nil {
		return nil, fmt.Errorf("尚未打开 Vault")
	}

	cleanName := filepath.Base(strings.TrimSpace(name))
	if cleanName == "" || cleanName == "." {
		cleanName = "attachment"
	}

	rawB64 := base64Data
	if commaIdx := strings.Index(rawB64, ","); commaIdx != -1 {
		rawB64 = rawB64[commaIdx+1:]
	}

	data, err := base64.StdEncoding.DecodeString(rawB64)
	if err != nil {
		return nil, fmt.Errorf("base64 解码失败: %w", err)
	}

	filesDir := filepath.Join(v.RootPath, "files")
	if err := os.MkdirAll(filesDir, 0755); err != nil {
		return nil, fmt.Errorf("创建 files 目录失败: %w", err)
	}

	var (
		uniqueName string
		targetPath string
		baseline   *markdown.FileBaseline
	)

	const maxRetries = 100
	for attempt := 0; attempt < maxRetries; attempt++ {
		uniqueName = generateUniqueFilename(filesDir, cleanName)
		targetPath = filepath.Join(filesDir, uniqueName)

		b, err := markdown.SafeWriteExclusive(targetPath, data, v.Tracker)
		if err != nil {
			if errors.Is(err, os.ErrExist) {
				// Target appeared concurrently during write; retry with a new unique filename
				continue
			}
			return nil, fmt.Errorf("写入文件失败: %w", err)
		}
		baseline = b
		break
	}
	if baseline == nil {
		return nil, fmt.Errorf("写入文件失败: 无法生成唯一文件名")
	}

	relPath := "files/" + uniqueName
	res := markdown.FileResource{
		Path:    relPath,
		Name:    uniqueName,
		Ext:     filepath.Ext(uniqueName),
		Size:    int64(len(data)),
		ModTime: baseline.ModTime,
	}

	v.Index.PutFile(res)
	s.dispatchEvent(EventVaultChanged, VaultChangeEvent{
		Op:       "create",
		Path:     targetPath,
		EntityID: relPath,
		Type:     string(markdown.EntityTypeFile),
	})

	return &res, nil
}

func (s *VaultService) resolveSafeFilePath(filePath string) (string, error) {
	s.mu.Lock()
	v := s.vault
	s.mu.Unlock()
	if v == nil {
		return "", fmt.Errorf("尚未打开 Vault")
	}

	absPath, _, err := markdown.SafeResolveVaultPath(v.RootPath, filePath)
	if err != nil {
		return "", fmt.Errorf("非法文件路径: %w", err)
	}

	if _, err := os.Stat(absPath); err != nil {
		return "", fmt.Errorf("文件不存在或已移动: %s", filePath)
	}

	return absPath, nil
}

func startAndReap(cmd *exec.Cmd) error {
	if err := cmd.Start(); err != nil {
		return err
	}
	go func() {
		_ = cmd.Wait()
	}()
	return nil
}

func (s *VaultService) runCommand(cmd *exec.Cmd) error {
	if s.launcher != nil {
		return s.launcher(cmd)
	}
	return startAndReap(cmd)
}

// PreviewFile invokes the macOS Quick Look preview or system preview for a file in the vault.
func (s *VaultService) PreviewFile(filePath string) error {
	absPath, err := s.resolveSafeFilePath(filePath)
	if err != nil {
		return err
	}

	if runtime.GOOS == "darwin" {
		cmd := exec.Command("qlmanage", "-p", absPath)
		if err := s.runCommand(cmd); err == nil {
			return nil
		}
	}

	return s.OpenFile(filePath)
}

// OpenFile opens a file in the vault with the system default application.
func (s *VaultService) OpenFile(filePath string) error {
	absPath, err := s.resolveSafeFilePath(filePath)
	if err != nil {
		return err
	}

	var cmd *exec.Cmd
	switch runtime.GOOS {
	case "darwin":
		cmd = exec.Command("open", absPath)
	case "windows":
		cmd = exec.Command("cmd", "/c", "start", "", absPath)
	default:
		cmd = exec.Command("xdg-open", absPath)
	}

	return s.runCommand(cmd)
}

// RevealInFinder reveals a file inside Finder (or Explorer on Windows).
func (s *VaultService) RevealInFinder(filePath string) error {
	absPath, err := s.resolveSafeFilePath(filePath)
	if err != nil {
		return err
	}

	var cmd *exec.Cmd
	switch runtime.GOOS {
	case "darwin":
		cmd = exec.Command("open", "-R", absPath)
	case "windows":
		cmd = exec.Command("explorer", "/select,", absPath)
	default:
		cmd = exec.Command("xdg-open", filepath.Dir(absPath))
	}

	return s.runCommand(cmd)
}

// OpenVaultInFinder opens the current vault root directory in Finder (or native file explorer).
func (s *VaultService) OpenVaultInFinder() error {
	s.mu.Lock()
	v := s.vault
	s.mu.Unlock()
	if v == nil {
		return fmt.Errorf("Vault 尚未打开")
	}
	path := v.RootPath
	if path == "" {
		return fmt.Errorf("Vault 路径为空")
	}
	fi, err := os.Stat(path)
	if err != nil || !fi.IsDir() {
		return fmt.Errorf("Vault 目录不存在或无法访问: %s", path)
	}

	var cmd *exec.Cmd
	switch runtime.GOOS {
	case "darwin":
		cmd = exec.Command("open", path)
	case "windows":
		cmd = exec.Command("explorer", path)
	default:
		cmd = exec.Command("xdg-open", path)
	}

	return s.runCommand(cmd)
}
