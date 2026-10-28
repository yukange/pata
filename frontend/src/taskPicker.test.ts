import test from 'node:test';
import assert from 'node:assert/strict';
import type { Task } from '../bindings/pata/internal/storage/markdown/models.js';
import { getInlineTaskCandidates, splitAndSortTasksForPicker, sortTasksChronologically } from './taskPicker.ts';

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

test('splitAndSortTasksForPicker: 按时间正向排序并分成未完成与已完成两块', () => {
  const taskA = makeTask({ id: 't1', title: '待办 1', status: 'todo' as any, created_at: '2026-10-20T12:00:00+08:00' });
  const taskB = makeTask({ id: 't2', title: '已完成 1', status: 'done' as any, created_at: '2026-10-20T09:00:00+08:00' });
  const taskC = makeTask({ id: 't3', title: '待办 2', status: 'todo' as any, created_at: '2026-10-20T08:00:00+08:00' });
  const taskD = makeTask({ id: 't4', title: '已完成 2', status: 'done' as any, created_at: '2026-10-20T14:00:00+08:00' });

  const tasks = [taskA, taskB, taskC, taskD];
  const { uncompletedTasks, completedTasks, totalAvailableCount } = splitAndSortTasksForPicker(tasks, [], '');

  assert.strictEqual(totalAvailableCount, 4);

  // 第一块：未完成，按时间正向排序（t3 08:00 先于 t1 12:00）
  assert.strictEqual(uncompletedTasks.length, 2);
  assert.strictEqual(uncompletedTasks[0].id, 't3');
  assert.strictEqual(uncompletedTasks[1].id, 't1');

  // 第二块：已完成，按时间正向排序（t2 09:00 先于 t4 14:00）
  assert.strictEqual(completedTasks.length, 2);
  assert.strictEqual(completedTasks[0].id, 't2');
  assert.strictEqual(completedTasks[1].id, 't4');
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

test('getInlineTaskCandidates: empty input suggests up to five unfinished tasks, excluding the day plan', () => {
  const tasks = Array.from({ length: 7 }, (_, i) =>
    makeTask({ id: `t${i + 1}`, title: `待办 ${i + 1}`, status: 'todo' as any, created_at: `2026-10-20T10:0${i}:00+08:00` })
  );
  tasks.push(makeTask({ id: 'done', title: '已完成', status: 'done' as any }));

  const result = getInlineTaskCandidates(tasks, ['t1'], '');
  assert.deepEqual(result.uncompletedTasks.map((t) => t.id), ['t2', 't3', 't4', 't5', 't6']);
  assert.deepEqual(result.completedTasks, []);
});

test('getInlineTaskCandidates: typed query matches title/tags and still offers completed tasks', () => {
  const tasks = [
    makeTask({ id: 'todo', title: 'Pata 任务', status: 'todo' as any }),
    makeTask({ id: 'done', title: '设计', tags: ['pata'], status: 'done' as any }),
    makeTask({ id: 'other', title: '其他任务', status: 'todo' as any }),
  ];
  const result = getInlineTaskCandidates(tasks, [], 'PATA');
  assert.deepEqual(result.uncompletedTasks.map((t) => t.id), ['todo']);
  assert.deepEqual(result.completedTasks.map((t) => t.id), ['done']);
});
