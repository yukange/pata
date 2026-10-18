package asr

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"
)

func TestClient_EndToEndMock(t *testing.T) {
	// Setup mock DashScope HTTP Server
	var (
		policyCalled bool
		uploadCalled bool
		submitCalled bool
		pollCount    int
		resultCalled bool
	)

	var server *httptest.Server
	server = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch {
		case r.Method == http.MethodGet && strings.HasPrefix(r.URL.Path, "/api/v1/uploads"):
			policyCalled = true
			if auth := r.Header.Get("Authorization"); auth != "Bearer test-key" {
				http.Error(w, "unauthorized", http.StatusUnauthorized)
				return
			}
			w.Header().Set("Content-Type", "application/json")
			_ = json.NewEncoder(w).Encode(map[string]any{
				"request_id": "req-123",
				"data": map[string]any{
					"policy":                 "mock-policy",
					"signature":              "mock-sig",
					"upload_dir":             "dashscope-instant/test/2026",
					"upload_host":            server.URL + "/oss-upload",
					"oss_access_key_id":      "LTAI_test",
					"x_oss_object_acl":       "private",
					"x_oss_forbid_overwrite": "true",
				},
			})

		case r.Method == http.MethodPost && r.URL.Path == "/oss-upload":
			uploadCalled = true
			_ = r.ParseMultipartForm(10 << 20)
			if r.FormValue("OSSAccessKeyId") != "LTAI_test" || r.FormValue("policy") != "mock-policy" {
				http.Error(w, "invalid form", http.StatusBadRequest)
				return
			}
			file, header, err := r.FormFile("file")
			if err != nil || header.Filename == "" {
				http.Error(w, "missing file", http.StatusBadRequest)
				return
			}
			_ = file.Close()
			w.WriteHeader(http.StatusOK)

		case r.Method == http.MethodPost && r.URL.Path == "/api/v1/services/audio/asr/transcription":
			submitCalled = true
			if r.Header.Get("X-DashScope-Async") != "enable" || r.Header.Get("X-DashScope-OssResourceResolve") != "enable" {
				http.Error(w, "missing async headers", http.StatusBadRequest)
				return
			}
			bodyBytes, _ := io.ReadAll(r.Body)
			var reqData struct {
				Model string `json:"model"`
				Input struct {
					FileURLs []string `json:"file_urls"`
				} `json:"input"`
				Parameters struct {
					DiarizationEnabled bool `json:"diarization_enabled"`
				} `json:"parameters"`
			}
			_ = json.Unmarshal(bodyBytes, &reqData)
			if reqData.Model != DefaultModel || len(reqData.Input.FileURLs) == 0 || !reqData.Parameters.DiarizationEnabled {
				http.Error(w, "invalid submit payload", http.StatusBadRequest)
				return
			}
			w.Header().Set("Content-Type", "application/json")
			_ = json.NewEncoder(w).Encode(map[string]any{
				"output": map[string]any{
					"task_id":     "task-abc-123",
					"task_status": "PENDING",
				},
			})

		case r.Method == http.MethodGet && strings.HasPrefix(r.URL.Path, "/api/v1/tasks/task-abc-123"):
			pollCount++
			w.Header().Set("Content-Type", "application/json")
			if pollCount < 2 {
				_ = json.NewEncoder(w).Encode(map[string]any{
					"output": map[string]any{
						"task_id":     "task-abc-123",
						"task_status": "RUNNING",
					},
				})
			} else {
				_ = json.NewEncoder(w).Encode(map[string]any{
					"output": map[string]any{
						"task_id":     "task-abc-123",
						"task_status": "SUCCEEDED",
						"results": []map[string]any{
							{
								"subtask_status":    "SUCCEEDED",
								"transcription_url": server.URL + "/results/transcript.json",
							},
						},
					},
				})
			}

		case r.Method == http.MethodGet && r.URL.Path == "/results/transcript.json":
			resultCalled = true
			w.Header().Set("Content-Type", "application/json")
			_ = json.NewEncoder(w).Encode(map[string]any{
				"sentences": []Sentence{
					{
						BeginTime: 1200,
						EndTime:   3500,
						Text:      "大家好，今天讨论阶段 11 逐字稿实现。",
						SpeakerID: 0,
					},
					{
						BeginTime: 4000,
						EndTime:   6500,
						Text:      "好的，方案已对齐，开始执行。",
						SpeakerID: 1,
					},
				},
			})

		default:
			http.NotFound(w, r)
		}
	}))
	defer server.Close()

	client := NewClient(server.URL, DefaultModel)
	ctx := context.Background()

	// 1. Get Policy
	policy, err := client.GetUploadPolicy(ctx, "test-key")
	if err != nil {
		t.Fatalf("GetUploadPolicy failed: %v", err)
	}
	if !policyCalled || policy.UploadHost != server.URL+"/oss-upload" {
		t.Errorf("unexpected policy: %+v", policy)
	}

	// Create temp audio file
	tmpDir := t.TempDir()
	sampleMP3 := filepath.Join(tmpDir, "sample.mp3")
	_ = os.WriteFile(sampleMP3, []byte("fake-mp3-binary-data"), 0644)

	// 2. Upload to OSS
	ossURL, err := client.UploadToOSS(ctx, policy, sampleMP3)
	if err != nil {
		t.Fatalf("UploadToOSS failed: %v", err)
	}
	if !uploadCalled || !strings.HasPrefix(ossURL, "oss://dashscope-instant/test/2026/sample.mp3") {
		t.Errorf("unexpected ossURL: %s", ossURL)
	}

	// 3. Submit Task
	taskID, err := client.SubmitTask(ctx, "test-key", ossURL, true)
	if err != nil {
		t.Fatalf("SubmitTask failed: %v", err)
	}
	if !submitCalled || taskID != "task-abc-123" {
		t.Errorf("unexpected taskID: %s", taskID)
	}

	// 4. Poll Task until SUCCEEDED
	res1, err := client.PollTask(ctx, "test-key", taskID)
	if err != nil || res1.Output.TaskStatus != "RUNNING" {
		t.Errorf("expected RUNNING, got %v (err: %v)", res1, err)
	}

	res2, err := client.PollTask(ctx, "test-key", taskID)
	if err != nil || res2.Output.TaskStatus != "SUCCEEDED" {
		t.Fatalf("expected SUCCEEDED, got %v (err: %v)", res2, err)
	}

	// 5. Fetch Result
	sentences, err := client.FetchTranscriptionResult(ctx, res2.Output.Results[0].TranscriptionURL)
	if err != nil {
		t.Fatalf("FetchTranscriptionResult failed: %v", err)
	}
	if !resultCalled || len(sentences) != 2 {
		t.Fatalf("expected 2 sentences, got %d", len(sentences))
	}

	// 6. Format Markdown
	md := FormatTranscriptMarkdown(sentences)
	expectedMD := `[00:00:01.200](#t=00:00:01.200) 说话人 1

大家好，今天讨论阶段 11 逐字稿实现。

[00:00:04.000](#t=00:00:04.000) 说话人 2

好的，方案已对齐，开始执行。`

	if md != expectedMD {
		t.Errorf("markdown formatting mismatch:\nGot:\n%s\nExpected:\n%s", md, expectedMD)
	}
}

