package asr

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"runtime"
	"strconv"
	"strings"
)

// FormatMilliseconds formats an integer millisecond timestamp into HH:MM:SS.mmm.
func FormatMilliseconds(ms int) string {
	if ms < 0 {
		ms = 0
	}
	hours := ms / 3600000
	remainder := ms % 3600000
	minutes := remainder / 60000
	remainder = remainder % 60000
	seconds := remainder / 1000
	millis := remainder % 1000

	return fmt.Sprintf("%02d:%02d:%02d.%03d", hours, minutes, seconds, millis)
}

var tsRegex = regexp.MustCompile(`^(\d{2}):(\d{2}):(\d{2})\.(\d{3})$`)

// ParseTimestamp parses HH:MM:SS.mmm into milliseconds.
func ParseTimestamp(ts string) (int, error) {
	ts = strings.TrimSpace(ts)
	matches := tsRegex.FindStringSubmatch(ts)
	if len(matches) != 5 {
		return 0, fmt.Errorf("invalid timestamp format %q, expected HH:MM:SS.mmm", ts)
	}

	h, _ := strconv.Atoi(matches[1])
	m, _ := strconv.Atoi(matches[2])
	s, _ := strconv.Atoi(matches[3])
	ms, _ := strconv.Atoi(matches[4])

	return h*3600000 + m*60000 + s*1000 + ms, nil
}

// AudioInfo holds inspected audio channel count and duration.
type AudioInfo struct {
	Channels    int
	DurationSec float64
}

// InspectAudio inspects an MP3 audio file. It first checks via afinfo (on Darwin),
// and falls back to pure Go MP3 frame header parsing.
func InspectAudio(filePath string) (AudioInfo, error) {
	return InspectAudioContext(context.Background(), filePath)
}

// InspectAudioContext inspects an MP3 audio file with a cancellation context.
func InspectAudioContext(ctx context.Context, filePath string) (AudioInfo, error) {
	info := AudioInfo{Channels: 2, DurationSec: 0}

	// 1. Try macOS afinfo if available
	if runtime.GOOS == "darwin" {
		cmd := exec.CommandContext(ctx, "afinfo", filePath)
		out, err := cmd.Output()
		if err == nil {
			str := string(out)
			// Parse channels: e.g. "Data format: 1 ch" or "1 channels"
			chRegex := regexp.MustCompile(`(\d+)\s+ch(?:annel)?`)
			if m := chRegex.FindStringSubmatch(str); len(m) > 1 {
				if c, err := strconv.Atoi(m[1]); err == nil && c > 0 {
					info.Channels = c
				}
			}
			// Parse duration: e.g. "estimated duration: 123.456 sec"
			durRegex := regexp.MustCompile(`estimated duration:\s*([0-9.]+)\s*sec`)
			if m := durRegex.FindStringSubmatch(str); len(m) > 1 {
				if d, err := strconv.ParseFloat(m[1], 64); err == nil {
					info.DurationSec = d
				}
			}
			return info, nil
		}
	}

	// 2. Pure Go MP3 header inspection fallback (bounded read to avoid large memory allocations)
	channels, err := inspectMP3FileChannels(filePath)
	if err != nil {
		return info, err
	}
	info.Channels = channels
	return info, nil
}

// inspectMP3FileChannels reads a bounded prefix/header of the file without loading the entire file into memory.
func inspectMP3FileChannels(filePath string) (int, error) {
	f, err := os.Open(filePath)
	if err != nil {
		return 2, err
	}
	defer f.Close()

	fi, err := f.Stat()
	if err != nil {
		return 2, err
	}
	if fi.Size() == 0 {
		return 2, nil
	}

	var header [10]byte
	n, err := io.ReadFull(f, header[:])
	if err != nil && err != io.ErrUnexpectedEOF && err != io.EOF {
		return 2, err
	}

	startOffset := int64(0)
	if n == 10 && bytes.Equal(header[:3], []byte("ID3")) {
		tagSize := (int64(header[6]&0x7F) << 21) |
			(int64(header[7]&0x7F) << 14) |
			(int64(header[8]&0x7F) << 7) |
			int64(header[9]&0x7F)
		if 10+tagSize < fi.Size() {
			startOffset = 10 + tagSize
		}
	}

	if _, err := f.Seek(startOffset, io.SeekStart); err != nil {
		return 2, err
	}

	// Read a bounded chunk (up to 64KB) to find the first audio frame header
	buf := make([]byte, 64*1024)
	bytesRead, err := io.ReadFull(f, buf)
	if err != nil && err != io.ErrUnexpectedEOF && err != io.EOF {
		return 2, err
	}
	if bytesRead < 4 {
		return 2, nil
	}

	return inspectMP3Channels(buf[:bytesRead])
}

