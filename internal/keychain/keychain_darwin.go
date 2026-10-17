package keychain

import (
	"bytes"
	"errors"
	"fmt"
	"os/exec"
	"strings"
)

// DarwinStore uses macOS `/usr/bin/security` to store secrets in login keychain.
type DarwinStore struct {
	binaryPath string
}

// NewDarwinStore creates a new DarwinStore instance.
func NewDarwinStore() *DarwinStore {
	return &DarwinStore{
		binaryPath: "/usr/bin/security",
	}
}

// Get retrieves a generic password item from macOS Keychain.
func (d *DarwinStore) Get(service, account string) (string, error) {
	cmd := exec.Command(d.binaryPath, "find-generic-password", "-s", service, "-a", account, "-w")
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	err := cmd.Run()
	if err != nil {
		var exitErr *exec.ExitError
		if errors.As(err, &exitErr) && exitErr.ExitCode() == 44 {
			return "", ErrNotFound
		}
		errMsg := strings.TrimSpace(stderr.String())
		if errMsg == "" {
			errMsg = err.Error()
		}
		return "", fmt.Errorf("Keychain 读取失败: %s", errMsg)
	}

	secret := strings.TrimRight(stdout.String(), "\r\n")
	return secret, nil
}

// Set adds or updates a generic password item in macOS Keychain.
func (d *DarwinStore) Set(service, account, secret string) error {
	trimmed := strings.TrimSpace(secret)
	if trimmed == "" {
		return ErrEmptySecret
	}

	cmd := exec.Command(d.binaryPath, "add-generic-password", "-U", "-s", service, "-a", account, "-w", trimmed)
	var stderr bytes.Buffer
	cmd.Stderr = &stderr

	err := cmd.Run()
	if err != nil {
		errMsg := strings.TrimSpace(stderr.String())
		if errMsg == "" {
			errMsg = err.Error()
		}
		// Ensure any potential reflection of secret in stderr is stripped
		errMsg = strings.ReplaceAll(errMsg, trimmed, "[REDACTED]")
		return fmt.Errorf("Keychain 写入失败: %s", errMsg)
	}

	return nil
}

// Delete removes a generic password item from macOS Keychain.
func (d *DarwinStore) Delete(service, account string) error {
	cmd := exec.Command(d.binaryPath, "delete-generic-password", "-s", service, "-a", account)
	var stderr bytes.Buffer
	cmd.Stderr = &stderr

	err := cmd.Run()
	if err != nil {
		var exitErr *exec.ExitError
		if errors.As(err, &exitErr) && exitErr.ExitCode() == 44 {
			return nil // item already gone
		}
		errMsg := strings.TrimSpace(stderr.String())
		if errMsg == "" {
			errMsg = err.Error()
		}
		return fmt.Errorf("Keychain 删除失败: %s", errMsg)
	}

	return nil
}