func TestManager_Flow(t *testing.T) {
	var (
		writtenBody string
		writeMu     sync.Mutex
	)

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		switch {
		case strings.HasPrefix(r.URL.Path, "/api/v1/uploads"):
			_ = json.NewEncoder(w).Encode(map[string]any{
				"data": map[string]any{
					"policy":            "p",
					"signature":         "s",
					"upload_dir":        "dir",
					"upload_host":       "http://" + r.Host + "/oss",
					"oss_access_key_id": "key",
				},
			})
		case r.URL.Path == "/oss":
			w.WriteHeader(http.StatusOK)
		case strings.HasPrefix(r.URL.Path, "/api/v1/services/audio/asr/transcription"):
			_ = json.NewEncoder(w).Encode(map[string]any{
				"output": map[string]any{
					"task_id": "t-1",
				},
			})
		case strings.HasPrefix(r.URL.Path, "/api/v1/tasks/t-1"):
			_ = json.NewEncoder(w).Encode(map[string]any{
				"output": map[string]any{
					"task_status": "SUCCEEDED",
					"results": []map[string]any{
						{
							"subtask_status":    "SUCCEEDED",
							"transcription_url": "http://" + r.Host + "/res.json",
						},
					},
				},
			})
		case r.URL.Path == "/res.json":
			_ = json.NewEncoder(w).Encode(map[string]any{
				"sentences": []Sentence{
					{BeginTime: 1000, EndTime: 2000, Text: "第一句发言", SpeakerID: 0},
				},
			})
		default:
			http.NotFound(w, r)
		}
	}))
	defer server.Close()

	client := NewClient(server.URL, DefaultModel)
	mgr := NewManager(client, nil)
	mgr.PollInterval = 10 * time.Millisecond

	tmpAudio := filepath.Join(t.TempDir(), "test.mp3")
	monoFrame := []byte{0xFF, 0xFB, 0x90, 0xC0, 0x00, 0x00, 0x00, 0x00}
	_ = os.WriteFile(tmpAudio, monoFrame, 0644)

	// Test 1: Initial transcription writes directly
	noteID := "n-test1"
	saveDone := make(chan struct{})
	mgr.StartTask(noteID, tmpAudio, false, "test-key", func(body string) error {
		writeMu.Lock()
		writtenBody = body
		writeMu.Unlock()
		close(saveDone)
		return nil
	})

	<-saveDone
	st := mgr.GetStatus(noteID)
	if st.State != StateCompleted {
		t.Errorf("expected StateCompleted, got %s (err: %s)", st.State, st.Error)
	}

	writeMu.Lock()
	if !strings.Contains(writtenBody, "第一句发言") {
		t.Errorf("expected body to contain text, got: %s", writtenBody)
	}
	writeMu.Unlock()

	// Test 2: Retranscribe holds candidate transcript in pending_confirmation
	noteID2 := "n-test2"
	mgr.StartTask(noteID2, tmpAudio, true, "test-key", func(body string) error {
		t.Fatalf("should not save directly during re-transcription")
		return nil
	})

	// Wait for pending confirmation state
	for i := 0; i < 50; i++ {
		st2 := mgr.GetStatus(noteID2)
		if st2.State == StatePendingConfirmation {
			break
		}
		time.Sleep(20 * time.Millisecond)
		if i == 49 {
			t.Fatalf("timed out waiting for StatePendingConfirmation, got %s (err: %s)", st2.State, st2.Error)
		}
	}

	st2 := mgr.GetStatus(noteID2)
	if st2.CandidateTranscript == "" {
		t.Fatalf("expected candidate transcript to be non-empty")
	}

	// Confirm replacement
	var confirmedBody string
	err := mgr.ConfirmReplace(noteID2, func(body string) error {
		confirmedBody = body
		return nil
	})
	if err != nil {
		t.Fatalf("ConfirmReplace failed: %v", err)
	}
	if !strings.Contains(confirmedBody, "第一句发言") {
		t.Errorf("expected confirmedBody to contain transcript, got: %s", confirmedBody)
	}
	if mgr.GetStatus(noteID2).State != StateCompleted {
		t.Errorf("expected StateCompleted after confirm, got %s", mgr.GetStatus(noteID2).State)
	}
}

