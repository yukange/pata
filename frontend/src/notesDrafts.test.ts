import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import type { Note } from '../bindings/pata/internal/storage/markdown/models.ts';

// Helper to partition and sort notes according to proposal 016
function partitionAndSortNotes(allNotes: Note[]): { drafts: Note[]; formal: Note[] } {
  const drafts = allNotes
    .filter((n) => Boolean(n.draft))
    .sort((a, b) => {
      const uDiff = new Date(b.updated_at).getTime() - new Date(a.updated_at).getTime();
      if (uDiff !== 0) return uDiff;
      const cDiff = new Date(b.created_at).getTime() - new Date(a.created_at).getTime();
      if (cDiff !== 0) return cDiff;
      return a.id.localeCompare(b.id);
    });

  const formal = allNotes
    .filter((n) => !n.draft)
    .sort((a, b) => {
      const uDiff = new Date(b.updated_at).getTime() - new Date(a.updated_at).getTime();
      if (uDiff !== 0) return uDiff;
      const cDiff = new Date(b.created_at).getTime() - new Date(a.created_at).getTime();
      if (cDiff !== 0) return cDiff;
      return a.id.localeCompare(b.id);
    });

  return { drafts, formal };
}

test('partitionAndSortNotes: groups drafts vs formal notes with independent descending order', () => {
  const notes: Note[] = [
    {
      id: 'note-1',
      title: '正式笔记 1',
      draft: false,
      created_at: '2026-10-26T10:00:00Z',
      updated_at: '2026-10-26T12:00:00Z',
    } as Note,
    {
      id: 'draft-1',
      title: '',
      draft: true,
      body: '草稿正文 1',
      created_at: '2026-10-26T11:00:00Z',
      updated_at: '2026-10-26T13:00:00Z',
    } as Note,
    {
      id: 'note-2',
      title: '正式笔记 2',
      draft: false,
      created_at: '2026-10-26T10:30:00Z',
      updated_at: '2026-10-26T14:00:00Z',
    } as Note,
    {
      id: 'draft-2',
      title: '',
      draft: true,
      body: '草稿正文 2',
      created_at: '2026-10-26T09:00:00Z',
      updated_at: '2026-10-26T15:00:00Z',
    } as Note,
  ];

  const { drafts, formal } = partitionAndSortNotes(notes);

  assert.equal(drafts.length, 2);
  assert.equal(formal.length, 2);

  // Drafts sorted by updated_at desc: draft-2 (15:00) then draft-1 (13:00)
  assert.equal(drafts[0].id, 'draft-2');
  assert.equal(drafts[1].id, 'draft-1');

  // Formal notes sorted by updated_at desc: note-2 (14:00) then note-1 (12:00)
  assert.equal(formal[0].id, 'note-2');
  assert.equal(formal[1].id, 'note-1');
});

