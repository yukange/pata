package asr

import (
	"fmt"
	"time"
)

const (
	DefaultProvider = "阿里云百炼"
	DefaultModel    = "qwen-audio-3.1-asr-flash-filetrans"
	DefaultRegion   = "华北2（北京）"
	DefaultBaseURL  = "https://dashscope.aliyuncs.com"

	// MaxUploadSizeBytes defines the maximum allowed audio upload size (1 GB).
	MaxUploadSizeBytes int64 = 1024 * 1024 * 1024
)

// APIError represents an error response from the DashScope API.
type APIError struct {
	StatusCode int    `json:"status_code"`
	Code       string `json:"code,omitempty"`
	Message    string `json:"message,omitempty"`
}

func (e *APIError) Error() string {
	if e.Code != "" && e.Message != "" {
		return fmt.Sprintf("API 错误 (%s): %s", e.Code, e.Message)
	}
	if e.Message != "" {
		return fmt.Sprintf("API 错误 (HTTP %d): %s", e.StatusCode, e.Message)
	}
	return fmt.Sprintf("API 请求失败，HTTP 状态码: %d", e.StatusCode)
}

// IsPermanent returns true if the error indicates a permanent failure that shouldn't be retried.
func (e *APIError) IsPermanent() bool {
	// 400 Bad Request, 401 Unauthorized, 403 Forbidden, 404 Not Found, 422 Unprocessable Entity
	// Note: 429 Too Many Requests and 408 Request Timeout are usually transient.
	return e.StatusCode >= 400 && e.StatusCode < 500 && e.StatusCode != 429 && e.StatusCode != 408
}

// UploadPolicy contains temporary credentials and endpoint returned by DashScope.
type UploadPolicy struct {
	Policy              string `json:"policy"`
	Signature           string `json:"signature"`
	UploadDir           string `json:"upload_dir"`
	UploadHost          string `json:"upload_host"`
	ExpireInSeconds     any    `json:"expire_in_seconds"`
	MaxFileSizeMB       any    `json:"max_file_size_mb"`
	OSSAccessKeyID      string `json:"oss_access_key_id"`
	XOSSObjectACL       string `json:"x_oss_object_acl"`
	XOSSForbidOverwrite string `json:"x_oss_forbid_overwrite"`
}

// Sentence represents a single recognized sentence with timestamps and speaker attribution.
type Sentence struct {
	BeginTime int    `json:"begin_time"` // in ms
	EndTime   int    `json:"end_time"`   // in ms
	Text      string `json:"text"`
	SpeakerID int    `json:"speaker_id"`
}

// ASRTaskState represents the current state of an in-flight or completed transcription.
type ASRTaskState string

const (
	StateIdle                ASRTaskState = "idle"
	StateUploading           ASRTaskState = "uploading"
	StateTranscribing        ASRTaskState = "transcribing"
	StateWriting             ASRTaskState = "writing"
	StatePendingConfirmation ASRTaskState = "pending_confirmation"
	StateCompleted           ASRTaskState = "completed"
	StateFailed              ASRTaskState = "failed"
)

// ASRTaskStatus reports the transcription progress to frontend.
type ASRTaskStatus struct {
	NoteID              string       `json:"note_id"`
	State               ASRTaskState `json:"state"`
	StageMessage        string       `json:"stage_message"`
	Error               string       `json:"error,omitempty"`
	Warning             string       `json:"warning,omitempty"`
	CandidateTranscript string       `json:"candidate_transcript,omitempty"`
	UpdatedAt           time.Time    `json:"updated_at"`
}