func TestManager_EmptyTranscriptionRejected(t *testing.T) {
	var server *httptest.Server
	server = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch {
		case r.Method == http.MethodGet && strings.HasPrefix(r.URL.Path, "/api/v1/uploads"):
			w.Header().Set("Content-Type", "application/json")
			_ = json.NewEncoder(w).Encode(map[string]any{
				"data": map[string]any{
					"policy":                 "p",
					"signature":              "s",
					"upload_dir":             "dir",
					"upload_host":            server.URL + "/oss-upload",
					"oss_access_key_id":      "k",
					"x_oss_object_acl":       "private",
					"x_oss_forbid_overwrite": "true",
				},
			})
		case r.Method == http.MethodPost && r.URL.Path == "/oss-upload":
			w.WriteHeader(http.StatusOK)
		case r.Method == http.MethodPost && strings.HasPrefix(r.URL.Path, "/api/v1/services/audio/asr/transcription"):
			w.Header().Set("Content-Type", "application/json")
			_ = json.NewEncoder(w).Encode(map[string]any{
				"output": map[string]any{
					"task_id": "empty-task-1",
				},
			})
		case r.Method == http.MethodGet && strings.HasPrefix(r.URL.Path, "/api/v1/tasks/empty-task-1"):
			w.Header().Set("Content-Type", "application/json")
			_ = json.NewEncoder(w).Encode(map[string]any{
				"output": map[string]any{
					"task_id":     "empty-task-1",
					"task_status": "SUCCEEDED",
					"results": []map[string]any{
						{
							"subtask_status":    "SUCCEEDED",
							"transcription_url": server.URL + "/results/empty-transcript.json",
						},
					},
				},
			})
		case r.Method == http.MethodGet && r.URL.Path == "/results/empty-transcript.json":
			w.Header().Set("Content-Type", "application/json")
			// Return sentences that only contain whitespace
			_ = json.NewEncoder(w).Encode(map[string]any{
				"sentences": []Sentence{
					{
						BeginTime: 0,
						EndTime:   1000,
						Text:      "   \n  \t ",
						SpeakerID: 0,
					},
				},
			})
		default:
			http.NotFound(w, r)
		}
	}))
	defer server.Close()

	tmpDir := t.TempDir()
	dummyAudio := filepath.Join(tmpDir, "silence.mp3")
	monoFrame := []byte{0xFF, 0xFB, 0x90, 0xC0, 0x00, 0x00, 0x00, 0x00}
	_ = os.WriteFile(dummyAudio, monoFrame, 0644)

	client := NewClient(server.URL, DefaultModel)
	client.HTTPClient = server.Client()

	mgr := NewManager(client, nil)
	mgr.PollInterval = 10 * time.Millisecond

	// 1. Initial transcription with empty result must fail and NOT call onSave
	onSaveCalled := false
	mgr.StartTask("n-empty-1", dummyAudio, false, "key", func(body string) error {
		onSaveCalled = true
		return nil
	})

	for i := 0; i < 50; i++ {
		st := mgr.GetStatus("n-empty-1")
		if st.State == StateFailed {
			break
		}
		time.Sleep(20 * time.Millisecond)
		if i == 49 {
			t.Fatalf("expected StateFailed, got %s", st.State)
		}
	}

	if onSaveCalled {
		t.Fatalf("onSave should not be called when transcription result is empty")
	}
	st := mgr.GetStatus("n-empty-1")
	if !strings.Contains(st.Error, "未识别到有效语音内容") {
		t.Errorf("expected error message to mention empty result, got %q", st.Error)
	}

	// 2. Retranscription with empty result must also fail and NOT enter StatePendingConfirmation
	mgr.StartTask("n-empty-2", dummyAudio, true, "key", func(body string) error {
		t.Fatalf("onSave should not be called during re-transcription")
		return nil
	})

	for i := 0; i < 50; i++ {
		st2 := mgr.GetStatus("n-empty-2")
		if st2.State == StateFailed {
			break
		}
		if st2.State == StatePendingConfirmation {
			t.Fatalf("empty retranscription must not enter StatePendingConfirmation")
		}
		time.Sleep(20 * time.Millisecond)
		if i == 49 {
			t.Fatalf("expected StateFailed, got %s", st2.State)
		}
	}
}

