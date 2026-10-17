package asr

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

// TaskStatusResponse models DashScope task query output.
type TaskStatusResponse struct {
	Output struct {
		TaskID           string `json:"task_id"`
		TaskStatus       string `json:"task_status"` // PENDING, RUNNING, SUCCEEDED, FAILED
		TranscriptionURL string `json:"transcription_url,omitempty"`
		Code             string `json:"code,omitempty"`
		Message          string `json:"message,omitempty"`
		Results    []struct {
			FileURL          string `json:"file_url"`
			SubtaskStatus    string `json:"subtask_status"`
			TranscriptionURL string `json:"transcription_url"`
			Code             string `json:"code,omitempty"`
			Message          string `json:"message,omitempty"`
		} `json:"results,omitempty"`
	} `json:"output"`
	Code      string `json:"code,omitempty"`
	Message   string `json:"message,omitempty"`
	RequestID string `json:"request_id,omitempty"`
}

// Client interacts with DashScope API endpoints.
type Client struct {
	BaseURL    string
	Model      string
	HTTPClient *http.Client
}

func withOpTimeout(ctx context.Context, defaultTimeout time.Duration) (context.Context, context.CancelFunc) {
	return context.WithTimeout(ctx, defaultTimeout)
}

// NewClient creates a new DashScope ASR Client.
func NewClient(baseURL string, model string) *Client {
	if baseURL == "" {
		baseURL = DefaultBaseURL
	}
	if model == "" {
		model = DefaultModel
	}
	return &Client{
		BaseURL:    strings.TrimRight(baseURL, "/"),
		Model:      model,
		HTTPClient: &http.Client{},
	}
}

// GetUploadPolicy requests a temporary upload policy and lease from DashScope.
func (c *Client) GetUploadPolicy(ctx context.Context, apiKey string) (*UploadPolicy, error) {
	if strings.TrimSpace(apiKey) == "" {
		return nil, fmt.Errorf("API Key 不能为空")
	}

	reqCtx, cancel := withOpTimeout(ctx, 60*time.Second)
	defer cancel()

	reqURL := fmt.Sprintf("%s/api/v1/uploads?action=getPolicy&model=%s", c.BaseURL, url.QueryEscape(c.Model))
	req, err := http.NewRequestWithContext(reqCtx, http.MethodGet, reqURL, nil)
	if err != nil {
		return nil, fmt.Errorf("构建上传策略请求失败: %w", err)
	}

	req.Header.Set("Authorization", "Bearer "+apiKey)
	req.Header.Set("Content-Type", "application/json")

	resp, err := c.HTTPClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("获取上传策略失败: %w", err)
	}
	defer resp.Body.Close()

	bodyBytes, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("读取上传策略响应失败: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		var errResp struct {
			Code    string `json:"code"`
			Message string `json:"message"`
		}
		_ = json.Unmarshal(bodyBytes, &errResp)
		if errResp.Message != "" {
			return nil, fmt.Errorf("DashScope 上传策略接口错误 (%s): %s", errResp.Code, errResp.Message)
		}
		return nil, fmt.Errorf("获取上传策略失败，HTTP 状态码: %d, 响应: %s", resp.StatusCode, string(bodyBytes))
	}

	var policyResp struct {
		Data      UploadPolicy `json:"data"`
		RequestID string       `json:"request_id"`
	}
	if err := json.Unmarshal(bodyBytes, &policyResp); err != nil {
		return nil, fmt.Errorf("解析上传策略失败: %w", err)
	}

	if policyResp.Data.UploadHost == "" || policyResp.Data.Policy == "" {
		return nil, fmt.Errorf("返回的上传策略参数不完整")
	}

	return &policyResp.Data, nil
}

func parseMaxFileSizeMB(v any) (int64, bool) {
	if v == nil {
		return 0, false
	}
	switch val := v.(type) {
	case float64:
		if val > 0 {
			return int64(val), true
		}
	case float32:
		if val > 0 {
			return int64(val), true
		}
	case int:
		if val > 0 {
			return int64(val), true
		}
	case int64:
		if val > 0 {
			return val, true
		}
	case json.Number:
		if n, err := val.Int64(); err == nil && n > 0 {
			return n, true
		}
		if f, err := val.Float64(); err == nil && f > 0 {
			return int64(f), true
		}
	case string:
		var n int64
		if _, err := fmt.Sscanf(strings.TrimSpace(val), "%d", &n); err == nil && n > 0 {
			return n, true
		}
	}
	return 0, false
}

