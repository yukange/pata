import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

test('Design Tokens: 核心语义色、字体栈与变量定义完备', () => {
  const cssPath = path.resolve(__dirname, 'index.css');
  const cssContent = fs.readFileSync(cssPath, 'utf-8');

  // 1. 字体栈
  assert.ok(cssContent.includes('--pata-font-sans:'), '应包含系统 sans 字体栈');
  assert.ok(cssContent.includes('--pata-font-mono:'), '应包含系统 mono 字体栈');

  // 2. 语义色
  const requiredTokens = [
    '--pata-bg:',
    '--pata-surface:',
    '--pata-foreground:',
    '--pata-muted-foreground:',
    '--pata-border:',
    '--pata-accent:',
    '--pata-accent-foreground:',
    '--pata-focus-ring:',
    '--pata-brand:',
    '--pata-brand-foreground:',
    '--pata-success:',
    '--pata-warning:',
    '--pata-destructive:',
    '--pata-radius-sm:',
    '--pata-radius-md:',
    '--pata-radius-lg:',
  ];

  for (const token of requiredTokens) {
    assert.ok(cssContent.includes(token), `CSS 中应定义 ${token}`);
  }

  // 3. 强调色跟随系统 AccentColor，与品牌绿保持语义分离
  assert.ok(cssContent.includes('--pata-accent: AccentColor;'), '强调色跟随系统 AccentColor');
  assert.ok(cssContent.includes('--pata-focus-ring: AccentColor;'), '焦点环跟随系统 AccentColor');
  assert.ok(cssContent.includes('--pata-brand: #047857;'), '浅色品牌绿为 emerald-700');
  assert.ok(cssContent.includes('--pata-brand: #10b981;'), '深色品牌绿为 emerald-500');
});

test('可访问键盘焦点: 恢复可见的 :focus-visible，局部隔离编辑器', () => {
  const cssPath = path.resolve(__dirname, 'index.css');
  const cssContent = fs.readFileSync(cssPath, 'utf-8');

  // 禁止全局关闭 outline
  assert.ok(
    !cssContent.includes(':focus,\n:focus-visible {\n  outline: none;\n}'),
    '不应有全局禁用 focus-visible 的破坏性样式'
  );

  // 统一的可见焦点定义
  assert.ok(
    cssContent.includes(':focus-visible {\n  outline: 2px solid var(--pata-focus-ring, AccentColor);'),
    ':focus-visible 应使用系统强调色焦点环'
  );

  // Vditor 编辑区局部排除
  assert.ok(
    cssContent.includes('.vditor-reset:focus,\n.vditor-reset:focus-visible'),
    'Vditor 内部应局部避免与文本光标冲突'
  );

  // 无边框透明输入框与复合卡片内部输入避免内部焦点环
  assert.ok(
    cssContent.includes('textarea.outline-none:focus-visible'),
    '无边框或复合卡片内部 textarea 应避免内部粗糙焦点环'
  );
});

test('任务详情评论框焦点: 外层圆角卡片统一光圈，内层 textarea 无多余焦点框', () => {
  const taskDetailPath = path.resolve(__dirname, 'TaskDetailPanel.tsx');
  const taskDetailContent = fs.readFileSync(taskDetailPath, 'utf-8');

  assert.ok(
    taskDetailContent.includes('focus-within:ring-2 focus-within:ring-emerald-500/20'),
    '任务详情评论卡片外层应使用整卡圆角 focus-within ring'
  );
});

test('排版与正文可读性: Notes 编辑区与代码块字号校准', () => {
  const cssPath = path.resolve(__dirname, 'index.css');
  const cssContent = fs.readFileSync(cssPath, 'utf-8');

  // Note 正文调整为 15px / 1.68
  assert.ok(cssContent.includes('font-size: 15px !important;'), 'Notes 编辑器正文字号应为 15px');
  assert.ok(cssContent.includes('line-height: 1.68 !important;'), 'Notes 编辑器行高应约为 1.68');

  // 代码块调整为 13px / 1.5
  assert.ok(cssContent.includes('font-size: 13px !important;'), '代码块字号应为 13px');
  assert.ok(cssContent.includes('line-height: 1.5 !important;'), '代码块行高应为 1.5');

  // 列表项行高调整为 1.45，紧凑对齐，消除列表回车新行（如 2.）光标悬浮偏上问题
  assert.ok(cssContent.includes('line-height: 1.45 !important;'), '列表项应为紧凑行高 1.45');
});

test('系统 Reduce Motion 遵循: scrollIntoView 避免无条件 smooth', () => {
  const transcriptPath = path.resolve(__dirname, 'TranscriptViewer.tsx');
  const transcriptContent = fs.readFileSync(transcriptPath, 'utf-8');

  assert.ok(
    transcriptContent.includes("window.matchMedia('(prefers-reduced-motion: reduce)')"),
    'TranscriptViewer 应检测系统减少动态效果偏好'
  );
  assert.ok(
    transcriptContent.includes("behavior: prefersReducedMotion ? 'auto' : 'smooth'"),
    '逐字稿跳转滚动在 reduce-motion 下应为 auto'
  );

  const settingsPath = path.resolve(__dirname, 'SettingsView.tsx');
  const settingsContent = fs.readFileSync(settingsPath, 'utf-8');
  assert.ok(
    settingsContent.includes("behavior: prefersReducedMotion ? 'auto' : 'smooth'"),
    '设置页锚点跳转在 reduce-motion 下应为 auto'
  );
});

