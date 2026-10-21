/**
 * 统一 Activity 相关的展示文案与交互逻辑。
 * 不依赖 React 或 DOM，可在 Node 测试中直接运行。
 */

/**
 * 格式化状态事件的动词短语。
 * - 详情面板（无任务上下文）：展示精简动词“已完成”或“重新打开”；
 * - 今日视图（有任务上下文）：展示及物动词“完成了 ”或“重新打开 ”，后续衔接任务标题链接。
 */
export function formatStatusAction(action: string, hasTaskContext: boolean): string {
  const isCompleted = action === 'completed' || action === 'completion';
  return hasTaskContext
    ? (isCompleted ? '完成了 ' : '重新打开 ')
    : (isCompleted ? '已完成' : '重新打开');
}

/**
 * 判断键盘事件是否符合活动记录的提交快捷键 (⌘+Enter / Ctrl+Enter)。
 * 并保护输入法合成态（isComposing 或 keyCode 229 时严禁触发提交）。
 */
export function isActivitySubmitShortcut(e: {
  key: string;
  metaKey?: boolean;
  ctrlKey?: boolean;
  isComposing?: boolean;
  keyCode?: number;
}): boolean {
  if (e.isComposing || e.keyCode === 229) return false;
  return (Boolean(e.metaKey) || Boolean(e.ctrlKey)) && e.key === 'Enter';
}