// UploadToOSS uploads a local audio file to the temporary OSS storage specified by policy.
// Returns the oss:// URI.
func (c *Client) UploadToOSS(ctx context.Context, policy *UploadPolicy, filePath string) (string, error) {
	if policy == nil {
		return "", fmt.Errorf("上传策略不能为空")
	}

	f, err := os.Open(filePath)
	if err != nil {
		return "", fmt.Errorf("打开待上传音频文件失败: %w", err)
	}
	defer f.Close()

	fi, err := f.Stat()
	if err != nil {
		return "", fmt.Errorf("获取待上传音频文件信息失败: %w", err)
	}

	if fi.Size() == 0 {
		return "", fmt.Errorf("音频文件为空 (0 字节)")
	}

	effectiveLimit := MaxUploadSizeBytes
	if maxMB, ok := parseMaxFileSizeMB(policy.MaxFileSizeMB); ok {
		policyLimit := maxMB * 1024 * 1024
		if policyLimit > 0 && policyLimit < effectiveLimit {
			effectiveLimit = policyLimit
		}
	}

	if fi.Size() > effectiveLimit {
		return "", fmt.Errorf("音频文件大小 (%d 字节) 超过允许的最大限制 (%d 字节)", fi.Size(), effectiveLimit)
	}

	baseName := filepath.Base(filePath)
	cleanDir := strings.TrimRight(policy.UploadDir, "/")
	ossKey := fmt.Sprintf("%s/%s", cleanDir, baseName)

	var prefix bytes.Buffer
	w := multipart.NewWriter(&prefix)

	// Required form fields according to DashScope policy upload spec:
	// OSSAccessKeyId, policy, Signature, key, x-oss-object-acl, x-oss-forbid-overwrite, success_action_status, file
	_ = w.WriteField("OSSAccessKeyId", policy.OSSAccessKeyID)
	_ = w.WriteField("policy", policy.Policy)
	_ = w.WriteField("Signature", policy.Signature)
	_ = w.WriteField("key", ossKey)
	if policy.XOSSObjectACL != "" {
		_ = w.WriteField("x-oss-object-acl", policy.XOSSObjectACL)
	} else {
		_ = w.WriteField("x-oss-object-acl", "private")
	}
	if policy.XOSSForbidOverwrite != "" {
		_ = w.WriteField("x-oss-forbid-overwrite", policy.XOSSForbidOverwrite)
	} else {
		_ = w.WriteField("x-oss-forbid-overwrite", "true")
	}
	_ = w.WriteField("success_action_status", "200")

	// File MUST be the last field in multipart/form-data for OSS
	_, err = w.CreateFormFile("file", baseName)
	if err != nil {
		return "", fmt.Errorf("创建上传表单文件字段失败: %w", err)
	}

	// Prepare trailer and calculate exact content length so OSS receives Content-Length without chunked encoding
	prefixBytes := prefix.Bytes()
	trailer := fmt.Sprintf("\r\n--%s--\r\n", w.Boundary())
	totalLength := int64(len(prefixBytes)) + fi.Size() + int64(len(trailer))

	bodyReader := io.MultiReader(bytes.NewReader(prefixBytes), f, strings.NewReader(trailer))

	reqCtx, cancel := withOpTimeout(ctx, 20*time.Minute)
	defer cancel()

	req, err := http.NewRequestWithContext(reqCtx, http.MethodPost, policy.UploadHost, bodyReader)
	if err != nil {
		return "", fmt.Errorf("构建 OSS 上传请求失败: %w", err)
	}
	req.ContentLength = totalLength
	req.Header.Set("Content-Type", w.FormDataContentType())

	resp, err := c.HTTPClient.Do(req)
	if err != nil {
		return "", fmt.Errorf("上传音频至 OSS 失败: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK && resp.StatusCode != http.StatusNoContent {
		respBody, _ := io.ReadAll(resp.Body)
		return "", fmt.Errorf("上传至 OSS 失败，HTTP 状态码: %d, 响应: %s", resp.StatusCode, string(respBody))
	}

	return "oss://" + ossKey, nil
}

// SubmitTask submits an asynchronous transcription task to DashScope.
func (c *Client) SubmitTask(ctx context.Context, apiKey string, ossURL string, diarization bool) (string, error) {
	if strings.TrimSpace(apiKey) == "" {
		return "", fmt.Errorf("API Key 不能为空")
	}
	if strings.TrimSpace(ossURL) == "" {
		return "", fmt.Errorf("音频 OSS URL 不能为空")
	}

	payload := map[string]any{
		"model": c.Model,
		"input": map[string]any{
			"file_urls": []string{ossURL},
		},
		"parameters": map[string]any{
			"diarization_enabled": diarization,
		},
	}

	payloadBytes, err := json.Marshal(payload)
	if err != nil {
		return "", fmt.Errorf("序列化转写请求失败: %w", err)
	}

	reqCtx, cancel := withOpTimeout(ctx, 60*time.Second)
	defer cancel()

	reqURL := fmt.Sprintf("%s/api/v1/services/audio/asr/transcription", c.BaseURL)
	req, err := http.NewRequestWithContext(reqCtx, http.MethodPost, reqURL, bytes.NewReader(payloadBytes))
	if err != nil {
		return "", fmt.Errorf("构建转写任务请求失败: %w", err)
	}

	req.Header.Set("Authorization", "Bearer "+apiKey)
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-DashScope-Async", "enable")
	req.Header.Set("X-DashScope-OssResourceResolve", "enable")

	resp, err := c.HTTPClient.Do(req)
	if err != nil {
		return "", fmt.Errorf("提交转写任务请求失败: %w", err)
	}
	defer resp.Body.Close()

	bodyBytes, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", fmt.Errorf("读取转写任务响应失败: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		var errResp struct {
			Code    string `json:"code"`
			Message string `json:"message"`
		}
		_ = json.Unmarshal(bodyBytes, &errResp)
		if errResp.Message != "" {
			return "", fmt.Errorf("提交转写失败 (%s): %s", errResp.Code, errResp.Message)
		}
		return "", fmt.Errorf("提交转写失败，HTTP 状态码: %d, 响应: %s", resp.StatusCode, string(bodyBytes))
	}

	var submitResp struct {
		Output struct {
			TaskID     string `json:"task_id"`
			TaskStatus string `json:"task_status"`
			Code       string `json:"code,omitempty"`
			Message    string `json:"message,omitempty"`
		} `json:"output"`
		Code    string `json:"code,omitempty"`
		Message string `json:"message,omitempty"`
	}
	if err := json.Unmarshal(bodyBytes, &submitResp); err != nil {
		return "", fmt.Errorf("解析转写任务响应失败: %w", err)
	}

	if submitResp.Output.TaskID == "" {
		if submitResp.Output.Message != "" {
			return "", fmt.Errorf("DashScope 拒绝转写任务: %s", submitResp.Output.Message)
		}
		if submitResp.Message != "" {
			return "", fmt.Errorf("DashScope 拒绝转写任务: %s", submitResp.Message)
		}
		return "", fmt.Errorf("DashScope 返回空的 task_id")
	}

	return submitResp.Output.TaskID, nil
}

