package markdown

import (
	"os"
	"path/filepath"
	"testing"
)

func TestParseExamples(t *testing.T) {
	// Find repo root examples directory
	examplesDir := filepath.Join("..", "..", "..", "docs", "02-foundation", "examples")
	if _, err := os.Stat(examplesDir); os.IsNotExist(err) {
		t.Fatalf("examples dir does not exist at %s", examplesDir)
	}

	count := 0
	err := filepath.Walk(examplesDir, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		if info.IsDir() || filepath.Ext(path) != ".md" {
			return nil
		}

		data, err := os.ReadFile(path)
		if err != nil {
			t.Fatalf("failed to read %s: %v", path, err)
		}

		entity, err := ParseMarkdown(path, data)
		if err != nil {
			t.Fatalf("failed to parse example %s: %v", path, err)
		}

		// Verify round-trip serialization doesn't fail
		serialized, err := SerializeMarkdown(entity)
		if err != nil {
			t.Fatalf("failed to serialize example %s: %v", path, err)
		}

		// Parse the serialized data again to ensure round-trip fidelity
		roundTripEntity, err := ParseMarkdown(path, serialized)
		if err != nil {
			t.Fatalf("failed to parse round-tripped markdown of %s: %v", path, err)
		}

		if roundTripEntity.GetType() != entity.GetType() {
			t.Fatalf("type mismatch after round-trip: %s vs %s", roundTripEntity.GetType(), entity.GetType())
		}
		if roundTripEntity.GetID() != entity.GetID() {
			t.Fatalf("id mismatch after round-trip: %s vs %s", roundTripEntity.GetID(), entity.GetID())
		}

		count++
		t.Logf("Successfully parsed and verified: %s (type: %s, id: %s)", path, entity.GetType(), entity.GetID())
		return nil
	})

	if err != nil {
		t.Fatalf("Walk failed: %v", err)
	}

	if count < 4 {
		t.Fatalf("expected at least 4 example files, found %d", count)
	}
}

func TestNote_AudioTranscriptRoundTrip(t *testing.T) {
	raw := `---
type: note
id: n-audio123
title: 会议录音讨论
tags: [架构, 评审]
audio_file: files/meeting.mp3
audio_transcript: true
created_at: 2026-10-15T09:00:00+08:00
updated_at: 2026-10-15T09:20:00+08:00
---

[00:01:05.230](#t=00:01:05.230) 说话人 1

我们先讨论一下这次技术架构的调整。

[00:01:18.760](#t=00:01:18.760) 说话人 2

我觉得可以先把现有的方案简化一下。
`
	entity, err := ParseMarkdown("notes/meeting.md", []byte(raw))
	if err != nil {
		t.Fatalf("ParseMarkdown failed: %v", err)
	}
	note, ok := entity.(*Note)
	if !ok {
		t.Fatalf("expected *Note, got %T", entity)
	}
	if note.AudioFile != "files/meeting.mp3" {
		t.Errorf("expected AudioFile 'files/meeting.mp3', got %q", note.AudioFile)
	}
	if !note.AudioTranscript {
		t.Errorf("expected AudioTranscript true, got false")
	}

	serialized, err := SerializeMarkdown(note)
	if err != nil {
		t.Fatalf("SerializeMarkdown failed: %v", err)
	}

	roundTrip, err := ParseMarkdown("notes/meeting.md", serialized)
	if err != nil {
		t.Fatalf("re-parse serialized note failed: %v", err)
	}
	rtNote := roundTrip.(*Note)
	if rtNote.AudioFile != "files/meeting.mp3" || !rtNote.AudioTranscript {
		t.Fatalf("mismatch after roundtrip: audio_file=%s, transcript=%v", rtNote.AudioFile, rtNote.AudioTranscript)
	}

	// Invalid audio_file escaping vault root should fail validation
	invalid := note.Clone().(*Note)
	invalid.AudioFile = "../secret/meeting.mp3"
	if err := ValidateEntity("notes/invalid.md", invalid); err == nil {
		t.Fatalf("expected error for escaping audio_file, got nil")
	}

	// audio_transcript true but missing audio_file should fail validation
	invalidMissingAudio := note.Clone().(*Note)
	invalidMissingAudio.AudioFile = ""
	if err := ValidateEntity("notes/invalid.md", invalidMissingAudio); err == nil {
		t.Fatalf("expected error for audio_transcript=true without audio_file, got nil")
	}
}
