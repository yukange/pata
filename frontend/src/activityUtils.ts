/**
 * 统一 Activity 相关的展示文案与交互逻辑。
 * 不依赖 React 或 DOM，可在 Node 测试中直接运行。
 */

/** 缺省来源为我，来源描述不依赖任务上下文。 */
export function formatSource(by?: string): string {
  return by === 'agent' ? 'Agent' : '我';
}

export function formatStatusAction(action: string, by?: string): string {
  const verb = action === 'creation' ? '创建'
    : action === 'completed' || action === 'completion' ? '完成' : '重新打开';
  return `由${by === 'agent' ? ' Agent ' : '我'}${verb}`;
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
