import test from 'node:test';
import assert from 'node:assert/strict';
import React from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { componentCallbacks } from '../scripts/componentCallbacks.ts';

const callback = componentCallbacks(new URL('./App.tsx', import.meta.url));

function updater() {
  const calls: string[] = [];
  const context: Record<string, any> = {
    draftCheckersRef: { current: new Map() }, detailRef: { current: null },
    showToast: (message: string) => calls.push(message),
    UpdaterService: {
      ApplyUpdateAndRestart: async () => { calls.push('restart'); },
      SetWaitingInstall: async () => { calls.push('wait'); },
    },
  };
  context.checkAllDrafts = callback('checkAllDrafts', context);
  return { context, calls, register: callback('registerDraftChecker', context), ready: callback('event:pata:updater:ready-to-apply', context), install: callback('handleWaitingInstallClick', context) };
}

test('App update-ready waits for registered drafts and only installs on a later user action', async () => {
  const h = updater();
  let dirty = true;
  const unregister = h.register('notes', () => dirty);
  await h.ready();
  assert.deepEqual(h.calls, ['wait']);
  await h.install();
  assert.deepEqual(h.calls, ['wait', '请先保存当前编辑']);
  dirty = false;
  assert.equal(h.context.checkAllDrafts(), false);
  assert.ok(!h.calls.includes('restart'), 'saving a draft must not restart automatically');
  await h.install();
  assert.equal(h.calls.at(-1), 'restart');
  unregister();
  assert.equal(h.context.draftCheckersRef.current.size, 0);
});

test('App update-ready checks inspector drafts and restarts immediately only when clean', async () => {
  const h = updater();
  h.context.detailRef.current = { hasDraft: () => true };
  await h.ready();
  assert.deepEqual(h.calls, ['wait']);
  h.context.detailRef.current = { hasDraft: () => false };
  await h.ready();
  assert.deepEqual(h.calls, ['wait', 'restart']);
});

test('App reports restart failures without clearing drafts', async () => {
  const h = updater();
  h.context.UpdaterService.ApplyUpdateAndRestart = async () => { throw new Error('helper failed'); };
  await h.ready();
  assert.deepEqual(h.calls, ['helper failed']);
});

test('App renders real update buttons for progress, waiting, and recovery states', () => {
  const context = {
    React, Download: () => null, RefreshCw: () => null, Clock: () => null,
    handleStartDownload: () => {}, handleWaitingInstallClick: () => {}, handleRetryUpdate: () => {},
    updateStatus: { state: 'idle', progress_percent: 0, available_version: '0.2.0', error_message: 'download failed' },
  };
  const render = callback('renderUpdateButton', context);
  for (const [state, percent, label, disabled] of [
    ['idle', -1, null, false], ['checking', -1, null, false], ['available', -1, '更新', false],
    ['downloading', 42, '42%', true], ['downloading', -1, '下载中', true], ['staging', 100, '100%', true],
    ['waiting_install', 100, '等待安装', false], ['restarting', 100, '正在更新', true], ['error', -1, '重试更新', false],
  ] as const) {
    context.updateStatus.state = state;
    context.updateStatus.progress_percent = percent;
    const element = render();
    if (label === null) {
      assert.equal(element, null);
    } else {
      const html = renderToStaticMarkup(element);
      assert.ok(html.includes(`<span>${label}</span>`), html);
      assert.equal(html.includes('disabled=""'), disabled, html);
      assert.ok(!html.includes('准备安装'), html);
    }
  }
});
