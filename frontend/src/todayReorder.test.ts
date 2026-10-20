import test from 'node:test';
import assert from 'node:assert/strict';
import { move } from '@dnd-kit/helpers';
import { reorderTaskIds } from './todayReorder.ts';

test('reorderTaskIds: 基本元素移动', () => {
  const ids = ['t-1', 't-2', 't-3', 't-4'];

  // 下移：把 t-1 移到 t-3 后面 (index 0 -> index 2)
  assert.deepEqual(reorderTaskIds(ids, 0, 2), ['t-2', 't-3', 't-1', 't-4']);

  // 上移：把 t-4 移到第一位 (index 3 -> index 0)
  assert.deepEqual(reorderTaskIds(ids, 3, 0), ['t-4', 't-1', 't-2', 't-3']);

  // 移到相同位置，内容不变
  assert.deepEqual(reorderTaskIds(ids, 1, 1), ['t-1', 't-2', 't-3', 't-4']);

  // 超出边界自动 clamp
  assert.deepEqual(reorderTaskIds(ids, 0, 99), ['t-2', 't-3', 't-4', 't-1']);
  assert.deepEqual(reorderTaskIds(ids, 3, -10), ['t-4', 't-1', 't-2', 't-3']);

  // 原数组不被改变
  assert.deepEqual(ids, ['t-1', 't-2', 't-3', 't-4']);
});

test('reorderTaskIds: 空数组或单元素安全返回', () => {
  assert.deepEqual(reorderTaskIds([], 0, 1), []);
  assert.deepEqual(reorderTaskIds(['t-1'], 0, 1), ['t-1']);
  assert.deepEqual(reorderTaskIds(['t-1', 't-2'], -1, 1), ['t-1', 't-2']);
  assert.deepEqual(reorderTaskIds(['t-1', 't-2'], 5, 0), ['t-1', 't-2']);
});

test('dnd-kit move: 基于 DragEndEvent 正确重排数组', () => {
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

test('拖拽排序生命周期：乐观更新与失败回滚模拟', async () => {
  let currentTaskIds = ['t-1', 't-2', 't-3'];
  const snapshotBefore = [...currentTaskIds];

  const dropEvent = {
    operation: {
      source: { id: 't-1', initialIndex: 0, index: 2 },
      target: { id: 't-3', index: 2 },
    },
  } as any;

  const optimisticNext = move(currentTaskIds, dropEvent) as string[];
  assert.deepEqual(optimisticNext, ['t-2', 't-3', 't-1']);

  // 1. 模拟网络/存储失败回滚
  let saveSuccess = false;
  currentTaskIds = optimisticNext; // 乐观提交
  if (!saveSuccess) {
    currentTaskIds = snapshotBefore; // 回滚
  }
  assert.deepEqual(currentTaskIds, ['t-1', 't-2', 't-3']);

  // 2. 模拟保存成功保持新顺序
  saveSuccess = true;
  currentTaskIds = optimisticNext;
  assert.deepEqual(currentTaskIds, ['t-2', 't-3', 't-1']);
});
