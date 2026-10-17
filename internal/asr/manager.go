package asr

import (
	"context"
	"fmt"
	"log"
	"strings"
	"sync"
	"time"
)

// EventASRStatus is emitted when an ASR task state changes.
const EventASRStatus = "asr:status"

// SaveTranscriptFunc writes the generated markdown transcript to disk safely.
type SaveTranscriptFunc func(transcriptMarkdown string) error

// Manager manages in-memory ASR tasks for Notes across view navigation.
type Manager struct {
	mu           sync.Mutex
	tasks        map[string]*ASRTaskStatus
	client       *Client
	emitFunc     func(name string, data any)
	PollInterval time.Duration
}

// NewManager creates an ASR Manager.
func NewManager(client *Client, emitFunc func(name string, data any)) *Manager {
	if client == nil {
		client = NewClient("", "")
	}
	return &Manager{
		tasks:        make(map[string]*ASRTaskStatus),
		client:       client,
		emitFunc:     emitFunc,
		PollInterval: 2 * time.Second,
	}
}

// SetClient updates the underlying DashScope client (useful for unit testing).
func (m *Manager) SetClient(c *Client) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.client = c
}

// GetStatus returns the current transcription status for a note.
func (m *Manager) GetStatus(noteID string) ASRTaskStatus {
	m.mu.Lock()
	defer m.mu.Unlock()

	if st, ok := m.tasks[noteID]; ok {
		return *st
	}
	return ASRTaskStatus{
		NoteID:    noteID,
		State:     StateIdle,
		UpdatedAt: time.Now(),
	}
}

func (m *Manager) updateStatus(noteID string, fn func(st *ASRTaskStatus)) ASRTaskStatus {
	m.mu.Lock()
	st, ok := m.tasks[noteID]
	if !ok {
		st = &ASRTaskStatus{
			NoteID: noteID,
			State:  StateIdle,
		}
		m.tasks[noteID] = st
	}
	fn(st)
	st.UpdatedAt = time.Now()
	copySt := *st
	emit := m.emitFunc
	m.mu.Unlock()

	if emit != nil {
		emit(EventASRStatus, copySt)
	}
	return copySt
}

// StartTask launches the asynchronous upload and transcription pipeline in the background.
func (m *Manager) StartTask(
	noteID string,
	audioAbsPath string,
	isRetranscribe bool,
	apiKey string,
	onSave SaveTranscriptFunc,
) {
	// Guard against starting duplicate active tasks on same note
	m.mu.Lock()
	existing, ok := m.tasks[noteID]
	if ok && (existing.State == StateUploading || existing.State == StateTranscribing || existing.State == StateWriting) {
		m.mu.Unlock()
		return
	}
	m.mu.Unlock()

	m.updateStatus(noteID, func(st *ASRTaskStatus) {
		st.State = StateUploading
		st.StageMessage = "正在上传音频..."
		st.Error = ""
		st.CandidateTranscript = ""
	})

	go m.runPipeline(noteID, audioAbsPath, isRetranscribe, apiKey, onSave)
}

