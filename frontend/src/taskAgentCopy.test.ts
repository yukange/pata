import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { componentCallbacks } from '../scripts/componentCallbacks.ts';

const callback = componentCallbacks(new URL('./TaskDetailPanel.tsx', import.meta.url));
const isMCPReadyForAgent = callback('isMCPReadyForAgent');

test('Copy for Agent is available only while MCP is enabled, running, and on the current vault', () => {
  assert.equal(isMCPReadyForAgent({ enabled: true, running: true, vaultChanged: false }), true);
  assert.equal(isMCPReadyForAgent({ enabled: false, running: false, vaultChanged: false }), false);
  assert.equal(isMCPReadyForAgent({ enabled: true, running: false, vaultChanged: false }), false);
  assert.equal(isMCPReadyForAgent({ enabled: true, running: true, vaultChanged: true }), false);
});

test('Copy for Agent uses the stable task URI, without MCP setup prose', async () => {
  const copied: string[] = [];
  const menu: boolean[] = [];
  const feedback: boolean[] = [];
  const errors: string[] = [];
  let timeout: (() => void) | undefined;
  const context = {
    taskId: 't-01abc',
    formDirty: false,
    saving: false,
    MCPService: { GetStatus: async () => ({ enabled: true, running: true, vaultChanged: false }) },
    isMCPReadyForAgent,
    Clipboard: { SetText: async (text: string) => { copied.push(text); } },
    setMenuOpen: (value: boolean) => menu.push(value),
    setCopiedForAgent: (value: boolean) => feedback.push(value),
    setDetailError: (message: string) => errors.push(message),
    copyFeedbackTimerRef: { current: null },
    window: {
      clearTimeout: () => {},
      setTimeout: (fn: () => void, ms: number) => {
        assert.equal(ms, 2000);
        timeout = fn;
        return 1;
      },
    },
  };
  await callback('handleCopyForAgent', context)();
  assert.deepEqual(copied, ['处理这个 Pata 任务：pata://task/t-01abc']);
  assert.deepEqual(menu, [false]);
  assert.deepEqual(feedback, [true]);
  assert.deepEqual(errors, []);
  timeout?.();
  assert.deepEqual(feedback, [true, false]);
});

test('Copy for Agent refuses to copy when MCP stops or switches vault after the menu opened', async () => {
  for (const status of [
    { enabled: true, running: false, vaultChanged: false },
    { enabled: true, running: true, vaultChanged: true },
  ]) {
    const copied: string[] = [];
    const errors: string[] = [];
    await callback('handleCopyForAgent', {
      taskId: 't-01abc',
      formDirty: false,
      saving: false,
      MCPService: { GetStatus: async () => status },
      isMCPReadyForAgent,
      Clipboard: { SetText: async (text: string) => { copied.push(text); } },
      setMenuOpen: () => {},
      setCopiedForAgent: () => {},
      setDetailError: (message: string) => errors.push(message),
      copyFeedbackTimerRef: { current: null },
    })();
    assert.deepEqual(copied, []);
    assert.deepEqual(errors, ['MCP 服务未就绪，请先在设置中启动或重启服务']);
  }
});

test('Copy for Agent saves dirty task edits before copying and preserves save failures', async () => {
  for (const saved of [true, false]) {
    const calls: string[] = [];
    const errors: string[] = [];
    await callback('handleCopyForAgent', {
      taskId: 't-01abc',
      formDirty: true,
      saving: false,
      saveTask: async () => {
        calls.push('save');
        if (!saved) errors.push('保存冲突，草稿已保留');
        return saved;
      },
      MCPService: { GetStatus: async () => {
        calls.push('status');
        return { enabled: true, running: true, vaultChanged: false };
      } },
      isMCPReadyForAgent,
      Clipboard: { SetText: async () => { calls.push('copy'); } },
      setMenuOpen: () => {},
      setCopiedForAgent: () => { calls.push('feedback'); },
      setDetailError: (message: string) => errors.push(message),
      copyFeedbackTimerRef: { current: null },
      window: { setTimeout: () => 1, clearTimeout: () => {} },
    })();
    assert.deepEqual(calls, saved ? ['save', 'status', 'copy', 'feedback'] : ['save']);
    assert.deepEqual(errors, saved ? [] : ['保存冲突，草稿已保留']);
  }
});

test('Copy for Agent waits for an in-flight task save and refuses to copy if it fails', async () => {
  for (const saved of [true, false]) {
    const calls: string[] = [];
    let finish!: (saved: boolean) => void;
    const pending = callback('handleCopyForAgent', {
      taskId: 't-01abc',
      formDirty: false,
      saving: true,
      taskSaveRef: { current: new Promise<boolean>((resolve) => { finish = resolve; }) },
      MCPService: { GetStatus: async () => {
        calls.push('status');
        return { enabled: true, running: true, vaultChanged: false };
      } },
      isMCPReadyForAgent,
      Clipboard: { SetText: async () => { calls.push('copy'); } },
      setMenuOpen: () => {},
      setCopiedForAgent: () => { calls.push('feedback'); },
      setDetailError: (message: string) => { throw new Error(message); },
      copyFeedbackTimerRef: { current: null },
      window: { setTimeout: () => 1, clearTimeout: () => {} },
    })();
    await Promise.resolve();
    assert.deepEqual(calls, [], 'handoff must wait until the task save finishes');
    finish(saved);
    await pending;
    assert.deepEqual(calls, saved ? ['status', 'copy', 'feedback'] : []);
  }
});

test('Clipboard failure explains what happened without reporting a successful copy', async () => {
  const feedback: boolean[] = [];
  const errors: string[] = [];
  await callback('handleCopyForAgent', {
    taskId: 't-01abc',
    formDirty: false,
    saving: false,
    MCPService: { GetStatus: async () => ({ enabled: true, running: true, vaultChanged: false }) },
    isMCPReadyForAgent,
    Clipboard: { SetText: async () => { throw new Error('clipboard denied'); } },
    setMenuOpen: () => {},
    setCopiedForAgent: (value: boolean) => feedback.push(value),
    setDetailError: (message: string) => errors.push(message),
    copyFeedbackTimerRef: { current: null },
  })();
  assert.deepEqual(feedback, []);
  assert.deepEqual(errors, ['检查 MCP 状态或复制失败，请重试']);
});

test('Copy for Agent includes hover preview tooltip matching settings copy instruction preview', () => {
  const panelSrc = fs.readFileSync(new URL('./TaskDetailPanel.tsx', import.meta.url), 'utf-8');
  assert.ok(panelSrc.includes('id="task-agent-prompt-preview"'), '应包含 task-agent-prompt-preview ID');
  assert.ok(panelSrc.includes('role="tooltip"'), '应具有标准 tooltip 无障碍角色');
  assert.ok(panelSrc.includes('aria-describedby="task-agent-prompt-preview"'), '按钮应通过 aria-describedby 关联预览');
  assert.ok(panelSrc.includes('Agent 任务指令'), '悬停预览标题应为 Agent 任务指令');
  assert.ok(panelSrc.includes('group-hover:block'), '悬停时应展示预览框');
  assert.ok(panelSrc.includes('group-focus-within:block'), '获得焦点时应展示预览框');
  assert.ok(panelSrc.includes('select-text'), '预览文本应可选中复制');
  assert.ok(
    panelSrc.includes('`处理这个 Pata 任务：pata://task/${taskId}`'),
    '预览文本应包含正确的任务指令格式'
  );
});