// PollTask queries the status of an asynchronous transcription task.
func (c *Client) PollTask(ctx context.Context, apiKey string, taskID string) (*TaskStatusResponse, error) {
	if strings.TrimSpace(taskID) == "" {
		return nil, fmt.Errorf("task_id 不能为空")
	}

	reqCtx, cancel := withOpTimeout(ctx, 60*time.Second)
	defer cancel()

	reqURL := fmt.Sprintf("%s/api/v1/tasks/%s", c.BaseURL, url.PathEscape(taskID))
	req, err := http.NewRequestWithContext(reqCtx, http.MethodGet, reqURL, nil)
	if err != nil {
		return nil, fmt.Errorf("构建任务轮询请求失败: %w", err)
	}

	req.Header.Set("Authorization", "Bearer "+apiKey)
	req.Header.Set("Content-Type", "application/json")

	resp, err := c.HTTPClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("查询转写任务进度失败: %w", err)
	}
	defer resp.Body.Close()

	bodyBytes, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("读取任务状态响应失败: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		var errResp struct {
			Code    string `json:"code"`
			Message string `json:"message"`
		}
		_ = json.Unmarshal(bodyBytes, &errResp)
		return nil, &APIError{
			StatusCode: resp.StatusCode,
			Code:       errResp.Code,
			Message:    errResp.Message,
		}
	}

	var taskResp TaskStatusResponse
	if err := json.Unmarshal(bodyBytes, &taskResp); err != nil {
		return nil, fmt.Errorf("解析任务状态响应失败: %w", err)
	}

	if taskResp.Code != "" && taskResp.Code != "200" {
		return nil, &APIError{
			StatusCode: resp.StatusCode,
			Code:       taskResp.Code,
			Message:    taskResp.Message,
		}
	}

	if taskResp.Output.TaskStatus == "" {
		msg := taskResp.Output.Message
		if msg == "" {
			msg = taskResp.Message
		}
		if msg == "" {
			msg = "服务端未返回有效任务状态"
		}
		return nil, &APIError{
			StatusCode: http.StatusBadRequest,
			Code:       taskResp.Output.Code,
			Message:    msg,
		}
	}

	return &taskResp, nil
}

