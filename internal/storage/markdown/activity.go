package markdown

import (
	"bytes"
	"fmt"
	"strings"
	"time"

	"gopkg.in/yaml.v3"
)

const (
	activityStartTag = "<!-- pata:activity"
	activityEndMeta  = "-->"
	activityEndTag   = "<!-- /pata:activity -->"
)

type activityMeta struct {
	ID       string               `yaml:"id"`
	At       time.Time            `yaml:"at"`
	By       string               `yaml:"by,omitempty"`
	Tags     []string             `yaml:"tags,omitempty"`
	NoteRefs map[string]string    `yaml:"note_refs,omitempty"`
	Extra    map[string]yaml.Node `yaml:",inline"`
}

func isActivityMarkerLine(line string) bool {
	marker := strings.TrimSpace(strings.TrimLeft(line, " \t\\"))
	return marker == activityStartTag || marker == activityEndTag
}

// ParseActivities parses activity blocks from markdown body content.
// Task/DayPlan body must only contain activity blocks and whitespace.
func ParseActivities(raw string) ([]Activity, error) {
	normalized := strings.ReplaceAll(raw, "\r\n", "\n")
	trimmedAll := strings.TrimSpace(normalized)
	if trimmedAll == "" {
		return []Activity{}, nil
	}

	lines := strings.Split(normalized, "\n")
	type state int
	const (
		stateOutside state = iota
		stateMeta
		stateBody
	)

	currState := stateOutside
	var metaLines []string
	var bodyLines []string
	var activities []Activity
	seenIDs := make(map[string]bool)

	for lineNum, line := range lines {
		trimmed := strings.TrimSpace(line)

		switch currState {
		case stateOutside:
			if trimmed == "" {
				continue
			}
			if trimmed == activityStartTag {
				currState = stateMeta
				metaLines = nil
				bodyLines = nil
			} else {
				return nil, fmt.Errorf("unexpected content outside activity block at line %d: %q", lineNum+1, trimmed)
			}

		case stateMeta:
			if trimmed == activityEndMeta {
				currState = stateBody
			} else if trimmed == activityStartTag {
				return nil, fmt.Errorf("nested activity start tag at line %d", lineNum+1)
			} else if trimmed == activityEndTag {
				return nil, fmt.Errorf("unexpected activity end tag in metadata at line %d", lineNum+1)
			} else {
				metaLines = append(metaLines, line)
			}

		case stateBody:
			if trimmed == activityEndTag {
				// Block finished, parse and validate
				metaStr := strings.Join(metaLines, "\n")
				var meta activityMeta
				if err := yaml.Unmarshal([]byte(metaStr), &meta); err != nil {
					return nil, fmt.Errorf("invalid YAML in activity metadata: %w", err)
				}

				meta.ID = strings.TrimSpace(meta.ID)
				if meta.ID == "" {
					return nil, fmt.Errorf("activity missing required 'id'")
				}
				if !strings.HasPrefix(meta.ID, "a-") || len(meta.ID) <= 2 {
					return nil, fmt.Errorf("activity id must start with 'a-'; got '%s'", meta.ID)
				}
				if meta.At.IsZero() {
					return nil, fmt.Errorf("activity %s missing required valid timestamp 'at'", meta.ID)
				}
				if err := validateSource("", "by", meta.By); err != nil {
					return nil, err
				}
				if seenIDs[meta.ID] {
					return nil, fmt.Errorf("duplicate activity id '%s' in same entity", meta.ID)
				}
				seenIDs[meta.ID] = true

				for i, tag := range meta.Tags {
					if strings.Contains(tag, "#") {
						return nil, fmt.Errorf("activity %s tag[%d] must not contain '#': %q", meta.ID, i, tag)
					}
				}

				// Unescape body lines
				unescapedBody := make([]string, len(bodyLines))
				for i, bl := range bodyLines {
					if strings.HasPrefix(bl, `\`) && isActivityMarkerLine(bl[1:]) {
						unescapedBody[i] = bl[1:]
					} else {
						unescapedBody[i] = bl
					}
				}

				activities = append(activities, Activity{
					ID:       meta.ID,
					At:       meta.At,
					By:       meta.By,
					Tags:     meta.Tags,
					NoteRefs: meta.NoteRefs,
					Body:     strings.Join(unescapedBody, "\n"),
					Extra:    meta.Extra,
				})

				currState = stateOutside
			} else if trimmed == activityStartTag {
				return nil, fmt.Errorf("nested activity start tag without closing previous activity at line %d", lineNum+1)
			} else {
				bodyLines = append(bodyLines, line)
			}
		}
	}

	if currState != stateOutside {
		return nil, fmt.Errorf("unclosed activity block: missing %s", activityEndTag)
	}

	return activities, nil
}

// FormatActivities serializes a slice of Activity structs into markdown blocks.
func FormatActivities(activities []Activity) (string, error) {
	if len(activities) == 0 {
		return "", nil
	}

	var buf bytes.Buffer
	for i, act := range activities {
		if i > 0 {
			buf.WriteString("\n\n")
		}

		meta := activityMeta{
			ID:       act.ID,
			At:       act.At,
			By:       act.By,
			Tags:     act.Tags,
			NoteRefs: act.NoteRefs,
			Extra:    act.Extra,
		}

		metaBytes, err := yaml.Marshal(&meta)
		if err != nil {
			return "", fmt.Errorf("failed to encode activity metadata: %w", err)
		}

		buf.WriteString(activityStartTag + "\n")
		buf.Write(metaBytes)
		buf.WriteString(activityEndMeta + "\n")

		if act.Body != "" {
			normalized := strings.ReplaceAll(act.Body, "\r\n", "\n")
			lines := strings.Split(normalized, "\n")
			for _, line := range lines {
				if isActivityMarkerLine(line) {
					buf.WriteString(`\` + line + "\n")
				} else {
					buf.WriteString(line + "\n")
				}
			}
		}

		buf.WriteString(activityEndTag)
	}
	buf.WriteString("\n")

	return buf.String(), nil
}
