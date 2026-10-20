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
