/**
 * Today 任务拖拽与键盘重排核心计算辅助函数。
 * 纯逻辑函数，便于全自动化单元测试。
 */

/**
 * 将列表中的元素从 fromIndex 移动到 toIndex，返回新的数组。
 * 不改变原数组。如索引无效或相同，返回浅拷贝。
 */
export function reorderTaskIds(taskIds: string[], fromIndex: number, toIndex: number): string[] {
  if (taskIds.length <= 1) return [...taskIds];
  if (fromIndex < 0 || fromIndex >= taskIds.length) return [...taskIds];

  const clampedTarget = Math.max(0, Math.min(taskIds.length - 1, toIndex));
  if (fromIndex === clampedTarget) return [...taskIds];

  const result = [...taskIds];
  const [removed] = result.splice(fromIndex, 1);
  result.splice(clampedTarget, 0, removed);
  return result;
}

/**
 * 根据各任务行在拖拽开始时快照的中心点垂直位置，计算当前指针所在的落点索引。
 * 使用相邻中心点的中值作为分界线，保证在单次手势中映射单调递增且不抖动。
 */
export function computeTargetIndex(itemMidpoints: number[], pointerY: number): number {
  const n = itemMidpoints.length;
  if (n <= 1) return 0;

  // 处于第一个中心之前，落点为 0
  if (pointerY <= itemMidpoints[0]) return 0;
  // 处于最后一个中心之后，落点为 n - 1
  if (pointerY >= itemMidpoints[n - 1]) return n - 1;

  for (let i = 0; i < n - 1; i++) {
    const threshold = (itemMidpoints[i] + itemMidpoints[i + 1]) / 2;
    if (pointerY < threshold) {
      return i;
    }
  }

  return n - 1;
}

/**
 * 判断指针坐标 (x, y) 是否在有效列表区域内（可带容差 margin）。
 * 若离开有效区域，拖拽视为松开取消或无效落点，不修改既有计划。
 */
export function isPointerInDropZone(
  rect: { top: number; bottom: number; left: number; right: number },
  x: number,
  y: number,
  margin = 48
): boolean {
  return (
    y >= rect.top - margin &&
    y <= rect.bottom + margin &&
    x >= rect.left - margin &&
    x <= rect.right + margin
  );
}

/**
 * 键盘排序计算：聚焦手柄后通过 ArrowUp / ArrowDown / Home / End 调整次序。
 * 成功移动返回新的 taskIds 数组与目标索引；若已至边界或无效则返回 null。
 */
export function computeKeyboardReorder(
  taskIds: string[],
  taskId: string,
  key: string
): { nextIds: string[]; nextIndex: number } | null {
  if (taskIds.length <= 1) return null;
  const currentIndex = taskIds.indexOf(taskId);
  if (currentIndex === -1) return null;

  let targetIndex = currentIndex;
  if (key === 'ArrowUp') {
    if (currentIndex > 0) targetIndex = currentIndex - 1;
  } else if (key === 'ArrowDown') {
    if (currentIndex < taskIds.length - 1) targetIndex = currentIndex + 1;
  } else if (key === 'Home') {
    if (currentIndex > 0) targetIndex = 0;
  } else if (key === 'End') {
    if (currentIndex < taskIds.length - 1) targetIndex = taskIds.length - 1;
  } else {
    return null;
  }

  if (targetIndex === currentIndex) return null;

  const nextIds = reorderTaskIds(taskIds, currentIndex, targetIndex);
  return { nextIds, nextIndex: targetIndex };
}

/**
 * 计算兄弟列表项在拖拽过程中的平滑让位位移（像素）。
 *
 * @param initialIndex 拖拽项的初始索引
 * @param targetIndex 当前指针所在的目标落点索引
 * @param itemIndex 正在计算位移的兄弟项索引
 * @param draggedHeight 拖拽项的实际高度（像素）
 * @returns 兄弟项应应用的 translateY 偏移量（像素）
 */