func (m *Manager) runPipeline(
	noteID string,
	audioAbsPath string,
	isRetranscribe bool,
	apiKey string,
	onSave SaveTranscriptFunc,
) {
	if strings.TrimSpace(apiKey) == "" {
		m.updateStatus(noteID, func(st *ASRTaskStatus) {
			st.State = StateFailed
			st.StageMessage = "未配置 API Key"
			st.Error = "未配置语音转写 API Key，请先在「设置 - 语音转写」中配置后重试"
		})
		return
	}

	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Minute)
	defer cancel()

	// 1. Audio Preprocessing (channel check, mono downmixing for diarization)
	targetAudioPath, warning, cleanup, prepErr := PrepareAudioForDiarization(audioAbsPath)
	defer cleanup()
	if prepErr != nil {
		m.updateStatus(noteID, func(st *ASRTaskStatus) {
			st.State = StateFailed
			st.StageMessage = "音频预处理失败"
			st.Error = prepErr.Error()
		})
		return
	}

	if warning != "" {
		m.updateStatus(noteID, func(st *ASRTaskStatus) {
			st.Warning = warning
		})
	}

	// 2. Request upload policy
	m.updateStatus(noteID, func(st *ASRTaskStatus) {
		st.State = StateUploading
		st.StageMessage = "正在获取上传凭证..."
	})

	m.mu.Lock()
	client := m.client
	m.mu.Unlock()

	policy, err := client.GetUploadPolicy(ctx, apiKey)
	if err != nil {
		m.updateStatus(noteID, func(st *ASRTaskStatus) {
			st.State = StateFailed
			st.StageMessage = "获取上传凭证失败"
			st.Error = err.Error()
		})
		return
	}

	// 3. Upload file to DashScope temporary OSS
	m.updateStatus(noteID, func(st *ASRTaskStatus) {
		st.State = StateUploading
		st.StageMessage = "正在上传音频文件..."
	})

	ossURL, err := client.UploadToOSS(ctx, policy, targetAudioPath)
	if err != nil {
		m.updateStatus(noteID, func(st *ASRTaskStatus) {
			st.State = StateFailed
			st.StageMessage = "音频上传失败"
			st.Error = err.Error()
		})
		return
	}

	// 4. Submit transcription task
	m.updateStatus(noteID, func(st *ASRTaskStatus) {
		st.State = StateUploading
		st.StageMessage = "正在提交转写任务..."
	})

	taskID, err := client.SubmitTask(ctx, apiKey, ossURL, true)
	if err != nil {
		m.updateStatus(noteID, func(st *ASRTaskStatus) {
			st.State = StateFailed
			st.StageMessage = "提交转写任务失败"
			st.Error = err.Error()
		})
		return
	}

	// 5. Poll task status
	m.updateStatus(noteID, func(st *ASRTaskStatus) {
		st.State = StateTranscribing
		st.StageMessage = "正在转写音频..."
	})

	interval := m.PollInterval
	if interval <= 0 {
		interval = 2 * time.Second
	}
	pollTicker := time.NewTicker(interval)
	defer pollTicker.Stop()

	var transcriptionURL string
	for {
		select {
		case <-ctx.Done():
			m.updateStatus(noteID, func(st *ASRTaskStatus) {
				st.State = StateFailed
				st.StageMessage = "转写请求超时"
				st.Error = "请求等待超时，请稍后重试"
			})
			return

		case <-pollTicker.C:
			res, err := client.PollTask(ctx, apiKey, taskID)
			if err != nil {
				log.Printf("asr: poll task %s transient error: %v", taskID, err)
				continue
			}

			switch res.Output.TaskStatus {
			case "PENDING", "RUNNING":
				// continue polling
			case "SUCCEEDED":
				if len(res.Output.Results) > 0 {
					transcriptionURL = res.Output.Results[0].TranscriptionURL
					if res.Output.Results[0].SubtaskStatus == "FAILED" {
						m.updateStatus(noteID, func(st *ASRTaskStatus) {
							st.State = StateFailed
							st.StageMessage = "音频转写失败"
							st.Error = res.Output.Results[0].Message
						})
						return
					}
				}
				if transcriptionURL == "" && res.Output.TranscriptionURL != "" {
					transcriptionURL = res.Output.TranscriptionURL
				}
				goto TaskCompleted

			case "FAILED":
				errMsg := res.Output.Message
				if errMsg == "" {
					errMsg = res.Message
				}
				if errMsg == "" {
					errMsg = "百炼服务端识别失败"
				}
				m.updateStatus(noteID, func(st *ASRTaskStatus) {
					st.State = StateFailed
					st.StageMessage = "转写失败"
					st.Error = errMsg
				})
				return

			default:
				log.Printf("asr: unknown status %s for task %s", res.Output.TaskStatus, taskID)
			}
		}
	}