func TestManager_PermanentPollingError(t *testing.T) {
	pollAttempts := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch {
		case r.Method == http.MethodGet && strings.HasPrefix(r.URL.Path, "/api/v1/uploads"):
			w.Header().Set("Content-Type", "application/json")
			_ = json.NewEncoder(w).Encode(map[string]any{
				"data": map[string]any{
					"policy":                 "p",
					"signature":              "s",
					"upload_dir":             "dir",
					"upload_host":            "http://" + r.Host + "/oss-upload",
					"oss_access_key_id":      "k",
					"x_oss_object_acl":       "private",
					"x_oss_forbid_overwrite": "true",
				},
			})
		case r.Method == http.MethodPost && r.URL.Path == "/oss-upload":
			w.WriteHeader(http.StatusOK)
		case r.Method == http.MethodPost && strings.HasPrefix(r.URL.Path, "/api/v1/services/audio/asr/transcription"):
			w.Header().Set("Content-Type", "application/json")
			_ = json.NewEncoder(w).Encode(map[string]any{
				"output": map[string]any{
					"task_id": "perm-task-1",
				},
			})
		case r.Method == http.MethodGet && strings.HasPrefix(r.URL.Path, "/api/v1/tasks/perm-task-1"):
			pollAttempts++
			// Return 401 Unauthorized (permanent error)
			w.WriteHeader(http.StatusUnauthorized)
			_ = json.NewEncoder(w).Encode(map[string]any{
				"code":    "InvalidApiKey",
				"message": "API key is invalid or revoked",
			})
		default:
			http.NotFound(w, r)
		}
	}))
	defer server.Close()

	dummyAudio := filepath.Join(t.TempDir(), "silence.mp3")
	monoFrame := []byte{0xFF, 0xFB, 0x90, 0xC0, 0x00, 0x00, 0x00, 0x00}
	_ = os.WriteFile(dummyAudio, monoFrame, 0644)

	client := NewClient(server.URL, DefaultModel)
	client.HTTPClient = server.Client()

	mgr := NewManager(client, nil)
	mgr.PollInterval = 10 * time.Millisecond

	mgr.StartTask("n-perm", dummyAudio, false, "key", func(body string) error {
		return nil
	})

	for i := 0; i < 50; i++ {
		st := mgr.GetStatus("n-perm")
		if st.State == StateFailed {
			break
		}
		time.Sleep(20 * time.Millisecond)
		if i == 49 {
			t.Fatalf("expected StateFailed, got %s", st.State)
		}
	}

	st := mgr.GetStatus("n-perm")
	if !strings.Contains(st.Error, "InvalidApiKey") && !strings.Contains(st.Error, "401") {
		t.Errorf("expected actionable 401/InvalidApiKey error, got: %q", st.Error)
	}
	if pollAttempts != 1 {
		t.Errorf("permanent error should not be retried, expected 1 poll attempt, got %d", pollAttempts)
	}
}

