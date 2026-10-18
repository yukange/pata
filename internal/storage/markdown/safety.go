package markdown

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

var (
	// ErrConflict is returned when disk file has been modified externally since baseline,
	// or when creating a new file over an already existing different file.
	ErrConflict = errors.New("write conflict: disk file has changed since baseline")
)

// ConflictError provides detailed context about a concurrent edit collision.
type ConflictError struct {
	Path              string    `json:"path"`
	ExpectedHash      string    `json:"expected_hash"`
	ActualDiskHash    string    `json:"actual_disk_hash"`
	ExpectedModTime   time.Time `json:"expected_mod_time"`
	ActualDiskModTime time.Time `json:"actual_disk_mod_time"`
}

func (e *ConflictError) Error() string {
	return fmt.Sprintf("conflict at %s: disk hash %s != baseline %s (mod_time disk: %s, baseline: %s)",
		e.Path, e.ActualDiskHash, e.ExpectedHash, e.ActualDiskModTime.Format(time.RFC3339Nano), e.ExpectedModTime.Format(time.RFC3339Nano))
}

func (e *ConflictError) Is(target error) bool {
	return target == ErrConflict
}

// ComputeContentHash computes SHA-256 hex digest of data.
func ComputeContentHash(data []byte) string {
	h := sha256.Sum256(data)
	return hex.EncodeToString(h[:])
}

// WriteTracker tracks internal writes to suppress fsnotify self-feedback loops.
type WriteTracker struct {
	mu           sync.Mutex
	recentWrites map[string]writeRecord
	retention    time.Duration
}

type writeRecord struct {
	hash      string
	timestamp time.Time
}

// NewWriteTracker creates a new WriteTracker.
func NewWriteTracker(retention time.Duration) *WriteTracker {
	if retention <= 0 {
		retention = 2 * time.Second
	}
	return &WriteTracker{
		recentWrites: make(map[string]writeRecord),
		retention:    retention,
	}
}

// MarkInternalWrite records an internally initiated write for a file path.
func (wt *WriteTracker) MarkInternalWrite(absPath string, hash string) {
	if wt == nil {
		return
	}
	wt.mu.Lock()
	defer wt.mu.Unlock()
	wt.cleanupLocked()
	wt.recentWrites[absPath] = writeRecord{
		hash:      hash,
		timestamp: time.Now(),
	}
}

// IsInternalWrite checks if a path update was caused by internal write and consumes or verifies it.
func (wt *WriteTracker) IsInternalWrite(absPath string, hash string) bool {
	if wt == nil {
		return false
	}
	wt.mu.Lock()
	defer wt.mu.Unlock()
	wt.cleanupLocked()

	rec, ok := wt.recentWrites[absPath]
	if !ok {
		return false
	}

	// If hash is provided, match hash; otherwise if recent enough, match
	if hash != "" && rec.hash != "" {
		if rec.hash == hash {
			delete(wt.recentWrites, absPath)
			return true
		}
		return false
	}

	delete(wt.recentWrites, absPath)
	return true
}

func (wt *WriteTracker) cleanupLocked() {
	cutoff := time.Now().Add(-wt.retention)
	for p, rec := range wt.recentWrites {
		if rec.timestamp.Before(cutoff) {
			delete(wt.recentWrites, p)
		}
	}
}

// ReadBaseline reads the current state of path and generates a FileBaseline.
// If the file does not exist, it returns os.ErrNotExist.
func ReadBaseline(absPath string) (*FileBaseline, []byte, error) {
	data, err := os.ReadFile(absPath)
	if err != nil {
		return nil, nil, err
	}
	fi, err := os.Stat(absPath)
	if err != nil {
		return nil, nil, err
	}

	hash := ComputeContentHash(data)
	return &FileBaseline{
		Path:    absPath,
		Hash:    hash,
		ModTime: fi.ModTime(),
	}, data, nil
}

