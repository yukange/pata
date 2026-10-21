import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

test('013-001: App Shell 提升 Inspector 所有权', () => {
  const appPath = path.resolve(__dirname, 'App.tsx');
  const appContent = fs.readFileSync(appPath, 'utf-8');

  // App 顶层单实例 DetailSplit 与 TaskDetailPanel
  assert.ok(
    appContent.includes('<DetailSplit') && appContent.includes('<TaskDetailPanel'),
    'App 顶层应持有全局唯一的 DetailSplit 与 TaskDetailPanel'
  );

  // 跨页面切换时不卸载右侧详情
  assert.ok(
    appContent.includes('key={detailSelection.taskId}'),
    'TaskDetailPanel 应使用 taskId 作为 key 隔离任务，跨页面切换保持实例'
  );

  // Today、Tasks、Tag 等子视图不再私自包裹 DetailSplit
  const todayPath = path.resolve(__dirname, 'TodayView.tsx');
  const todayContent = fs.readFileSync(todayPath, 'utf-8');
  assert.ok(
    !todayContent.includes('<DetailSplit') && !todayContent.includes('<TaskDetailPanel'),
    'TodayView 应不再私自渲染 DetailSplit 或 TaskDetailPanel'
  );

  const tasksPath = path.resolve(__dirname, 'TasksView.tsx');
  const tasksContent = fs.readFileSync(tasksPath, 'utf-8');
  assert.ok(
    !tasksContent.includes('<DetailSplit') && !tasksContent.includes('<TaskDetailPanel'),
    'TasksView 应不再私自渲染 DetailSplit 或 TaskDetailPanel'
  );

  const tagPath = path.resolve(__dirname, 'TagView.tsx');
  const tagContent = fs.readFileSync(tagPath, 'utf-8');
  assert.ok(
    !tagContent.includes('<DetailSplit') && !tagContent.includes('<TaskDetailPanel'),
    'TagView 应不再私自渲染 DetailSplit 或 TaskDetailPanel'
  );
});

test('013-002: DetailSplit 拖拽、尺寸持久化与快捷键微调', () => {
  const splitPath = path.resolve(__dirname, 'DetailSplit.tsx');
  const splitContent = fs.readFileSync(splitPath, 'utf-8');

  // 支持键盘微调
  assert.ok(
    splitContent.includes("event.key === 'ArrowLeft'") &&
      splitContent.includes("event.key === 'ArrowRight'"),
    'DetailSplit 应支持方向键微调'
  );

  // 支持 Home / End 极值定位
  assert.ok(
    splitContent.includes("event.key === 'Home'") &&
      splitContent.includes("event.key === 'End'"),
    'DetailSplit 应支持 Home/End 快捷极值定位'
  );

  // 面板卸载时光标与选择重置
  assert.ok(
    splitContent.includes("document.body.style.cursor = ''") &&
      splitContent.includes("document.body.style.userSelect = ''"),
    'DetailSplit 应在卸载或结束拖拽时恢复全局 cursor 与 userSelect'
  );
});

test('013-003: ActivityItem 结构与视觉层次规范', () => {
  const itemPath = path.resolve(__dirname, 'ActivityItem.tsx');
  const content = fs.readFileSync(itemPath, 'utf-8');

  // 1. 时间位于正文上方
  assert.ok(
    content.includes('font-mono text-[11px] text-stone-400 dark:text-stone-500 shrink-0 select-none'),
    'ActivityItem 应使用精简等宽时间展示于顶部'
  );

  // 2. Today 任务链接在时间右侧，保持正常正文字号 (text-xs font-medium)，不刻意变小
  assert.ok(
    content.includes('text-xs font-medium text-emerald-700 dark:text-emerald-400 hover:underline cursor-pointer'),
    '任务链接应保持 text-xs font-medium 正文同级字号'
  );

  // 3. 悬停出现编辑按钮
  assert.ok(
    content.includes('opacity-0 group-hover:opacity-100 focus:opacity-100'),
    '人工评论悬停或聚焦时应显示编辑按钮'
  );

  // 4. 系统事件保持单行只读
  assert.ok(
    content.includes('if (statusEvent) {'),
    '系统状态事件独立渲染为单行只读'
  );
  assert.ok(
    content.includes('CheckCircle2') && content.includes('Undo2'),
    '系统事件应包含完成与重新打开图标'
  );
});

test('013-004: ActivityComposer 一体式容器规范', () => {
  const composerPath = path.resolve(__dirname, 'ActivityComposer.tsx');
  const content = fs.readFileSync(composerPath, 'utf-8');

  // 1. 输入区与发送按钮位于同一圆角卡片容器
  assert.ok(
    content.includes('rounded-xl border border-stone-200 dark:border-stone-800 bg-white dark:bg-stone-950 p-2.5'),
    'ActivityComposer 外层应为圆角卡片容器'
  );
  assert.ok(
    content.includes('focus-within:border-emerald-600/80') &&
      content.includes('focus-within:ring-2 focus-within:ring-emerald-500/20'),
    '外层容器应具有 focus-within 统一环状光圈'
  );

  // 2. 发送按钮位于容器右下角
  assert.ok(
    content.includes('flex items-center justify-end pt-1.5'),
    '发送按钮应位于容器内右下角'
  );

  // 3. 快捷键 ⌘+Enter 且具备 IME 组合保护
  assert.ok(
    content.includes('(e.metaKey || e.ctrlKey)') &&
      content.includes("e.key === 'Enter'") &&
      content.includes('!e.nativeEvent.isComposing') &&
      content.includes('e.keyCode !== 229'),
    '应支持 ⌘+Enter 发送并兼容中文输入法合成'
  );
});

test('013-005: TaskDetailPanel 与 TodayView 人工评论原地编辑与草稿保护', () => {
  const taskDetailPath = path.resolve(__dirname, 'TaskDetailPanel.tsx');
  const taskDetailContent = fs.readFileSync(taskDetailPath, 'utf-8');

  // TaskDetailPanel 支持原地编辑
  assert.ok(
    taskDetailContent.includes('editingActivityId') &&
      taskDetailContent.includes('handleSaveActivityEdit'),
    'TaskDetailPanel 应具备人工评论原地编辑与保存能力'
  );

  // TaskDetailPanel 离开确认覆盖未保存的评论编辑草稿
  assert.ok(
    taskDetailContent.includes('editDirty') &&
      taskDetailContent.includes('confirmLeave'),
    'TaskDetailPanel confirmLeave 应覆盖编辑中的评论草稿'
  );

  const todayViewPath = path.resolve(__dirname, 'TodayView.tsx');
  const todayViewContent = fs.readFileSync(todayViewPath, 'utf-8');

  // TodayView 复用统一 Composer 与 ActivityItem
  assert.ok(
    todayViewContent.includes('<ActivityComposer') &&
      todayViewContent.includes('<ActivityItem'),
    'TodayView 应统一复用 ActivityComposer 与 ActivityItem'
  );

  // TodayView 离开确认覆盖未保存的评论编辑草稿
  assert.ok(
    todayViewContent.includes('editDirty') &&
      todayViewContent.includes('quickActivityBody'),
    'TodayView leaveGuard 应继续保护未发送与编辑中的草稿'
  );
});
