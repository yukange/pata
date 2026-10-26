package app

import (
	"fmt"
	"strings"
	"time"

	"pata/internal/storage/markdown"
)

// CreateNoteInput defines parameters for creating a new Note.
type CreateNoteInput struct {
	Title string   `json:"title"`
	Tags  []string `json:"tags,omitempty"`
	Body  string   `json:"body,omitempty"`
}

// UpdateNoteInput defines parameters for updating an existing Note.
// Note: tags and body follow full-replacement semantics (not partial patch).
type UpdateNoteInput struct {
	ID    string   `json:"id"`
	Title string   `json:"title"`
	Tags  []string `json:"tags,omitempty"`
	Body  string   `json:"body"`
}

// cleanNoteRefs drops blank entries. Bindings to missing notes are kept on purpose:
// a deleted target must stay dangling instead of being re-guessed by title.
func cleanNoteRefs(in map[string]string) map[string]string {
	var out map[string]string
	for k, v := range in {
		k, v = strings.TrimSpace(k), strings.TrimSpace(v)
		if k == "" || v == "" {
			continue
		}
		if out == nil {
			out = map[string]string{}
		}
		out[k] = v
	}
	return out
}

// ListNoteRefs returns all notes (ID, title, vault-relative path) for [[ candidates and link resolution.
func (s *VaultService) ListNoteRefs() ([]markdown.NoteRef, error) {
	s.mu.Lock()
	v := s.vault
	s.mu.Unlock()
	if v == nil {
		return nil, fmt.Errorf("尚未打开 Vault")
	}
	return v.Index.ListNoteRefs(v.RootPath), nil
}

// GetNoteBacklinks returns the notes/tasks referencing noteID, deduped by source identity.
func (s *VaultService) GetNoteBacklinks(noteID string) ([]markdown.LinkSource, error) {
	s.mu.Lock()
	v := s.vault
	s.mu.Unlock()
	if v == nil {
		return nil, fmt.Errorf("尚未打开 Vault")
	}
	return v.Index.Backlinks(strings.TrimSpace(noteID), v.RootPath), nil
}

// validateAndCleanNoteIDs validates that all non-empty note IDs exist in the index.
func validateAndCleanNoteIDs(v *markdown.Vault, noteIDs []string) ([]string, error) {
	if len(noteIDs) == 0 {
		return []string{}, nil
	}
	cleaned := make([]string, len(noteIDs))
	for i, nid := range noteIDs {
		id := strings.TrimSpace(nid)
		if id == "" {
			return nil, fmt.Errorf("笔记 ID 不能为空")
		}
		if _, ok := v.Index.GetNote(id); !ok {
			return nil, fmt.Errorf("笔记不存在: %s", id)
		}
		cleaned[i] = id
	}
	return cleaned, nil
}

// ListNotes returns all notes from the vault index, newest updated first.
func (s *VaultService) ListNotes() ([]*markdown.Note, error) {
	s.mu.Lock()
	v := s.vault
	s.mu.Unlock()
	if v == nil {
		return nil, fmt.Errorf("尚未打开 Vault")
	}
	return v.Index.ListNotes(), nil
}

// GetNote returns a note by its ID.
func (s *VaultService) GetNote(id string) (*markdown.Note, error) {
	s.mu.Lock()
	v := s.vault
	s.mu.Unlock()
	if v == nil {
		return nil, fmt.Errorf("尚未打开 Vault")
	}

	trimmedID := strings.TrimSpace(id)
	if trimmedID == "" {
		return nil, fmt.Errorf("笔记 ID 不能为空")
	}

	note, ok := v.Index.GetNote(trimmedID)
	if !ok {
		return nil, fmt.Errorf("笔记不存在: %s", trimmedID)
	}
	return note, nil
}

// CreateNote creates a new Note, writes it safely as Markdown, and updates the index.
func (s *VaultService) CreateNote(input CreateNoteInput) (*markdown.Note, error) {
	return s.createNote(input, "")
}

