//go:build darwin

package keychain

import (
	"errors"
	"os"
	"runtime"
	"testing"
)

func TestDarwinStoreLive(t *testing.T) {
	if runtime.GOOS != "darwin" {
		t.Skip("skipping darwin test on non-darwin OS")
	}
	if os.Getenv("PATA_LIVE_MACOS_TEST") != "1" {
		t.Skip("skipping live macOS keychain test; set PATA_LIVE_MACOS_TEST=1 on macOS to run")
	}

	s := NewDarwinStore()
	svc := "pata.test.darwin.unit"
	acct := "unit_key"

	// Cleanup first
	_ = s.Delete(svc, acct)

	// 1. Initial get should return ErrNotFound
	_, err := s.Get(svc, acct)
	if !errors.Is(err, ErrNotFound) {
		t.Fatalf("expected ErrNotFound, got %v", err)
	}

	// 2. Empty key rejection
	if err := s.Set(svc, acct, "   "); !errors.Is(err, ErrEmptySecret) {
		t.Fatalf("expected ErrEmptySecret, got %v", err)
	}

	// 3. Set and retrieve key
	secretVal := "sk-darwin-unit-test-key-789"
	if err := s.Set(svc, acct, secretVal); err != nil {
		t.Fatalf("Set failed: %v", err)
	}
	defer func() {
		_ = s.Delete(svc, acct)
	}()

	got, err := s.Get(svc, acct)
	if err != nil {
		t.Fatalf("Get failed: %v", err)
	}
	if got != secretVal {
		t.Fatalf("got %q, want %q", got, secretVal)
	}

	// 4. Overwrite
	newSecret := "sk-darwin-unit-test-key-replaced"
	if err := s.Set(svc, acct, newSecret); err != nil {
		t.Fatalf("Overwrite failed: %v", err)
	}
	got, err = s.Get(svc, acct)
	if err != nil {
		t.Fatalf("Get after overwrite failed: %v", err)
	}
	if got != newSecret {
		t.Fatalf("got %q, want %q", got, newSecret)
	}

	// 5. Delete
	if err := s.Delete(svc, acct); err != nil {
		t.Fatalf("Delete failed: %v", err)
	}
	_, err = s.Get(svc, acct)
	if !errors.Is(err, ErrNotFound) {
		t.Fatalf("expected ErrNotFound after delete, got %v", err)
	}
}