// SafeWrite writes data to targetPath safely:
// 1. Checks baseline against disk content. If disk modified and contents differ, returns ConflictError.
// 2. Writes to a temporary file in the same directory (filepath.Dir(targetPath)).
// 3. Flushes and syncs to disk (f.Sync()).
// 4. Atomically renames temporary file over targetPath.
// 5. fsyncs parent directory to ensure directory entry persistence.
// 6. Registers internal write in WriteTracker to prevent fsnotify self-feedback.
// 7. Cleans up temp file if any step fails.
func SafeWrite(targetPath string, data []byte, baseline *FileBaseline, tracker *WriteTracker) (*FileBaseline, error) {
	absPath, err := filepath.Abs(targetPath)
	if err != nil {
		return nil, fmt.Errorf("failed to resolve absolute path: %w", err)
	}

	dir := filepath.Dir(absPath)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return nil, fmt.Errorf("failed to create target directory %s: %w", dir, err)
	}

	newHash := ComputeContentHash(data)

	// Optimistic concurrency check if file exists or baseline provided
	existingData, readErr := os.ReadFile(absPath)
	if readErr == nil {
		existingInfo, _ := os.Stat(absPath)
		diskHash := ComputeContentHash(existingData)

		if baseline != nil {
			// Compare baseline with current disk
			if baseline.Hash != diskHash {
				// If disk changed, but new content is identical to current disk, no conflict needed
				if newHash != diskHash {
					var diskModTime time.Time
					if existingInfo != nil {
						diskModTime = existingInfo.ModTime()
					}
					return nil, &ConflictError{
						Path:              absPath,
						ExpectedHash:      baseline.Hash,
						ActualDiskHash:    diskHash,
						ExpectedModTime:   baseline.ModTime,
						ActualDiskModTime: diskModTime,
					}
				}
			}
		} else {
			// H1: baseline is nil (e.g. creating a new entity or unversioned save).
			// If file already exists on disk and content differs, reject overwrite to prevent silent data loss!
			if newHash != diskHash {
				var diskModTime time.Time
				if existingInfo != nil {
					diskModTime = existingInfo.ModTime()
				}
				return nil, &ConflictError{
					Path:              absPath,
					ExpectedHash:      "<new-file>",
					ActualDiskHash:    diskHash,
					ExpectedModTime:   time.Time{},
					ActualDiskModTime: diskModTime,
				}
			}
		}
	} else if !os.IsNotExist(readErr) {
		return nil, fmt.Errorf("failed to inspect existing file: %w", readErr)
	} else if baseline != nil {
		// File was deleted on disk while baseline expected it to exist!
		return nil, &ConflictError{
			Path:            absPath,
			ExpectedHash:    baseline.Hash,
			ActualDiskHash:  "<deleted>",
			ExpectedModTime: baseline.ModTime,
		}
	}

	// 2. Write to temp file in the SAME directory to ensure atomic rename on the same filesystem
	// Note (L3): os.CreateTemp creates files with 0600 mode. On overwriting existing 0644 files,
	// permissions may narrow and Finder xattrs (labels) are not preserved across inode replacement.
	// Acceptable for Spike stage; production can preserve file mode and xattrs.
	tmpFile, err := os.CreateTemp(dir, ".pata_tmp_*")
	if err != nil {
		return nil, fmt.Errorf("failed to create temporary file in %s: %w", dir, err)
	}
	tmpPath := tmpFile.Name()

	// Ensure cleanup on error
	success := false
	defer func() {
		if !success {
			_ = tmpFile.Close()
			_ = os.Remove(tmpPath)
		}
	}()

	// Write data
	if _, err := tmpFile.Write(data); err != nil {
		return nil, fmt.Errorf("failed to write data to temp file: %w", err)
	}

	// 3. Flush & sync to disk
	if err := tmpFile.Sync(); err != nil {
		return nil, fmt.Errorf("failed to sync temp file: %w", err)
	}

	if err := tmpFile.Close(); err != nil {
		return nil, fmt.Errorf("failed to close temp file: %w", err)
	}

	// Register internal write prior to atomic rename
	if tracker != nil {
		tracker.MarkInternalWrite(absPath, newHash)
	}

	// shortcut: TOCTOU window exists between reading/checking disk baseline and os.Rename.
	// This is acceptable for a single-user desktop app in the Spike stage.
	// Upgrade trigger: When long-running external agents (e.g. Pi agent) or concurrent background
	// workers perform continuous writes, upgrade to POSIX file locking (flock/fcntl) or a coordination server.

	// 4. Atomically replace target
	if err := os.Rename(tmpPath, absPath); err != nil {
		return nil, fmt.Errorf("failed to atomic replace %s with %s: %w", absPath, tmpPath, err)
	}

	// M4: fsync parent directory to ensure rename metadata is persisted on crash/power loss
	if dirFile, dirErr := os.Open(dir); dirErr == nil {
		_ = dirFile.Sync()
		_ = dirFile.Close()
	}

	success = true

	// Read updated modtime
	fi, err := os.Stat(absPath)
	var modTime time.Time
	if err == nil {
		modTime = fi.ModTime()
	} else {
		modTime = time.Now()
	}

	return &FileBaseline{
		Path:    absPath,
		Hash:    newHash,
		ModTime: modTime,
	}, nil
}