export function computeSiblingDisplacement(
  initialIndex: number,
  targetIndex: number,
  itemIndex: number,
  draggedHeight: number
): number {
  if (initialIndex === targetIndex || itemIndex === initialIndex || draggedHeight <= 0) {
    return 0;
  }

  if (targetIndex > initialIndex) {
    // 拖拽项向下移动：位于 (initialIndex, targetIndex] 之间的兄弟项向上让出拖拽项高度
    if (itemIndex > initialIndex && itemIndex <= targetIndex) {
      return -draggedHeight;
    }
  } else if (targetIndex < initialIndex) {
    // 拖拽项向上移动：位于 [targetIndex, initialIndex) 之间的兄弟项向下让出拖拽项高度
    if (itemIndex >= targetIndex && itemIndex < initialIndex) {
      return draggedHeight;
    }
  }

  return 0;
}

/**
 * 计算拖拽松手吸附时，拖拽项对齐到目标槽位的目标垂直位移（像素）。
 * 基于拖拽开始时快照的各项真实边界矩形，完美适应不同行高场景。
 *
 * @param initialIndex 拖拽项初始索引
 * @param targetIndex 目标吸附槽位索引
 * @param itemRects 各项在列表流中的 top, bottom 矩形信息
 * @returns 拖拽项相对其初始位置的 translateY 目标偏移量（像素）
 */
export function computeSnapOffset(
  initialIndex: number,
  targetIndex: number,
  itemRects: Array<{ top: number; bottom: number; height?: number }>
): number {
  const n = itemRects.length;
  if (n <= 1 || targetIndex === initialIndex) return 0;
  if (initialIndex < 0 || initialIndex >= n) return 0;
  if (targetIndex < 0 || targetIndex >= n) return 0;

  if (targetIndex > initialIndex) {
    // 向下移动：拖拽项底部对齐目标项原始底部
    return itemRects[targetIndex].bottom - itemRects[initialIndex].bottom;
  } else {
    // 向上移动：拖拽项顶部对齐目标项原始顶部
    return itemRects[targetIndex].top - itemRects[initialIndex].top;
  }
}

export interface DragSessionConfig {
  taskIds: string[];
  initialIndex: number;
  itemRects: Array<{ top: number; bottom: number; height: number }>;
  containerRect: { top: number; bottom: number; left: number; right: number };
  initialScrollTop: number;
  startY: number;
}

export interface DragSessionUpdate {
  pointerX: number;
  pointerY: number;
  scrollTop: number;
}

export interface DragSessionSnapshot {
  targetIndex: number;
  isOver: boolean;
  draggedTranslateY: number;
  siblingDisplacements: number[];
  canCommit: boolean;
}

/**
 * 单帧拖拽计算核心函数：统一处理指针位移、列表滚动差值、落点有效性判定、
 * 拖动项连续跟手偏移量以及全量兄弟项平滑让位向量。
 */
export function evaluateDragSession(
  config: DragSessionConfig,
  update: DragSessionUpdate
): DragSessionSnapshot {
  const scrollDelta = update.scrollTop - config.initialScrollTop;
  const containerTop = config.containerRect.top - scrollDelta;
  const containerBottom = config.containerRect.bottom - scrollDelta;

  const isOver = isPointerInDropZone(
    {
      top: containerTop,
      bottom: containerBottom,
      left: config.containerRect.left,
      right: config.containerRect.right,
    },
    update.pointerX,
    update.pointerY,
    48
  );

  const itemMids = config.itemRects.map((r) => (r.top + r.bottom) / 2);
  const adjustedY = update.pointerY + scrollDelta;
  const targetIndex = isOver ? computeTargetIndex(itemMids, adjustedY) : config.initialIndex;

  const draggedHeight = config.itemRects[config.initialIndex]?.height ?? 0;
  const draggedTranslateY = update.pointerY - config.startY + scrollDelta;

  const siblingDisplacements = config.itemRects.map((_, idx) =>
    isOver
      ? computeSiblingDisplacement(config.initialIndex, targetIndex, idx, draggedHeight)
      : 0
  );

  const canCommit = isOver && targetIndex !== config.initialIndex;

  return {
    targetIndex,
    isOver,
    draggedTranslateY,
    siblingDisplacements,
    canCommit,
  };
}