// FetchTranscriptionResult downloads the JSON result from transcription_url and parses sentence segments.
func (c *Client) FetchTranscriptionResult(ctx context.Context, transcriptionURL string) ([]Sentence, error) {
	reqCtx, cancel := withOpTimeout(ctx, 60*time.Second)
	defer cancel()

	req, err := http.NewRequestWithContext(reqCtx, http.MethodGet, transcriptionURL, nil)
	if err != nil {
		return nil, fmt.Errorf("构建获取逐字稿结果请求失败: %w", err)
	}

	resp, err := c.HTTPClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("下载逐字稿结果失败: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("下载逐字稿结果失败，HTTP 状态码: %d", resp.StatusCode)
	}

	data, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("读取逐字稿内容失败: %w", err)
	}

	return ParseTranscriptionJSON(data)
}

// ParseTranscriptionJSON parses the raw JSON result into Sentence slice.
// Supports both top-level `sentences` and nested `transcripts[i].sentences`.
func ParseTranscriptionJSON(data []byte) ([]Sentence, error) {
	var raw struct {
		Sentences   []Sentence `json:"sentences"`
		Transcripts []struct {
			Sentences []Sentence `json:"sentences"`
		} `json:"transcripts"`
	}

	if err := json.Unmarshal(data, &raw); err != nil {
		return nil, fmt.Errorf("解析逐字稿 JSON 格式失败: %w", err)
	}

	var results []Sentence
	if len(raw.Sentences) > 0 {
		results = raw.Sentences
	} else {
		for _, t := range raw.Transcripts {
			results = append(results, t.Sentences...)
		}
	}

	// Filter empty sentences and sort by begin_time
	var cleaned []Sentence
	for _, s := range results {
		txt := strings.TrimSpace(s.Text)
		if txt != "" {
			s.Text = txt
			cleaned = append(cleaned, s)
		}
	}

	sort.Slice(cleaned, func(i, j int) bool {
		return cleaned[i].BeginTime < cleaned[j].BeginTime
	})

	return cleaned, nil
}

// FormatTranscriptMarkdown converts sentences into the standard Stage 11 Markdown format.
// Format:
// [HH:MM:SS.mmm](#t=HH:MM:SS.mmm) 说话人 1
//
// 句子文本内容
func FormatTranscriptMarkdown(sentences []Sentence) string {
	if len(sentences) == 0 {
		return ""
	}

	// Map raw speaker IDs into consistent 1-based sequential indices: 说话人 1, 说话人 2...
	speakerMap := make(map[int]int)
	nextSpeakerIndex := 1

	var b strings.Builder
	for i, s := range sentences {
		idx, ok := speakerMap[s.SpeakerID]
		if !ok {
			idx = nextSpeakerIndex
			speakerMap[s.SpeakerID] = idx
			nextSpeakerIndex++
		}

		timeStr := FormatMilliseconds(s.BeginTime)
		speakerLabel := fmt.Sprintf("说话人 %d", idx)

		if i > 0 {
			b.WriteString("\n\n")
		}

		b.WriteString(fmt.Sprintf("[%s](#t=%s) %s\n\n%s", timeStr, timeStr, speakerLabel, s.Text))
	}

	return b.String()
}
