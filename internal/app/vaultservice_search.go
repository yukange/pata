package app

import (
	"fmt"
	"sort"
	"strings"

	"pata/internal/storage/markdown"
)

// cleanTags normalizes and deduplicates tags case-insensitively,
// stripping leading '#' characters, trimming spaces, and preserving the first display casing.
// Commas inside tags are kept as valid characters.
func cleanTags(in []string) []string {
	var out []string
	seen := make(map[string]struct{})
	for _, raw := range in {
		trimmed := strings.TrimSpace(raw)
		cleaned := strings.TrimSpace(strings.TrimLeft(trimmed, "#"))
		if cleaned == "" {
			continue
		}
		key := strings.ToLower(cleaned)
		if _, ok := seen[key]; ok {
			continue
		}
		seen[key] = struct{}{}
		out = append(out, cleaned)
	}
	return out
}

// GetTagOverview returns aggregated counts of all unique tags across tasks, notes, and activities.
func (s *VaultService) GetTagOverview() ([]markdown.TagOverviewItem, error) {
	s.mu.Lock()
	v := s.vault
	s.mu.Unlock()
	if v == nil {
		return nil, fmt.Errorf("尚未打开 Vault")
	}

	return v.Index.TagOverview(), nil
}

// ListByTag returns all entities matching the specified tag.
// For Activities, tag matching checks act.Tags ∪ parentTask.Tags (for task activities).
func (s *VaultService) ListByTag(tag string) ([]markdown.EntityRef, error) {
	s.mu.Lock()
	v := s.vault
	s.mu.Unlock()
	if v == nil {
		return nil, fmt.Errorf("尚未打开 Vault")
	}

	trimmed := strings.TrimSpace(tag)
	if trimmed == "" {
		return []markdown.EntityRef{}, nil
	}

	refs := v.Index.FindByTag(trimmed)
	result := make([]markdown.EntityRef, len(refs))
	copy(result, refs)

	sort.SliceStable(result, func(i, j int) bool {
		if !result[i].Time.Equal(result[j].Time) {
			return result[i].Time.After(result[j].Time)
		}
		if result[i].Type != result[j].Type {
			return result[i].Type < result[j].Type
		}
		return result[i].ID < result[j].ID
	})

	return result, nil
}

// ListAllEntities returns all entities matching no tag filter, sorted chronologically descending.
func (s *VaultService) ListAllEntities() ([]markdown.EntityRef, error) {
	s.mu.Lock()
	v := s.vault
	s.mu.Unlock()
	if v == nil {
		return nil, fmt.Errorf("尚未打开 Vault")
	}

	refs := v.Index.FindAll()
	result := make([]markdown.EntityRef, len(refs))
	copy(result, refs)

	sort.SliceStable(result, func(i, j int) bool {
		if !result[i].Time.Equal(result[j].Time) {
			return result[i].Time.After(result[j].Time)
		}
		if result[i].Type != result[j].Type {
			return result[i].Type < result[j].Type
		}
		return result[i].ID < result[j].ID
	})

	return result, nil
}

// SearchAll performs case-insensitive substring search across tasks, notes, activities, and files.
// Empty or whitespace-only queries return an empty list without error.
func (s *VaultService) SearchAll(query string) ([]markdown.SearchResultItem, error) {
	s.mu.Lock()
	v := s.vault
	s.mu.Unlock()
	if v == nil {
		return nil, fmt.Errorf("尚未打开 Vault")
	}

	return v.Index.SearchAll(query), nil
}