func (s *VaultService) createNote(input CreateNoteInput, by string) (*markdown.Note, error) {
	s.mu.Lock()
	v := s.vault
	s.mu.Unlock()
	if v == nil {
		return nil, fmt.Errorf("尚未打开 Vault")
	}
	v.MutationMu.Lock()
	defer v.MutationMu.Unlock()

	title := strings.TrimSpace(input.Title)
	if title == "" {
		return nil, fmt.Errorf("笔记标题不能为空")
	}

	now := time.Now()
	note := &markdown.Note{
		Type:      markdown.EntityTypeNote,
		ID:        markdown.GenerateEntityID(markdown.EntityTypeNote),
		Title:     title,
		Tags:      cleanTags(input.Tags),
		CreatedAt: now,
		CreatedBy: by,
		UpdatedAt: now,
		Body:      input.Body,
	}

	if _, err := v.SaveEntity(note, nil); err != nil {
		return nil, err
	}

	return note, nil
}

// UpdateNote updates an existing Note, safely writes changes to Markdown, and preserves unknown frontmatter.
func (s *VaultService) UpdateNote(input UpdateNoteInput) (*markdown.Note, error) {
	s.mu.Lock()
	v := s.vault
	s.mu.Unlock()
	if v == nil {
		return nil, fmt.Errorf("尚未打开 Vault")
	}
	v.MutationMu.Lock()
	defer v.MutationMu.Unlock()

	trimmedID := strings.TrimSpace(input.ID)
	if trimmedID == "" {
		return nil, fmt.Errorf("笔记 ID 不能为空")
	}

	title := strings.TrimSpace(input.Title)
	if title == "" {
		return nil, fmt.Errorf("笔记标题不能为空")
	}

	existing, ok := v.Index.GetNote(trimmedID)
	if !ok {
		return nil, fmt.Errorf("笔记不存在: %s", trimmedID)
	}

	now := time.Now()
	existing.Title = title
	existing.Tags = cleanTags(input.Tags)
	if !(existing.AudioTranscript && strings.TrimSpace(existing.AudioFile) != "") {
		existing.Body = input.Body
	}
	existing.UpdatedAt = now

	baseline := noteBaseline(v, existing)
	newBaseline, err := v.SaveEntity(existing, baseline)
	if err != nil {
		return nil, err
	}

	s.mu.Lock()
	if s.transcriptRecords != nil {
		if rec, ok := s.transcriptRecords[trimmedID]; ok && rec != nil {
			rec.baseline = newBaseline
		}
	}
	s.mu.Unlock()

	return existing, nil
}

// DeleteNote deletes a note from disk and cleans up its index entry.
func (s *VaultService) DeleteNote(id string) error {
	s.mu.Lock()
	v := s.vault
	s.mu.Unlock()
	if v == nil {
		return fmt.Errorf("尚未打开 Vault")
	}
	v.MutationMu.Lock()
	defer v.MutationMu.Unlock()

	trimmedID := strings.TrimSpace(id)
	if trimmedID == "" {
		return fmt.Errorf("笔记 ID 不能为空")
	}

	if _, ok := v.Index.GetNote(trimmedID); !ok {
		return fmt.Errorf("笔记不存在: %s", trimmedID)
	}

	if err := v.DeleteEntity(trimmedID); err != nil {
		return err
	}

	s.mu.Lock()
	if s.transcriptRecords != nil {
		delete(s.transcriptRecords, trimmedID)
	}
	asrMgr := s.asrManager
	s.mu.Unlock()

	if asrMgr != nil {
		asrMgr.CancelAndClear(trimmedID)
	}

	return nil
}

// noteBaseline looks up the baseline for a note directly from the memory index.
func noteBaseline(v *markdown.Vault, note *markdown.Note) *markdown.FileBaseline {
	path := v.ResolveEntityPath(note)
	if b, ok := v.Index.GetBaseline(path); ok {
		return &b
	}
	return nil
}