// writeStreamExclusive streams data from r to a temporary file in the target directory,
// fsyncs it, and links it atomically to targetPath (failing with os.ErrExist if targetPath already exists).
// If linking fails due to lack of hard link support, it stats and renames.
func writeStreamExclusive(targetPath string, r io.Reader, tracker *WriteTracker) (*FileBaseline, error) {
	absTarget, err := filepath.Abs(targetPath)
	if err != nil {
		return nil, fmt.Errorf("failed to resolve target path: %w", err)
	}
	if _, err := os.Stat(absTarget); err == nil {
		return nil, fmt.Errorf("target file %s already exists: %w", absTarget, os.ErrExist)
	}

	dir := filepath.Dir(absTarget)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return nil, fmt.Errorf("failed to create target directory %s: %w", dir, err)
	}

	tmpFile, err := os.CreateTemp(dir, ".pata_tmp_*")
	if err != nil {
		return nil, fmt.Errorf("failed to create temporary file in %s: %w", dir, err)
	}
	tmpPath := tmpFile.Name()

	success := false
	defer func() {
		if !success {
			_ = tmpFile.Close()
			_ = os.Remove(tmpPath)
		}
	}()

	hasher := sha256.New()
	mw := io.MultiWriter(tmpFile, hasher)
	if _, err := io.Copy(mw, r); err != nil {
		return nil, fmt.Errorf("failed to stream copy data: %w", err)
	}

	if err := tmpFile.Sync(); err != nil {
		return nil, fmt.Errorf("failed to sync temp file: %w", err)
	}
	if err := tmpFile.Close(); err != nil {
		return nil, fmt.Errorf("failed to close temp file: %w", err)
	}

	newHash := hex.EncodeToString(hasher.Sum(nil))

	// Atomically ensure destination does not exist by linking tmpPath to absTarget.
	// On POSIX (including macOS), link() fails with EEXIST if absTarget already exists,
	// preventing concurrent imports from silently replacing each other.
	if err := os.Link(tmpPath, absTarget); err != nil {
		if os.IsExist(err) {
			return nil, fmt.Errorf("target file %s already exists: %w", absTarget, os.ErrExist)
		}
		// If filesystem does not support hard links (e.g. FAT/exFAT/SMB), exclusively reserve destination atomically
		destFile, exclErr := os.OpenFile(absTarget, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0644)
		if exclErr != nil {
			if os.IsExist(exclErr) {
				return nil, fmt.Errorf("target file %s already exists: %w", absTarget, os.ErrExist)
			}
			return nil, fmt.Errorf("failed to exclusively reserve destination %s: %w", absTarget, exclErr)
		}
		_ = destFile.Close()
		if err := os.Rename(tmpPath, absTarget); err != nil {
			_ = os.Remove(absTarget)
			return nil, fmt.Errorf("failed to rename %s to %s: %w", tmpPath, absTarget, err)
		}
	} else {
		_ = os.Remove(tmpPath)
	}

	if tracker != nil {
		tracker.MarkInternalWrite(absTarget, newHash)
	}

	parentDir, err := os.Open(dir)
	if err == nil {
		_ = parentDir.Sync()
		_ = parentDir.Close()
	}

	success = true
	fi, err := os.Stat(absTarget)
	var modTime time.Time
	if err == nil {
		modTime = fi.ModTime()
	} else {
		modTime = time.Now()
	}

	return &FileBaseline{
		Path:    absTarget,
		Hash:    newHash,
		ModTime: modTime,
	}, nil
}

