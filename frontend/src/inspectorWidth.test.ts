import test from 'node:test';
import assert from 'node:assert/strict';
import {
  DEFAULT_INSPECTOR_WIDTH,
  clampInspectorWidth,
  maxInspectorWidth,
  parseInspectorWidth,
} from './inspectorWidth.ts';

test('inspector starts at 400px and accepts only sensible persisted widths', () => {
  assert.equal(parseInspectorWidth(null), DEFAULT_INSPECTOR_WIDTH);
  assert.equal(parseInspectorWidth('440'), 440);
  assert.equal(parseInspectorWidth('280'), 280);
  assert.equal(parseInspectorWidth('720'), 720);
  assert.equal(parseInspectorWidth('Infinity'), DEFAULT_INSPECTOR_WIDTH);
  assert.equal(parseInspectorWidth('NaN'), DEFAULT_INSPECTOR_WIDTH);
  assert.equal(parseInspectorWidth(''), DEFAULT_INSPECTOR_WIDTH);
  assert.equal(parseInspectorWidth('99'), DEFAULT_INSPECTOR_WIDTH);
  assert.equal(parseInspectorWidth('2000'), DEFAULT_INSPECTOR_WIDTH);
});

test('resizing stays bounded and protects the workspace on smaller windows', () => {
  assert.equal(clampInspectorWidth(250, 1400), 280);
  assert.equal(clampInspectorWidth(900, 1400), 720);
  assert.equal(clampInspectorWidth(600, 760), 440);
  assert.equal(maxInspectorWidth(640), 320);
  assert.equal(clampInspectorWidth(700, 640), 320);
  assert.equal(clampInspectorWidth(700, 500), 280);
});
