import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { formatStatusAction, isActivitySubmitShortcut } from './activityUtils.ts';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

test('App Shell: 顶层单实例 DetailSplit 与跨页任务详情保持', () => {
  const appPath = path.resolve(__dirname, 'App.tsx');
  const appContent = fs.readFileSync(appPath, 'utf-8');

  // App 顶层单实例 DetailSplit 与 TaskDetailPanel
  assert.ok(
    appContent.includes('<DetailSplit') && appContent.includes('<TaskDetailPanel'),
    'App 顶层应持有全局唯一的 DetailSplit 与 TaskDetailPanel'
  );

  // 跨页面切换时不卸载右侧详情，按任务 ID 隔离
  assert.ok(
    appContent.includes('key={detailSelection.taskId}'),
    'TaskDetailPanel 应使用 taskId 作为 key 隔离任务，跨页面切换保持实例'
  );

  // Today、Tasks、Tag 等子视图不再私自包裹 DetailSplit 或渲染 TaskDetailPanel
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

test('DetailSplit: 拖拽调整、尺寸限制与键盘快捷键微调', () => {
  const splitPath = path.resolve(__dirname, 'DetailSplit.tsx');
  const splitContent = fs.readFileSync(splitPath, 'utf-8');

  // 支持键盘微调与极值快捷定位
  assert.ok(
    splitContent.includes("event.key === 'ArrowLeft'") &&
      splitContent.includes("event.key === 'ArrowRight'"),
    'DetailSplit 应支持方向键微调'
  );
  assert.ok(
    splitContent.includes("event.key === 'Home'") &&
      splitContent.includes("event.key === 'End'"),
    'DetailSplit 应支持 Home/End 快捷极值定位'
  );

  // ARIA 分隔栏无障碍无障碍属性
  assert.ok(
    splitContent.includes('role="separator"') &&
      splitContent.includes('aria-orientation="vertical"'),
    'DetailSplit 应提供标准无障碍 separator 语义'
  );

  // 面板卸载时光标与文本选择状态重置
  assert.ok(
    splitContent.includes("document.body.style.cursor = ''") &&
      splitContent.includes("document.body.style.userSelect = ''"),
    'DetailSplit 应在卸载或结束拖拽时恢复全局 cursor 与 userSelect'
  );
});

test('ActivityItem: 状态事件文案与时间戳层次规范', () => {
  // 1. 状态事件动词：无任务上下文（详情面板）显示“已完成/重新打开”；有任务上下文显示“完成了 /重新打开 ”
  assert.equal(formatStatusAction('completed', false), '已完成');
  assert.equal(formatStatusAction('reopened', false), '重新打开');
  assert.equal(formatStatusAction('completion', true), '完成了 ');
  assert.equal(formatStatusAction('reopen', true), '重新打开 ');
  assert.equal(formatStatusAction('completed', true), '完成了 ');
  assert.equal(formatStatusAction('reopened', true), '重新打开 ');

  const itemPath = path.resolve(__dirname, 'ActivityItem.tsx');
  const content = fs.readFileSync(itemPath, 'utf-8');

  // 2. 悬停出现编辑按钮
  assert.ok(
    content.includes('onStartEdit') && content.includes('Pencil'),
    '人工评论应提供编辑入口'
  );

  // 3. 系统事件包含对应状态图标且只读
  assert.ok(
    content.includes('CheckCircle2') && content.includes('Undo2'),
    '系统事件应包含完成与重新打开图标'
  );

  // 4. 正文与笔记引用组件集成
  assert.ok(
    content.includes('<NoteRefText') && content.includes('<NoteRefTextarea'),
    'ActivityItem 应分别集成笔记引用预览与编辑框'
  );
});

test('ActivityComposer: Cmd/Ctrl+Enter 快捷提交与输入法合成保护', () => {
  // 1. 快捷键逻辑：支持 Cmd+Enter 与 Ctrl+Enter
  assert.equal(isActivitySubmitShortcut({ key: 'Enter', metaKey: true }), true);
  assert.equal(isActivitySubmitShortcut({ key: 'Enter', ctrlKey: true }), true);

  // 2. 普通 Enter 不触发提交
  assert.equal(isActivitySubmitShortcut({ key: 'Enter' }), false);

  // 3. 其它按键不触发提交
  assert.equal(isActivitySubmitShortcut({ key: 'a', metaKey: true }), false);

  // 4. 输入法合成保护：isComposing 或 keyCode 229 时严禁触发提交
  assert.equal(
    isActivitySubmitShortcut({ key: 'Enter', metaKey: true, isComposing: true }),
    false,
    '输入法合成期间不应触发提交'
  );
  assert.equal(
    isActivitySubmitShortcut({ key: 'Enter', metaKey: true, keyCode: 229 }),
    false,
    'keyCode 229 合成事件不应触发提交'
  );

  const composerPath = path.resolve(__dirname, 'ActivityComposer.tsx');
  const content = fs.readFileSync(composerPath, 'utf-8');

  // 5. 输入框与发送按钮位于同一卡片容器，发送按钮位于右下角
  assert.ok(
    content.includes('focus-within:ring-2') && content.includes('justify-end'),
    'ActivityComposer 应提供一体式卡片焦点环与右下角按钮'
  );
});

test('TaskDetail & TodayView: 评论原地编辑、状态事件只读与离开草稿保护', () => {
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

test('Activity 回归: 任务链接在详情栏已打开时仍正确切换目标任务', () => {
  const itemContent = fs.readFileSync(path.resolve(__dirname, 'ActivityItem.tsx'), 'utf-8');
  const todayContent = fs.readFileSync(path.resolve(__dirname, 'TodayView.tsx'), 'utf-8');
  const appContent = fs.readFileSync(path.resolve(__dirname, 'App.tsx'), 'utf-8');

  // ActivityItem 有两类任务链接：系统状态事件与人工评论。
  // 两者都需要屏蔽右栏输入框的先行 blur 自动保存，再将 taskId 交给 App Shell。
  const taskButtons = itemContent.match(/<button[\s\S]*?taskContext\.onOpenTask\(taskContext\.taskId\)[\s\S]*?<\/button>/g) ?? [];
  assert.equal(taskButtons.length, 2, '完成/重开事件与普通评论都应能打开对应任务');
  for (const taskButton of taskButtons) {
    assert.ok(
      taskButton.includes('onMouseDown={(e) => e.preventDefault()}'),
      '每个任务链接都应避免在切换前触发详情失焦自动保存'
    );
  }

  // Today 的任务链接不能只在右栏为空时打开，必须使用 App 级选择入口。
  assert.ok(todayContent.includes('onOpenTask(id, dayPlanTaskIds.includes(id)'));
  assert.ok(appContent.includes('detailSelection?.taskId !== taskID'));
  assert.ok(appContent.includes('setDetailSelection({ taskId: taskID, planContext })'));
  assert.ok(appContent.includes('key={detailSelection.taskId}'));
});

test('Activity 回归: 评论并发编辑保护、日期切换草稿保护与复合保存短路', () => {
  const taskDetailContent = fs.readFileSync(path.resolve(__dirname, 'TaskDetailPanel.tsx'), 'utf-8');
  const todayContent = fs.readFileSync(path.resolve(__dirname, 'TodayView.tsx'), 'utf-8');

  // 1. 同任务内切换编辑评论脏数据保护：TaskDetailPanel 与 TodayView 都在 editDirty 时先走 leavePrompt，禁止无条件覆盖
  assert.ok(
    taskDetailContent.includes('handleStartEditActivity') &&
      taskDetailContent.includes('if (editDirty) {'),
    'TaskDetailPanel 在切换编辑已有评论时应检查 editDirty 并弹窗确认'
  );
  assert.ok(
    todayContent.includes('handleStartEditActivity') &&
      todayContent.includes('if (editDirty) {'),
    'TodayView 在切换编辑已有评论时应检查 editDirty 并弹窗确认'
  );

  // 2. 避免在已有评论正在保存时并发开启其他编辑
  assert.ok(
    taskDetailContent.includes('if (editSaving || submittingActivity) return;'),
    'TaskDetailPanel 保存期间严禁并发开启其他评论编辑'
  );
  assert.ok(
    todayContent.includes('if (editSaving || creatingActivity) return;'),
    'TodayView 保存期间严禁并发开启其他评论编辑'
  );

  // 3. Today 日期切换草稿防护：上一天、下一天与回到今天必须经过 confirmDateChange 拦截
  assert.ok(
    todayContent.includes('confirmDateChange') &&
      todayContent.includes('if (quickActivityBody.trim() || editDirty) {'),
    'TodayView 日期切换前必须保护未发送与编辑中的草稿'
  );
  assert.ok(
    todayContent.includes('confirmDateChange((d) => shiftDateStr(d, -1))') &&
      todayContent.includes('confirmDateChange((d) => shiftDateStr(d, 1))') &&
      todayContent.includes('confirmDateChange(todayStr)'),
    '前一天、后一天与回到今天按钮都必须经过 confirmDateChange 防护'
  );

  // 4. 复合保存短路保护：保存已有评论失败时短路，绝不继续调用 handleAddActivity / handleCreateQuickActivity 产生部分提交
  assert.ok(
    taskDetailContent.includes('if (!editOk) {') &&
      taskDetailContent.includes('// 保存已有评论失败：短路，不继续发送新 Activity，避免部分提交'),
    'TaskDetailPanel 在旧评论保存失败时必须短路，不继续提交新评论'
  );
  assert.ok(
    todayContent.includes('if (!editOk) {') &&
      todayContent.includes('// 保存已有评论失败：短路，不继续发送新 Activity，避免部分提交'),
    'TodayView 在旧评论保存失败时必须短路，不继续提交新评论'
  );
});
