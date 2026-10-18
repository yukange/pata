package main

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"pata/internal/asr"
	"pata/internal/keychain"
)

// setupMockDashScopeServer sets up a fake DashScope Beijing ASR server for testing.
func setupMockDashScopeServer(t *testing.T, sentences []asr.Sentence) *httptest.Server {
	var mu sync.Mutex
	tasks := make(map[string]string)

	handler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		mu.Lock()
		defer mu.Unlock()

		// 1. Upload policy
		if r.Method == http.MethodGet && strings.Contains(r.URL.Path, "/uploads") {
			w.Header().Set("Content-Type", "application/json")
			_ = json.NewEncoder(w).Encode(map[string]interface{}{
				"data": map[string]interface{}{
					"upload_host": "http://" + r.Host + "/oss-mock",
					"upload_dir":  "tmp-dir",
					"oss_access_key_id": "test-key-id",
					"policy":      "test-policy",
					"signature":   "test-sig",
				},
			})
			return
		}

		// 2. OSS mock upload
		if r.Method == http.MethodPost && strings.Contains(r.URL.Path, "/oss-mock") {
			w.WriteHeader(http.StatusNoContent)
			return
		}

		// 3. Submit task
		if r.Method == http.MethodPost && strings.Contains(r.URL.Path, "/services/audio/asr/transcription") {
			// Verify header
			if r.Header.Get("X-DashScope-OssResourceResolve") != "enable" {
				http.Error(w, "missing X-DashScope-OssResourceResolve", http.StatusBadRequest)
				return
			}
			taskID := fmt.Sprintf("task-%d", time.Now().UnixNano())
			tasks[taskID] = "SUCCEEDED"
			w.Header().Set("Content-Type", "application/json")
			_ = json.NewEncoder(w).Encode(map[string]interface{}{
				"output": map[string]interface{}{
					"task_id":     taskID,
					"task_status": "PENDING",
				},
			})
			return
		}

		// 4. Poll task
		if r.Method == http.MethodGet && strings.Contains(r.URL.Path, "/tasks/") {
			parts := strings.Split(r.URL.Path, "/")
			taskID := parts[len(parts)-1]
			w.Header().Set("Content-Type", "application/json")
			_ = json.NewEncoder(w).Encode(map[string]interface{}{
				"output": map[string]interface{}{
					"task_id":          taskID,
					"task_status":      "SUCCEEDED",
					"transcription_url": "http://" + r.Host + "/results/" + taskID,
					"results": []map[string]interface{}{
						{
							"subtask_status":    "SUCCEEDED",
							"transcription_url": "http://" + r.Host + "/results/" + taskID,
						},
					},
				},
			})
			return
		}

		// 5. Download transcription result
		if r.Method == http.MethodGet && strings.Contains(r.URL.Path, "/results/") {
			w.Header().Set("Content-Type", "application/json")
			_ = json.NewEncoder(w).Encode(map[string]interface{}{
				"transcripts": []map[string]interface{}{
					{
						"sentences": sentences,
					},
				},
			})
			return
		}

		http.NotFound(w, r)
	})

	server := httptest.NewServer(handler)
	return server
}

// createTestMP3 creates a minimal synthetic MP3 file (MPEG-1 Layer 3, mono or stereo).
func createTestMP3(t *testing.T, path string, mono bool) {
	modeBits := byte(0x00) // 00 = stereo
	if mono {
		modeBits = 0xC0 // 11 = single channel (mono)
	}
	// Frame header: 0xFF, 0xFB (MPEG 1 Layer 3, 128kbps, 44100Hz), Byte 2: 0x90, Byte 3: modeBits
	header := []byte{0xFF, 0xFB, 0x90, modeBits}
	content := append(header, make([]byte, 417-4)...) // 417 bytes frame
	if err := os.WriteFile(path, content, 0644); err != nil {
		t.Fatalf("failed to create test MP3: %v", err)
	}
}

