import test from 'node:test';
import assert from 'node:assert/strict';
import type { Task } from '../bindings/pata/internal/storage/markdown/models.js';
import { getInlineTaskCandidates, getInlineTaskFooterHint, splitAndSortTasksForPicker, sortTasksChronologically } from './taskPicker.ts';

function makeTask(overrides: Partial<Task>): Task {
  return {
    type: 'task' as any,
    id: overrides.id || 'task-default',
    title: overrides.title || 'Untitled',
    description: '',
    status: overrides.status ?? ('todo' as any),
    due: null,
    created_at: overrides.created_at ?? '2026-10-20T10:00:00+08:00',
    updated_at: '2026-10-20T10:00:00+08:00',
    body: '',
    tags: overrides.tags ?? [],
    ...overrides,
  };
}

test('splitAndSortTasksForPicker: 按时间倒序排序并分成未完成与已完成两块', () => {
  const taskA = makeTask({ id: 't1', title: '待办 1', status: 'todo' as any, created_at: '2026-10-20T12:00:00+08:00' });
  const taskB = makeTask({ id: 't2', title: '已完成 1', status: 'done' as any, created_at: '2026-10-20T09:00:00+08:00' });
  const taskC = makeTask({ id: 't3', title: '待办 2', status: 'todo' as any, created_at: '2026-10-20T08:00:00+08:00' });
  const taskD = makeTask({ id: 't4', title: '已完成 2', status: 'done' as any, created_at: '2026-10-20T14:00:00+08:00' });

  const tasks = [taskA, taskB, taskC, taskD];
  const { uncompletedTasks, completedTasks, totalAvailableCount } = splitAndSortTasksForPicker(tasks, [], '');

  assert.strictEqual(totalAvailableCount, 4);

  // 第一块：未完成，按时间倒序排序（t1 12:00 先于 t3 08:00）
  assert.strictEqual(uncompletedTasks.length, 2);
  assert.strictEqual(uncompletedTasks[0].id, 't1');
  assert.strictEqual(uncompletedTasks[1].id, 't3');

  // 第二块：已完成，按时间倒序排序（t4 14:00 先于 t2 09:00）
  assert.strictEqual(completedTasks.length, 2);
  assert.strictEqual(completedTasks[0].id, 't4');
  assert.strictEqual(completedTasks[1].id, 't2');
});

test('splitAndSortTasksForPicker: 过滤已在计划中的任务', () => {
  const task1 = makeTask({ id: 't1', title: '任务 1', status: 'todo' as any });
  const task2 = makeTask({ id: 't2', title: '任务 2', status: 'done' as any });

  const { uncompletedTasks, completedTasks, totalAvailableCount } = splitAndSortTasksForPicker(
    [task1, task2],
    ['t1'],
    ''
  );

  assert.strictEqual(totalAvailableCount, 1);
  assert.strictEqual(uncompletedTasks.length, 0);
  assert.strictEqual(completedTasks.length, 1);
  assert.strictEqual(completedTasks[0].id, 't2');
});

test('splitAndSortTasksForPicker: 搜索过滤支持标题和标签', () => {
  const task1 = makeTask({ id: 't1', title: '设计 Figma 原型', tags: ['ui', 'pata'], status: 'todo' as any });
  const task2 = makeTask({ id: 't2', title: '编写代码', tags: ['frontend'], status: 'todo' as any });
  const task3 = makeTask({ id: 't3', title: '修复 bug', tags: ['ui'], status: 'done' as any });

  // 搜 "ui"
  const resByTag = splitAndSortTasksForPicker([task1, task2, task3], [], 'UI');
  assert.strictEqual(resByTag.totalAvailableCount, 2);
  assert.strictEqual(resByTag.uncompletedTasks[0].id, 't1');
  assert.strictEqual(resByTag.completedTasks[0].id, 't3');

  // 搜 "代码"
  const resByTitle = splitAndSortTasksForPicker([task1, task2, task3], [], '代码');
  assert.strictEqual(resByTitle.totalAvailableCount, 1);
  assert.strictEqual(resByTitle.uncompletedTasks[0].id, 't2');
  assert.strictEqual(resByTitle.completedTasks.length, 0);
});

test('splitAndSortTasksForPicker: 兼容 doing 等状态归入未完成', () => {
  const taskDoing = makeTask({ id: 't1', title: '进行中任务', status: 'doing' as any });
  const { uncompletedTasks, completedTasks } = splitAndSortTasksForPicker([taskDoing], [], '');
  assert.strictEqual(uncompletedTasks.length, 1);
  assert.strictEqual(completedTasks.length, 0);
});

test('getInlineTaskCandidates: empty input suggests both unfinished and completed tasks for tabs, excluding day plan', () => {
  const tasks = Array.from({ length: 7 }, (_, i) =>
    makeTask({ id: `t${i + 1}`, title: `待办 ${i + 1}`, status: 'todo' as any, created_at: `2026-10-20T10:0${i}:00+08:00` })
  );
  // Add 6 completed tasks to verify no artificial truncation to 5
  for (let i = 1; i <= 6; i++) {
    tasks.push(makeTask({ id: `done${i}`, title: `已完成 ${i}`, status: 'done' as any, created_at: `2026-10-21T10:0${i}:00+08:00` }));
  }

  const result = getInlineTaskCandidates(tasks, ['t1'], '');
  // Newest first: t7 is latest, t2 is earliest
  assert.deepEqual(result.uncompletedTasks.map((t) => t.id), ['t7', 't6', 't5', 't4', 't3', 't2']);
  assert.deepEqual(result.completedTasks.map((t) => t.id), ['done6', 'done5', 'done4', 'done3', 'done2', 'done1']);
  assert.deepEqual(result.searchResults, []);
});

test('getInlineTaskCandidates: typed query matches title/tags and provides unified search results', () => {
  const tasks = [
    makeTask({ id: 'todo', title: 'Pata 任务', status: 'todo' as any }),
    makeTask({ id: 'done', title: '设计', tags: ['pata'], status: 'done' as any }),
    makeTask({ id: 'other', title: '其他任务', status: 'todo' as any }),
  ];
  const result = getInlineTaskCandidates(tasks, [], 'PATA');
  assert.deepEqual(result.uncompletedTasks.map((t) => t.id), ['todo']);
  assert.deepEqual(result.completedTasks.map((t) => t.id), ['done']);
  assert.deepEqual(result.searchResults.map((t) => t.id), ['todo', 'done']);
});

test('getInlineTaskFooterHint: reports correct Enter behavior depending on selection and input presence', () => {
  // Empty input (browsing): always shows unified hint for Enter, Up/Down, and Left/Right
  assert.strictEqual(getInlineTaskFooterHint(false, false), '↵ 加入今日 · ↑↓ 选择任务 · ←→ 切换分类');
  assert.strictEqual(getInlineTaskFooterHint(true, false), '↵ 加入今日 · ↑↓ 选择任务 · ←→ 切换分类');

  // Typed input with no active arrow selection: Enter creates new task
  assert.strictEqual(getInlineTaskFooterHint(false, true), '↵ 创建新任务 · ↑↓ 选择已有任务');
  // Typed input with active arrow selection: Enter adds selected existing task
  assert.strictEqual(getInlineTaskFooterHint(true, true), '↵ 加入已有任务 · ↑↓ 切换');
});