test('Search overlay: draft note with empty title formats correctly as draft snippet', () => {
  const draftNote: Note = {
    id: 'draft-abc',
    title: '',
    draft: true,
    body: '## 架构规划\n这是第一条想法\n这是第二条想法',
    created_at: '2026-10-26T10:00:00Z',
    updated_at: '2026-10-26T10:00:00Z',
  } as Note;

  const displayTitle = draftNote.title?.trim() || '草稿';
  assert.equal(displayTitle, '草稿');

  const snippet = draftNote.body
    ?.split('\n')
    .map((l) => l.replace(/^#+\s*/, '').trim())
    .filter(Boolean)
    .slice(0, 2)
    .join(' ') || '';
  assert.equal(snippet, '架构规划 这是第一条想法');
});

test('focusNoteId consumption: waits for notes list to populate before clearing', () => {
  // Simulates the effect logic
  let notesLoaded = false;
  let notes: Note[] = [];
  let focusNoteId: string | null = 'draft-test-123';
  let cleared = false;
  let expandedDrafts = false;

  const runEffect = () => {
    if (!focusNoteId) return;
    if (!notesLoaded && notes.length === 0) return;
    const target = notes.find((n) => n.id === focusNoteId);
    if (target?.draft) {
      expandedDrafts = true;
    }
    cleared = true;
    focusNoteId = null;
  };

  // 1. Initial mount: notes empty, not loaded yet -> must NOT clear focusNoteId
  runEffect();
  assert.equal(cleared, false);
  assert.equal(focusNoteId, 'draft-test-123');
  assert.equal(expandedDrafts, false);

  // 2. Load completes with the target draft
  notes = [{ id: 'draft-test-123', draft: true, title: '', body: '草稿' } as Note];
  notesLoaded = true;
  runEffect();
  assert.equal(cleared, true);
  assert.equal(focusNoteId, null);
  assert.equal(expandedDrafts, true);
});

test('Chinese IME composition guard: prevents Enter from submitting during composition', () => {
  const isEnterPressedDuringComposition = (event: { key: string; isComposing: boolean; keyCode: number }) => {
    if (event.isComposing || event.keyCode === 229) return false;
    return event.key === 'Enter';
  };

  // Enter while composing pinyin (e.g. keyCode 229 or isComposing=true)
  assert.equal(isEnterPressedDuringComposition({ key: 'Enter', isComposing: true, keyCode: 229 }), false);
  assert.equal(isEnterPressedDuringComposition({ key: 'Enter', isComposing: true, keyCode: 13 }), false);
  assert.equal(isEnterPressedDuringComposition({ key: 'Enter', isComposing: false, keyCode: 229 }), false);

  // Real Enter after composition finished
  assert.equal(isEnterPressedDuringComposition({ key: 'Enter', isComposing: false, keyCode: 13 }), true);
});

test('草稿与正式笔记顶栏布局：草稿正文顶格对齐无空行，操作按钮右上角悬浮，正式笔记共用拖拽行', () => {
  const notesSrc = fs.readFileSync(new URL('./NotesView.tsx', import.meta.url), 'utf-8');

  // 1. 正式笔记展开按钮与返回任务入口必须位于同一个 flex 容器中，杜绝 absolute top-5 left-5 叠层冲突
  assert.ok(
    notesSrc.includes('flex items-center gap-2 flex-1 min-w-0') &&
      notesSrc.includes('onToggleListCollapse') &&
      notesSrc.includes('returnToTask'),
    '展开按钮与返回任务按钮应在同一个 flex 容器中并排渲染'
  );
  assert.ok(
    !notesSrc.includes('absolute top-5 left-5'),
    '不应使用 absolute top-5 left-5 导致两个按钮彼此重叠或覆盖首行文本'
  );

  // 2. 顶栏必须对正式笔记保留原生窗口拖拽区域 drag-region
  assert.ok(
    notesSrc.includes('drag-region min-h-[28px]'),
    '顶栏应统一拥有 drag-region 且最小高度对齐，确保拖拽窗口不失效'
  );

  // 3. 不应在正文区域通过 pr-36 弥补浮动按钮，避免长文正文被单侧挤压
  assert.ok(
    !notesSrc.includes('pr-36'),
    '不应对编辑器 wrapper 注入 pr-36 导致草稿全局行宽被单侧挤压'
  );

  // 4. 草稿模式下「转为笔记」与操作菜单在右上角悬浮，正文顶格无独立空行
  assert.ok(
    notesSrc.includes('isDraftNote && !isNaming &&') &&
      notesSrc.includes('absolute top-6 right-6') &&
      notesSrc.includes('handleStartNaming') &&
      notesSrc.includes('转为笔记'),
    '草稿状态下应提供右上角悬浮的「转为笔记」转换入口，避免独占一行造成空隙'
  );

  // 5. 草稿无额外 space-y 间距，正文顶格对齐
  assert.ok(
    notesSrc.includes("!isDraftNote || isNaming ? 'space-y-2.5' : ''"),
    '草稿模式下应移除上层 space-y 间隙，确保正文直接顶格与笔记对齐'
  );
});

test('响应式笔记列表折叠：隐藏状态（width === 0）不应误折叠列表', () => {
  let listCollapsed = false;
  const onResize = (width: number) => {
    if (width > 0 && width < 560) {
      listCollapsed = true;
    }
  };

  // 1. 正常宽度下不折叠
  onResize(800);
  assert.equal(listCollapsed, false);

  // 2. 切至设置页等隐藏场景（display: none 导致 width 为 0），不应误触发折叠
  onResize(0);
  assert.equal(listCollapsed, false);

  // 3. 真实窄窗口（如 500px）下正常自动折叠
  onResize(500);
  assert.equal(listCollapsed, true);

  // 4. 源码校验
  const notesSrc = fs.readFileSync(new URL('./NotesView.tsx', import.meta.url), 'utf-8');
  assert.ok(
    notesSrc.includes('entry.contentRect.width > 0 && entry.contentRect.width < 560'),
    'ResizeObserver 应严格判断 width > 0，避免容器因隐藏（display: none）导致 width 为 0 时误收起列表'
  );
});
