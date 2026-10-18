package asr

import (
	"context"
	"encoding/binary"
	"os"
	"path/filepath"
	"runtime"
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

func createTestStereoWAV(t *testing.T, dir string) string {
	t.Helper()
	p := filepath.Join(dir, "stereo.wav")
	sampleRate := uint32(44100)
	numChannels := uint16(2)
	bitsPerSample := uint16(16)
	dataSize := uint32(4410 * 4) // 0.1s
	data := make([]byte, 44+dataSize)
	copy(data[0:4], "RIFF")
	binary.LittleEndian.PutUint32(data[4:8], 36+dataSize)
	copy(data[8:12], "WAVE")
	copy(data[12:16], "fmt ")
	binary.LittleEndian.PutUint32(data[16:20], 16)
	binary.LittleEndian.PutUint16(data[20:22], 1)
	binary.LittleEndian.PutUint16(data[22:24], numChannels)
	binary.LittleEndian.PutUint32(data[24:28], sampleRate)
	binary.LittleEndian.PutUint32(data[28:32], sampleRate*uint32(numChannels)*uint32(bitsPerSample/8))
	binary.LittleEndian.PutUint16(data[32:34], numChannels*(bitsPerSample/8))
	binary.LittleEndian.PutUint16(data[34:36], bitsPerSample)
	copy(data[36:40], "data")
	binary.LittleEndian.PutUint32(data[40:44], dataSize)
	if err := os.WriteFile(p, data, 0644); err != nil {
		t.Fatalf("failed to create test stereo wav: %v", err)
	}
	return p
}

func TestAudio_PrepareAudioForDiarizationStereoExtension(t *testing.T) {
	if runtime.GOOS != "darwin" {
		t.Skip("afconvert only available on macOS")
	}

	tmpDir := t.TempDir()
	stereoPath := createTestStereoWAV(t, tmpDir)

	targetPath, _, cleanup, err := PrepareAudioForDiarization(stereoPath)
	defer cleanup()
	if err != nil {
		t.Fatalf("PrepareAudioForDiarization failed: %v", err)
	}

	if targetPath == stereoPath {
		t.Errorf("expected targetPath to be converted mono file, but got original %s", stereoPath)
	}
	ext := filepath.Ext(targetPath)
	if ext != ".m4a" && ext != ".wav" {
		t.Errorf("converted mono file must have .m4a or .wav extension, got %q (path: %s)", ext, targetPath)
	}
}

func TestAudio_PrepareAudioForDiarizationStereoFailure(t *testing.T) {
	if runtime.GOOS != "darwin" {
		t.Skip("afconvert only available on macOS")
	}

	tmpDir := t.TempDir()
	// Invalid truncated stereo header that cannot be converted by afconvert
	invalidStereoPath := filepath.Join(tmpDir, "invalid-stereo.mp3")
	stereoFrame := []byte{0xFF, 0xFB, 0x90, 0x00, 0x00, 0x00, 0x00, 0x00}
	_ = os.WriteFile(invalidStereoPath, stereoFrame, 0644)

	_, _, cleanup, err := PrepareAudioForDiarization(invalidStereoPath)
	defer cleanup()
	if err == nil {
		t.Fatalf("expected error when afconvert fails on invalid stereo audio, got nil")
	}
}

func TestAudio_InspectMP3FileChannels(t *testing.T) {
	tmpDir := t.TempDir()

	// 1. Mono file
	monoPath := filepath.Join(tmpDir, "mono.mp3")
	monoFrame := []byte{0xFF, 0xFB, 0x90, 0xC0}
	_ = os.WriteFile(monoPath, monoFrame, 0644)

	ch, err := inspectMP3FileChannels(monoPath)
	if err != nil || ch != 1 {
		t.Fatalf("expected 1 channel, got %d, err: %v", ch, err)
	}

	// 2. Stereo file with ID3 tag and extra trailing data (verifying bounded read)
	stereoPath := filepath.Join(tmpDir, "stereo_with_id3.mp3")
	id3Header := []byte{'I', 'D', '3', 0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x04, 'a', 'b', 'c', 'd'}
	stereoFrame := []byte{0xFF, 0xFB, 0x90, 0x00}
	fullContent := append(id3Header, stereoFrame...)
	fullContent = append(fullContent, make([]byte, 1024)...)
	_ = os.WriteFile(stereoPath, fullContent, 0644)

	ch, err = inspectMP3FileChannels(stereoPath)
	if err != nil || ch != 2 {
		t.Fatalf("expected 2 channels, got %d, err: %v", ch, err)
	}

	// 3. Non-existent file returns error
	_, err = inspectMP3FileChannels(filepath.Join(tmpDir, "nonexistent.mp3"))
	if err == nil {
		t.Fatalf("expected error for non-existent file")
	}
}

func TestAudio_PrepareAudioForDiarizationContextTimeout(t *testing.T) {
	if runtime.GOOS != "darwin" {
		t.Skip("skipping on non-darwin")
	}
	tmpDir := t.TempDir()
	stereoWAV := createTestStereoWAV(t, tmpDir)

	// Provide an already-cancelled context
	ctx, cancel := context.WithCancel(context.Background())
	cancel()

	_, _, cleanup, err := PrepareAudioForDiarizationContext(ctx, stereoWAV)
	defer cleanup()
	if err == nil {
		t.Fatalf("expected error when context is cancelled, got nil")
	}
}


