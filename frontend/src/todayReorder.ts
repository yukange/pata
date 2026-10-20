/**
 * Today 任务拖拽与重排辅助纯逻辑函数。
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
