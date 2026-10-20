import test from 'node:test';
import assert from 'node:assert/strict';
import { move } from '@dnd-kit/helpers';

test('dnd-kit move: 基于 DragEndEvent 正确重排任务 ID 列表', () => {
  const items = ['t-1', 't-2', 't-3', 't-4'];

  // 1. 向下拖动：t-1 拖到 t-3 槽位
  const downEvent = {
    operation: {
      source: { id: 't-1', initialIndex: 0, index: 2 },
      target: { id: 't-3', index: 2 },
    },
  } as any;
  assert.deepEqual(move(items, downEvent), ['t-2', 't-3', 't-1', 't-4']);

  // 2. 向上拖动：t-4 拖到 t-2 槽位
  const upEvent = {
    operation: {
      source: { id: 't-4', initialIndex: 3, index: 1 },
      target: { id: 't-2', index: 1 },
    },
  } as any;
  assert.deepEqual(move(items, upEvent), ['t-1', 't-4', 't-2', 't-3']);

  // 3. 原地释放：位置不变
  const sameEvent = {
    operation: {
      source: { id: 't-2', initialIndex: 1, index: 1 },
      target: { id: 't-2', index: 1 },
    },
  } as any;
  assert.deepEqual(move(items, sameEvent), ['t-1', 't-2', 't-3', 't-4']);

  // 4. 操作取消：保持原数组不变
  const cancelEvent = {
    operation: {
      canceled: true,
      source: { id: 't-1', initialIndex: 0, index: 2 },
      target: { id: 't-3', index: 2 },
    },
  } as any;
  assert.deepEqual(move(items, cancelEvent), ['t-1', 't-2', 't-3', 't-4']);
});

test('dnd-kit move: 含有失效/占位任务 ID 时正常重排', () => {
  const items = ['ghost-deleted-1', 't-2', 't-3'];

  // 把 t-3 拖到 t-2 前方
  const event = {
    operation: {
      source: { id: 't-3', initialIndex: 2, index: 1 },
      target: { id: 't-2', index: 1 },
    },
  } as any;

  assert.deepEqual(move(items, event), ['ghost-deleted-1', 't-3', 't-2']);
});