func TestManager_ConsecutivePollingErrorsCapped(t *testing.T) {
	pollAttempts := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch {
		case r.Method == http.MethodGet && strings.HasPrefix(r.URL.Path, "/api/v1/uploads"):
			w.Header().Set("Content-Type", "application/json")
			_ = json.NewEncoder(w).Encode(map[string]any{
				"data": map[string]any{
					"policy":                 "p",
					"signature":              "s",
					"upload_dir":             "dir",
					"upload_host":            "http://" + r.Host + "/oss-upload",
					"oss_access_key_id":      "k",
					"x_oss_object_acl":       "private",
					"x_oss_forbid_overwrite": "true",
				},
			})
		case r.Method == http.MethodPost && r.URL.Path == "/oss-upload":
			w.WriteHeader(http.StatusOK)
		case r.Method == http.MethodPost && strings.HasPrefix(r.URL.Path, "/api/v1/services/audio/asr/transcription"):
			w.Header().Set("Content-Type", "application/json")
			_ = json.NewEncoder(w).Encode(map[string]any{
				"output": map[string]any{
					"task_id": "transient-task-1",
				},
			})
		case r.Method == http.MethodGet && strings.HasPrefix(r.URL.Path, "/api/v1/tasks/transient-task-1"):
			pollAttempts++
			// Return 500 Internal Server Error (transient error)
			w.WriteHeader(http.StatusInternalServerError)
			_, _ = w.Write([]byte("internal gateway crash"))
		default:
			http.NotFound(w, r)
		}
	}))
	defer server.Close()

	dummyAudio := filepath.Join(t.TempDir(), "silence.mp3")
	monoFrame := []byte{0xFF, 0xFB, 0x90, 0xC0, 0x00, 0x00, 0x00, 0x00}
	_ = os.WriteFile(dummyAudio, monoFrame, 0644)

	client := NewClient(server.URL, DefaultModel)
	client.HTTPClient = server.Client()

	mgr := NewManager(client, nil)
	mgr.PollInterval = 10 * time.Millisecond
	mgr.MaxConsecutivePollErrors = 3

	mgr.StartTask("n-capped", dummyAudio, false, "key", func(body string) error {
		return nil
	})

	for i := 0; i < 50; i++ {
		st := mgr.GetStatus("n-capped")
		if st.State == StateFailed {
			break
		}
		time.Sleep(20 * time.Millisecond)
		if i == 49 {
			t.Fatalf("expected StateFailed, got %s", st.State)
		}
	}

	st := mgr.GetStatus("n-capped")
	if !strings.Contains(st.Error, "连续失败") {
		t.Errorf("expected consecutive failure error, got: %q", st.Error)
	}
	if pollAttempts != 3 {
		t.Errorf("expected exactly 3 poll attempts before capping, got %d", pollAttempts)
	}
}

