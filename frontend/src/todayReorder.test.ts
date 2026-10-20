import test from 'node:test';
import assert from 'node:assert/strict';
import {
  reorderTaskIds,
  computeTargetIndex,
  isPointerInDropZone,
  computeKeyboardReorder,
} from './todayReorder.ts';

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

test('computeTargetIndex: 根据中心点与中值计算落点', () => {
  // 假设 4 个项的垂直中心点分别为 100, 140, 180, 220
  // 分界线为 120, 160, 200
  const mids = [100, 140, 180, 220];

  // 在第一项上方或附近
  assert.equal(computeTargetIndex(mids, 80), 0);
  assert.equal(computeTargetIndex(mids, 100), 0);
  assert.equal(computeTargetIndex(mids, 119), 0);

  // 越过第一个分界线 120 进入第二项
  assert.equal(computeTargetIndex(mids, 120), 1);
  assert.equal(computeTargetIndex(mids, 150), 1);
  assert.equal(computeTargetIndex(mids, 159), 1);

  // 越过第二个分界线 160 进入第三项
  assert.equal(computeTargetIndex(mids, 160), 2);
  assert.equal(computeTargetIndex(mids, 190), 2);

  // 越过第三个分界线 200 进入第四项
  assert.equal(computeTargetIndex(mids, 200), 3);
  assert.equal(computeTargetIndex(mids, 250), 3);

  // 边界保护
  assert.equal(computeTargetIndex([], 100), 0);
  assert.equal(computeTargetIndex([150], 200), 0);
});

test('isPointerInDropZone: 判断指针是否在有效区域内', () => {
  const rect = { top: 100, bottom: 400, left: 50, right: 350 };

  // 区域内部
  assert.equal(isPointerInDropZone(rect, 100, 200), true);

  // 边缘及容差以内 (默认 margin = 48)
  assert.equal(isPointerInDropZone(rect, 40, 90), true);
  assert.equal(isPointerInDropZone(rect, 370, 420), true);

  // 超出容差范围（例如拖至侧边栏或窗口外）
  assert.equal(isPointerInDropZone(rect, -10, 200), false);
  assert.equal(isPointerInDropZone(rect, 500, 200), false);
  assert.equal(isPointerInDropZone(rect, 200, 20), false);
  assert.equal(isPointerInDropZone(rect, 200, 500), false);
});

test('computeKeyboardReorder: 键盘方向键调整次序', () => {
  const ids = ['t-1', 't-2', 't-3'];

  // t-2 上移一位
  const upRes = computeKeyboardReorder(ids, 't-2', 'ArrowUp');
  assert.ok(upRes);
  assert.deepEqual(upRes.nextIds, ['t-2', 't-1', 't-3']);
  assert.equal(upRes.nextIndex, 0);

  // t-2 下移一位
  const downRes = computeKeyboardReorder(ids, 't-2', 'ArrowDown');
  assert.ok(downRes);
  assert.deepEqual(downRes.nextIds, ['t-1', 't-3', 't-2']);
  assert.equal(downRes.nextIndex, 2);

  // t-3 移至顶部 Home
  const homeRes = computeKeyboardReorder(ids, 't-3', 'Home');
  assert.ok(homeRes);
  assert.deepEqual(homeRes.nextIds, ['t-3', 't-1', 't-2']);
  assert.equal(homeRes.nextIndex, 0);

  // t-1 移至末尾 End
  const endRes = computeKeyboardReorder(ids, 't-1', 'End');
  assert.ok(endRes);
  assert.deepEqual(endRes.nextIds, ['t-2', 't-3', 't-1']);
  assert.equal(endRes.nextIndex, 2);

  // 已经到顶部继续按 ArrowUp / Home 返回 null
  assert.equal(computeKeyboardReorder(ids, 't-1', 'ArrowUp'), null);
  assert.equal(computeKeyboardReorder(ids, 't-1', 'Home'), null);

  // 已经到底部继续按 ArrowDown / End 返回 null
  assert.equal(computeKeyboardReorder(ids, 't-3', 'ArrowDown'), null);
  assert.equal(computeKeyboardReorder(ids, 't-3', 'End'), null);

  // 不支持的按键或未知任务 ID 返回 null
  assert.equal(computeKeyboardReorder(ids, 't-2', 'Enter'), null);
  assert.equal(computeKeyboardReorder(ids, 'unknown-task', 'ArrowUp'), null);
  assert.equal(computeKeyboardReorder(['single'], 'single', 'ArrowUp'), null);
});