func TestStage11_AudioTranscriptionAcceptance(t *testing.T) {
	tmpDir, err := os.MkdirTemp("", "pata-stage11-*")
	if err != nil {
		t.Fatal(err)
	}
	defer os.RemoveAll(tmpDir)

	configPath := filepath.Join(tmpDir, "config", "vault.json")
	vaultDir := filepath.Join(tmpDir, "vault")
	_ = os.MkdirAll(vaultDir, 0755)

	memKeychain := keychain.NewMemoryStore()

	svc := &VaultService{
		configPath: configPath,
		keychain:   memKeychain,
	}

	if _, err := svc.openVault(vaultDir); err != nil {
		t.Fatalf("openVault failed: %v", err)
	}

	// 1. Missing Key Scenario
	cfgStatus, err := svc.GetASRConfigStatus()
	if err != nil {
		t.Fatalf("GetASRConfigStatus failed: %v", err)
	}
	if cfgStatus.Configured {
		t.Fatalf("expected unconfigured ASR initially")
	}

	// Create a test MP3 outside vault
	sourceMP3 := filepath.Join(tmpDir, "meeting-standup.mp3")
	createTestMP3(t, sourceMP3, true)

	// Attempting to create an audio note without key should still create Note and MP3 in files/,
	// but background ASR should fail with clear explanation.
	audioNote, err := svc.CreateAudioNote(sourceMP3)
	if err != nil {
		t.Fatalf("CreateAudioNote failed: %v", err)
	}
	if audioNote == nil {
		t.Fatalf("expected audioNote to be created immediately")
	}
	if audioNote.Title != "meeting-standup" {
		t.Errorf("expected default title 'meeting-standup', got %q", audioNote.Title)
	}
	if !audioNote.AudioTranscript {
		t.Errorf("expected AudioTranscript == true")
	}
	if !strings.HasPrefix(audioNote.AudioFile, "files/meeting-standup") {
		t.Errorf("expected AudioFile in files/, got %q", audioNote.AudioFile)
	}

	// Check that source MP3 was NOT modified or deleted
	if _, err := os.Stat(sourceMP3); err != nil {
		t.Fatalf("source MP3 must remain intact: %v", err)
	}

	// Check that copied MP3 exists in files/
	copiedPath := filepath.Join(vaultDir, audioNote.AudioFile)
	if _, err := os.Stat(copiedPath); err != nil {
		t.Fatalf("copied MP3 does not exist in vault: %v", err)
	}

	// Wait briefly for initial task without key to register failure
	time.Sleep(100 * time.Millisecond)
	taskStatus, err := svc.GetASRTaskStatus(audioNote.ID)
	if err != nil {
		t.Fatalf("GetASRTaskStatus failed: %v", err)
	}
	if taskStatus.State != asr.StateFailed {
		t.Errorf("expected task to fail due to missing key, got %v", taskStatus.State)
	}
	if !strings.Contains(taskStatus.Error, "设置 - 语音转写") {
		t.Errorf("expected missing key error message, got %q", taskStatus.Error)
	}

	// Note and MP3 must still be preserved on failure
	savedNote, err := svc.GetNote(audioNote.ID)
	if err != nil || savedNote == nil {
		t.Fatalf("Note must be preserved after ASR failure: %v", err)
	}
	if savedNote.AudioFile != audioNote.AudioFile {
		t.Errorf("expected audio_file preserved, got %q", savedNote.AudioFile)
	}

	// 2. Duplicate file naming: importing another file with same name generates unique filename
	anotherSource := filepath.Join(tmpDir, "another", "meeting-standup.mp3")
	_ = os.MkdirAll(filepath.Dir(anotherSource), 0755)
	createTestMP3(t, anotherSource, true)

	note2, err := svc.CreateAudioNote(anotherSource)
	if err != nil {
		t.Fatalf("CreateAudioNote for duplicate failed: %v", err)
	}
	if note2.AudioFile == audioNote.AudioFile {
		t.Errorf("expected unique audio filename, both got %q", note2.AudioFile)
	}
	if !strings.Contains(note2.AudioFile, "meeting-standup 1.mp3") && !strings.Contains(note2.AudioFile, "meeting-standup (1).mp3") {
		t.Errorf("expected numbered 'meeting-standup' mp3, got %q", note2.AudioFile)
	}

	// 3. Configure valid API key and run mocked ASR pipeline
	mockSentences := []asr.Sentence{
		{
			SpeakerID: 1,
			BeginTime: 1250,
			EndTime:   3890,
			Text:      "大家早上好，今天开始阶段 11 联调。",
		},
		{
			SpeakerID: 2,
			BeginTime: 4100,
			EndTime:   7520,
			Text:      "好的，语音转写管线已经接通，准备验证前端交互。",
		},
	}
	mockServer := setupMockDashScopeServer(t, mockSentences)
	defer mockServer.Close()

	if err := svc.SetASRKey("sk-test-valid-key"); err != nil {
		t.Fatalf("SetASRKey failed: %v", err)
	}

	// Custom client with BaseURL set to mock server and fast polling
	mockClient := asr.NewClient(mockServer.URL, asr.DefaultModel)
	mockClient.HTTPClient = mockServer.Client()
	fastManager := asr.NewManager(mockClient, nil)
	fastManager.PollInterval = 20 * time.Millisecond
	// Swap manager for test
	svc.asrManager = fastManager

	// Now trigger transcription for audioNote
	if err := svc.StartAudioTranscription(audioNote.ID); err != nil {
		t.Fatalf("StartAudioTranscription failed: %v", err)
	}

	// Poll until completed
	deadline := time.Now().Add(5 * time.Second)
	var finalStatus asr.ASRTaskStatus
	for time.Now().Before(deadline) {
		st, err := svc.GetASRTaskStatus(audioNote.ID)
		if err == nil && (st.State == asr.StateCompleted || st.State == asr.StateFailed) {
			finalStatus = st
			break
		}
		time.Sleep(30 * time.Millisecond)
	}

	if finalStatus.State != asr.StateCompleted {
		t.Fatalf("expected ASR to complete successfully, got state: %s, error: %s", finalStatus.State, finalStatus.Error)
	}

	// 4. Verify Note contents after transcription
	updatedNote, err := svc.GetNote(audioNote.ID)
	if err != nil || updatedNote == nil {
		t.Fatalf("failed to get updated note: %v", err)
	}

	// Title must still be "meeting-standup" (not duplicated in body as # meeting-standup)
	if updatedNote.Title != "meeting-standup" {
		t.Errorf("expected title 'meeting-standup', got %q", updatedNote.Title)
	}
	if strings.Contains(updatedNote.Body, "# meeting-standup") {
		t.Errorf("body must not repeat note title as heading")
	}

	// Body must contain formatted sentences with millisecond timestamps and speaker labels
	expectedSentence1 := "[00:00:01.250](#t=00:00:01.250) 说话人 1\n\n大家早上好，今天开始阶段 11 联调。"
	expectedSentence2 := "[00:00:04.100](#t=00:00:04.100) 说话人 2\n\n好的，语音转写管线已经接通，准备验证前端交互。"
	if !strings.Contains(updatedNote.Body, expectedSentence1) {
		t.Errorf("body missing expected sentence 1.\nBody:\n%s", updatedNote.Body)
	}
	if !strings.Contains(updatedNote.Body, expectedSentence2) {
		t.Errorf("body missing expected sentence 2.\nBody:\n%s", updatedNote.Body)
	}

	// 5. User modifies Title & Tags while body remains read-only; even if caller sends empty body, body must be protected
	editInput := UpdateNoteInput{
		ID:    audioNote.ID,
		Title: "晨会纪要 2026-10-17",
		Tags:  []string{"晨会", "语音逐字稿"},
		Body:  "", // simulate in-flight auto-save with empty/stale body
	}
	editedNote, err := svc.UpdateNote(editInput)
	if err != nil {
		t.Fatalf("UpdateNote failed: %v", err)
	}
	if editedNote.Title != "晨会纪要 2026-10-17" {
		t.Errorf("expected updated title, got %q", editedNote.Title)
	}
	if len(editedNote.Tags) != 2 || editedNote.Tags[0] != "晨会" {
		t.Errorf("expected updated tags, got %v", editedNote.Tags)
	}
	if !strings.Contains(editedNote.Body, expectedSentence1) {
		t.Fatalf("UpdateNote must preserve transcript body for audio transcript notes, got: %q", editedNote.Body)
	}

	// 6. Re-transcription & Confirmation Flow
	// Setup second mock server with new transcription content
	newSentences := []asr.Sentence{
		{
			SpeakerID: 1,
			BeginTime: 1250,
			EndTime:   3890,
			Text:      "（重新转写）大家早上好，今天开始阶段 11 联调。",
		},
	}
	mockServer2 := setupMockDashScopeServer(t, newSentences)
	defer mockServer2.Close()

	mockClient2 := asr.NewClient(mockServer2.URL, asr.DefaultModel)
	mockClient2.HTTPClient = mockServer2.Client()
	fastManager2 := asr.NewManager(mockClient2, nil)
	fastManager2.PollInterval = 20 * time.Millisecond
	svc.asrManager = fastManager2

	// Start re-transcription
	if err := svc.StartAudioTranscription(audioNote.ID); err != nil {
		t.Fatalf("StartAudioTranscription for re-transcription failed: %v", err)
	}

	// Poll until StatePendingConfirmation
	deadline = time.Now().Add(5 * time.Second)
	var retransStatus asr.ASRTaskStatus
	for time.Now().Before(deadline) {
		st, err := svc.GetASRTaskStatus(audioNote.ID)
		if err == nil && st.State == asr.StatePendingConfirmation {
			retransStatus = st
			break
		}
		time.Sleep(30 * time.Millisecond)
	}

	if retransStatus.State != asr.StatePendingConfirmation {
		t.Fatalf("expected StatePendingConfirmation, got %v", retransStatus.State)
	}

	// Original Note body on disk must NOT have changed yet!
	noteBeforeConfirm, err := svc.GetNote(audioNote.ID)
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(noteBeforeConfirm.Body, "（重新转写）") {
		t.Fatalf("candidate transcript must not overwrite disk before user confirmation")
	}

	// 7. Test Discard Candidate Transcript:
	// If user discards, candidate is dropped and note body stays unchanged
	if err := svc.DiscardCandidateTranscript(audioNote.ID); err != nil {
		t.Fatalf("DiscardCandidateTranscript failed: %v", err)
	}
	stAfterDiscard, _ := svc.GetASRTaskStatus(audioNote.ID)
	if stAfterDiscard.State != asr.StateIdle && stAfterDiscard.State != asr.StateCompleted {
		t.Errorf("expected idle/completed after discard, got %v", stAfterDiscard.State)
	}

	// Re-run re-transcription to test ConfirmReplaceTranscript
	if err := svc.StartAudioTranscription(audioNote.ID); err != nil {
		t.Fatalf("StartAudioTranscription failed: %v", err)
	}
	deadline = time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		st, err := svc.GetASRTaskStatus(audioNote.ID)
		if err == nil && st.State == asr.StatePendingConfirmation {
			break
		}
		time.Sleep(30 * time.Millisecond)
	}

	// Confirm replacement
	confirmedNote, err := svc.ConfirmReplaceTranscript(audioNote.ID)
	if err != nil {
		t.Fatalf("ConfirmReplaceTranscript failed: %v", err)
	}
	if !strings.Contains(confirmedNote.Body, "（重新转写）") {
		t.Errorf("expected confirmedNote to have replaced body, got:\n%s", confirmedNote.Body)
	}
	// Title and tags must still be preserved!
	if confirmedNote.Title != "晨会纪要 2026-10-17" {
		t.Errorf("title must be preserved across replace, got %q", confirmedNote.Title)
	}
	if len(confirmedNote.Tags) != 2 || confirmedNote.Tags[0] != "晨会" {
		t.Errorf("tags must be preserved across replace, got %v", confirmedNote.Tags)
	}

	// 7b. Conflict protection: if external editor modifies the note while candidate is waiting, confirm must reject!
	if err := svc.StartAudioTranscription(audioNote.ID); err != nil {
		t.Fatalf("StartAudioTranscription for conflict test failed: %v", err)
	}
	deadline = time.Now().Add(5 * time.Second)
	reachedPending := false
	for time.Now().Before(deadline) {
		st, _ := svc.GetASRTaskStatus(audioNote.ID)
		if st.State == asr.StatePendingConfirmation {
			reachedPending = true
			break
		}
		time.Sleep(30 * time.Millisecond)
	}
	if !reachedPending {
		t.Fatalf("timed out waiting for StatePendingConfirmation in conflict test")
	}

	// Simulate external edit directly to file on disk
	notePath := svc.vault.ResolveEntityPath(confirmedNote)
	noteDiskData, err := os.ReadFile(notePath)
	if err != nil {
		t.Fatalf("failed to read note file: %v", err)
	}
	modifiedData := append(noteDiskData, []byte("\n外部编辑新增内容\n")...)
	if err := os.WriteFile(notePath, modifiedData, 0644); err != nil {
		t.Fatalf("failed to write external modification: %v", err)
	}
	time.Sleep(50 * time.Millisecond)

	// Attempt to confirm replace: MUST FAIL and preserve external content!
	_, conflictErr := svc.ConfirmReplaceTranscript(audioNote.ID)
	if conflictErr == nil {
		t.Fatalf("expected ConfirmReplaceTranscript to fail when note was externally modified, but succeeded")
	}

	// Verify disk still contains external edit
	dataAfterConflict, _ := os.ReadFile(notePath)
	if !strings.Contains(string(dataAfterConflict), "外部编辑新增内容") {
		t.Errorf("external edit was overwritten despite conflict!")
	}

	// Repeated confirmation attempt must continue to reject conflict and not bypass checks
	_, secondConflictErr := svc.ConfirmReplaceTranscript(audioNote.ID)
	if secondConflictErr == nil {
		t.Fatalf("expected repeated ConfirmReplaceTranscript to also fail and protect external edits, but succeeded")
	}
	dataAfterSecond, _ := os.ReadFile(notePath)
	if !strings.Contains(string(dataAfterSecond), "外部编辑新增内容") {
		t.Errorf("external edit was overwritten on repeated confirm attempt!")
	}

	// Starting transcription while awaiting confirmation must be rejected to protect the candidate
	if err := svc.StartAudioTranscription(audioNote.ID); err == nil {
		t.Fatalf("expected StartAudioTranscription to fail while in StatePendingConfirmation, but succeeded")
	}

	// Discard rejected candidate to reset state before restarting
	if err := svc.DiscardCandidateTranscript(audioNote.ID); err != nil {
		t.Fatalf("DiscardCandidateTranscript failed: %v", err)
	}

	// 7c. In-app metadata edits (title/tags) during transcription/candidate must NOT trigger conflict rejection
	// Re-start transcription
	if err := svc.StartAudioTranscription(audioNote.ID); err != nil {
		t.Fatalf("StartAudioTranscription for in-app edit test failed: %v", err)
	}
	deadline = time.Now().Add(5 * time.Second)
	reachedPending = false
	for time.Now().Before(deadline) {
		st, _ := svc.GetASRTaskStatus(audioNote.ID)
		if st.State == asr.StatePendingConfirmation {
			reachedPending = true
			break
		}
		time.Sleep(30 * time.Millisecond)
	}
	if !reachedPending {
		t.Fatalf("timed out waiting for StatePendingConfirmation in in-app edit test")
	}

	// Update title and tags in-app while candidate is waiting
	_, err = svc.UpdateNote(UpdateNoteInput{
		ID:    audioNote.ID,
		Title: "晨会纪要（更新标题）",
		Tags:  []string{"晨会", "已更新"},
	})
	if err != nil {
		t.Fatalf("UpdateNote failed: %v", err)
	}

	// ConfirmReplaceTranscript must succeed and not be falsely rejected as external conflict
	inAppConfirmed, err := svc.ConfirmReplaceTranscript(audioNote.ID)
	if err != nil {
		t.Fatalf("ConfirmReplaceTranscript should succeed after in-app metadata edit, got: %v", err)
	}
	if inAppConfirmed.Title != "晨会纪要（更新标题）" {
		t.Errorf("expected updated title preserved, got %q", inAppConfirmed.Title)
	}
	if len(inAppConfirmed.Tags) != 2 || inAppConfirmed.Tags[1] != "已更新" {
		t.Errorf("expected updated tags preserved, got %v", inAppConfirmed.Tags)
	}
	if !strings.Contains(inAppConfirmed.Body, "（重新转写）") {
		t.Errorf("expected candidate body replaced, got:\n%s", inAppConfirmed.Body)
	}

	// 8. Audio URL & Security:
	audioURL, err := svc.GetAudioURL(confirmedNote.AudioFile)
	if err != nil {
		t.Fatalf("GetAudioURL failed: %v", err)
	}
	if audioURL != "/vault-audio/"+confirmedNote.AudioFile {
		t.Errorf("expected /vault-audio/%s, got %q", confirmedNote.AudioFile, audioURL)
	}

	// Audio URL must escape special characters (e.g. #, spaces, ?)
	specialPath := filepath.Join(vaultDir, "files", "standup #1.mp3")
	createTestMP3(t, specialPath, true)
	specialURL, err := svc.GetAudioURL("files/standup #1.mp3")
	if err != nil {
		t.Fatalf("GetAudioURL for special filename failed: %v", err)
	}
	expectedSpecial := "/vault-audio/files/standup%20%231.mp3"
	if specialURL != expectedSpecial {
		t.Errorf("expected %q, got %q", expectedSpecial, specialURL)
	}

	// Directory traversal attempt must be rejected
	if _, err := svc.GetAudioURL("../../etc/passwd"); err == nil {
		t.Errorf("expected directory traversal in GetAudioURL to fail")
	}
	if _, err := svc.GetAudioData("../../etc/passwd"); err == nil {
		t.Errorf("expected directory traversal in GetAudioData to fail")
	}

	// 9. Ordinary Note isolation:
	// A standard note created normally must have AudioTranscript == false and no audio_file
	normalNote, err := svc.CreateNote(CreateNoteInput{
		Title: "普通手写笔记",
		Tags:  []string{"dev"},
		Body:  "普通内容，[音频链接](files/meeting-standup.mp3)",
	})
	if err != nil {
		t.Fatalf("CreateNote failed: %v", err)
	}
	if normalNote.AudioTranscript {
		t.Errorf("ordinary note must not have AudioTranscript == true")
	}
	if normalNote.AudioFile != "" {
		t.Errorf("ordinary note must not have AudioFile set, got %q", normalNote.AudioFile)
	}
}