func TestManager_ConcurrentStartTaskGuard(t *testing.T) {
	uploadCount := 0
	var mu sync.Mutex
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch {
		case r.Method == http.MethodGet && strings.HasPrefix(r.URL.Path, "/api/v1/uploads"):
			mu.Lock()
			uploadCount++
			mu.Unlock()
			w.Header().Set("Content-Type", "application/json")
			_ = json.NewEncoder(w).Encode(map[string]any{
				"data": map[string]any{
					"policy":                 "p",
					"signature":              "s",
					"upload_dir":             "dir",
					"upload_host":            "http://" + r.Host + "/oss-upload",
					"oss_access_key_id":      "k",
					"x_oss_object_acl":       "private",
					"x_oss_forbid_overwrite": "true",
				},
			})
		case r.Method == http.MethodPost && r.URL.Path == "/oss-upload":
			w.WriteHeader(http.StatusOK)
		case r.Method == http.MethodPost && strings.HasPrefix(r.URL.Path, "/api/v1/services/audio/asr/transcription"):
			w.Header().Set("Content-Type", "application/json")
			_ = json.NewEncoder(w).Encode(map[string]any{
				"output": map[string]any{
					"task_id": "c-task-1",
				},
			})
		case r.Method == http.MethodGet && strings.HasPrefix(r.URL.Path, "/api/v1/tasks/c-task-1"):
			w.Header().Set("Content-Type", "application/json")
			_ = json.NewEncoder(w).Encode(map[string]any{
				"output": map[string]any{
					"task_id":     "c-task-1",
					"task_status": "SUCCEEDED",
					"results": []map[string]any{
						{
							"subtask_status":    "SUCCEEDED",
							"transcription_url": "http://" + r.Host + "/res.json",
						},
					},
				},
			})
		case r.Method == http.MethodGet && r.URL.Path == "/res.json":
			w.Header().Set("Content-Type", "application/json")
			_ = json.NewEncoder(w).Encode(map[string]any{
				"sentences": []Sentence{
					{BeginTime: 1000, EndTime: 2000, Text: "内容", SpeakerID: 0},
				},
			})
		default:
			http.NotFound(w, r)
		}
	}))
	defer server.Close()

	dummyAudio := filepath.Join(t.TempDir(), "silence.mp3")
	monoFrame := []byte{0xFF, 0xFB, 0x90, 0xC0, 0x00, 0x00, 0x00, 0x00}
	_ = os.WriteFile(dummyAudio, monoFrame, 0644)

	client := NewClient(server.URL, DefaultModel)
	client.HTTPClient = server.Client()

	mgr := NewManager(client, nil)
	mgr.PollInterval = 10 * time.Millisecond

	// Concurrently call StartTask for the same note 10 times
	var wg sync.WaitGroup
	saveCount := 0
	var saveMu sync.Mutex

	for i := 0; i < 10; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			mgr.StartTask("n-concurrent-guard", dummyAudio, false, "key", func(body string) error {
				saveMu.Lock()
				saveCount++
				saveMu.Unlock()
				return nil
			})
		}()
	}

	wg.Wait()

	// Wait for task to finish
	for i := 0; i < 50; i++ {
		st := mgr.GetStatus("n-concurrent-guard")
		if st.State == StateCompleted {
			break
		}
		time.Sleep(20 * time.Millisecond)
	}

	mu.Lock()
	actualUploads := uploadCount
	mu.Unlock()

	if actualUploads != 1 {
		t.Errorf("expected exactly 1 upload for concurrent StartTask calls on same note, got %d", actualUploads)
	}

	saveMu.Lock()
	actualSaves := saveCount
	saveMu.Unlock()
	if actualSaves != 1 {
		t.Errorf("expected exactly 1 onSave call for concurrent StartTask calls on same note, got %d", actualSaves)
	}
}

func TestManager_PendingConfirmationGuard(t *testing.T) {
	mgr := NewManager(nil, nil)
	noteID := "n-pending-guard"

	// Simulate a note already in StatePendingConfirmation
	mgr.updateStatus(noteID, func(st *ASRTaskStatus) {
		st.State = StatePendingConfirmation
		st.StageMessage = "等待确认替换"
		st.CandidateTranscript = "## 候选逐字稿内容\n\n[00:01](#t=00:01) 测试发言"
	})

	dummyAudio := filepath.Join(t.TempDir(), "dummy.mp3")
	_ = os.WriteFile(dummyAudio, []byte("fake mp3"), 0644)

	// Attempting to StartTask while pending confirmation must be rejected
	started := mgr.StartTask(noteID, dummyAudio, false, "key", func(body string) error {
		return nil
	})
	if started {
		t.Fatalf("expected StartTask to return false when in StatePendingConfirmation, got true")
	}

	// Verify CandidateTranscript was not cleared
	st := mgr.GetStatus(noteID)
	if st.State != StatePendingConfirmation {
		t.Fatalf("expected StatePendingConfirmation, got %v", st.State)
	}
	if !strings.Contains(st.CandidateTranscript, "候选逐字稿内容") {
		t.Fatalf("expected CandidateTranscript to be preserved, got %q", st.CandidateTranscript)
	}

	// Discarding candidate allows StartTask to succeed
	mgr.DiscardCandidate(noteID)
	st = mgr.GetStatus(noteID)
	if st.State != StateIdle {
		t.Fatalf("expected StateIdle after discard, got %v", st.State)
	}
}

func TestParseMaxFileSizeMB(t *testing.T) {
	cases := []struct {
		input    any
		expected int64
		ok       bool
	}{
		{input: float64(1024), expected: 1024, ok: true},
		{input: float32(512), expected: 512, ok: true},
		{input: int(256), expected: 256, ok: true},
		{input: int64(128), expected: 128, ok: true},
		{input: json.Number("64"), expected: 64, ok: true},
		{input: "32", expected: 32, ok: true},
		{input: "  16  ", expected: 16, ok: true},
		{input: nil, expected: 0, ok: false},
		{input: -1, expected: 0, ok: false},
		{input: "invalid", expected: 0, ok: false},
	}

	for _, c := range cases {
		val, ok := parseMaxFileSizeMB(c.input)
		if ok != c.ok || val != c.expected {
			t.Errorf("parseMaxFileSizeMB(%v) = (%v, %v), want (%v, %v)", c.input, val, ok, c.expected, c.ok)
		}
	}
}

