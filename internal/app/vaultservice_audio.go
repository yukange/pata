package app

import (
	"encoding/base64"
	"fmt"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/wailsapp/wails/v3/pkg/application"

	"pata/internal/asr"
	"pata/internal/storage/markdown"
)

type transcriptRecord struct {
	vault        *markdown.Vault
	baseline     *markdown.FileBaseline
	expectedBody string
}

func (s *VaultService) getASRManager() *asr.Manager {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.asrManager == nil {
		s.asrManager = asr.NewManager(asr.NewClient("", ""), s.dispatchEvent)
	}
	return s.asrManager
}

func (s *VaultService) setASRClient(c *asr.Client) {
	mgr := s.getASRManager()
	mgr.SetClient(c)
}

func isSupportedAudioExt(ext string) bool {
	ext = strings.ToLower(ext)
	return ext == ".mp3" || ext == ".m4a"
}

// SelectAudioFile opens a native dialog for selecting an audio file (MP3 / M4A).
func (s *VaultService) SelectAudioFile() (string, error) {
	app := application.Get()
	if app == nil || app.Dialog == nil {
		return "", fmt.Errorf("桌面对话框不可用")
	}
	dialog := app.Dialog.OpenFile()
	dialog.SetTitle("选择要转写的音频文件")
	dialog.CanChooseFiles(true)
	dialog.CanChooseDirectories(false)
	dialog.AddFilter("音频文件 (*.mp3;*.m4a)", "*.mp3;*.m4a")
	dialog.AddFilter("MP3 音频 (*.mp3)", "*.mp3")
	dialog.AddFilter("M4A 音频 (*.m4a)", "*.m4a")
	path, err := dialog.PromptForSingleSelection()
	if err != nil {
		return "", fmt.Errorf("打开文件选择器失败: %w", err)
	}
	return path, nil
}

// CreateAudioNote imports an audio file (MP3 / M4A) into files/, creates an audio transcript Note immediately,
// and starts the asynchronous transcription pipeline in the background.
func (s *VaultService) CreateAudioNote(sourcePath string) (*markdown.Note, error) {
	cleanSrc := filepath.Clean(strings.TrimSpace(sourcePath))
	ext := strings.ToLower(filepath.Ext(cleanSrc))
	if !isSupportedAudioExt(ext) {
		return nil, fmt.Errorf("仅支持导入 MP3 或 M4A 格式音频文件")
	}

	// Try retrieving API key (if unconfigured, task will report failure, but Note and audio file are preserved)
	apiKey, _ := s.getASRKeyInternal()

	// 1. Import file to files/ (copies without overwriting)
	res, err := s.ImportFile(cleanSrc)
	if err != nil {
		return nil, fmt.Errorf("导入音频文件失败: %w", err)
	}

	s.mu.Lock()
	v := s.vault
	s.mu.Unlock()
	if v == nil {
		return nil, fmt.Errorf("尚未打开 Vault")
	}
	v.MutationMu.Lock()
	defer v.MutationMu.Unlock()

	// Derive default note title from base name without audio extension
	title := strings.TrimSuffix(res.Name, filepath.Ext(res.Name))
	if strings.TrimSpace(title) == "" {
		title = "音频逐字稿"
	}

	now := time.Now()
	note := &markdown.Note{
		Type:            markdown.EntityTypeNote,
		ID:              markdown.GenerateEntityID(markdown.EntityTypeNote),
		Title:           title,
		Tags:            []string{},
		AudioFile:       res.Path,
		AudioTranscript: true,
		CreatedAt:       now,
		UpdatedAt:       now,
		Body:            "",
	}

	initBaseline, err := v.SaveEntity(note, nil)
	if err != nil {
		return nil, fmt.Errorf("创建逐字稿笔记失败: %w", err)
	}

	noteID := note.ID
	rec := &transcriptRecord{
		vault:        v,
		baseline:     initBaseline,
		expectedBody: "",
	}
	s.mu.Lock()
	if s.transcriptRecords == nil {
		s.transcriptRecords = make(map[string]*transcriptRecord)
	}
	s.transcriptRecords[noteID] = rec
	s.mu.Unlock()

	// 2. Start asynchronous transcription in background
	originVault := v
	audioAbsPath := filepath.Join(v.RootPath, filepath.FromSlash(res.Path))
	mgr := s.getASRManager()
	cleanup := func(state asr.ASRTaskState) {
		if state == asr.StateFailed || state == asr.StateCompleted {
			s.mu.Lock()
			if s.transcriptRecords != nil && s.transcriptRecords[noteID] == rec {
				delete(s.transcriptRecords, noteID)
			}
			s.mu.Unlock()
		}
	}
	if !mgr.StartTask(noteID, audioAbsPath, false, apiKey, func(transcriptBody string) error {
		return s.saveTranscriptBody(originVault, noteID, transcriptBody)
	}, cleanup) {
		s.mu.Lock()
		if s.transcriptRecords != nil && s.transcriptRecords[noteID] == rec {
			delete(s.transcriptRecords, noteID)
		}
		s.mu.Unlock()
	}

	return note, nil
}

