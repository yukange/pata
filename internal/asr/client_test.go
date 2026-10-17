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
