package asr

import (
	"os"
	"path/filepath"
	"testing"
)

func TestAudio_TimestampFormatting(t *testing.T) {
	tests := []struct {
		ms  int
		str string
	}{
		{0, "00:00:00.000"},
		{123, "00:00:00.123"},
		{1000, "00:00:01.000"},
		{65230, "00:01:05.230"},
		{3661005, "01:01:01.005"},
	}

	for _, tt := range tests {
		formatted := FormatMilliseconds(tt.ms)
		if formatted != tt.str {
			t.Errorf("FormatMilliseconds(%d) = %q, expected %q", tt.ms, formatted, tt.str)
		}

		parsed, err := ParseTimestamp(tt.str)
		if err != nil {
			t.Errorf("ParseTimestamp(%q) error: %v", tt.str, err)
		}
		if parsed != tt.ms {
			t.Errorf("ParseTimestamp(%q) = %d, expected %d", tt.str, parsed, tt.ms)
		}
	}

	// Invalid format
	if _, err := ParseTimestamp("invalid"); err == nil {
		t.Errorf("expected error for invalid timestamp string")
	}
}

func TestAudio_InspectMP3Channels(t *testing.T) {
	// Synthesize a minimal MP3 frame header (4 bytes):
	// Byte 0: 0xFF
	// Byte 1: 0xFB (11111011 = sync + MPEG 1 + Layer III + no CRC)
	// Byte 2: 0x90 (10010000 = 128kbps + 44100Hz + no padding + private)
	// Byte 3: bits 7-6:
	//   11 = Mono (Single Channel) -> 0xC0
	//   00 = Stereo -> 0x00
	monoFrame := []byte{0xFF, 0xFB, 0x90, 0xC0}
	stereoFrame := []byte{0xFF, 0xFB, 0x90, 0x00}

	chMono, err := inspectMP3Channels(monoFrame)
	if err != nil || chMono != 1 {
		t.Errorf("expected 1 channel for monoFrame, got %d (err: %v)", chMono, err)
	}

	chStereo, err := inspectMP3Channels(stereoFrame)
	if err != nil || chStereo != 2 {
		t.Errorf("expected 2 channels for stereoFrame, got %d (err: %v)", chStereo, err)
	}

	// With ID3 header preceding frame
	// "ID3" + 2 bytes version + 1 byte flags + 4 bytes synchsafe size
	id3Header := []byte{'I', 'D', '3', 0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x04, 'a', 'b', 'c', 'd'}
	withID3 := append(id3Header, monoFrame...)
	chID3, err := inspectMP3Channels(withID3)
	if err != nil || chID3 != 1 {
		t.Errorf("expected 1 channel for withID3 monoFrame, got %d (err: %v)", chID3, err)
	}
}

func TestAudio_PrepareAudioForDiarizationMono(t *testing.T) {
	tmpDir := t.TempDir()
	monoPath := filepath.Join(tmpDir, "mono.mp3")
	monoFrame := []byte{0xFF, 0xFB, 0x90, 0xC0, 0x00, 0x00, 0x00, 0x00}
	_ = os.WriteFile(monoPath, monoFrame, 0644)

	targetPath, warning, cleanup, err := PrepareAudioForDiarization(monoPath)
	if err != nil {
		t.Fatalf("PrepareAudioForDiarization failed: %v", err)
	}
	defer cleanup()

	if targetPath != monoPath {
		t.Errorf("expected targetPath to be original monoPath %s, got %s", monoPath, targetPath)
	}
	if warning != "" {
		t.Errorf("expected empty warning, got %s", warning)
	}
}

func TestAudio_PrepareAudioForDiarizationStereoExtension(t *testing.T) {
	tmpDir := t.TempDir()
	stereoPath := filepath.Join(tmpDir, "meeting-standup.mp3")
	// Stereo frame: mode bits = 00
	stereoFrame := []byte{0xFF, 0xFB, 0x90, 0x00, 0x00, 0x00, 0x00, 0x00}
	_ = os.WriteFile(stereoPath, stereoFrame, 0644)

	targetPath, _, cleanup, err := PrepareAudioForDiarization(stereoPath)
	defer cleanup()
	if err != nil {
		t.Fatalf("PrepareAudioForDiarization failed: %v", err)
	}

	// On darwin with afconvert available, targetPath should have .m4a or .wav extension, NOT .mp3
	if targetPath != stereoPath {
		ext := filepath.Ext(targetPath)
		if ext != ".m4a" && ext != ".wav" {
			t.Errorf("converted mono file must have .m4a or .wav extension, got %q (path: %s)", ext, targetPath)
		}
	}
}