// CreateAudioNoteData imports base64 audio data (MP3 / M4A) into files/, creates an audio transcript Note immediately,
// and starts the asynchronous transcription pipeline in the background.
func (s *VaultService) CreateAudioNoteData(name string, base64Data string) (*markdown.Note, error) {
	cleanName := filepath.Base(strings.TrimSpace(name))
	ext := strings.ToLower(filepath.Ext(cleanName))
	if !isSupportedAudioExt(ext) {
		return nil, fmt.Errorf("仅支持导入 MP3 或 M4A 格式音频文件")
	}

	apiKey, _ := s.getASRKeyInternal()

	res, err := s.ImportFileData(cleanName, base64Data)
	if err != nil {
		return nil, fmt.Errorf("导入音频数据失败: %w", err)
	}

	s.mu.Lock()
	v := s.vault
	s.mu.Unlock()
	if v == nil {
		return nil, fmt.Errorf("尚未打开 Vault")
	}
	v.MutationMu.Lock()
	defer v.MutationMu.Unlock()

	title := strings.TrimSuffix(res.Name, filepath.Ext(res.Name))
	if strings.TrimSpace(title) == "" {
		title = "音频逐字稿"
	}

	now := time.Now()
	note := &markdown.Note{
		Type:            markdown.EntityTypeNote,
		ID:              markdown.GenerateEntityID(markdown.EntityTypeNote),
		Title:           title,
		Tags:            []string{},
		AudioFile:       res.Path,
		AudioTranscript: true,
		CreatedAt:       now,
		UpdatedAt:       now,
		Body:            "",
	}

	initBaseline, err := v.SaveEntity(note, nil)
	if err != nil {
		return nil, fmt.Errorf("创建逐字稿笔记失败: %w", err)
	}

	noteID := note.ID
	rec := &transcriptRecord{
		vault:        v,
		baseline:     initBaseline,
		expectedBody: "",
	}
	s.mu.Lock()
	if s.transcriptRecords == nil {
		s.transcriptRecords = make(map[string]*transcriptRecord)
	}
	s.transcriptRecords[noteID] = rec
	s.mu.Unlock()

	originVault := v
	audioAbsPath := filepath.Join(v.RootPath, filepath.FromSlash(res.Path))
	mgr := s.getASRManager()
	cleanup := func(state asr.ASRTaskState) {
		if state == asr.StateFailed || state == asr.StateCompleted {
			s.mu.Lock()
			if s.transcriptRecords != nil && s.transcriptRecords[noteID] == rec {
				delete(s.transcriptRecords, noteID)
			}
			s.mu.Unlock()
		}
	}
	if !mgr.StartTask(noteID, audioAbsPath, false, apiKey, func(transcriptBody string) error {
		return s.saveTranscriptBody(originVault, noteID, transcriptBody)
	}, cleanup) {
		s.mu.Lock()
		if s.transcriptRecords != nil && s.transcriptRecords[noteID] == rec {
			delete(s.transcriptRecords, noteID)
		}
		s.mu.Unlock()
	}

	return note, nil
}

func (s *VaultService) saveTranscriptBody(v *markdown.Vault, noteID string, transcriptBody string) error {
	s.mu.Lock()
	activeVault := s.vault
	s.mu.Unlock()
	if activeVault == nil || v == nil {
		return fmt.Errorf("Vault 为空")
	}
	if filepath.Clean(v.RootPath) != filepath.Clean(activeVault.RootPath) {
		return fmt.Errorf("逐字稿任务所属 Vault 与当前激活 Vault 不一致，已取消写入")
	}
	if strings.TrimSpace(transcriptBody) == "" {
		return fmt.Errorf("逐字稿内容为空，未识别到有效内容")
	}
	v = activeVault
	v.MutationMu.Lock()
	defer v.MutationMu.Unlock()

	existing, ok := v.Index.GetNote(noteID)
	if !ok {
		return fmt.Errorf("目标笔记不存在: %s", noteID)
	}

	s.mu.Lock()
	var rec *transcriptRecord
	if s.transcriptRecords != nil {
		rec = s.transcriptRecords[noteID]
	}
	s.mu.Unlock()

	// Reject if note's body was modified externally
	if rec != nil {
		if strings.TrimSpace(existing.Body) != strings.TrimSpace(rec.expectedBody) {
			return fmt.Errorf("笔记正文在生成逐字稿期间已被外部修改，已取消写入以保护外部编辑")
		}
	}

	// Reject if external editor changed the file (trusted in-app UpdateNote updates rec.baseline)
	currentBaseline := noteBaseline(v, existing)
	if rec != nil && rec.baseline != nil && currentBaseline != nil {
		if rec.baseline.Hash != currentBaseline.Hash {
			return fmt.Errorf("笔记在生成逐字稿期间已被外部修改，已取消写入以保护外部编辑")
		}
	}

	existing.Body = transcriptBody
	existing.UpdatedAt = time.Now()

	saveBaseline := currentBaseline
	if rec != nil && rec.baseline != nil {
		saveBaseline = rec.baseline
	}
	if _, err := v.SaveEntity(existing, saveBaseline); err != nil {
		return err
	}

	s.mu.Lock()
	if s.transcriptRecords != nil {
		delete(s.transcriptRecords, noteID)
	}
	s.mu.Unlock()

	return nil
}

