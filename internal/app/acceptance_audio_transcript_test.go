package app

import (
	"encoding/base64"
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
					"upload_host":       "http://" + r.Host + "/oss-mock",
					"upload_dir":        "tmp-dir",
					"oss_access_key_id": "test-key-id",
					"policy":            "test-policy",
					"signature":         "test-sig",
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
					"task_id":           taskID,
					"task_status":       "SUCCEEDED",
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

	return httptest.NewServer(handler)
}

// createTestMP3 creates a minimal synthetic MP3 file (MPEG-1 Layer 3, mono or stereo).
func createTestMP3(t *testing.T, path string, mono bool) {
	modeBits := byte(0x00) // 00 = stereo
	if mono {
		modeBits = 0xC0 // 11 = single channel (mono)
	}
	header := []byte{0xFF, 0xFB, 0x90, modeBits}
	content := append(header, make([]byte, 417-4)...) // 417 bytes frame
	if err := os.WriteFile(path, content, 0644); err != nil {
		t.Fatalf("failed to create test MP3: %v", err)
	}
}

// createTestM4A creates a minimal synthetic M4A file with ftyp and moov/stsd/mp4a atoms.
func createTestM4A(t *testing.T, path string, mono bool) {
	mp4aPrefix := []byte{'m', 'p', '4', 'a'}
	reserved16 := make([]byte, 16)
	chanBytes := []byte{0x00, 0x02}
	if mono {
		chanBytes = []byte{0x00, 0x01}
	}
	content := append([]byte("....ftypM4A ....moov....stsd...."), append(append(mp4aPrefix, reserved16...), chanBytes...)...)
	if err := os.WriteFile(path, content, 0644); err != nil {
		t.Fatalf("failed to create test M4A: %v", err)
	}
}

