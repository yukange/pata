/**
 * Shared tag normalization, validation, deduplication and draft formatting.
 * Implements docs/04-knowledge-loop/proposal.md "后续改进：统一 Note / Task 标签编辑".
 */

/**
 * Strips leading/trailing whitespace and removes any leading '#' characters.
 */
export function cleanTag(raw: string): string {
  return raw.trim().replace(/^#+/, '').trim();
}

export interface TagValidationResult {
  ok: boolean;
  error?: string;
  tag?: string;
}

/**
 * Validates a candidate tag according to Pata schema & UI rules:
 * - Leading '#' characters are stripped.
 * - Empty tags are rejected.
 * - Internal '#' characters are rejected with a descriptive error.
 * - Commas (English and Chinese) are legal characters within tags, not delimiters.
 */
export function validateTag(raw: string): TagValidationResult {
  const tag = cleanTag(raw);
  if (!tag) {
    return { ok: false, error: '标签不能为空' };
  }
  if (tag.includes('#')) {
    return { ok: false, error: "标签不能包含 '#'", tag };
  }
  return { ok: true, tag };
}

/**
 * Case-insensitive tag membership check.
 */
export function hasTag(tags: string[], candidate: string): boolean {
  const target = cleanTag(candidate).toLowerCase();
  if (!target) return false;
  return tags.some((t) => cleanTag(t).toLowerCase() === target);
}

/**
 * Case-insensitive comparison of two tag lists.
 */
export function sameTags(a: string[] = [], b: string[] = []): boolean {
  if (a.length !== b.length) return false;
  return a.every((t, i) => cleanTag(t).toLowerCase() === cleanTag(b[i] ?? '').toLowerCase());
}

/**
 * Case-insensitive deduplication, preserving the display casing of the FIRST encountered tag.
 * Commas are preserved intact.
 */
export function dedupeTags(tags: string[]): string[] {
  const seen = new Set<string>();
  const out: string[] = [];
  for (const raw of tags) {
    const t = cleanTag(raw);
    const key = t.toLowerCase();
    if (!t || seen.has(key)) continue;
    seen.add(key);
    out.push(t);
  }
  return out;
}

/**
 * Filters suggested global tags by excluding already adopted tags (case-insensitively)
 * and matching against the current query substring.
 */
export function filterSuggestedTags(
  allTags: string[],
  currentTags: string[],
  query: string = '',
  limit: number = 6
): string[] {
  const q = cleanTag(query).toLowerCase();
  return (allTags ?? [])
    .filter((t) => !hasTag(currentTags, t))
    .filter((t) => !q || t.toLowerCase().includes(q))
    .slice(0, limit);
}

/**
 * Formats a note draft text for copy/recovery on conflict or navigation leave.
 * Complete draft includes title, all current tags (prefixed with # for clarity), and body.
 */
export function formatDraftText(title: string, tags: string[], body: string): string {
  const parts: string[] = [];
  const cleanTitle = title.trim();
  if (cleanTitle) {
    parts.push(`# ${cleanTitle}`);
  }
  if (tags && tags.length > 0) {
    parts.push(tags.map((t) => `#${cleanTag(t)}`).join(' '));
  }
  if (body) {
    parts.push(body);
  }
  return parts.join('\n\n');
}
