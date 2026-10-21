import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { getLocalDateStr, followTodayOnDateChange } from './todayDate.ts';

test('本地日期跨午夜与跨年正确，不使用 UTC ISO 日期', () => {
  assert.equal(getLocalDateStr(new Date(2026, 9, 20, 23, 59, 59)), '2026-10-20');
  assert.equal(getLocalDateStr(new Date(2026, 9, 21, 0, 0, 1)), '2026-10-21');
  assert.equal(getLocalDateStr(new Date(2026, 11, 31, 23, 59)), '2026-12-31');
  assert.equal(getLocalDateStr(new Date(2027, 0, 1, 0, 1)), '2027-01-01');
});

test('原本查看今天时跟随新日期，查看历史/未来日期时不强制切换', () => {
  assert.equal(followTodayOnDateChange('2026-10-20', '2026-10-20', '2026-10-21'), '2026-10-21');
  assert.equal(followTodayOnDateChange('2026-10-19', '2026-10-20', '2026-10-21'), '2026-10-19');
  assert.equal(followTodayOnDateChange('2026-10-22', '2026-10-20', '2026-10-21'), '2026-10-22');
  assert.equal(followTodayOnDateChange('2026-10-20', '2026-10-20', '2026-10-20'), '2026-10-20');
});

test('跨日时编辑暂缓跟随，结束编辑后仍可恢复；主动切换历史日期则不恢复', () => {
  // 编辑中选中的仍是旧日期；完成后用旧日期与当前今天比较决定是否自动跟随。
  const oldToday = '2026-10-20';
  const newToday = '2026-10-21';
  assert.equal(followTodayOnDateChange(oldToday, oldToday, newToday), newToday);
  assert.equal(followTodayOnDateChange('2026-10-19', oldToday, newToday), '2026-10-19');
});

test('TodayView 监听午夜、窗口重新聚焦和休眠恢复，并对活动草稿延迟跳转', () => {
  const view = fs.readFileSync(path.join(path.dirname(fileURLToPath(import.meta.url)), 'TodayView.tsx'), 'utf-8');
  assert.ok(view.includes('window.setInterval(refreshToday, 15_000)'));
  assert.ok(view.includes("document.addEventListener('visibilitychange', onVisibilityChange)"));
  assert.ok(view.includes("window.addEventListener('focus', refreshToday)"));
  assert.ok(view.includes('autoFollowBlockedRef.current'));
  assert.ok(view.includes('pendingAutoFollowRef.current'));
  assert.ok(view.includes('window.clearInterval(interval)'));
});

test('TodayView 拖拽计划冷却期间不丢失外部 vault:changed 事件，通过定时器延后同步', () => {
  const view = fs.readFileSync(path.join(path.dirname(fileURLToPath(import.meta.url)), 'TodayView.tsx'), 'utf-8');
  assert.ok(view.includes('pendingVaultChangeTimerRef'));
  assert.ok(view.includes('window.setTimeout(() => {\n            pendingVaultChangeTimerRef.current = null;\n            void loadData();\n          }, remaining)'));
  assert.ok(view.includes('window.clearTimeout(pendingVaultChangeTimerRef.current)'));
});