// StartAudioTranscription triggers or retries transcription on an existing Note.
func (s *VaultService) StartAudioTranscription(noteID string) error {
	s.mu.Lock()
	v := s.vault
	s.mu.Unlock()
	if v == nil {
		return fmt.Errorf("尚未打开 Vault")
	}
	v.MutationMu.Lock()
	defer v.MutationMu.Unlock()

	trimmedID := strings.TrimSpace(noteID)
	if trimmedID == "" {
		return fmt.Errorf("笔记 ID 不能为空")
	}

	mgr := s.getASRManager()
	currStatus := mgr.GetStatus(trimmedID)
	if currStatus.State == asr.StatePendingConfirmation {
		return fmt.Errorf("当前逐字稿已有待确认的新结果，请先确认替换或放弃")
	}
	if currStatus.State == asr.StateUploading || currStatus.State == asr.StateTranscribing || currStatus.State == asr.StateWriting {
		return fmt.Errorf("当前笔记已有正在进行的转写任务")
	}

	note, ok := v.Index.GetNote(trimmedID)
	if !ok {
		mgr.SetTaskFailed(trimmedID, "笔记不存在", fmt.Sprintf("笔记不存在: %s", trimmedID))
		return fmt.Errorf("笔记不存在: %s", trimmedID)
	}

	if !note.AudioTranscript || note.AudioFile == "" {
		mgr.SetTaskFailed(trimmedID, "类型错误", "该笔记不是音频逐字稿笔记")
		return fmt.Errorf("该笔记不是音频逐字稿笔记")
	}

	apiKey, err := s.getASRKeyInternal()
	if err != nil {
		mgr.SetTaskFailed(trimmedID, "未配置 API Key", err.Error())
		return err
	}

	audioAbsPath, err := s.resolveSafeFilePath(note.AudioFile)
	if err != nil {
		mgr.SetTaskFailed(trimmedID, "音频文件失效", "关联音频文件不存在或失效: "+err.Error())
		return fmt.Errorf("关联音频文件不存在或失效: %w", err)
	}

	isRetranscribe := strings.TrimSpace(note.Body) != ""
	var initBaseline *markdown.FileBaseline
	b := noteBaseline(v, note)
	if b != nil {
		cp := *b
		initBaseline = &cp
	}
	rec := &transcriptRecord{
		vault:        v,
		baseline:     initBaseline,
		expectedBody: note.Body,
	}
	s.mu.Lock()
	if s.transcriptRecords == nil {
		s.transcriptRecords = make(map[string]*transcriptRecord)
	}
	s.transcriptRecords[trimmedID] = rec
	s.mu.Unlock()

	originVault := v
	cleanup := func(state asr.ASRTaskState) {
		if state == asr.StateFailed || state == asr.StateCompleted {
			s.mu.Lock()
			if s.transcriptRecords != nil && s.transcriptRecords[trimmedID] == rec {
				delete(s.transcriptRecords, trimmedID)
			}
			s.mu.Unlock()
		}
	}
	if !mgr.StartTask(trimmedID, audioAbsPath, isRetranscribe, apiKey, func(transcriptBody string) error {
		return s.saveTranscriptBody(originVault, trimmedID, transcriptBody)
	}, cleanup) {
		s.mu.Lock()
		if s.transcriptRecords != nil && s.transcriptRecords[trimmedID] == rec {
			delete(s.transcriptRecords, trimmedID)
		}
		s.mu.Unlock()
		return fmt.Errorf("当前逐字稿已有正在进行的转写任务或等待确认")
	}

	return nil
}

// GetASRTaskStatus returns the current in-memory transcription status for a note.
func (s *VaultService) GetASRTaskStatus(noteID string) (asr.ASRTaskStatus, error) {
	trimmedID := strings.TrimSpace(noteID)
	if trimmedID == "" {
		return asr.ASRTaskStatus{}, fmt.Errorf("笔记 ID 不能为空")
	}
	mgr := s.getASRManager()
	return mgr.GetStatus(trimmedID), nil
}

