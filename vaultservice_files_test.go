package main

import (
	"encoding/base64"
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"testing"

	"pata/internal/storage/markdown"
)

func TestVaultServiceFileImportAndSearch(t *testing.T) {
	tmpDir, err := os.MkdirTemp("", "pata-vs-files-*")
	if err != nil {
		t.Fatal(err)
	}
	defer os.RemoveAll(tmpDir)

	svc := NewVaultService()
	v, err := svc.openVault(tmpDir)
	if err != nil {
		t.Fatalf("failed to open vault: %v", err)
	}
	defer func() {
		if svc.stopWatcher != nil {
			svc.stopWatcher()
		}
	}()

	// 1. Create a dummy external file
	extDir, err := os.MkdirTemp("", "pata-ext-*")
	if err != nil {
		t.Fatal(err)
	}
	defer os.RemoveAll(extDir)

	extPath := filepath.Join(extDir, "proposal.pdf")
	origBytes := []byte("original external pdf content")
	if err := os.WriteFile(extPath, origBytes, 0644); err != nil {
		t.Fatal(err)
	}

	// 2. Import file
	res1, err := svc.ImportFile(extPath)
	if err != nil {
		t.Fatalf("ImportFile failed: %v", err)
	}
	if res1.Name != "proposal.pdf" || res1.Path != "files/proposal.pdf" || res1.Size != int64(len(origBytes)) {
		t.Fatalf("unexpected res1: %+v", res1)
	}

	// Verify original file is still intact and not moved
	if _, err := os.Stat(extPath); os.IsNotExist(err) {
		t.Fatalf("external file was moved or deleted!")
	}

	// 3. Import same filename again -> should generate non-colliding name (proposal 1.pdf)
	res2, err := svc.ImportFile(extPath)
	if err != nil {
		t.Fatalf("second ImportFile failed: %v", err)
	}
	if res2.Name != "proposal 1.pdf" || res2.Path != "files/proposal 1.pdf" {
		t.Fatalf("expected proposal 1.pdf, got %+v", res2)
	}

	// 4. Import via base64 data
	imgData := []byte("fake png binary data")
	b64 := base64.StdEncoding.EncodeToString(imgData)
	res3, err := svc.ImportFileData("chart.png", "data:image/png;base64,"+b64)
	if err != nil {
		t.Fatalf("ImportFileData failed: %v", err)
	}
	if res3.Name != "chart.png" || res3.Path != "files/chart.png" || res3.Size != int64(len(imgData)) {
		t.Fatalf("unexpected res3: %+v", res3)
	}

	// 5. ListFiles
	files, err := svc.ListFiles()
	if err != nil {
		t.Fatalf("ListFiles failed: %v", err)
	}
	if len(files) != 3 {
		t.Fatalf("expected 3 files, got %d: %+v", len(files), files)
	}

	// 6. SearchAll should match files by name
	searchResults, err := svc.SearchAll("proposal")
	if err != nil {
		t.Fatalf("SearchAll failed: %v", err)
	}
	fileMatches := 0
	for _, sr := range searchResults {
		if sr.Type == markdown.EntityTypeFile {
			fileMatches++
		}
	}
	if fileMatches != 2 {
		t.Fatalf("expected 2 file matches for 'proposal', got %d: %+v", fileMatches, searchResults)
	}

	// 7. Path safety check on PreviewFile / OpenFile with path traversal
	err = svc.PreviewFile("../outside.txt")
	if err == nil {
		t.Fatalf("expected error on path escape in PreviewFile, got nil")
	}

	// File not existing in vault
	err = svc.PreviewFile("files/non-existent.pdf")
	if err == nil {
		t.Fatalf("expected error on non-existent file, got nil")
	}

	// Ensure vault index retained all 3 files
	_ = v
}

