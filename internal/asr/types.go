package asr

import "time"

const (
	DefaultProvider = "阿里云百炼"
	DefaultModel    = "qwen-audio-3.1-asr-flash-filetrans"
	DefaultRegion   = "华北2（北京）"
	DefaultBaseURL  = "https://dashscope.aliyuncs.com"
)

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