// SafeCopyFile copies a file from srcPath to targetPath using a streamed copy into a temporary file
// and atomic link/rename, failing with os.ErrExist if targetPath already exists.
// It hashes the data while streaming to construct the FileBaseline without buffering the entire file in memory.
func SafeCopyFile(srcPath string, targetPath string, tracker *WriteTracker) (*FileBaseline, error) {
	absSrc, err := filepath.Abs(srcPath)
	if err != nil {
		return nil, fmt.Errorf("failed to resolve source path: %w", err)
	}
	srcFile, err := os.Open(absSrc)
	if err != nil {
		return nil, fmt.Errorf("failed to open source file: %w", err)
	}
	defer srcFile.Close()

	return writeStreamExclusive(targetPath, srcFile, tracker)
}

// SafeWriteExclusive writes byte data to targetPath exclusively, failing with os.ErrExist if targetPath
// already exists on disk. It guarantees no concurrent overwriting via atomic link/rename.
func SafeWriteExclusive(targetPath string, data []byte, tracker *WriteTracker) (*FileBaseline, error) {
	return writeStreamExclusive(targetPath, bytes.NewReader(data), tracker)
}

// SafeResolveVaultPath resolves a relative or absolute targetPath against vaultRoot.
// It verifies that the resulting path is strictly located within vaultRoot and does not
// escape via ".." or symlinks. Returns the absolute path and slash-separated vault-relative path.
func SafeResolveVaultPath(vaultRoot, targetPath string) (absPath string, relPath string, err error) {
	if strings.TrimSpace(vaultRoot) == "" {
		return "", "", fmt.Errorf("vault root cannot be empty")
	}
	cleanTarget := strings.TrimSpace(targetPath)
	if cleanTarget == "" {
		return "", "", fmt.Errorf("target path cannot be empty")
	}

	absRoot, err := filepath.Abs(vaultRoot)
	if err != nil {
		return "", "", fmt.Errorf("invalid vault root: %w", err)
	}

	var candidate string
	if filepath.IsAbs(cleanTarget) {
		candidate = filepath.Clean(cleanTarget)
	} else {
		candidate = filepath.Clean(filepath.Join(absRoot, filepath.FromSlash(cleanTarget)))
	}

	rel, err := filepath.Rel(absRoot, candidate)
	if err != nil || strings.HasPrefix(rel, "..") || filepath.IsAbs(rel) {
		return "", "", fmt.Errorf("path escapes vault: %s", targetPath)
	}

	realRoot, err := filepath.EvalSymlinks(absRoot)
	if err != nil {
		realRoot = absRoot
	}

	// Verify symlinks to prevent symlink escape (both terminal and ancestor directories)
	if _, err := os.Stat(candidate); err == nil {
		evalTarget, err := filepath.EvalSymlinks(candidate)
		if err != nil {
			return "", "", fmt.Errorf("failed to evaluate symlink: %w", err)
		}
		evalRel, err := filepath.Rel(realRoot, evalTarget)
		if err != nil || strings.HasPrefix(evalRel, "..") || filepath.IsAbs(evalRel) {
			return "", "", fmt.Errorf("path escapes vault via symlink: %s", targetPath)
		}
	} else if fi, err := os.Lstat(candidate); err == nil && fi.Mode()&os.ModeSymlink != 0 {
		// Terminal broken symlink
		evalTarget, err := filepath.EvalSymlinks(candidate)
		if err != nil {
			return "", "", fmt.Errorf("failed to evaluate broken symlink: %w", err)
		}
		evalRel, err := filepath.Rel(realRoot, evalTarget)
		if err != nil || strings.HasPrefix(evalRel, "..") || filepath.IsAbs(evalRel) {
			return "", "", fmt.Errorf("symlink target escapes vault: %s", targetPath)
		}
	} else {
		// Target does not exist yet; check nearest existing ancestor directory
		checkDir := filepath.Dir(candidate)
		for {
			if _, err := os.Stat(checkDir); err == nil {
				evalDir, err := filepath.EvalSymlinks(checkDir)
				if err == nil {
					evalRel, err := filepath.Rel(realRoot, evalDir)
					if err != nil || strings.HasPrefix(evalRel, "..") || filepath.IsAbs(evalRel) {
						return "", "", fmt.Errorf("path escapes vault via ancestor symlink: %s", targetPath)
					}
				}
				break
			}
			parent := filepath.Dir(checkDir)
			if parent == checkDir {
				break
			}
			checkDir = parent
		}
	}

	return candidate, filepath.ToSlash(rel), nil
}