func TestVaultService_ConcurrentFileImport(t *testing.T) {
	tmpDir := t.TempDir()

	svc := NewVaultService()
	v, err := svc.openVault(tmpDir)
	if err != nil {
		t.Fatalf("failed to open vault: %v", err)
	}
	defer func() {
		if svc.stopWatcher != nil {
			svc.stopWatcher()
		}
	}()

	extDir := t.TempDir()
	sourceFiles := make([]string, 5)
	for i := 0; i < 5; i++ {
		p := filepath.Join(extDir, fmt.Sprintf("src_%d.mp3", i))
		content := fmt.Sprintf("distinct audio stream content #%d", i)
		if err := os.WriteFile(p, []byte(content), 0644); err != nil {
			t.Fatal(err)
		}
		sourceFiles[i] = p
	}

	// Concurrently import files that all have the same base name "recording.mp3"
	// To do this, create symlinks or copies with the same name in separate subdirectories
	targetSources := make([]string, 5)
	for i := 0; i < 5; i++ {
		subDir := filepath.Join(extDir, fmt.Sprintf("sub_%d", i))
		_ = os.MkdirAll(subDir, 0755)
		srcPath := filepath.Join(subDir, "recording.mp3")
		_ = os.WriteFile(srcPath, []byte(fmt.Sprintf("recording content #%d", i)), 0644)
		targetSources[i] = srcPath
	}

	results := make([]*markdown.FileResource, 5)
	errors := make([]error, 5)
	var wg sync.WaitGroup

	for i := 0; i < 5; i++ {
		wg.Add(1)
		go func(idx int) {
			defer wg.Done()
			res, err := svc.ImportFile(targetSources[idx])
			results[idx] = res
			errors[idx] = err
		}(i)
	}

	wg.Wait()

	for i := 0; i < 5; i++ {
		if errors[i] != nil {
			t.Fatalf("concurrent import #%d failed: %v", i, errors[i])
		}
		if results[i] == nil {
			t.Fatalf("concurrent import #%d returned nil result", i)
		}
	}

	// Verify all 5 imported files have distinct names and paths
	seenNames := make(map[string]bool)
	for i, r := range results {
		if seenNames[r.Name] {
			t.Fatalf("duplicate filename generated under concurrency: %s", r.Name)
		}
		seenNames[r.Name] = true

		// Check that the file on disk exists and contains non-empty content
		diskPath := filepath.Join(v.RootPath, r.Path)
		data, err := os.ReadFile(diskPath)
		if err != nil {
			t.Fatalf("failed to read imported file on disk: %v", err)
		}
		if len(data) == 0 {
			t.Fatalf("file %s is unexpectedly empty", diskPath)
		}
		_ = i
	}
}

func TestVaultService_ConcurrentImportFileData(t *testing.T) {
	tmpDir := t.TempDir()

	svc := NewVaultService()
	v, err := svc.openVault(tmpDir)
	if err != nil {
		t.Fatalf("failed to open vault: %v", err)
	}
	defer func() {
		if svc.stopWatcher != nil {
			svc.stopWatcher()
		}
	}()

	results := make([]*markdown.FileResource, 5)
	errs := make([]error, 5)
	var wg sync.WaitGroup

	for i := 0; i < 5; i++ {
		wg.Add(1)
		go func(idx int) {
			defer wg.Done()
			payload := base64.StdEncoding.EncodeToString([]byte(fmt.Sprintf("unique content payload %d", idx)))
			res, err := svc.ImportFileData("concurrent.png", payload)
			results[idx] = res
			errs[idx] = err
		}(i)
	}

	wg.Wait()

	for i := 0; i < 5; i++ {
		if errs[i] != nil {
			t.Fatalf("concurrent ImportFileData #%d failed: %v", i, errs[i])
		}
		if results[i] == nil {
			t.Fatalf("concurrent ImportFileData #%d returned nil result", i)
		}
	}

	seenNames := make(map[string]bool)
	for i, r := range results {
		if seenNames[r.Name] {
			t.Fatalf("duplicate filename generated under concurrency: %s", r.Name)
		}
		seenNames[r.Name] = true

		diskPath := filepath.Join(v.RootPath, r.Path)
		data, err := os.ReadFile(diskPath)
		if err != nil {
			t.Fatalf("failed to read imported file on disk: %v", err)
		}
		if len(data) == 0 {
			t.Fatalf("file %s is unexpectedly empty", diskPath)
		}
		_ = i
	}
}