func TestTranscriptRecord_CleanupOnFailure(t *testing.T) {
	vaultDir := t.TempDir()
	extDir := t.TempDir()
	mp3Path := filepath.Join(extDir, "fail-sample.mp3")
	createTestMP3(t, mp3Path, true)

	svc := NewVaultService()
	svc.keychain = keychain.NewMemoryStore() // unconfigured key
	_, err := svc.openVault(vaultDir)
	if err != nil {
		t.Fatalf("openVault failed: %v", err)
	}
	defer func() {
		if svc.stopWatcher != nil {
			svc.stopWatcher()
		}
	}()

	note, err := svc.CreateAudioNote(mp3Path)
	if err != nil {
		t.Fatalf("CreateAudioNote failed: %v", err)
	}

	// Task will fail due to missing API key
	deadline := time.Now().Add(3 * time.Second)
	for time.Now().Before(deadline) {
		st, _ := svc.GetASRTaskStatus(note.ID)
		if st.State == asr.StateFailed {
			break
		}
		time.Sleep(20 * time.Millisecond)
	}

	st, _ := svc.GetASRTaskStatus(note.ID)
	if st.State != asr.StateFailed {
		t.Fatalf("expected task to fail, got %v", st.State)
	}

	// Wait briefly for completion cleanup to execute
	time.Sleep(50 * time.Millisecond)

	svc.mu.Lock()
	rec := svc.transcriptRecords[note.ID]
	svc.mu.Unlock()

	if rec != nil {
		t.Errorf("expected transcriptRecord to be cleaned up after task failure, but it still exists: %+v", rec)
	}
}

