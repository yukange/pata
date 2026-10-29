import test from 'node:test';
import assert from 'node:assert/strict';
import { matchesVaultEventType } from './vaultEvents.ts';

test('matchesVaultEventType: handles untyped or missing payloads gracefully', () => {
  assert.equal(matchesVaultEventType(null, ['task']), true);
  assert.equal(matchesVaultEventType(undefined, ['note']), true);
  assert.equal(matchesVaultEventType({}, ['task']), true);
  assert.equal(matchesVaultEventType({ data: {} }, ['task']), true);
  assert.equal(matchesVaultEventType({ data: { type: '' } }, ['task']), true);
});

test('matchesVaultEventType: always accepts errors', () => {
  assert.equal(matchesVaultEventType({ data: { type: 'error' } }, ['task']), true);
  assert.equal(matchesVaultEventType({ data: { op: 'error', type: 'something' } }, ['task']), true);
});

test('matchesVaultEventType: correctly filters matching and non-matching types', () => {
  // Task event
  assert.equal(matchesVaultEventType({ data: { type: 'task' } }, ['task']), true);
  assert.equal(matchesVaultEventType({ data: { type: 'task' } }, ['note']), false);
  assert.equal(matchesVaultEventType({ data: { type: 'task' } }, ['day_plan', 'task']), true);

  // Note event
  assert.equal(matchesVaultEventType({ data: { type: 'note' } }, ['note']), true);
  assert.equal(matchesVaultEventType({ data: { type: 'note' } }, ['task']), false);

  // File event
  assert.equal(matchesVaultEventType({ data: { type: 'file' } }, ['file']), true);
  assert.equal(matchesVaultEventType({ data: { type: 'file' } }, ['task', 'note', 'day_plan']), false);

  // DayPlan event
  assert.equal(matchesVaultEventType({ data: { type: 'day_plan' } }, ['day_plan']), true);
  assert.equal(matchesVaultEventType({ data: { type: 'day_plan' } }, ['note']), false);
});
