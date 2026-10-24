import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const source = (name: string) => fs.readFileSync(new URL(name, import.meta.url), 'utf8');

test('来源在两处 Activity 传递，Note 元信息仅属于编辑页，列表不显示来源', () => {
  const today = source('./TodayView.tsx');
  const detail = source('./TaskDetailPanel.tsx');
  assert.match(today, /item\.kind === 'creation'/);
  assert.match(today, /statusEvent=\{\{ action: item\.kind, by: item\.by \}\}/);
  assert.match(detail, /statusEvent=\{\{ action: item\.action, by: item\.by \}\}/);
  for (const view of [today, detail]) assert.match(view, /by: act\.by/);

  const notes = source('./NotesView.tsx');
  const listStart = notes.indexOf('export function NotesView');
  assert.ok(listStart > 0);
  assert.match(notes.slice(0, listStart), /formatStatusAction\('creation', initialNote\.created_by\)/);
  assert.doesNotMatch(notes.slice(listStart), /created_by|formatSource|formatStatusAction/);
  assert.doesNotMatch(source('./TasksView.tsx'), /created_by|formatSource|formatStatusAction/);
  assert.doesNotMatch(source('./TagView.tsx'), /created_by|formatSource|formatStatusAction/);
});