// inspectMP3Channels reads MPEG audio frame headers to determine channel mode.
func inspectMP3Channels(data []byte) (int, error) {
	idx := 0
	// Skip ID3v2 tag if present
	if len(data) >= 10 && bytes.Equal(data[:3], []byte("ID3")) {
		tagSize := (int(data[6]) << 21) | (int(data[7]) << 14) | (int(data[8]) << 7) | int(data[9])
		idx = 10 + tagSize
	}

	// Scan for frame sync: 11 bits of 1s (0xFF followed by 0xE0 mask)
	for i := idx; i+4 <= len(data); i++ {
		if data[i] == 0xFF && (data[i+1]&0xE0) == 0xE0 {
			// Check MPEG layer: Layer III is 0x01
			layer := (data[i+1] >> 1) & 0x03
			if layer == 0 {
				continue // reserved layer
			}
			// Channel mode is bits 7-6 of byte 3 (data[i+3])
			channelMode := (data[i+3] >> 6) & 0x03
			if channelMode == 3 {
				// Single channel (Mono)
				return 1, nil
			}
			// Stereo, Joint stereo, or Dual channel (2 channels)
			return 2, nil
		}
	}

	return 2, nil // default assumption if no sync found
}

// PrepareAudioForDiarization ensures that the audio submitted to speaker diarization is mono.
// If the input audio is already mono, it returns the original path and a no-op cleanup func.
// If stereo, it converts it to a temporary mono copy and returns the cleanup func.
func PrepareAudioForDiarization(srcPath string) (targetPath string, warning string, cleanup func(), err error) {
	return PrepareAudioForDiarizationContext(context.Background(), srcPath)
}

// PrepareAudioForDiarizationContext ensures mono audio bound to ctx.
func PrepareAudioForDiarizationContext(ctx context.Context, srcPath string) (targetPath string, warning string, cleanup func(), err error) {
	cleanup = func() {}
	info, inspectErr := InspectAudioContext(ctx, srcPath)
	if inspectErr == nil && info.DurationSec > 7200 {
		warning = "音频时长超过 2 小时建议上限，说话人分离可能耗时较长或处理受限"
	}

	if info.Channels <= 1 {
		// Already mono!
		return srcPath, warning, cleanup, nil
	}

	// Audio has multiple channels. Check if afconvert is available (macOS)
	if runtime.GOOS == "darwin" {
		taskDir, err := os.MkdirTemp("", "pata_mono_*")
		if err != nil {
			return "", warning, cleanup, fmt.Errorf("创建音频临时转换目录失败: %w", err)
		}
		baseNoExt := strings.TrimSuffix(filepath.Base(srcPath), filepath.Ext(srcPath))
		monoPath := filepath.Join(taskDir, fmt.Sprintf("%s.m4a", baseNoExt))

		// afconvert -f m4af -d aac -c 1 srcPath monoPath
		// DashScope accepts .m4a, .wav, .mp3
		cmd := exec.CommandContext(ctx, "afconvert", "-f", "m4af", "-d", "aac", "-c", "1", srcPath, monoPath)
		outM4a, convertErr := cmd.CombinedOutput()
		if convertErr == nil {
			cleanup = func() {
				_ = os.RemoveAll(taskDir)
			}
			return monoPath, warning, cleanup, nil
		}

		// If m4a fails, try WAVE
		wavPath := filepath.Join(taskDir, fmt.Sprintf("%s.wav", baseNoExt))
		cmdWav := exec.CommandContext(ctx, "afconvert", "-f", "WAVE", "-d", "LEI16", "-c", "1", srcPath, wavPath)
		outWav, wavErr := cmdWav.CombinedOutput()
		if wavErr == nil {
			cleanup = func() {
				_ = os.RemoveAll(taskDir)
			}
			return wavPath, warning, cleanup, nil
		}

		_ = os.RemoveAll(taskDir)
		return "", warning, cleanup, fmt.Errorf("多声道音频转单声道失败: %v (m4a: %s, wav: %s)", convertErr, strings.TrimSpace(string(outM4a)), strings.TrimSpace(string(outWav)))
	}

	return "", warning, cleanup, fmt.Errorf("当前系统暂不支持多声道音频转单声道")
}
