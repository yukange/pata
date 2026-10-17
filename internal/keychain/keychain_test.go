package keychain

import (
	"errors"
	"testing"
)

func TestMemoryStore(t *testing.T) {
	s := NewMemoryStore()
	svc := "pata.test"
	acct := "key"

	// 1. Non-existent key
	_, err := s.Get(svc, acct)
	if !errors.Is(err, ErrNotFound) {
		t.Fatalf("expected ErrNotFound, got %v", err)
	}

	// 2. Empty secret rejection
	if err := s.Set(svc, acct, "   "); !errors.Is(err, ErrEmptySecret) {
		t.Fatalf("expected ErrEmptySecret for whitespace, got %v", err)
	}

	// 3. Set secret
	secretVal := "sk-test-secret-123"
	if err := s.Set(svc, acct, secretVal); err != nil {
		t.Fatalf("Set failed: %v", err)
	}

	// 4. Get secret
	val, err := s.Get(svc, acct)
	if err != nil {
		t.Fatalf("Get failed: %v", err)
	}
	if val != secretVal {
		t.Fatalf("got %q, want %q", val, secretVal)
	}

	// 5. Overwrite secret
	newSecret := "sk-new-secret-456"
	if err := s.Set(svc, acct, newSecret); err != nil {
		t.Fatalf("Set failed: %v", err)
	}
	val, err = s.Get(svc, acct)
	if err != nil {
		t.Fatalf("Get failed: %v", err)
	}
	if val != newSecret {
		t.Fatalf("got %q, want %q", val, newSecret)
	}

	// 6. Delete secret
	if err := s.Delete(svc, acct); err != nil {
		t.Fatalf("Delete failed: %v", err)
	}
	_, err = s.Get(svc, acct)
	if !errors.Is(err, ErrNotFound) {
		t.Fatalf("expected ErrNotFound after deletion, got %v", err)
	}
}