test('Today 拖拽体验: 引入 closestCenter 算法与降级动效控制', () => {
  const todayListPath = path.resolve(__dirname, 'TodayPlanList.tsx');
  const todayListContent = fs.readFileSync(todayListPath, 'utf-8');

  assert.ok(
    todayListContent.includes("import { closestCenter } from '@dnd-kit/collision';"),
    '应引入 closestCenter 算法消除按格跳滞后感'
  );
  assert.ok(
    todayListContent.includes('collisionDetector: closestCenter'),
    'SortableItem 应配置 closestCenter 碰撞算法'
  );
  assert.ok(
    todayListContent.includes("transition: prefersReducedMotion\n      ? { duration: 0 }"),
    '拖拽过渡应遵守 prefersReducedMotion 降级'
  );
  assert.ok(
    todayListContent.includes('dropAnimation={null}'),
    '放手时应禁用滞后的悬浮动画以消除松手慢半拍感'
  );
});

test('模态与确认弹层收敛: NotesView 复用 ConfirmDialog 基础组件', () => {
  const notesPath = path.resolve(__dirname, 'NotesView.tsx');
  const notesContent = fs.readFileSync(notesPath, 'utf-8');

  assert.ok(
    notesContent.includes("import { ConfirmDialog } from './components/ui/confirm-dialog';"),
    'NotesView 应引入 ConfirmDialog 基础组件'
  );

  // 验证弹窗复用
  assert.ok(notesContent.includes('<ConfirmDialog\n        open={showReloadConfirm}'), '重新加载确认应复用 ConfirmDialog');
  assert.ok(notesContent.includes('<ConfirmDialog\n        open={showLeaveConflictConfirm}'), '冲突离开确认应复用 ConfirmDialog');
  assert.ok(notesContent.includes('<ConfirmDialog\n        open={showSaveFailedConfirm}'), '保存失败离开确认应复用 ConfirmDialog');
  assert.ok(notesContent.includes('<ConfirmDialog\n        open={showReplaceConfirm}'), '替换逐字稿确认应复用 ConfirmDialog');
  assert.ok(notesContent.includes('<ConfirmDialog\n        open={showDeleteConfirm}'), '删除笔记确认应复用 ConfirmDialog');
  assert.ok(notesContent.includes('<ConfirmDialog\n        open={showMissingKeyModal}'), '缺失密钥确认应复用 ConfirmDialog');
  assert.ok(notesContent.includes('<ConfirmDialog\n        open={Boolean(noteToDelete)}'), '列表卡片删除确认应复用 ConfirmDialog');

  // 无标题草稿离开弹层按 Esc 必须正确恢复 Promise
  assert.ok(
    notesContent.includes('leavePromptResolverRef.current = null;\n            resolve?.(false);'),
    '无标题草稿弹窗关闭/按 Esc 时必须调用 resolve(false) 避免页面死锁'
  );

  // ConfirmDialog 阻断外部点击
  const confirmDialogPath = path.resolve(__dirname, 'components/ui/confirm-dialog.tsx');
  const confirmDialogContent = fs.readFileSync(confirmDialogPath, 'utf-8');
  assert.ok(
    confirmDialogContent.includes('disablePointerDismissal={preventDismissOnOutsideClick}'),
    'ConfirmDialog 应正确将 preventDismissOnOutsideClick 传入 disablePointerDismissal'
  );
  assert.ok(
    confirmDialogContent.includes('variant={variant}'),
    'ConfirmDialog 应直接将 variant 传给 Button 避免类名样式冲突'
  );

  // Button 支持 warning 变体
  const buttonPath = path.resolve(__dirname, 'components/ui/button.tsx');
  const buttonContent = fs.readFileSync(buttonPath, 'utf-8');
  assert.ok(buttonContent.includes("'warning'"), 'ButtonVariant 应包含 warning 变体');
  assert.ok(buttonContent.includes('bg-amber-600'), 'Button 样式表应包含 amber 警示色');

  // package.json 声明直接依赖 @dnd-kit/collision
  const packageJsonPath = path.resolve(__dirname, '../package.json');
  const packageJson = JSON.parse(fs.readFileSync(packageJsonPath, 'utf-8'));
  assert.ok(
    packageJson.dependencies['@dnd-kit/collision'],
    'package.json dependencies 必须声明 @dnd-kit/collision'
  );

  // DialogContent 支持 padded 控制并避免 edge-to-edge 弹窗样式冲突
  const dialogPath = path.resolve(__dirname, 'components/ui/dialog.tsx');
  const dialogContent = fs.readFileSync(dialogPath, 'utf-8');
  assert.ok(
    dialogContent.includes('padded = true'),
    'DialogContent 默认应开启 padded 内边距'
  );
  assert.ok(
    dialogContent.includes("padded ? 'p-5 space-y-4' : ''"),
    'DialogContent 应按 padded 属性条件添加 p-5 space-y-4'
  );

  const appPath = path.resolve(__dirname, 'App.tsx');
  const appContent = fs.readFileSync(appPath, 'utf-8');
  assert.ok(
    appContent.includes('padded={false}'),
    'App.tsx Vault 健康弹窗应显式设置 padded={false} 保证贴边展示'
  );
});
