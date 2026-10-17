package keychain

import (
	"errors"
	"strings"
	"sync"
)

var (
	// ErrNotFound indicates the requested secret does not exist in the keychain.
	ErrNotFound = errors.New("item not found in keychain")

	// ErrEmptySecret indicates a secret cannot be empty or purely whitespace.
	ErrEmptySecret = errors.New("secret cannot be empty")
)

// Store defines operations for storing and retrieving credentials securely.
type Store interface {
	Get(service, account string) (string, error)
	Set(service, account, secret string) error
	Delete(service, account string) error
}

// MemoryStore provides an in-memory credential store for testing or unsupported platforms.
type MemoryStore struct {
	mu    sync.RWMutex
	items map[string]string
}

// NewMemoryStore creates a new in-memory store.
func NewMemoryStore() *MemoryStore {
	return &MemoryStore{
		items: make(map[string]string),
	}
}

func key(service, account string) string {
	return service + ":" + account
}

func (m *MemoryStore) Get(service, account string) (string, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	val, ok := m.items[key(service, account)]
	if !ok {
		return "", ErrNotFound
	}
	return val, nil
}

func (m *MemoryStore) Set(service, account, secret string) error {
	if strings.TrimSpace(secret) == "" {
		return ErrEmptySecret
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	m.items[key(service, account)] = strings.TrimSpace(secret)
	return nil
}

func (m *MemoryStore) Delete(service, account string) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	delete(m.items, key(service, account))
	return nil
}
