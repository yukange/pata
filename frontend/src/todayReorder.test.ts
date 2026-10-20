import test from 'node:test';
import assert from 'node:assert/strict';
import {
  reorderTaskIds,
  computeTargetIndex,
  isPointerInDropZone,
  computeKeyboardReorder,
  computeSiblingDisplacement,
  computeSnapOffset,
  evaluateDragSession,
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

test('computeSiblingDisplacement: 兄弟项平滑让位位移计算', () => {
  const draggedHeight = 44;

  // 1. 向下拖动：从 index 0 拖到 index 2
  // (0, 2] 之间的项（index 1, 2）向上让位 -44，其余为 0
  assert.equal(computeSiblingDisplacement(0, 2, 0, draggedHeight), 0);
  assert.equal(computeSiblingDisplacement(0, 2, 1, draggedHeight), -44);
  assert.equal(computeSiblingDisplacement(0, 2, 2, draggedHeight), -44);
  assert.equal(computeSiblingDisplacement(0, 2, 3, draggedHeight), 0);

  // 2. 向上拖动：从 index 3 拖到 index 1
  // [1, 3) 之间的项（index 1, 2）向下让位 +44，其余为 0
  assert.equal(computeSiblingDisplacement(3, 1, 0, draggedHeight), 0);
  assert.equal(computeSiblingDisplacement(3, 1, 1, draggedHeight), 44);
  assert.equal(computeSiblingDisplacement(3, 1, 2, draggedHeight), 44);
  assert.equal(computeSiblingDisplacement(3, 1, 3, draggedHeight), 0);

  // 3. 原地不动：所有项位移为 0
  assert.equal(computeSiblingDisplacement(1, 1, 0, draggedHeight), 0);
  assert.equal(computeSiblingDisplacement(1, 1, 1, draggedHeight), 0);
  assert.equal(computeSiblingDisplacement(1, 1, 2, draggedHeight), 0);

  // 4. 边界与保护：高度为 0 或负数返回 0
  assert.equal(computeSiblingDisplacement(0, 2, 1, 0), 0);
  assert.equal(computeSiblingDisplacement(0, 2, 1, -10), 0);
});

test('computeSnapOffset: 松手吸附槽位目标偏移计算（支持非等高项）', () => {
  // 模拟三个不同行高的任务行：
  // 任务 0 (短标题): top 0, bottom 36, height 36
  // 任务 1 (多行标签): top 36, bottom 96, height 60
  // 任务 2 (普通高度): top 96, bottom 140, height 44
  const rects = [
    { top: 0, bottom: 36, height: 36 },
    { top: 36, bottom: 96, height: 60 },
    { top: 96, bottom: 140, height: 44 },
  ];

  // 1. 向下拖：任务 0 (height 36) 吸附到 index 2 槽位
  // 目标槽位底部为 140，自身初始底部为 36，偏移为 140 - 36 = 104
  // 新布局为：任务 1 (0..60), 任务 2 (60..104), 任务 0 (104..140, 长度 36)
  assert.equal(computeSnapOffset(0, 2, rects), 104);

  // 2. 向上拖：任务 2 (height 44) 吸附到 index 0 槽位
  // 目标槽位顶部为 0，自身初始顶部为 96，偏移为 0 - 96 = -96
  // 新布局为：任务 2 (0..44), 任务 0 (44..80), 任务 1 (80..140)
  assert.equal(computeSnapOffset(2, 0, rects), -96);

  // 3. 中间项下移：任务 1 (height 60) 吸附到 index 2 槽位
  // 目标槽位底部 140，自身底部 96，偏移为 140 - 96 = 44
  assert.equal(computeSnapOffset(1, 2, rects), 44);

  // 4. 中间项上移：任务 1 吸附到 index 0 槽位
  // 目标槽位顶部 0，自身顶部 36，偏移为 0 - 36 = -36
  assert.equal(computeSnapOffset(1, 0, rects), -36);

  // 5. 原地吸附返回 0
  assert.equal(computeSnapOffset(1, 1, rects), 0);

  // 6. 越界保护
  assert.equal(computeSnapOffset(0, 99, rects), 0);
  assert.equal(computeSnapOffset(-1, 2, rects), 0);
  assert.equal(computeSnapOffset(0, 1, []), 0);
});

test('evaluateDragSession: 连续跟手位移与兄弟项平滑让位状态机', () => {
  const config = {
    taskIds: ['t-0', 't-1', 't-2', 't-3'],
    initialIndex: 0,
    itemRects: [
      { top: 100, bottom: 140, height: 40 },
      { top: 140, bottom: 180, height: 40 },
      { top: 180, bottom: 220, height: 40 },
      { top: 220, bottom: 260, height: 40 },
    ],
    containerRect: { top: 100, bottom: 260, left: 50, right: 350 },
    initialScrollTop: 0,
    startY: 120,
  };

  // 1. 微小位移（还在第 0 项内）：跟手移动，兄弟项不让位，不可提交
  const move1 = evaluateDragSession(config, { pointerX: 100, pointerY: 130, scrollTop: 0 });
  assert.equal(move1.draggedTranslateY, 10);
  assert.equal(move1.targetIndex, 0);
  assert.deepEqual(move1.siblingDisplacements, [0, 0, 0, 0]);
  assert.equal(move1.canCommit, false);

  // 2. 连续向下移动进入第 2 项 (targetIndex = 2)：
  // 拖动项精确跟手 (195 - 120 = 75px)，index 1 与 2 项向上让位 -40px
  const move2 = evaluateDragSession(config, { pointerX: 100, pointerY: 195, scrollTop: 0 });
  assert.equal(move2.draggedTranslateY, 75);
  assert.equal(move2.targetIndex, 2);
  assert.deepEqual(move2.siblingDisplacements, [0, -40, -40, 0]);
  assert.equal(move2.canCommit, true);

  // 3. 移出有效落点区域（例如水平拖出列表）：
  // isOver 为 false，兄弟项全部归位 0，canCommit 为 false
  const moveOut = evaluateDragSession(config, { pointerX: 500, pointerY: 195, scrollTop: 0 });
  assert.equal(moveOut.isOver, false);
  assert.equal(moveOut.targetIndex, 0); // 恢复原索引
  assert.deepEqual(moveOut.siblingDisplacements, [0, 0, 0, 0]);
  assert.equal(moveOut.canCommit, false);
});

test('evaluateDragSession: 边缘自动滚动与指针静止联动更新（修复脱节缺陷）', () => {
  const config = {
    taskIds: ['t-0', 't-1', 't-2', 't-3', 't-4'],
    initialIndex: 0,
    itemRects: [
      { top: 100, bottom: 140, height: 40 }, // mid: 120
      { top: 140, bottom: 180, height: 40 }, // mid: 160
      { top: 180, bottom: 220, height: 40 }, // mid: 200
      { top: 220, bottom: 260, height: 40 }, // mid: 240
      { top: 260, bottom: 300, height: 40 }, // mid: 280
    ],
    containerRect: { top: 100, bottom: 300, left: 50, right: 350 },
    initialScrollTop: 0,
    startY: 120,
  };

  // 用户光标停在底部边缘 Y=200 不动（pointerY 恒定 200）
  // 随着列表由于自动滚动持续滚动，scrollTop 依次增加：
  // 帧 1: scrollTop = 0 -> adjustedY = 200 -> targetIndex = 2
  const frame1 = evaluateDragSession(config, { pointerX: 100, pointerY: 200, scrollTop: 0 });
  assert.equal(frame1.targetIndex, 2);
  assert.deepEqual(frame1.siblingDisplacements, [0, -40, -40, 0, 0]);

  // 帧 2: 滚动条自动向下滚到 30px -> adjustedY = 230 -> 越过分界线 (200+240)/2=220，落点变为 3！
  const frame2 = evaluateDragSession(config, { pointerX: 100, pointerY: 200, scrollTop: 30 });
  assert.equal(frame2.targetIndex, 3);
  assert.deepEqual(frame2.siblingDisplacements, [0, -40, -40, -40, 0]);

  // 帧 3: 滚动条继续滚到 70px -> adjustedY = 270 -> 越过 (240+280)/2=260，落点变为 4！
  const frame3 = evaluateDragSession(config, { pointerX: 100, pointerY: 200, scrollTop: 70 });
  assert.equal(frame3.targetIndex, 4);
  assert.deepEqual(frame3.siblingDisplacements, [0, -40, -40, -40, -40]);

  // 验证指针无需移动，落点随滚动实时推进！
});

test('拖拽排序生命周期：乐观更新与失败回滚模拟', async () => {
  let currentTaskIds = ['t-1', 't-2', 't-3'];
  const snapshotBefore = [...currentTaskIds];

  // 模拟从 index 0 拖到 index 2 (t-1 放到最后)
  const targetIndex = 2;
  const optimisticNext = reorderTaskIds(currentTaskIds, 0, targetIndex);
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
  if (saveSuccess) {
    // 确认保留
  }
  assert.deepEqual(currentTaskIds, ['t-2', 't-3', 't-1']);
});


