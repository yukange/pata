import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

test('侧栏收起状态记忆与偏好持久化（默认完全收起）', () => {
  const appPath = path.resolve(__dirname, 'App.tsx');
  const appContent = fs.readFileSync(appPath, 'utf-8');

  // 1. 初始化偏好读取与异常回退（默认收起）
  assert.ok(
    appContent.includes("localStorage.getItem('pata_sidebar_collapsed')"),
    '应从 localStorage 读取 pata_sidebar_collapsed 作为初始状态'
  );
  assert.ok(
    appContent.includes('return true; // 默认收起'),
    '未设置偏好时应默认完全收起'
  );

  // 2. 状态变更持久化
  assert.ok(
    appContent.includes("localStorage.setItem('pata_sidebar_collapsed', String(sidebarCollapsed))"),
    '侧栏状态变化时应持久化至 localStorage'
  );

  // 3. 收起态完全折叠并由顶栏承接导航，展开态使用动态宽度
  assert.ok(
    appContent.includes('{sidebarCollapsed && (') && appContent.includes('{!sidebarCollapsed && ('),
    '收起时侧栏完全折叠隐藏，由顶栏承接分段导航；展开时展示侧边栏'
  );
  assert.ok(
    appContent.includes('style={{ width: `${sidebarWidth}px` }}'),
    '展开态侧栏使用动态宽度 sidebarWidth'
  );
});

test('侧栏收起交互规范：避让交通灯、Logo 右侧按钮一致性、快捷键与拖拽折叠', () => {
  const appPath = path.resolve(__dirname, 'App.tsx');
  const appContent = fs.readFileSync(appPath, 'utf-8');

  // 避让交通灯（84px 安全边距）
  assert.ok(
    appContent.includes('pl-[84px]'),
    '顶栏与展开侧栏顶部均应保留 84px 避让 macOS 交通灯'
  );

  // 展开与收起按钮均位于 Logo 右侧
  assert.ok(
    appContent.includes('SidebarToggleIcon collapsed={true}') &&
    appContent.includes('SidebarToggleIcon collapsed={false}'),
    '展开与收起均使用规范的侧栏切换图标'
  );
  assert.ok(
    appContent.includes('setSidebarCollapsed(false)') && appContent.includes('setSidebarCollapsed(true)'),
    '应提供展开与收起的切换操作'
  );

  // 快捷键 ⌃⌘S 支持
  assert.ok(
    appContent.includes("e.code === 'KeyS'") &&
    appContent.includes('e.metaKey && e.ctrlKey'),
    '应支持 macOS 原生快捷键 ⌃⌘S 切换侧栏'
  );

  // 拖拽过度向左折叠 (Drag to fold)
  assert.ok(
    appContent.includes('e.clientX < 140') && appContent.includes('setSidebarCollapsed(true)'),
    '侧栏向左过度拖拽至小于 140px 时应自动吸附折叠'
  );

  // 顶部拖拽条与交互保护
  assert.ok(
    appContent.includes('drag-region') && appContent.includes('no-drag-region'),
    '顶栏应合理包含 drag-region 与 no-drag-region'
  );

  // 导航项在 active 时采用中性高对比文字与底色
  assert.ok(
    appContent.includes("activeNav === 'today'") &&
      appContent.includes('bg-stone-200/80') &&
      appContent.includes('text-stone-900'),
    '导航项在 active 时应使用克制的中性高对比底色与文字'
  );
});

test('工作区页面顶部工具栏支持原生窗口拖拽', () => {
  const todayPath = path.resolve(__dirname, 'TodayView.tsx');
  const todayContent = fs.readFileSync(todayPath, 'utf-8');
  assert.ok(
    todayContent.includes('drag-region') && todayContent.includes('no-drag-region'),
    'TodayView DateBar 应包含 drag-region 与 no-drag-region 交互保护'
  );

  const taskDetailPath = path.resolve(__dirname, 'TaskDetailPanel.tsx');
  const taskDetailContent = fs.readFileSync(taskDetailPath, 'utf-8');
  assert.ok(
    taskDetailContent.includes('drag-region') && taskDetailContent.includes('no-drag-region'),
    'TaskDetailPanel 顶部工具栏应支持原生拖拽'
  );
});
