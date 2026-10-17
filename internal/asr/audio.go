package asr

import (
	"bytes"
	"fmt"
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
	info := AudioInfo{Channels: 2, DurationSec: 0}

	// 1. Try macOS afinfo if available
	if runtime.GOOS == "darwin" {
		cmd := exec.Command("afinfo", filePath)
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

	// 2. Pure Go MP3 header inspection fallback
	data, err := os.ReadFile(filePath)
	if err != nil {
		return info, err
	}

	channels, err := inspectMP3Channels(data)
	if err == nil {
		info.Channels = channels
	}

	return info, nil
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
	cleanup = func() {}
	info, inspectErr := InspectAudio(srcPath)
	if inspectErr == nil && info.DurationSec > 7200 {
		warning = "音频时长超过 2 小时建议上限，说话人分离可能耗时较长或处理受限"
	}

	if info.Channels <= 1 {
		// Already mono!
		return srcPath, warning, cleanup, nil
	}

	// Audio has multiple channels. Check if afconvert is available (macOS)
	if runtime.GOOS == "darwin" {
		tempDir := os.TempDir()
		baseNoExt := strings.TrimSuffix(filepath.Base(srcPath), filepath.Ext(srcPath))
		monoPath := filepath.Join(tempDir, fmt.Sprintf("pata_mono_%d_%s.m4a", os.Getpid(), baseNoExt))
		
		// afconvert -f m4af -d aac -c 1 srcPath monoPath
		// DashScope accepts .m4a, .wav, .mp3
		cmd := exec.Command("afconvert", "-f", "m4af", "-d", "aac", "-c", "1", srcPath, monoPath)
		if _, convertErr := cmd.CombinedOutput(); convertErr == nil {
			cleanup = func() {
				_ = os.Remove(monoPath)
			}
			return monoPath, warning, cleanup, nil
		}

		// If m4a fails, try WAVE
		wavPath := filepath.Join(tempDir, fmt.Sprintf("pata_mono_%d_%s.wav", os.Getpid(), baseNoExt))
		cmdWav := exec.Command("afconvert", "-f", "WAVE", "-d", "LEI16", "-c", "1", srcPath, wavPath)
		if _, wavErr := cmdWav.CombinedOutput(); wavErr == nil {
			cleanup = func() {
				_ = os.Remove(wavPath)
			}
			return wavPath, warning, cleanup, nil
		}
	}

	// If no conversion tool available, proceed with original file
	return srcPath, warning, cleanup, nil
}