func TestTranscriptRecord_RetryPreservesNewRecord(t *testing.T) {
	svc := NewVaultService()
	noteID := "n-retry-race"

	rec1 := &transcriptRecord{expectedBody: "gen1"}
	rec2 := &transcriptRecord{expectedBody: "gen2"}

	svc.mu.Lock()
	svc.transcriptRecords = make(map[string]*transcriptRecord)
	svc.transcriptRecords[noteID] = rec1
	svc.mu.Unlock()

	// Simulate cleanup for rec1
	cleanup1 := func(state asr.ASRTaskState) {
		if state == asr.StateFailed || state == asr.StateCompleted {
			svc.mu.Lock()
			if svc.transcriptRecords != nil && svc.transcriptRecords[noteID] == rec1 {
				delete(svc.transcriptRecords, noteID)
			}
			svc.mu.Unlock()
		}
	}

	// Retry installs rec2 before cleanup1 runs
	svc.mu.Lock()
	svc.transcriptRecords[noteID] = rec2
	svc.mu.Unlock()

	// Now cleanup1 runs for the failed/completed prior task
	cleanup1(asr.StateFailed)

	// rec2 must NOT be deleted by cleanup1
	svc.mu.Lock()
	current := svc.transcriptRecords[noteID]
	svc.mu.Unlock()

	if current != rec2 {
		t.Fatalf("expected rec2 to be retained after prior task cleanup, got %+v", current)
	}

	// Cleanup for rec2 should delete it
	cleanup2 := func(state asr.ASRTaskState) {
		if state == asr.StateFailed || state == asr.StateCompleted {
			svc.mu.Lock()
			if svc.transcriptRecords != nil && svc.transcriptRecords[noteID] == rec2 {
				delete(svc.transcriptRecords, noteID)
			}
			svc.mu.Unlock()
		}
	}
	cleanup2(asr.StateCompleted)

	svc.mu.Lock()
	finalRec := svc.transcriptRecords[noteID]
	svc.mu.Unlock()

	if finalRec != nil {
		t.Fatalf("expected rec2 to be deleted after its own cleanup, got %+v", finalRec)
	}
}