func TestClient_UploadToOSS_SizeLimits(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	}))
	defer server.Close()

	client := NewClient(server.URL, "test-model")
	ctx := context.Background()

	tmpDir := t.TempDir()

	// 1. Empty file (0 bytes)
	emptyPath := filepath.Join(tmpDir, "empty.mp3")
	if err := os.WriteFile(emptyPath, []byte{}, 0644); err != nil {
		t.Fatal(err)
	}
	policy := &UploadPolicy{
		UploadHost: server.URL,
		UploadDir:  "test-dir",
	}
	_, err := client.UploadToOSS(ctx, policy, emptyPath)
	if err == nil || !strings.Contains(err.Error(), "音频文件为空") {
		t.Fatalf("expected empty file error, got: %v", err)
	}

	// 2. Policy MaxFileSizeMB limit exceeded
	smallLimitPath := filepath.Join(tmpDir, "small_limit.mp3")
	f1, err := os.Create(smallLimitPath)
	if err != nil {
		t.Fatal(err)
	}
	_ = f1.Truncate(2 * 1024 * 1024) // 2 MB
	_ = f1.Close()

	policyWithLimit := &UploadPolicy{
		UploadHost:    server.URL,
		UploadDir:     "test-dir",
		MaxFileSizeMB: 1, // 1 MB limit
	}
	_, err = client.UploadToOSS(ctx, policyWithLimit, smallLimitPath)
	if err == nil || !strings.Contains(err.Error(), "超过允许的最大限制") {
		t.Fatalf("expected policy size limit error, got: %v", err)
	}

	// 3. Documented 1 GB limit exceeded
	oversizedPath := filepath.Join(tmpDir, "oversized.mp3")
	f2, err := os.Create(oversizedPath)
	if err != nil {
		t.Fatal(err)
	}
	_ = f2.Truncate(MaxUploadSizeBytes + 1024) // 1 GB + 1 KB (sparse file)
	_ = f2.Close()

	_, err = client.UploadToOSS(ctx, policy, oversizedPath)
	if err == nil || !strings.Contains(err.Error(), "超过允许的最大限制") {
		t.Fatalf("expected 1 GB size limit error, got: %v", err)
	}

	// 4. File within limits succeeds
	normalPath := filepath.Join(tmpDir, "normal.mp3")
	if err := os.WriteFile(normalPath, []byte("fake audio content"), 0644); err != nil {
		t.Fatal(err)
	}
	ossURL, err := client.UploadToOSS(ctx, policy, normalPath)
	if err != nil {
		t.Fatalf("expected successful upload within limit, got: %v", err)
	}
	if !strings.HasPrefix(ossURL, "oss://") {
		t.Fatalf("expected oss:// URL, got %s", ossURL)
	}
}

func TestManager_OversizedFile(t *testing.T) {
	mgr := NewManager(nil, nil)
	tmpDir := t.TempDir()
	oversizedPath := filepath.Join(tmpDir, "oversized.mp3")
	f, err := os.Create(oversizedPath)
	if err != nil {
		t.Fatal(err)
	}
	_ = f.Truncate(MaxUploadSizeBytes + 1024)
	_ = f.Close()

	noteID := "note-oversized-1"
	mgr.StartTask(noteID, oversizedPath, false, "fake-api-key", nil)

	// Wait for pipeline to immediately fail
	deadline := time.Now().Add(2 * time.Second)
	var finalStatus ASRTaskStatus
	for time.Now().Before(deadline) {
		finalStatus = mgr.GetStatus(noteID)
		if finalStatus.State == StateFailed {
			break
		}
		time.Sleep(20 * time.Millisecond)
	}

	if finalStatus.State != StateFailed {
		t.Fatalf("expected StateFailed for oversized audio file, got %v", finalStatus.State)
	}
	if !strings.Contains(finalStatus.Error, "超过允许的最大限制") {
		t.Fatalf("expected error mentioning size limit, got %s", finalStatus.Error)
	}
}

