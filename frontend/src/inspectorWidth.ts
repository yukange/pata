/** 单一任务详情右栏的尺寸约束，不依赖 React 或 DOM。 */
export const DEFAULT_INSPECTOR_WIDTH = 400;
export const MIN_INSPECTOR_WIDTH = 280;
export const MAX_INSPECTOR_WIDTH = 720;
export const MIN_WORKSPACE_WIDTH = 320;

/** 小窗口时先保证主区宽度；右栏至少保留可操作的 280px。 */
export function maxInspectorWidth(containerWidth: number): number {
  if (!containerWidth) return MAX_INSPECTOR_WIDTH;
  return Math.max(
    MIN_INSPECTOR_WIDTH,
    Math.min(MAX_INSPECTOR_WIDTH, containerWidth - MIN_WORKSPACE_WIDTH),
  );
}

export function clampInspectorWidth(width: number, containerWidth: number): number {
  return Math.round(Math.max(
    MIN_INSPECTOR_WIDTH,
    Math.min(maxInspectorWidth(containerWidth), width),
  ));
}

export function parseInspectorWidth(value: string | null): number {
  const number = value === null ? NaN : Number(value);
  return Number.isFinite(number) && number >= MIN_INSPECTOR_WIDTH && number <= MAX_INSPECTOR_WIDTH
    ? number : DEFAULT_INSPECTOR_WIDTH;
}
