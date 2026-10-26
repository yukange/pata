package markdown

import (
	"net/url"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
)

// NoteRef 是笔记候选：稳定 ID、标题与 Vault 相对路径（斜杠分隔）。
type NoteRef struct {
	ID    string `json:"id"`
	Title string `json:"title"`
	Path  string `json:"path"`
}

// LinkSource 是「被引用」来源（Note 或 Task，按类型+ID 去重）。
type LinkSource struct {
	Type  EntityType `json:"type"`
	ID    string     `json:"id"`
	Title string     `json:"title"`
	Path  string     `json:"path"`
}

func cloneRefs(m map[string]string) map[string]string {
	if m == nil {
		return nil
	}
	cp := make(map[string]string, len(m))
	for k, v := range m {
		cp[k] = v
	}
	return cp
}

var (
	// 围栏代码块（未闭合则到文末）与行内代码内的链接是示例，不计入引用。
	fencedCodeRe = regexp.MustCompile("(?ms)^[ \\t]*(?:```|~~~).*?(?:^[ \\t]*(?:```|~~~)[ \\t]*$|\\z)")
	inlineCodeRe = regexp.MustCompile("`[^`\\n]*`")
	mdLinkRe     = regexp.MustCompile(`(!?)\[[^\]]*\]\(([^)\s]+)(?:\s+"[^"]*")?\)`)
	urlSchemeRe  = regexp.MustCompile(`^[a-zA-Z][a-zA-Z0-9+.-]*:`)
	// 以反斜杠转义的 \[[x]] 视为字面文字。
	textRefRe = regexp.MustCompile(`\\?\[\[([^\[\]\n]+)\]\]`)
)

// noteLinkDests returns relative link destinations (unescaped, no anchor) found in a Note body.
func noteLinkDests(body string) []string {
	body = inlineCodeRe.ReplaceAllString(fencedCodeRe.ReplaceAllString(body, ""), "")
	var out []string
	for _, m := range mdLinkRe.FindAllStringSubmatch(body, -1) {
		dest := m[2]
		if m[1] == "!" || strings.HasPrefix(dest, "/") || strings.HasPrefix(dest, "#") || urlSchemeRe.MatchString(dest) {
			continue
		}
		if i := strings.IndexAny(dest, "#?"); i >= 0 {
			dest = dest[:i]
		}
		if u, err := url.PathUnescape(dest); err == nil {
			dest = u
		}
		if dest != "" {
			out = append(out, dest)
		}
	}
	return out
}

// textRefKeys returns the [[名称]] names in a plain-text body (escaped ones skipped).
func textRefKeys(body string) []string {
	var out []string
	for _, m := range textRefRe.FindAllStringSubmatch(body, -1) {
		if !strings.HasPrefix(m[0], `\`) {
			out = append(out, m[1])
		}
	}
	return out
}

// resolveTextRefLocked: 已绑定则只认绑定的 ID（目标不存在即失效，不按标题改猜）；
// 未绑定仅在标题唯一匹配时解析。
func (idx *MemoryIndex) resolveTextRefLocked(name string, refs map[string]string) string {
	trimmed := strings.TrimSpace(name)
	if id, ok := refs[name]; ok {
		if _, exists := idx.notes[id]; exists {
			return id
		}
		return ""
	}
	if id, ok := refs[trimmed]; ok {
		if _, exists := idx.notes[id]; exists {
			return id
		}
		return ""
	}
	for k, id := range refs {
		if strings.TrimSpace(k) == trimmed {
			if _, exists := idx.notes[id]; exists {
				return id
			}
			return ""
		}
	}
	if trimmed == "" {
		return ""
	}
	found, n := "", 0
	for id, note := range idx.notes {
		if note.Title == name || strings.TrimSpace(note.Title) == trimmed {
			found, n = id, n+1
		}
	}
	if n == 1 {
		return found
	}
	return ""
}

func (idx *MemoryIndex) textRefsHitLocked(body string, refs map[string]string, target string) bool {
	for _, k := range textRefKeys(body) {
		if idx.resolveTextRefLocked(k, refs) == target {
			return true
		}
	}
	return false
}

func relSlash(root, abs string) string {
	if r, err := filepath.Rel(root, abs); err == nil {
		return filepath.ToSlash(r)
	}
	return abs
}

// ListNoteRefs returns all notes as candidates, sorted by title then path.
func (idx *MemoryIndex) ListNoteRefs(root string) []NoteRef {
	idx.mu.RLock()
	defer idx.mu.RUnlock()
	out := make([]NoteRef, 0, len(idx.notes))
	for id, n := range idx.notes {
		out = append(out, NoteRef{ID: id, Title: n.Title, Path: relSlash(root, idx.idToFile[id])})
	}
	sort.Slice(out, func(i, j int) bool {
		if out[i].Title != out[j].Title {
			return out[i].Title < out[j].Title
		}
		return out[i].Path < out[j].Path
	})
	return out
}

// Backlinks computes who references targetID: Notes (standard relative links) and Tasks
// (description/comment [[ ]] refs plus legacy note_ids), deduped by source type+ID.
// Everything is derived from files, nothing is written to the target.
func (idx *MemoryIndex) Backlinks(targetID, root string) []LinkSource {
	idx.mu.RLock()
	defer idx.mu.RUnlock()
	if _, ok := idx.notes[targetID]; !ok {
		return []LinkSource{}
	}
	out := []LinkSource{}
	seen := map[string]bool{}
	add := func(typ EntityType, id, title string) {
		if key := string(typ) + ":" + id; !seen[key] {
			seen[key] = true
			out = append(out, LinkSource{Type: typ, ID: id, Title: title, Path: relSlash(root, idx.idToFile[id])})
		}
	}

	for id, n := range idx.notes {
		if id == targetID {
			continue
		}
		dir := filepath.Dir(idx.idToFile[id])
		for _, dest := range noteLinkDests(n.Body) {
			abs := filepath.Join(dir, filepath.FromSlash(dest))
			if tid, ok := idx.fileToID[abs]; ok && tid == targetID {
				add(EntityTypeNote, id, n.Title)
				break
			}
		}
	}
	for id, t := range idx.tasks {
		for _, nid := range t.NoteIDs {
			if nid == targetID {
				add(EntityTypeTask, id, t.Title)
			}
		}
		if idx.textRefsHitLocked(t.Description, t.NoteRefs, targetID) {
			add(EntityTypeTask, id, t.Title)
		}
		for _, act := range t.Activities {
			if idx.textRefsHitLocked(act.Body, act.NoteRefs, targetID) {
				add(EntityTypeTask, id, t.Title)
			}
		}
	}

	sort.Slice(out, func(i, j int) bool {
		if out[i].Title != out[j].Title {
			return out[i].Title < out[j].Title
		}
		return out[i].Path < out[j].Path
	})
	return out
}