func TestManager_CompletionCallback(t *testing.T) {
	mgr := NewManager(nil, nil)
	tmpDir := t.TempDir()
	p := filepath.Join(tmpDir, "sample.mp3")
	_ = os.WriteFile(p, []byte("audio"), 0644)

	var completedState ASRTaskState
	var called bool

	// Task with empty API key fails immediately in runPipeline
	mgr.StartTask("n-cleanup", p, false, "", nil, func(state ASRTaskState) {
		called = true
		completedState = state
	})

	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		if called {
			break
		}
		time.Sleep(10 * time.Millisecond)
	}

	if !called {
		t.Fatalf("expected completion callback to be called")
	}
	if completedState != StateFailed {
		t.Fatalf("expected StateFailed, got %v", completedState)
	}
}

func TestManager_ResetFencesOldTaskGenerations(t *testing.T) {
	// Server that delays responding to simulate an in-flight request
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		time.Sleep(500 * time.Millisecond)
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"data":{"policy":"fake","upload_host":"http://fake"}}`))
	}))
	defer server.Close()

	client := NewClient("", "")
	client.BaseURL = server.URL
	mgr := NewManager(client, nil)

	tmpDir := t.TempDir()
	p := filepath.Join(tmpDir, "sample.mp3")
	_ = os.WriteFile(p, []byte("fake mp3"), 0644)

	noteID := "n-fence-test"
	var callbackCalled bool
	mgr.StartTask(noteID, p, false, "key", nil, func(state ASRTaskState) {
		callbackCalled = true
	})

	// Wait briefly to ensure task enters uploading state
	time.Sleep(20 * time.Millisecond)
	st := mgr.GetStatus(noteID)
	if st.State != StateUploading {
		t.Fatalf("expected StateUploading, got %v", st.State)
	}

	// Reset manager (simulating vault switch)
	mgr.Reset()

	// Immediately after Reset, status must be StateIdle
	if stAfter := mgr.GetStatus(noteID); stAfter.State != StateIdle {
		t.Fatalf("expected StateIdle immediately after Reset, got %v", stAfter.State)
	}

	// Wait past the in-flight server delay to ensure old task cancels/finishes
	time.Sleep(600 * time.Millisecond)

	// Old task must NOT have recreated status or modified tasks
	if stFinal := mgr.GetStatus(noteID); stFinal.State != StateIdle {
		t.Fatalf("expected StateIdle to remain after old canceled task completes, got %v", stFinal.State)
	}

	// Stale task's completion callback must NOT have been called
	if callbackCalled {
		t.Fatalf("expected stale task's completion callback to be dropped after Reset, but was called")
	}
}

func TestManager_ResetAndRestartSameNotePreservesNewTaskCancel(t *testing.T) {
	task1Entered := make(chan struct{})
	task2Block := make(chan struct{})
	var callCount int
	var mu sync.Mutex

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		mu.Lock()
		callCount++
		current := callCount
		mu.Unlock()

		if current == 1 {
			close(task1Entered)
			// Wait for cancel from context
			<-r.Context().Done()
			return
		}
		// Task 2: block until test releases it
		<-task2Block
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"data":{"policy":"fake","upload_host":"http://fake"}}`))
	}))
	defer server.Close()
	defer close(task2Block)

	client := NewClient("", "")
	client.BaseURL = server.URL
	mgr := NewManager(client, nil)

	tmpDir := t.TempDir()
	p := filepath.Join(tmpDir, "sample.mp3")
	monoFrame := []byte{0xFF, 0xFB, 0x90, 0xC0, 0x00, 0x00, 0x00, 0x00}
	_ = os.WriteFile(p, monoFrame, 0644)

	noteID := "n-cancel-scope-test"
	mgr.StartTask(noteID, p, false, "key", nil)

	// Wait for task 1 to reach HTTP server (so ctx & cancel are registered)
	select {
	case <-task1Entered:
	case <-time.After(2 * time.Second):
		t.Fatalf("timed out waiting for task 1 to start")
	}

	// Reset manager (cancels task 1)
	mgr.Reset()

	// Start new task 2 with the same noteID
	started := mgr.StartTask(noteID, p, false, "key", nil)
	if !started {
		t.Fatalf("expected new task to start successfully after Reset")
	}

	// Wait briefly for task 2 to register its cancel and task 1's defer to execute
	time.Sleep(100 * time.Millisecond)

	// Verify that task 1's defer did NOT delete task 2's cancel func
	mgr.mu.Lock()
	cancelFn := mgr.cancels[noteID]
	gen := mgr.taskGenerations[noteID]
	mgr.mu.Unlock()

	if cancelFn == nil {
		t.Fatalf("expected new task's cancel function to still be present in manager, but was deleted by old task defer")
	}
	if gen == 0 {
		t.Fatalf("expected task generation to be tracked for task 2")
	}
}