TaskCompleted:
	if transcriptionURL == "" {
		m.updateStatus(noteID, func(st *ASRTaskStatus) {
			st.State = StateFailed
			st.StageMessage = "转写失败"
			st.Error = "未获取到逐字稿结果 URL"
		})
		return
	}

	// 6. Download and format transcription
	m.updateStatus(noteID, func(st *ASRTaskStatus) {
		st.State = StateWriting
		st.StageMessage = "正在下载逐字稿结果..."
	})

	sentences, err := client.FetchTranscriptionResult(ctx, transcriptionURL)
	if err != nil {
		m.updateStatus(noteID, func(st *ASRTaskStatus) {
			st.State = StateFailed
			st.StageMessage = "获取逐字稿结果失败"
			st.Error = err.Error()
		})
		return
	}

	formattedMarkdown := FormatTranscriptMarkdown(sentences)
	if strings.TrimSpace(formattedMarkdown) == "" {
		m.updateStatus(noteID, func(st *ASRTaskStatus) {
			st.State = StateFailed
			st.StageMessage = "未识别到有效语音内容"
			st.Error = "未识别到有效语音内容"
			st.CandidateTranscript = ""
		})
		return
	}

	// 7. Save or require confirmation
	if isRetranscribe {
		// Retranscription: hold candidate transcript for user confirmation
		m.updateStatus(noteID, func(st *ASRTaskStatus) {
			st.State = StatePendingConfirmation
			st.StageMessage = "重新转写完成，等待确认替换"
			st.CandidateTranscript = formattedMarkdown
		})
		return
	}

	// First-time transcription: write directly to Note
	m.updateStatus(noteID, func(st *ASRTaskStatus) {
		st.State = StateWriting
		st.StageMessage = "正在写入逐字稿..."
	})

	if err := onSave(formattedMarkdown); err != nil {
		m.updateStatus(noteID, func(st *ASRTaskStatus) {
			st.State = StateFailed
			st.StageMessage = "保存逐字稿至笔记失败"
			st.Error = err.Error()
		})
		return
	}

	m.updateStatus(noteID, func(st *ASRTaskStatus) {
		st.State = StateCompleted
		st.StageMessage = "转写完成"
		st.CandidateTranscript = ""
		st.Error = ""
	})
}

// ConfirmReplace applies the candidate transcript to the Note via onSave.
func (m *Manager) ConfirmReplace(noteID string, onSave SaveTranscriptFunc) error {
	m.mu.Lock()
	st, ok := m.tasks[noteID]
	if !ok || st.State != StatePendingConfirmation || st.CandidateTranscript == "" {
		m.mu.Unlock()
		return fmt.Errorf("没有待确认的重新转写候选逐字稿")
	}
	candidate := st.CandidateTranscript
	m.mu.Unlock()

	if err := onSave(candidate); err != nil {
		m.updateStatus(noteID, func(s *ASRTaskStatus) {
			s.Error = fmt.Sprintf("替换逐字稿失败: %v", err)
		})
		return err
	}

	m.updateStatus(noteID, func(s *ASRTaskStatus) {
		s.State = StateCompleted
		s.StageMessage = "逐字稿已更新"
		s.CandidateTranscript = ""
		s.Error = ""
	})

	return nil
}

// DiscardCandidate drops the candidate transcript without modifying the note.
func (m *Manager) DiscardCandidate(noteID string) {
	m.updateStatus(noteID, func(st *ASRTaskStatus) {
		st.State = StateIdle
		st.StageMessage = "已保留原有逐字稿"
		st.CandidateTranscript = ""
		st.Error = ""
	})
}

// SetTaskFailed marks a note's transcription task as failed with the given stage message and error.
func (m *Manager) SetTaskFailed(noteID string, stageMsg string, errMsg string) {
	m.updateStatus(noteID, func(st *ASRTaskStatus) {
		st.State = StateFailed
		st.StageMessage = stageMsg
		st.Error = errMsg
	})
}
