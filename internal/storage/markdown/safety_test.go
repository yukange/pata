package markdown

import (
	"errors"
	"os"
	"path/filepath"
	"testing"
)

func TestSafeWriteBasic(t *testing.T) {
	tmpDir := t.TempDir()
	target := filepath.Join(tmpDir, "test.md")

	content1 := []byte("Initial content")
	baseline1, err := SafeWrite(target, content1, nil, nil)
	if err != nil {
		t.Fatalf("SafeWrite failed: %v", err)
	}

	readBack, err := os.ReadFile(target)
	if err != nil {
		t.Fatalf("failed to read back file: %v", err)
	}
	if string(readBack) != string(content1) {
		t.Fatalf("content mismatch: got %q, want %q", readBack, content1)
	}

	// Update with correct baseline
	content2 := []byte("Second content")
	baseline2, err := SafeWrite(target, content2, baseline1, nil)
	if err != nil {
		t.Fatalf("SafeWrite with valid baseline failed: %v", err)
	}
	if baseline2.Hash == baseline1.Hash {
		t.Fatalf("expected new hash, got same hash %s", baseline2.Hash)
	}
}

func TestSafeWriteConflictDetection(t *testing.T) {
	tmpDir := t.TempDir()
	target := filepath.Join(tmpDir, "conflict.md")

	initial := []byte("Version 0")
	baseline, err := SafeWrite(target, initial, nil, nil)
	if err != nil {
		t.Fatalf("initial write failed: %v", err)
	}

	// External editor modifies the file behind our back
	externalEdit := []byte("Version 1 (External edit by Pi agent)")
	if err := os.WriteFile(target, externalEdit, 0644); err != nil {
		t.Fatalf("simulating external write failed: %v", err)
	}

	// Try to write our un-merged edit based on old baseline
	myEdit := []byte("Version 1 (User local changes)")
	_, err = SafeWrite(target, myEdit, baseline, nil)
	if err == nil {
		t.Fatalf("expected ConflictError, got nil")
	}

	if !errors.Is(err, ErrConflict) {
		t.Fatalf("expected ErrConflict, got: %v", err)
	}

	// Disk file MUST NOT be overwritten
	diskContent, _ := os.ReadFile(target)
	if string(diskContent) != string(externalEdit) {
		t.Fatalf("file was overwritten despite conflict! got %q", diskContent)
	}
}

func TestWriteTrackerSuppression(t *testing.T) {
	tracker := NewWriteTracker(0)
	target := "/test/path/note.md"
	hash := ComputeContentHash([]byte("hello"))

	if tracker.IsInternalWrite(target, hash) {
		t.Fatalf("should not be internal before marking")
	}

	tracker.MarkInternalWrite(target, hash)

	if !tracker.IsInternalWrite(target, hash) {
		t.Fatalf("should be internal right after marking")
	}

	// Second check should be consumed
	if tracker.IsInternalWrite(target, hash) {
		t.Fatalf("internal write should have been consumed")
	}
}

func TestSafeCopyFile_NoOverwrite(t *testing.T) {
	tmpDir := t.TempDir()
	srcPath := filepath.Join(tmpDir, "src.bin")
	targetPath := filepath.Join(tmpDir, "target.bin")

	_ = os.WriteFile(srcPath, []byte("new source content"), 0644)
	_ = os.WriteFile(targetPath, []byte("existing target content"), 0644)

	// Attempting to SafeCopyFile to an existing target MUST fail and preserve target
	_, err := SafeCopyFile(srcPath, targetPath, nil)
	if err == nil {
		t.Fatalf("expected error when target file already exists, got nil")
	}
	if !errors.Is(err, os.ErrExist) {
		t.Fatalf("expected os.ErrExist, got %v", err)
	}

	content, _ := os.ReadFile(targetPath)
	if string(content) != "existing target content" {
		t.Fatalf("existing target was overwritten despite error! got %q", string(content))
	}

	// Copying to non-existent target succeeds
	newTarget := filepath.Join(tmpDir, "new_target.bin")
	b, err := SafeCopyFile(srcPath, newTarget, nil)
	if err != nil {
		t.Fatalf("SafeCopyFile to new target failed: %v", err)
	}
	if b == nil || b.Hash == "" {
		t.Fatalf("expected valid baseline, got %+v", b)
	}
	newContent, _ := os.ReadFile(newTarget)
	if string(newContent) != "new source content" {
		t.Fatalf("new target content mismatch, got %q", string(newContent))
	}
}

func TestSafeWriteExclusive_NoOverwrite(t *testing.T) {
	tmpDir := t.TempDir()
	targetPath := filepath.Join(tmpDir, "exclusive.bin")

	_ = os.WriteFile(targetPath, []byte("existing content"), 0644)

	// Writing to existing file MUST fail with os.ErrExist and keep content intact
	_, err := SafeWriteExclusive(targetPath, []byte("new content"), nil)
	if err == nil {
		t.Fatalf("expected error when target already exists, got nil")
	}
	if !errors.Is(err, os.ErrExist) {
		t.Fatalf("expected os.ErrExist, got %v", err)
	}

	content, _ := os.ReadFile(targetPath)
	if string(content) != "existing content" {
		t.Fatalf("existing file was overwritten! got %q", string(content))
	}

	// Writing to non-existent target succeeds
	newTarget := filepath.Join(tmpDir, "new_exclusive.bin")
	b, err := SafeWriteExclusive(newTarget, []byte("new content"), nil)
	if err != nil {
		t.Fatalf("SafeWriteExclusive failed: %v", err)
	}
	if b == nil || b.Hash == "" {
		t.Fatalf("expected valid baseline, got %+v", b)
	}
	readBack, _ := os.ReadFile(newTarget)
	if string(readBack) != "new content" {
		t.Fatalf("read back content mismatch: got %q, want %q", readBack, "new content")
	}
}