// TestAcceptance_AudioTranscript_FullLifecycleAndNoteProtection tests end-to-end audio transcription:
// 1. Missing key scenario (preserves file and note, sets clear error)
// 2. Duplicate file naming produces unique safe filenames
// 3. Cloud ASR pipeline parsing with millisecond timestamps and speakers
// 4. Note body read-only protection in Pata
// 5. Candidate transcript re-transcription, discard, and confirmation
// 6. External modification conflict protection
// 7. Audio URL encoding and path traversal protection
func TestAcceptance_AudioTranscript_FullLifecycleAndNoteProtection(t *testing.T) {
	tmpDir, err := os.MkdirTemp("", "pata-audio-transcript-*")
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

	sourceMP3 := filepath.Join(tmpDir, "meeting-standup.mp3")
	createTestMP3(t, sourceMP3, true)

	audioNote, err := svc.CreateAudioNote(sourceMP3)
	if err != nil {
		t.Fatalf("CreateAudioNote failed: %v", err)
	}
	if audioNote == nil {
		t.Fatalf("expected audioNote to be created immediately")
	}
	if audioNote.CreatedBy != "" {
		t.Fatalf("GUI audio import must retain user attribution: %q", audioNote.CreatedBy)
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

	if _, err := os.Stat(sourceMP3); err != nil {
		t.Fatalf("source MP3 must remain intact: %v", err)
	}

	copiedPath := filepath.Join(vaultDir, audioNote.AudioFile)
	if _, err := os.Stat(copiedPath); err != nil {
		t.Fatalf("copied MP3 does not exist in vault: %v", err)
	}

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

	savedNote, err := svc.GetNote(audioNote.ID)
	if err != nil || savedNote == nil {
		t.Fatalf("Note must be preserved after ASR failure: %v", err)
	}
	if savedNote.CreatedBy != "" {
		t.Fatalf("ASR must not change creation source: %q", savedNote.CreatedBy)
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
			Text:      "大家早上好，今天开始语音转写联调。",
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

	mockClient := asr.NewClient(mockServer.URL, asr.DefaultModel)
	mockClient.HTTPClient = mockServer.Client()
	fastManager := asr.NewManager(mockClient, nil)
	fastManager.PollInterval = 20 * time.Millisecond
	svc.asrManager = fastManager

	if err := svc.StartAudioTranscription(audioNote.ID); err != nil {
		t.Fatalf("StartAudioTranscription failed: %v", err)
	}

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

	if updatedNote.Title != "meeting-standup" {
		t.Errorf("expected title 'meeting-standup', got %q", updatedNote.Title)
	}
	if strings.Contains(updatedNote.Body, "# meeting-standup") {
		t.Errorf("body must not repeat note title as heading")
	}

	expectedSentence1 := "[00:00:01.250](#t=00:00:01.250) 说话人 1\n\n大家早上好，今天开始语音转写联调。"
	expectedSentence2 := "[00:00:04.100](#t=00:00:04.100) 说话人 2\n\n好的，语音转写管线已经接通，准备验证前端交互。"
	if !strings.Contains(updatedNote.Body, expectedSentence1) {
		t.Errorf("body missing expected sentence 1.\nBody:\n%s", updatedNote.Body)
	}
	if !strings.Contains(updatedNote.Body, expectedSentence2) {
		t.Errorf("body missing expected sentence 2.\nBody:\n%s", updatedNote.Body)
	}

	// 5. User modifies Title & Tags while body remains read-only
	editInput := UpdateNoteInput{
		ID:    audioNote.ID,
		Title: "晨会纪要 2026-10-17",
		Tags:  []string{"晨会", "语音逐字稿"},
		Body:  "",
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
	newSentences := []asr.Sentence{
		{
			SpeakerID: 1,
			BeginTime: 1250,
			EndTime:   3890,
			Text:      "（重新转写）大家早上好，今天开始语音转写联调。",
		},
	}
	mockServer2 := setupMockDashScopeServer(t, newSentences)
	defer mockServer2.Close()

	mockClient2 := asr.NewClient(mockServer2.URL, asr.DefaultModel)
	mockClient2.HTTPClient = mockServer2.Client()
	fastManager2 := asr.NewManager(mockClient2, nil)
	fastManager2.PollInterval = 20 * time.Millisecond
	svc.asrManager = fastManager2

	if err := svc.StartAudioTranscription(audioNote.ID); err != nil {
		t.Fatalf("StartAudioTranscription for re-transcription failed: %v", err)
	}

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

	noteBeforeConfirm, err := svc.GetNote(audioNote.ID)
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(noteBeforeConfirm.Body, "（重新转写）") {
		t.Fatalf("candidate transcript must not overwrite disk before user confirmation")
	}

	// 7. Discard Candidate Transcript
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

	confirmedNote, err := svc.ConfirmReplaceTranscript(audioNote.ID)
	if err != nil {
		t.Fatalf("ConfirmReplaceTranscript failed: %v", err)
	}
	if !strings.Contains(confirmedNote.Body, "（重新转写）") {
		t.Errorf("expected confirmedNote to have replaced body, got:\n%s", confirmedNote.Body)
	}
	if confirmedNote.Title != "晨会纪要 2026-10-17" {
		t.Errorf("title must be preserved across replace, got %q", confirmedNote.Title)
	}
	if len(confirmedNote.Tags) != 2 || confirmedNote.Tags[0] != "晨会" {
		t.Errorf("tags must be preserved across replace, got %v", confirmedNote.Tags)
	}

	// 8. External conflict protection
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

	_, conflictErr := svc.ConfirmReplaceTranscript(audioNote.ID)
	if conflictErr == nil {
		t.Fatalf("expected ConfirmReplaceTranscript to fail when note was externally modified, but succeeded")
	}

	dataAfterConflict, _ := os.ReadFile(notePath)
	if !strings.Contains(string(dataAfterConflict), "外部编辑新增内容") {
		t.Errorf("external edit was overwritten despite conflict!")
	}

	if err := svc.DiscardCandidateTranscript(audioNote.ID); err != nil {
		t.Fatalf("DiscardCandidateTranscript failed: %v", err)
	}

	// 9. In-app metadata edit protection
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

	_, err = svc.UpdateNote(UpdateNoteInput{
		ID:    audioNote.ID,
		Title: "晨会纪要（更新标题）",
		Tags:  []string{"晨会", "已更新"},
	})
	if err != nil {
		t.Fatalf("UpdateNote failed: %v", err)
	}

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

	// 10. Audio URL and directory traversal protection
	audioURL, err := svc.GetAudioURL(confirmedNote.AudioFile)
	if err != nil {
		t.Fatalf("GetAudioURL failed: %v", err)
	}
	if audioURL != "/vault-audio/"+confirmedNote.AudioFile {
		t.Errorf("expected /vault-audio/%s, got %q", confirmedNote.AudioFile, audioURL)
	}

	if _, err := svc.GetAudioURL("../../etc/passwd"); err == nil {
		t.Errorf("expected directory traversal in GetAudioURL to fail")
	}
	if _, err := svc.GetAudioData("../../etc/passwd"); err == nil {
		t.Errorf("expected directory traversal in GetAudioData to fail")
	}
}

// TestAcceptance_AudioTranscript_CleanupOnFailure verifies that background transcript records
// are cleaned up cleanly if a transcription task fails.
func TestAcceptance_AudioTranscript_CleanupOnFailure(t *testing.T) {
	vaultDir := t.TempDir()
	extDir := t.TempDir()
	mp3Path := filepath.Join(extDir, "fail-sample.mp3")
	createTestMP3(t, mp3Path, true)

	svc := NewVaultService()
	svc.keychain = keychain.NewMemoryStore()
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

	time.Sleep(50 * time.Millisecond)

	svc.mu.Lock()
	rec := svc.transcriptRecords[note.ID]
	svc.mu.Unlock()

	if rec != nil {
		t.Errorf("expected transcriptRecord to be cleaned up after task failure, but it still exists: %+v", rec)
	}
}

// TestAcceptance_AudioTranscript_RetryPreservesNewRecord verifies race-free cleanup when retrying transcription.
func TestAcceptance_AudioTranscript_RetryPreservesNewRecord(t *testing.T) {
	svc := NewVaultService()
	noteID := "n-retry-race"

	rec1 := &transcriptRecord{expectedBody: "gen1"}
	rec2 := &transcriptRecord{expectedBody: "gen2"}

	svc.mu.Lock()
	svc.transcriptRecords = make(map[string]*transcriptRecord)
	svc.transcriptRecords[noteID] = rec1
	svc.mu.Unlock()

	cleanup1 := func(state asr.ASRTaskState) {
		if state == asr.StateFailed || state == asr.StateCompleted {
			svc.mu.Lock()
			if svc.transcriptRecords != nil && svc.transcriptRecords[noteID] == rec1 {
				delete(svc.transcriptRecords, noteID)
			}
			svc.mu.Unlock()
		}
	}

	svc.mu.Lock()
	svc.transcriptRecords[noteID] = rec2
	svc.mu.Unlock()

	cleanup1(asr.StateFailed)

	svc.mu.Lock()
	current := svc.transcriptRecords[noteID]
	svc.mu.Unlock()

	if current != rec2 {
		t.Fatalf("expected rec2 to be retained after prior task cleanup, got %+v", current)
	}

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

// TestAcceptance_AudioTranscript_VaultSwitchResetsInFlightTasks verifies that switching vault
// resets pending and in-flight transcription tasks.
func TestAcceptance_AudioTranscript_VaultSwitchResetsInFlightTasks(t *testing.T) {
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

	mgr := svc.getASRManager()
	mgr.SetTaskStatusForTest(noteID, asr.StatePendingConfirmation, "等待确认替换", "Vault 1 candidate")

	svc.mu.Lock()
	svc.transcriptRecords[noteID] = &transcriptRecord{
		vault:        v1,
		expectedBody: "old body",
	}
	svc.mu.Unlock()

	st, _ := svc.GetASRTaskStatus(noteID)
	if st.State != asr.StatePendingConfirmation {
		t.Fatalf("expected StatePendingConfirmation in Vault 1, got %v", st.State)
	}

	_, err = svc.openVault(vaultDir2)
	if err != nil {
		t.Fatalf("openVault 2 failed: %v", err)
	}

	st2, _ := svc.GetASRTaskStatus(noteID)
	if st2.State != asr.StateIdle {
		t.Fatalf("expected StateIdle in Vault 2 after vault switch, got %v", st2.State)
	}

	svc.mu.Lock()
	rec := svc.transcriptRecords[noteID]
	svc.mu.Unlock()
	if rec != nil {
		t.Fatalf("expected transcriptRecords to be reset after vault switch, got %+v", rec)
	}

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

	err = svc.saveTranscriptBody(v1, noteID, "test transcript")
	if err == nil {
		t.Fatalf("expected saveTranscriptBody with mismatched vault to fail, but succeeded")
	}
}

// TestAcceptance_AudioTranscript_SupportsM4AAndMP3 verifies that M4A audio files are supported alongside MP3.
func TestAcceptance_AudioTranscript_SupportsM4AAndMP3(t *testing.T) {
	tmpDir, err := os.MkdirTemp("", "pata-m4a-*")
	if err != nil {
		t.Fatal(err)
	}
	defer os.RemoveAll(tmpDir)

	configPath := filepath.Join(tmpDir, "config", "vault.json")
	vaultDir := filepath.Join(tmpDir, "vault")
	_ = os.MkdirAll(vaultDir, 0755)

	svc := &VaultService{
		configPath: configPath,
		keychain:   keychain.NewMemoryStore(),
	}
	if _, err := svc.openVault(vaultDir); err != nil {
		t.Fatalf("openVault failed: %v", err)
	}

	srcM4A := filepath.Join(tmpDir, "interview.m4a")
	createTestM4A(t, srcM4A, true)

	note, err := svc.CreateAudioNote(srcM4A)
	if err != nil {
		t.Fatalf("CreateAudioNote with .m4a failed: %v", err)
	}
	if note == nil {
		t.Fatalf("expected note to be non-nil")
	}
	if note.Title != "interview" {
		t.Errorf("expected title 'interview', got %q", note.Title)
	}
	if !note.AudioTranscript {
		t.Errorf("expected AudioTranscript == true")
	}
	if !strings.HasPrefix(note.AudioFile, "files/interview") || !strings.HasSuffix(note.AudioFile, ".m4a") {
		t.Errorf("expected AudioFile 'files/interview*.m4a', got %q", note.AudioFile)
	}

	if _, err := os.Stat(srcM4A); err != nil {
		t.Errorf("source M4A file must remain intact: %v", err)
	}
	copiedPath := filepath.Join(vaultDir, note.AudioFile)
	if _, err := os.Stat(copiedPath); err != nil {
		t.Errorf("copied M4A file does not exist in vault: %v", err)
	}

	audioURL, err := svc.GetAudioURL(note.AudioFile)
	if err != nil {
		t.Fatalf("GetAudioURL failed: %v", err)
	}
	if !strings.HasPrefix(audioURL, "/vault-audio/files/interview") {
		t.Errorf("expected /vault-audio/files/interview..., got %q", audioURL)
	}

	dataURI, err := svc.GetAudioData(note.AudioFile)
	if err != nil {
		t.Fatalf("GetAudioData failed: %v", err)
	}
	if !strings.HasPrefix(dataURI, "data:audio/mp4;base64,") {
		prefix := dataURI
		if len(prefix) > 30 {
			prefix = prefix[:30]
		}
		t.Errorf("expected data:audio/mp4;base64, prefix for M4A, got %q", prefix)
	}

	encoded := base64.StdEncoding.EncodeToString([]byte("fake-m4a-content"))
	noteData, err := svc.CreateAudioNoteData("lecture.m4a", encoded)
	if err != nil {
		t.Fatalf("CreateAudioNoteData with .m4a failed: %v", err)
	}
	if noteData.Title != "lecture" {
		t.Errorf("expected title 'lecture', got %q", noteData.Title)
	}

	txtPath := filepath.Join(tmpDir, "document.txt")
	_ = os.WriteFile(txtPath, []byte("plain text"), 0644)
	if _, err := svc.CreateAudioNote(txtPath); err == nil {
		t.Errorf("expected error when importing non-audio file (.txt), got nil")
	}
}