// ConfirmReplaceTranscript applies the candidate re-transcription result to the Note body.
func (s *VaultService) ConfirmReplaceTranscript(noteID string) (*markdown.Note, error) {
	trimmedID := strings.TrimSpace(noteID)
	if trimmedID == "" {
		return nil, fmt.Errorf("笔记 ID 不能为空")
	}

	s.mu.Lock()
	var rec *transcriptRecord
	if s.transcriptRecords != nil {
		rec = s.transcriptRecords[trimmedID]
	}
	activeVault := s.vault
	s.mu.Unlock()

	if activeVault == nil {
		return nil, fmt.Errorf("尚未打开 Vault")
	}
	activeVault.MutationMu.Lock()
	defer activeVault.MutationMu.Unlock()

	if rec != nil && rec.vault != nil && filepath.Clean(rec.vault.RootPath) != filepath.Clean(activeVault.RootPath) {
		return nil, fmt.Errorf("逐字稿任务所属 Vault 与当前激活 Vault 不一致，已取消替换")
	}

	targetVault := activeVault
	var candidateBaseline *markdown.FileBaseline
	if rec != nil {
		candidateBaseline = rec.baseline
	}

	mgr := s.getASRManager()
	var updatedNote *markdown.Note
	err := mgr.ConfirmReplace(trimmedID, func(transcriptBody string) error {
		existing, ok := targetVault.Index.GetNote(trimmedID)
		if !ok {
			return fmt.Errorf("笔记不存在: %s", trimmedID)
		}

		// Reject replacement if note's body was modified externally
		if rec != nil {
			if strings.TrimSpace(existing.Body) != strings.TrimSpace(rec.expectedBody) {
				return fmt.Errorf("笔记在生成逐字稿候选期间正文已被外部修改，已取消替换以保护外部编辑")
			}
		}

		// Reject replacement if note was modified externally since candidate was generated
		currentBaseline := noteBaseline(targetVault, existing)
		if candidateBaseline != nil && currentBaseline != nil {
			if candidateBaseline.Hash != currentBaseline.Hash {
				return fmt.Errorf("笔记在生成逐字稿候选期间已被外部修改，已取消替换以保护外部编辑")
			}
		}

		existing.Body = transcriptBody
		existing.UpdatedAt = time.Now()
		// Save with candidateBaseline so disk-level concurrency check catches external edits
		if _, err := targetVault.SaveEntity(existing, candidateBaseline); err != nil {
			return err
		}
		updatedNote = existing
		return nil
	})
	if err != nil {
		return nil, err
	}

	s.mu.Lock()
	if s.transcriptRecords != nil && s.transcriptRecords[trimmedID] == rec {
		delete(s.transcriptRecords, trimmedID)
	}
	s.mu.Unlock()

	return updatedNote, nil
}

// DiscardCandidateTranscript discards candidate re-transcription results.
func (s *VaultService) DiscardCandidateTranscript(noteID string) error {
	trimmedID := strings.TrimSpace(noteID)
	if trimmedID == "" {
		return fmt.Errorf("笔记 ID 不能为空")
	}
	s.mu.Lock()
	if s.transcriptRecords != nil {
		delete(s.transcriptRecords, trimmedID)
	}
	s.mu.Unlock()

	mgr := s.getASRManager()
	mgr.DiscardCandidate(trimmedID)
	return nil
}

// GetAudioURL returns the internal asset URL to stream/play a vault audio file.
func (s *VaultService) GetAudioURL(filePath string) (string, error) {
	_, err := s.resolveSafeFilePath(filePath)
	if err != nil {
		return "", err
	}
	cleanRel := filepath.ToSlash(filepath.Clean(strings.TrimSpace(filePath)))
	cleanRel = strings.TrimPrefix(cleanRel, "/")
	segments := strings.Split(cleanRel, "/")
	for i, seg := range segments {
		segments[i] = url.PathEscape(seg)
	}
	return "/vault-audio/" + strings.Join(segments, "/"), nil
}

// GetAudioData returns the base64 data URI of a vault audio file (fallback/testing).
func (s *VaultService) GetAudioData(filePath string) (string, error) {
	absPath, err := s.resolveSafeFilePath(filePath)
	if err != nil {
		return "", err
	}
	data, err := os.ReadFile(absPath)
	if err != nil {
		return "", fmt.Errorf("读取音频文件失败: %w", err)
	}
	encoded := base64.StdEncoding.EncodeToString(data)
	ext := strings.ToLower(filepath.Ext(absPath))
	mimeType := "audio/mpeg"
	if ext == ".m4a" {
		mimeType = "audio/mp4"
	}
	return fmt.Sprintf("data:%s;base64,%s", mimeType, encoded), nil
}
