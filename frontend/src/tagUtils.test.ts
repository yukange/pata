import test from 'node:test';
import assert from 'node:assert/strict';
import {
  cleanTag,
  validateTag,
  hasTag,
  sameTags,
  dedupeTags,
  filterSuggestedTags,
  formatDraftText,
} from './tagUtils.ts';

test('validateTag: empty inputs and whitespaces are rejected', () => {
  assert.deepEqual(validateTag(''), { ok: false, error: '标签不能为空' });
  assert.deepEqual(validateTag('   '), { ok: false, error: '标签不能为空' });
  assert.deepEqual(validateTag('#'), { ok: false, error: '标签不能为空' });
  assert.deepEqual(validateTag('###'), { ok: false, error: '标签不能为空' });
});

test('validateTag: leading # characters are stripped', () => {
  assert.deepEqual(validateTag('#design'), { ok: true, tag: 'design' });
  assert.deepEqual(validateTag('###architecture'), { ok: true, tag: 'architecture' });
  assert.deepEqual(validateTag('  #pata  '), { ok: true, tag: 'pata' });
});

test('validateTag: internal # characters are rejected with clear error', () => {
  const r1 = validateTag('pata#app');
  assert.equal(r1.ok, false);
  assert.equal(r1.error, "标签不能包含 '#'");

  const r2 = validateTag('#foo#bar');
  assert.equal(r2.ok, false);
  assert.equal(r2.error, "标签不能包含 '#'");
});

test('validateTag: commas (English and Chinese) are legal characters within tags', () => {
  assert.deepEqual(validateTag('研发,平台'), { ok: true, tag: '研发,平台' });
  assert.deepEqual(validateTag('数据，治理'), { ok: true, tag: '数据，治理' });
  assert.deepEqual(validateTag('#C++,Qt'), { ok: true, tag: 'C++,Qt' });
});

test('hasTag: case-insensitive check and leading # normalization', () => {
  const current = ['Pata', '研发,平台', 'Go'];
  assert.equal(hasTag(current, 'pata'), true);
  assert.equal(hasTag(current, 'Pata'), true);
  assert.equal(hasTag(current, '#PATA'), true);
  assert.equal(hasTag(current, '研发,平台'), true);
  assert.equal(hasTag(current, 'go'), true);
  assert.equal(hasTag(current, 'Rust'), false);
});

test('sameTags: compares tag arrays case-insensitively and handles leading #', () => {
  assert.equal(sameTags([], []), true);
  assert.equal(sameTags(['a', 'b'], ['#A', 'B']), true);
  assert.equal(sameTags(['a', 'b'], ['a']), false);
  assert.equal(sameTags(['a'], ['b']), false);
  assert.equal(sameTags(['#Pata'], ['pata']), true);
});

test('dedupeTags: deduplicates case-insensitively and preserves FIRST adopted casing', () => {
  const input = ['Pata', 'pata', 'PATA', 'GoCore', 'gocore', '研发,平台', '研发,平台'];
  const res = dedupeTags(input);
  assert.deepEqual(res, ['Pata', 'GoCore', '研发,平台']);
});

test('dedupeTags: preserves single tag containing commas', () => {
  const res = dedupeTags(['研发,平台', '架构，设计']);
  assert.deepEqual(res, ['研发,平台', '架构，设计']);
});

test('filterSuggestedTags: excludes already adopted tags case-insensitively and filters by query', () => {
  const allTags = ['Pata', 'TypeScript', 'Golang', '前端', '后端'];
  const current = ['pata', '前端'];

  const suggestions = filterSuggestedTags(allTags, current, '');
  assert.deepEqual(suggestions, ['TypeScript', 'Golang', '后端']);

  const queryMatch = filterSuggestedTags(allTags, current, 'go');
  assert.deepEqual(queryMatch, ['Golang']);
});

test('formatDraftText: includes title, all tags prefixed with #, and body', () => {
  const text = formatDraftText('技术方案', ['研发,平台', 'Pata'], '正文第一段\n\n正文第二段');
  assert.equal(
    text,
    '# 技术方案\n\n#研发,平台 #Pata\n\n正文第一段\n\n正文第二段'
  );
});

test('formatDraftText: handles missing title or empty tags gracefully', () => {
  const noTitle = formatDraftText('', ['Pata'], '仅正文');
  assert.equal(noTitle, '#Pata\n\n仅正文');

  const noTags = formatDraftText('标题', [], '仅正文');
  assert.equal(noTags, '# 标题\n\n仅正文');

  const onlyTags = formatDraftText('', ['Tag1', 'Tag2'], '');
  assert.equal(onlyTags, '#Tag1 #Tag2');
});