func TestVaultService_VaultSwitchResetsASRTaskState(t *testing.T) {
	vaultDir1 := t.TempDir()
	vaultDir2 := t.TempDir()

	svc := NewVaultService()
	v1, err := svc.openVault(vaultDir1)
	if err != nil {
		t.Fatalf("openVault 1 failed: %v", err)
	}
	defer func() {
		if svc.stopWatcher != nil {
			svc.stopWatcher()
		}
	}()

	noteID := "n-shared-id"

	// Simulate in-flight / pending confirmation task in Vault 1
	mgr := svc.getASRManager()
	mgr.SetTaskStatusForTest(noteID, asr.StatePendingConfirmation, "等待确认替换", "Vault 1 candidate")

	svc.mu.Lock()
	svc.transcriptRecords[noteID] = &transcriptRecord{
		vault:        v1,
		expectedBody: "old body",
	}
	svc.mu.Unlock()

	// Verify status is pending in Vault 1
	st, _ := svc.GetASRTaskStatus(noteID)
	if st.State != asr.StatePendingConfirmation {
		t.Fatalf("expected StatePendingConfirmation in Vault 1, got %v", st.State)
	}

	// Switch to Vault 2
	_, err = svc.openVault(vaultDir2)
	if err != nil {
		t.Fatalf("openVault 2 failed: %v", err)
	}

	// In Vault 2, task status for noteID must be idle, not pending confirmation from Vault 1
	st2, _ := svc.GetASRTaskStatus(noteID)
	if st2.State != asr.StateIdle {
		t.Fatalf("expected StateIdle in Vault 2 after vault switch, got %v", st2.State)
	}

	// transcriptRecords must have been reset
	svc.mu.Lock()
	rec := svc.transcriptRecords[noteID]
	svc.mu.Unlock()
	if rec != nil {
		t.Fatalf("expected transcriptRecords to be reset after vault switch, got %+v", rec)
	}

	// Any stale attempt to confirm replace pointing to v1 must be rejected
	svc.mu.Lock()
	svc.transcriptRecords[noteID] = &transcriptRecord{
		vault:        v1,
		expectedBody: "old body",
	}
	svc.mu.Unlock()

	_, err = svc.ConfirmReplaceTranscript(noteID)
	if err == nil {
		t.Fatalf("expected ConfirmReplaceTranscript with mismatched vault to fail, but succeeded")
	}

	// Any stale attempt to save transcript body pointing to v1 must be rejected
	err = svc.saveTranscriptBody(v1, noteID, "test transcript")
	if err == nil {
		t.Fatalf("expected saveTranscriptBody with mismatched vault to fail, but succeeded")
	}
}

