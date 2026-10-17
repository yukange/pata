//go:build darwin

package keychain

// NewDefaultStore returns the platform-appropriate keychain store.
func NewDefaultStore() Store {
	return NewDarwinStore()
}
